package flashsale

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

var ErrNotFound = errors.New("flashsale: not found")

type Repository struct{ pool *pgxpool.Pool }

func NewRepository(pool *pgxpool.Pool) *Repository { return &Repository{pool: pool} }

// ProductInput is one product + its flash price as supplied by the admin.
type ProductInput struct {
	ProductID  uuid.UUID
	FlashPrice int
	StockLimit *int
}

type CreateParams struct {
	Name      string
	StartsAt  time.Time
	EndsAt    time.Time
	CreatedBy uuid.UUID
	Products  []ProductInput
}

func scanSale(row pgx.Row, s *FlashSale) error {
	return row.Scan(&s.ID, &s.Name, &s.StartsAt, &s.EndsAt, &s.IsActive, &s.CreatedBy, &s.CreatedAt)
}

const saleCols = `id, name, starts_at, ends_at, is_active, created_by, created_at`

func (r *Repository) Create(ctx context.Context, p CreateParams) (*FlashSale, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	var id uuid.UUID
	if err := tx.QueryRow(ctx,
		`INSERT INTO flash_sales (name, starts_at, ends_at, created_by)
		 VALUES ($1, $2, $3, $4) RETURNING id`,
		p.Name, p.StartsAt, p.EndsAt, p.CreatedBy,
	).Scan(&id); err != nil {
		return nil, err
	}
	if err := attachProducts(ctx, tx, id, p.Products); err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return r.GetByID(ctx, id)
}

// attachProducts links products to a sale in supplied order (sort_order = idx).
// Only ACTIVE catalog products are linked; unknown / inactive / duplicate ids
// are skipped so a stale admin selection can't fail the whole create.
func attachProducts(ctx context.Context, tx pgx.Tx, saleID uuid.UUID, items []ProductInput) error {
	if len(items) == 0 {
		return nil
	}
	ids := make([]uuid.UUID, 0, len(items))
	for _, it := range items {
		ids = append(ids, it.ProductID)
	}
	rows, err := tx.Query(ctx,
		`SELECT id FROM products WHERE id = ANY($1) AND status = 'active'`, ids)
	if err != nil {
		return err
	}
	allowed := make(map[uuid.UUID]bool)
	for rows.Next() {
		var id uuid.UUID
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return err
		}
		allowed[id] = true
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	order := 0
	seen := make(map[uuid.UUID]bool)
	for _, it := range items {
		if !allowed[it.ProductID] || seen[it.ProductID] {
			continue
		}
		seen[it.ProductID] = true
		if _, err := tx.Exec(ctx,
			`INSERT INTO flash_sale_products (flash_sale_id, product_id, flash_price, stock_limit, sort_order)
			 VALUES ($1, $2, $3, $4, $5)
			 ON CONFLICT (flash_sale_id, product_id)
			 DO UPDATE SET flash_price = EXCLUDED.flash_price, stock_limit = EXCLUDED.stock_limit, sort_order = EXCLUDED.sort_order`,
			saleID, it.ProductID, it.FlashPrice, it.StockLimit, order); err != nil {
			return err
		}
		order++
	}
	return nil
}

// SetProducts replaces the full product set of a sale in one transaction.
func (r *Repository) SetProducts(ctx context.Context, saleID uuid.UUID, items []ProductInput) error {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var exists bool
	if err := tx.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM flash_sales WHERE id = $1)`, saleID).Scan(&exists); err != nil {
		return err
	}
	if !exists {
		return ErrNotFound
	}
	if _, err := tx.Exec(ctx, `DELETE FROM flash_sale_products WHERE flash_sale_id = $1`, saleID); err != nil {
		return err
	}
	if err := attachProducts(ctx, tx, saleID, items); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func (r *Repository) RemoveProduct(ctx context.Context, saleID, productID uuid.UUID) error {
	tag, err := r.pool.Exec(ctx,
		`DELETE FROM flash_sale_products WHERE flash_sale_id = $1 AND product_id = $2`, saleID, productID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) GetByID(ctx context.Context, id uuid.UUID) (*FlashSale, error) {
	var s FlashSale
	if err := scanSale(r.pool.QueryRow(ctx, `SELECT `+saleCols+` FROM flash_sales WHERE id = $1`, id), &s); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	byID, err := r.productsForSales(ctx, []uuid.UUID{id})
	if err != nil {
		return nil, err
	}
	if s.Products = byID[id]; s.Products == nil {
		s.Products = []FlashSaleProduct{}
	}
	return &s, nil
}

// List returns sales for the admin console. includeInactive=false hides
// deactivated sales. Newest first.
func (r *Repository) List(ctx context.Context, includeInactive bool, limit, offset int) ([]FlashSale, error) {
	q := `SELECT ` + saleCols + ` FROM flash_sales`
	if !includeInactive {
		q += ` WHERE is_active = TRUE`
	}
	q += ` ORDER BY starts_at DESC LIMIT $1 OFFSET $2`
	return r.collect(ctx, q, limit, offset)
}

// ListActive returns only sales whose window currently covers now (public).
func (r *Repository) ListActive(ctx context.Context) ([]FlashSale, error) {
	q := `SELECT ` + saleCols + ` FROM flash_sales
		WHERE is_active = TRUE AND starts_at <= NOW() AND ends_at > NOW()
		ORDER BY ends_at ASC`
	return r.collect(ctx, q)
}

func (r *Repository) collect(ctx context.Context, q string, args ...any) ([]FlashSale, error) {
	rows, err := r.pool.Query(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]FlashSale, 0)
	ids := make([]uuid.UUID, 0)
	for rows.Next() {
		var s FlashSale
		if err := scanSale(rows, &s); err != nil {
			return nil, err
		}
		out = append(out, s)
		ids = append(ids, s.ID)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	byID, err := r.productsForSales(ctx, ids)
	if err != nil {
		return nil, err
	}
	for i := range out {
		if ps := byID[out[i].ID]; ps != nil {
			out[i].Products = ps
		} else {
			out[i].Products = []FlashSaleProduct{}
		}
	}
	return out, nil
}

func (r *Repository) productsForSales(ctx context.Context, saleIDs []uuid.UUID) (map[uuid.UUID][]FlashSaleProduct, error) {
	out := make(map[uuid.UUID][]FlashSaleProduct, len(saleIDs))
	if len(saleIDs) == 0 {
		return out, nil
	}
	const q = `
		SELECT fsp.flash_sale_id, p.id, p.name, p.slug, (p.images)[1], p.base_price,
		       fsp.flash_price, fsp.stock_limit, fsp.sold_count, fsp.sort_order
		FROM flash_sale_products fsp
		JOIN products p ON p.id = fsp.product_id
		WHERE fsp.flash_sale_id = ANY($1)
		ORDER BY fsp.flash_sale_id, fsp.sort_order`
	rows, err := r.pool.Query(ctx, q, saleIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var sid uuid.UUID
		var fp FlashSaleProduct
		if err := rows.Scan(&sid, &fp.ProductID, &fp.Name, &fp.Slug, &fp.ImageURL, &fp.BasePrice,
			&fp.FlashPrice, &fp.StockLimit, &fp.SoldCount, &fp.SortOrder); err != nil {
			return nil, err
		}
		out[sid] = append(out[sid], fp)
	}
	return out, rows.Err()
}

// Update patches mutable fields. Any nil pointer is left unchanged.
func (r *Repository) Update(ctx context.Context, id uuid.UUID, name *string, startsAt, endsAt *time.Time, isActive *bool) error {
	tag, err := r.pool.Exec(ctx, `
		UPDATE flash_sales SET
			name      = COALESCE($2, name),
			starts_at = COALESCE($3, starts_at),
			ends_at   = COALESCE($4, ends_at),
			is_active = COALESCE($5, is_active)
		WHERE id = $1`,
		id, name, startsAt, endsAt, isActive)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (r *Repository) Delete(ctx context.Context, id uuid.UUID) error {
	tag, err := r.pool.Exec(ctx, `DELETE FROM flash_sales WHERE id = $1`, id)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
