// Command seed populates the database with a small set of deterministic
// test fixtures so developers can poke around without registering by hand.
//
// Idempotent: re-running is safe (uses ON CONFLICT DO NOTHING). Passwords
// are bcrypt-hashed on every run.
//
// Usage (Windows):
//   .\scripts\seed.ps1
//
// Usage (Unix):
//   make seed
//
// Or directly:
//   go run ./cmd/seed
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
	"golang.org/x/crypto/bcrypt"
)

const (
	seedPassword = "Password123" // hashed below; used by all seed accounts
	bcryptCost   = 12
)

type seedUser struct {
	Email string
	Name  string
	Role  string // 'buyer' | 'seller' | 'admin'
	Phone string
}

var users = []seedUser{
	{Email: "admin@tropia.test", Name: "Tropia Admin", Role: "admin"},
	{Email: "seller@tropia.test", Name: "Tropia Fresh Market", Role: "seller", Phone: "0900000001"},
	{Email: "buyer@tropia.test", Name: "Test Buyer", Role: "buyer", Phone: "0900000002"},
}

type seedCategory struct {
	Name string
	Slug string
}

var categories = []seedCategory{
	{Name: "Trái cây", Slug: "trai-cay"},
	{Name: "Rau củ", Slug: "rau-cu"},
	{Name: "Hải sản", Slug: "hai-san"},
}

type seedProduct struct {
	Name        string
	Slug        string
	Description string
	BasePrice   int
	SalePrice   *int
	Stock       int
	Unit        string
	Category    string // matches seedCategory.Slug
	Image       string
}

func intP(v int) *int { return &v }

var products = []seedProduct{
	{
		Name: "Cam sành Hà Giang 1kg", Slug: "cam-sanh-ha-giang-1kg",
		Description: "Cam sành tươi, ngọt thanh, mọng nước.",
		BasePrice:   45000, SalePrice: intP(39000), Stock: 200, Unit: "kg",
		Category: "trai-cay",
		Image:    "https://images.unsplash.com/photo-1582979512210-99b6a53386f9",
	},
	{
		Name: "Cải bó xôi hữu cơ 500g", Slug: "cai-bo-xoi-huu-co-500g",
		Description: "Cải bó xôi (rau chân vịt) trồng hữu cơ, giàu chất sắt.",
		BasePrice:   28000, Stock: 150, Unit: "bó",
		Category: "rau-cu",
		Image:    "https://images.unsplash.com/photo-1576045057995-568f588f82fb",
	},
}

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

	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
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
	if err := seedProducts(ctx, pool); err != nil {
		log.Fatalf("seedProducts: %v", err)
	}
	if err := seedLiveSession(ctx, pool); err != nil {
		log.Fatalf("seedLiveSession: %v", err)
	}

	log.Println("✅ seed complete")
	log.Println("")
	log.Println("Test accounts (password for all = Password123):")
	for _, u := range users {
		log.Printf("  %-22s role=%s", u.Email, u.Role)
	}
}

func seedUsers(ctx context.Context, pool *pgxpool.Pool) error {
	const q = `
		INSERT INTO profiles (email, password_hash, name, phone, role, email_verified)
		VALUES ($1, $2, $3, NULLIF($4, ''), $5, TRUE)
		ON CONFLICT (email) DO UPDATE
			SET password_hash = EXCLUDED.password_hash,
			    name          = EXCLUDED.name,
			    role          = EXCLUDED.role,
			    email_verified = TRUE
	`
	hash, err := bcrypt.GenerateFromPassword([]byte(seedPassword), bcryptCost)
	if err != nil {
		return err
	}
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
		SELECT id, $1, $2, $3, TRUE
		FROM profiles WHERE email = $4
		ON CONFLICT (seller_id) DO UPDATE
			SET name = EXCLUDED.name, description = EXCLUDED.description
	`
	if _, err := pool.Exec(ctx, q,
		"Tropia Fresh Market",
		"tropia-fresh-market",
		"Cửa hàng thực phẩm tươi sống chính thức của Tropia.",
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

func seedProducts(ctx context.Context, pool *pgxpool.Pool) error {
	// Look up shop_id for the seller once.
	var shopID string
	err := pool.QueryRow(ctx, `SELECT id::text FROM shops WHERE slug = 'tropia-fresh-market'`).Scan(&shopID)
	if err != nil {
		return fmt.Errorf("lookup shop: %w", err)
	}

	const insertProduct = `
		INSERT INTO products (shop_id, name, slug, description, images, base_price, sale_price,
		                      unit, total_stock, status, has_variants)
		VALUES ($1, $2, $3, $4, ARRAY[$5]::text[], $6, $7, $8, $9, 'active', FALSE)
		ON CONFLICT (slug) DO UPDATE
			SET description = EXCLUDED.description,
			    base_price  = EXCLUDED.base_price,
			    sale_price  = EXCLUDED.sale_price,
			    total_stock = EXCLUDED.total_stock,
			    status      = 'active'
		RETURNING id
	`
	const linkCategory = `
		INSERT INTO product_categories (product_id, category_id, is_primary)
		SELECT $1, c.id, TRUE FROM categories c WHERE c.slug = $2
		ON CONFLICT DO NOTHING
	`
	const insertVariant = `
		INSERT INTO product_variants (product_id, price, sale_price, stock, is_active)
		VALUES ($1, $2, $3, $4, TRUE)
		ON CONFLICT DO NOTHING
	`

	for _, p := range products {
		var prodID string
		if err := pool.QueryRow(ctx, insertProduct,
			shopID, p.Name, p.Slug, p.Description, p.Image,
			p.BasePrice, p.SalePrice, p.Unit, p.Stock,
		).Scan(&prodID); err != nil {
			return fmt.Errorf("product %s: %w", p.Slug, err)
		}
		if _, err := pool.Exec(ctx, linkCategory, prodID, p.Category); err != nil {
			return fmt.Errorf("link %s -> %s: %w", p.Slug, p.Category, err)
		}
		// Default variant (so cart_items can reference it)
		if _, err := pool.Exec(ctx, insertVariant, prodID, p.BasePrice, p.SalePrice, p.Stock); err != nil {
			return fmt.Errorf("variant %s: %w", p.Slug, err)
		}
		log.Printf("  ✓ product %s", p.Slug)
	}
	return nil
}

func seedLiveSession(ctx context.Context, pool *pgxpool.Pool) error {
	// One live session for the seller, with one snapshot product.
	const insertSession = `
		INSERT INTO live_sessions (seller_id, title, description, category, agora_channel, status)
		SELECT id, $1, $2, $3, $4, 'scheduled'
		FROM profiles WHERE email = 'seller@tropia.test'
		ON CONFLICT (agora_channel) DO UPDATE
			SET title = EXCLUDED.title, description = EXCLUDED.description
		RETURNING id
	`
	channel := "live_seed_demo_session"
	var sessID string
	if err := pool.QueryRow(ctx, insertSession,
		"Demo Live - Trái cây tươi giảm 30%",
		"Buổi live demo cho team test backend + Flutter.",
		"Trái cây",
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
		       p.total_stock, p.unit, 'Trái cây', 0, TRUE
		FROM products p WHERE p.slug = $2
		ON CONFLICT DO NOTHING
	`
	if _, err := pool.Exec(ctx, insertSnap, sessID, "cam-sanh-ha-giang-1kg"); err != nil {
		return fmt.Errorf("snap product: %w", err)
	}

	log.Printf("  ✓ live session %s (channel=%s)", sessID, channel)
	return nil
}

// randomHex - kept for future seeding needs (e.g. stream keys)
func randomHex(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

var _ = randomHex
