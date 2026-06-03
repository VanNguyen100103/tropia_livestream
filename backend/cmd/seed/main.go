// Command seed populates the database with a realistic set of test fixtures:
// multi-image products, multi-variant SKUs (color × size), attributes
// (Màu sắc, Kích cỡ, Trọng lượng), live session snapshots.
//
// Idempotent: re-running just refreshes data (ON CONFLICT DO UPDATE).
//
// Usage:
//   go run ./cmd/seed
//   make seed                    # Unix
//   .\scripts\seed.ps1           # Windows
package main

import (
	"context"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
	"golang.org/x/crypto/bcrypt"
)

const (
	seedPassword = "Password123"
	bcryptCost   = 12
)

// ─── Users ──────────────────────────────────────────────────────────────────

type seedUser struct {
	Email string
	Name  string
	Role  string
	Phone string
}

var users = []seedUser{
	{Email: "admin@tropia.test", Name: "Tropia Admin", Role: "admin"},
	{Email: "seller@tropia.test", Name: "Tropia Fresh Market", Role: "seller", Phone: "0900000001"},
	{Email: "buyer@tropia.test", Name: "Test Buyer", Role: "buyer", Phone: "0900000002"},
}

// ─── Categories ─────────────────────────────────────────────────────────────

type seedCategory struct {
	Name string
	Slug string
}

var categories = []seedCategory{
	{Name: "Trái cây", Slug: "trai-cay"},
	{Name: "Rau củ", Slug: "rau-cu"},
	{Name: "Hải sản", Slug: "hai-san"},
	{Name: "Thời trang", Slug: "thoi-trang"},
	{Name: "Mỹ phẩm", Slug: "my-pham"},
}

// ─── Attribute types + values ──────────────────────────────────────────────

type seedAttrType struct {
	Name      string
	SortOrder int
	Values    []seedAttrValue
}

type seedAttrValue struct {
	Value       string
	DisplayName string
	ColorHex    string // only for Color type
	SortOrder   int
}

var attrTypes = []seedAttrType{
	{
		Name: "Trọng lượng", SortOrder: 1,
		Values: []seedAttrValue{
			{Value: "250g", DisplayName: "250 gram", SortOrder: 1},
			{Value: "500g", DisplayName: "500 gram", SortOrder: 2},
			{Value: "1kg", DisplayName: "1 kilogram", SortOrder: 3},
			{Value: "2kg", DisplayName: "2 kilogram", SortOrder: 4},
		},
	},
	{
		Name: "Màu sắc", SortOrder: 2,
		Values: []seedAttrValue{
			{Value: "Đỏ", DisplayName: "Đỏ rực", ColorHex: "#E53935", SortOrder: 1},
			{Value: "Xanh dương", DisplayName: "Xanh dương", ColorHex: "#1E88E5", SortOrder: 2},
			{Value: "Trắng", DisplayName: "Trắng", ColorHex: "#FFFFFF", SortOrder: 3},
			{Value: "Đen", DisplayName: "Đen", ColorHex: "#212121", SortOrder: 4},
		},
	},
	{
		Name: "Kích cỡ", SortOrder: 3,
		Values: []seedAttrValue{
			{Value: "S", DisplayName: "Size S", SortOrder: 1},
			{Value: "M", DisplayName: "Size M", SortOrder: 2},
			{Value: "L", DisplayName: "Size L", SortOrder: 3},
			{Value: "XL", DisplayName: "Size XL", SortOrder: 4},
		},
	},
}

// ─── Products (with variants + images) ──────────────────────────────────────

type seedVariant struct {
	SKU       string
	Price     int
	SalePrice *int
	Stock     int
	Images    []string         // images riêng cho từng variant
	Attrs     map[string]string // attribute_type.name → attribute_value.value
}

type seedProduct struct {
	Slug        string
	Name        string
	Description string
	Unit        string
	Category    string
	Images      []string // ảnh chung cho sản phẩm (gallery)
	BasePrice   int      // giá hiển thị mặc định khi chưa chọn variant
	SalePrice   *int
	TotalStock  int
	HasVariants bool
	Variants    []seedVariant // có thể rỗng
}

func intP(v int) *int { return &v }

var products = []seedProduct{
	// ── 1. Trái cây — multi-variant theo trọng lượng ────────────────────────
	{
		Slug:        "cam-sanh-ha-giang",
		Name:        "Cam sành Hà Giang",
		Description: "Cam sành tươi, ngọt thanh, mọng nước. Vỏ mỏng, vận chuyển bằng xe lạnh từ vườn.",
		Unit:        "kg",
		Category:    "trai-cay",
		Images: []string{
			"https://images.unsplash.com/photo-1582979512210-99b6a53386f9?w=800",
			"https://images.unsplash.com/photo-1607004468138-e7e23ea26947?w=800",
			"https://images.unsplash.com/photo-1611080626919-7cf5a9dbab12?w=800",
		},
		BasePrice: 45000, SalePrice: intP(39000), TotalStock: 600,
		HasVariants: true,
		Variants: []seedVariant{
			{SKU: "CAM-SANH-500G", Price: 25000, SalePrice: intP(22000), Stock: 200,
				Attrs: map[string]string{"Trọng lượng": "500g"}},
			{SKU: "CAM-SANH-1KG", Price: 45000, SalePrice: intP(39000), Stock: 250,
				Attrs: map[string]string{"Trọng lượng": "1kg"}},
			{SKU: "CAM-SANH-2KG", Price: 85000, SalePrice: intP(75000), Stock: 150,
				Attrs: map[string]string{"Trọng lượng": "2kg"}},
		},
	},

	// ── 2. Rau hữu cơ — single-variant ───────────────────────────────────────
	{
		Slug:        "cai-bo-xoi-huu-co-500g",
		Name:        "Cải bó xôi hữu cơ 500g",
		Description: "Cải bó xôi (rau chân vịt) trồng hữu cơ tại Đà Lạt, giàu chất sắt, không thuốc trừ sâu.",
		Unit:        "bó",
		Category:    "rau-cu",
		Images: []string{
			"https://images.unsplash.com/photo-1576045057995-568f588f82fb?w=800",
			"https://images.unsplash.com/photo-1515543237350-b3eea1ec8082?w=800",
		},
		BasePrice: 28000, TotalStock: 150,
		HasVariants: false,
	},

	// ── 3. Hải sản — multi-variant theo trọng lượng ──────────────────────────
	{
		Slug:        "tom-su-da-lat-tuoi",
		Name:        "Tôm sú tươi sống",
		Description: "Tôm sú đầm Quảng Yên, kích thước 20-25 con/kg, được vận chuyển còn sống.",
		Unit:        "kg",
		Category:    "hai-san",
		Images: []string{
			"https://images.unsplash.com/photo-1565680018434-b513d5e5fd47?w=800",
			"https://images.unsplash.com/photo-1610540022404-9a72f56b2c01?w=800",
		},
		BasePrice: 380000, SalePrice: intP(350000), TotalStock: 80,
		HasVariants: true,
		Variants: []seedVariant{
			{SKU: "TOM-SU-500G", Price: 200000, SalePrice: intP(180000), Stock: 30,
				Attrs: map[string]string{"Trọng lượng": "500g"}},
			{SKU: "TOM-SU-1KG", Price: 380000, SalePrice: intP(350000), Stock: 50,
				Attrs: map[string]string{"Trọng lượng": "1kg"}},
		},
	},

	// ── 4. Thời trang — multi-variant theo MÀU × SIZE, ảnh riêng cho màu ─────
	{
		Slug:        "ao-thun-tropia-cotton",
		Name:        "Áo thun Tropia cotton 100%",
		Description: "Áo thun cotton 100%, in logo Tropia, form unisex thoải mái. 4 màu × 4 size.",
		Unit:        "cái",
		Category:    "thoi-trang",
		Images: []string{
			"https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=800",
			"https://images.unsplash.com/photo-1583743814966-8936f5b7be1a?w=800",
		},
		BasePrice: 199000, SalePrice: intP(149000), TotalStock: 0, // sẽ sum từ variants
		HasVariants: true,
		Variants: buildShirtVariants(),
	},

	// ── 5. Mỹ phẩm — multi-variant theo MÀU ─────────────────────────────────
	{
		Slug:        "son-tropia-matte",
		Name:        "Son Tropia matte 6 tone",
		Description: "Son lì lâu trôi, không bám cốc, vitamin E dưỡng môi. 4 tone mẫu.",
		Unit:        "thỏi",
		Category:    "my-pham",
		Images: []string{
			"https://images.unsplash.com/photo-1586495777744-4413f21062fa?w=800",
			"https://images.unsplash.com/photo-1631214540242-3cd8c0a3c5f7?w=800",
		},
		BasePrice: 220000, SalePrice: intP(180000), TotalStock: 0,
		HasVariants: true,
		Variants: []seedVariant{
			{SKU: "SON-TROPIA-RED", Price: 220000, SalePrice: intP(180000), Stock: 50,
				Images: []string{"https://images.unsplash.com/photo-1586495777744-4413f21062fa?w=800"},
				Attrs:  map[string]string{"Màu sắc": "Đỏ"}},
			{SKU: "SON-TROPIA-NUDE", Price: 220000, SalePrice: intP(180000), Stock: 40,
				Images: []string{"https://images.unsplash.com/photo-1631214540242-3cd8c0a3c5f7?w=800"},
				Attrs:  map[string]string{"Màu sắc": "Trắng"}}, // dùng "Trắng" cho tone nude
		},
	},
}

// buildShirtVariants tạo 4 màu × 4 size = 16 SKU, mỗi màu có 1 ảnh riêng.
func buildShirtVariants() []seedVariant {
	colorImages := map[string]string{
		"Đỏ":         "https://images.unsplash.com/photo-1521572163474-6864f9cf17ab?w=800",
		"Xanh dương": "https://images.unsplash.com/photo-1583743814966-8936f5b7be1a?w=800",
		"Trắng":      "https://images.unsplash.com/photo-1576566588028-4147f3842f27?w=800",
		"Đen":        "https://images.unsplash.com/photo-1618354691373-d851c5c3a990?w=800",
	}
	sizes := []string{"S", "M", "L", "XL"}

	out := make([]seedVariant, 0, len(colorImages)*len(sizes))
	for color, img := range colorImages {
		for _, size := range sizes {
			out = append(out, seedVariant{
				SKU:       fmt.Sprintf("AO-TROPIA-%s-%s", colorCode(color), size),
				Price:     199000,
				SalePrice: intP(149000),
				Stock:     20,
				Images:    []string{img},
				Attrs:     map[string]string{"Màu sắc": color, "Kích cỡ": size},
			})
		}
	}
	return out
}

func colorCode(c string) string {
	switch c {
	case "Đỏ":
		return "RED"
	case "Xanh dương":
		return "BLUE"
	case "Trắng":
		return "WHITE"
	case "Đen":
		return "BLACK"
	}
	return "X"
}

// ────────────────────────────────────────────────────────────────────────────

func main() {
	for _, f := range []string{".env.development", ".env"} {
		if _, err := os.Stat(f); err == nil {
			_ = godotenv.Load(f)
			log.Printf("loaded env from %s", f)
			break
		}
	}
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL not set")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	defer cancel()

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		log.Fatalf("connect: %v", err)
	}
	defer pool.Close()
	if err := pool.Ping(ctx); err != nil {
		log.Fatalf("ping: %v", err)
	}
	log.Println("connected to database")

	if err := seedUsers(ctx, pool); err != nil {
		log.Fatalf("seedUsers: %v", err)
	}
	if err := seedShops(ctx, pool); err != nil {
		log.Fatalf("seedShops: %v", err)
	}
	if err := seedCategories(ctx, pool); err != nil {
		log.Fatalf("seedCategories: %v", err)
	}
	attrValueIDs, err := seedAttributes(ctx, pool)
	if err != nil {
		log.Fatalf("seedAttributes: %v", err)
	}
	if err := seedProducts(ctx, pool, attrValueIDs); err != nil {
		log.Fatalf("seedProducts: %v", err)
	}
	if err := seedLiveSession(ctx, pool); err != nil {
		log.Fatalf("seedLiveSession: %v", err)
	}

	log.Println("")
	log.Println("✅ seed complete")
	log.Println("")
	log.Println("Test accounts (password for all = Password123):")
	for _, u := range users {
		log.Printf("  %-22s role=%s", u.Email, u.Role)
	}
}

// ─── Steps ──────────────────────────────────────────────────────────────────

func seedUsers(ctx context.Context, pool *pgxpool.Pool) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(seedPassword), bcryptCost)
	if err != nil {
		return err
	}
	const q = `
		INSERT INTO profiles (email, password_hash, name, phone, role, email_verified)
		VALUES ($1, $2, $3, NULLIF($4, ''), $5, TRUE)
		ON CONFLICT (email) DO UPDATE
			SET password_hash = EXCLUDED.password_hash,
			    name          = EXCLUDED.name,
			    role          = EXCLUDED.role,
			    email_verified = TRUE
	`
	for _, u := range users {
		if _, err := pool.Exec(ctx, q, u.Email, string(hash), u.Name, u.Phone, u.Role); err != nil {
			return fmt.Errorf("user %s: %w", u.Email, err)
		}
		log.Printf("  ✓ user %s (%s)", u.Email, u.Role)
	}
	return nil
}

func seedShops(ctx context.Context, pool *pgxpool.Pool) error {
	const q = `
		INSERT INTO shops (seller_id, name, slug, description, is_active)
		SELECT id, $1, $2, $3, TRUE FROM profiles WHERE email = $4
		ON CONFLICT (seller_id) DO UPDATE
			SET name = EXCLUDED.name, description = EXCLUDED.description
	`
	if _, err := pool.Exec(ctx, q,
		"Tropia Fresh Market",
		"tropia-fresh-market",
		"Cửa hàng chính thức của Tropia — thực phẩm + lifestyle.",
		"seller@tropia.test",
	); err != nil {
		return err
	}
	log.Println("  ✓ shop tropia-fresh-market")
	return nil
}

func seedCategories(ctx context.Context, pool *pgxpool.Pool) error {
	const q = `
		INSERT INTO categories (name, slug, sort_order, is_active)
		VALUES ($1, $2, $3, TRUE)
		ON CONFLICT (slug) DO UPDATE
			SET name = EXCLUDED.name, sort_order = EXCLUDED.sort_order
	`
	for i, c := range categories {
		if _, err := pool.Exec(ctx, q, c.Name, c.Slug, i); err != nil {
			return fmt.Errorf("category %s: %w", c.Slug, err)
		}
		log.Printf("  ✓ category %s", c.Slug)
	}
	return nil
}

// seedAttributes returns a nested map[typeName][valueText] = attribute_value.id
// for cross-referencing when linking variants.
func seedAttributes(ctx context.Context, pool *pgxpool.Pool) (map[string]map[string]string, error) {
	const insertType = `
		INSERT INTO attribute_types (name, sort_order)
		VALUES ($1, $2)
		ON CONFLICT (name) DO UPDATE SET sort_order = EXCLUDED.sort_order
		RETURNING id
	`
	const insertValue = `
		INSERT INTO attribute_values (attribute_type_id, value, display_name, color_hex, sort_order)
		VALUES ($1, $2, NULLIF($3, ''), NULLIF($4, ''), $5)
		ON CONFLICT (attribute_type_id, value) DO UPDATE
			SET display_name = EXCLUDED.display_name,
			    color_hex    = EXCLUDED.color_hex,
			    sort_order   = EXCLUDED.sort_order
		RETURNING id
	`

	out := make(map[string]map[string]string)
	for _, at := range attrTypes {
		var typeID string
		if err := pool.QueryRow(ctx, insertType, at.Name, at.SortOrder).Scan(&typeID); err != nil {
			return nil, fmt.Errorf("attr type %s: %w", at.Name, err)
		}
		out[at.Name] = make(map[string]string)
		for _, v := range at.Values {
			var valueID string
			if err := pool.QueryRow(ctx, insertValue,
				typeID, v.Value, v.DisplayName, v.ColorHex, v.SortOrder,
			).Scan(&valueID); err != nil {
				return nil, fmt.Errorf("attr value %s.%s: %w", at.Name, v.Value, err)
			}
			out[at.Name][v.Value] = valueID
		}
		log.Printf("  ✓ attribute %q with %d values", at.Name, len(at.Values))
	}
	return out, nil
}

func seedProducts(ctx context.Context, pool *pgxpool.Pool, attrIDs map[string]map[string]string) error {
	var shopID string
	if err := pool.QueryRow(ctx,
		`SELECT id::text FROM shops WHERE slug = 'tropia-fresh-market'`,
	).Scan(&shopID); err != nil {
		return fmt.Errorf("lookup shop: %w", err)
	}

	const insertProduct = `
		INSERT INTO products (shop_id, name, slug, description, images, base_price, sale_price,
		                      unit, total_stock, has_variants, status)
		VALUES ($1, $2, $3, $4, $5::text[], $6, $7, $8, $9, $10, 'active')
		ON CONFLICT (slug) DO UPDATE
			SET description  = EXCLUDED.description,
			    images       = EXCLUDED.images,
			    base_price   = EXCLUDED.base_price,
			    sale_price   = EXCLUDED.sale_price,
			    unit         = EXCLUDED.unit,
			    total_stock  = EXCLUDED.total_stock,
			    has_variants = EXCLUDED.has_variants,
			    status       = 'active'
		RETURNING id
	`
	const linkCategory = `
		INSERT INTO product_categories (product_id, category_id, is_primary)
		SELECT $1, c.id, TRUE FROM categories c WHERE c.slug = $2
		ON CONFLICT DO NOTHING
	`
	// Variant insert: ON CONFLICT on sku doesn't work (sku is nullable, no unique
	// constraint on plain sku). We delete existing variants for this product
	// first, then re-insert — simpler than tracking matches by sku across re-runs.
	const deleteVariants  = `DELETE FROM product_variants WHERE product_id = $1`
	const insertVariant = `
		INSERT INTO product_variants (product_id, sku, price, sale_price, stock, images, is_active)
		VALUES ($1, $2, $3, $4, $5, $6::text[], TRUE)
		RETURNING id
	`
	const insertVariantAttr = `
		INSERT INTO variant_attributes (variant_id, attribute_value_id)
		VALUES ($1, $2)
		ON CONFLICT DO NOTHING
	`

	for _, p := range products {
		// total_stock = sum of variant stocks if has_variants
		totalStock := p.TotalStock
		if p.HasVariants {
			totalStock = 0
			for _, v := range p.Variants {
				totalStock += v.Stock
			}
		}

		var prodID string
		if err := pool.QueryRow(ctx, insertProduct,
			shopID, p.Name, p.Slug, p.Description, p.Images,
			p.BasePrice, p.SalePrice, p.Unit, totalStock, p.HasVariants,
		).Scan(&prodID); err != nil {
			return fmt.Errorf("product %s: %w", p.Slug, err)
		}
		if _, err := pool.Exec(ctx, linkCategory, prodID, p.Category); err != nil {
			return fmt.Errorf("link %s -> %s: %w", p.Slug, p.Category, err)
		}

		// Wipe + re-insert variants so the seed stays idempotent without
		// requiring unique constraint on sku.
		if _, err := pool.Exec(ctx, deleteVariants, prodID); err != nil {
			return fmt.Errorf("clear variants %s: %w", p.Slug, err)
		}

		variantList := p.Variants
		if !p.HasVariants {
			// Single default variant for products without explicit variants —
			// needed so cart_items can reference a variant_id.
			variantList = []seedVariant{{
				SKU: p.Slug + "-DEFAULT", Price: p.BasePrice, SalePrice: p.SalePrice,
				Stock: totalStock, Images: p.Images,
			}}
		}

		for _, v := range variantList {
			images := v.Images
			if len(images) == 0 {
				images = []string{}
			}
			var variantID string
			if err := pool.QueryRow(ctx, insertVariant,
				prodID, v.SKU, v.Price, v.SalePrice, v.Stock, images,
			).Scan(&variantID); err != nil {
				return fmt.Errorf("variant %s.%s: %w", p.Slug, v.SKU, err)
			}
			// Link attributes
			for attrType, attrValue := range v.Attrs {
				valueID, ok := attrIDs[attrType][attrValue]
				if !ok {
					return fmt.Errorf("unknown attr %s=%s on variant %s", attrType, attrValue, v.SKU)
				}
				if _, err := pool.Exec(ctx, insertVariantAttr, variantID, valueID); err != nil {
					return fmt.Errorf("link variant attr %s.%s=%s: %w", v.SKU, attrType, attrValue, err)
				}
			}
		}
		log.Printf("  ✓ product %s (%d variants, %d images)", p.Slug, len(variantList), len(p.Images))
	}
	return nil
}

func seedLiveSession(ctx context.Context, pool *pgxpool.Pool) error {
	const insertSession = `
		INSERT INTO live_sessions (seller_id, title, description, category, stream_key, status)
		SELECT id, $1, $2, $3, $4, 'scheduled'
		FROM profiles WHERE email = 'seller@tropia.test'
		ON CONFLICT (stream_key) DO UPDATE
			SET title = EXCLUDED.title, description = EXCLUDED.description
		RETURNING id
	`
	channel := "live_seed_demo_session"
	var sessID string
	if err := pool.QueryRow(ctx, insertSession,
		"Demo Live — Flash sale tổng hợp",
		"Buổi live demo có cả trái cây, hải sản và áo thun. Test cho team backend + Flutter.",
		"Tổng hợp",
		channel,
	).Scan(&sessID); err != nil {
		return err
	}

	const insertSnap = `
		INSERT INTO live_session_products (session_id, product_id, product_name, image_url,
		                                    original_price, sale_price, discount_pct, stock_left,
		                                    unit, category, sort_order, is_pinned)
		SELECT $1, p.id, p.name, COALESCE(p.images[1], ''),
		       p.base_price, COALESCE(p.sale_price, p.base_price),
		       CASE WHEN p.sale_price IS NULL THEN 0
		            ELSE ROUND(100.0 * (p.base_price - p.sale_price) / p.base_price)
		       END,
		       p.total_stock, p.unit, $3, $4, $5
		FROM products p WHERE p.slug = $2
		ON CONFLICT DO NOTHING
	`
	snapshots := []struct {
		slug, category string
		sortOrder      int
		pinned         bool
	}{
		{"cam-sanh-ha-giang", "Trái cây", 0, true},
		{"tom-su-da-lat-tuoi", "Hải sản", 1, false},
		{"ao-thun-tropia-cotton", "Thời trang", 2, false},
	}
	for _, s := range snapshots {
		if _, err := pool.Exec(ctx, insertSnap, sessID, s.slug, s.category, s.sortOrder, s.pinned); err != nil {
			return fmt.Errorf("snap %s: %w", s.slug, err)
		}
	}

	// Demo coupons attached to the session so the viewer's floating
	// voucher popup ("Lưu") fires on entry — without these, vouchers is
	// empty and LiveProvider.floatingVoucherId stays null.
	const insertCoupon = `
		INSERT INTO coupons (code, discount_type, discount_value, min_order_value, max_discount,
		                      max_uses, expires_at, is_active, session_id, created_by)
		SELECT $1, $2, $3, $4, $5, $6, NOW() + INTERVAL '30 days', TRUE, $7, p.id
		FROM profiles p WHERE p.email = 'seller@tropia.test'
		ON CONFLICT (code) DO UPDATE
			SET discount_value  = EXCLUDED.discount_value,
			    min_order_value = EXCLUDED.min_order_value,
			    max_discount    = EXCLUDED.max_discount,
			    max_uses        = EXCLUDED.max_uses,
			    expires_at      = EXCLUDED.expires_at,
			    is_active       = TRUE,
			    session_id      = EXCLUDED.session_id
	`
	coupons := []struct {
		code         string
		discountType string
		value        float64
		minOrder     int
		maxDiscount  *int
		maxUses      *int
	}{
		{"TROPIA10", "percent", 10, 0, intPtr(50_000), intPtr(100)},
		{"FRESH50K", "fixed", 50_000, 200_000, nil, intPtr(50)},
		{"WELCOME20", "percent", 20, 100_000, intPtr(100_000), intPtr(200)},
	}
	for _, c := range coupons {
		if _, err := pool.Exec(ctx, insertCoupon,
			c.code, c.discountType, c.value, c.minOrder, c.maxDiscount, c.maxUses, sessID,
		); err != nil {
			return fmt.Errorf("coupon %s: %w", c.code, err)
		}
	}

	log.Printf("  ✓ live session %s (channel=%s, %d snapshot products, %d coupons)",
		sessID, channel, len(snapshots), len(coupons))
	return nil
}

func intPtr(v int) *int { return &v }
