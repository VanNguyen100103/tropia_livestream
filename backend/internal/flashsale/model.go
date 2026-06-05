package flashsale

import (
	"time"

	"github.com/google/uuid"
)

// FlashSale is an admin-scheduled, platform-wide discount window. While
// StartsAt <= now < EndsAt and IsActive, the attached products show their
// flash_price + a countdown to EndsAt on every surface (video feed card,
// flash-sale page).
type FlashSale struct {
	ID        uuid.UUID `json:"id"`
	Name      string    `json:"name"`
	StartsAt  time.Time `json:"starts_at"`
	EndsAt    time.Time `json:"ends_at"`
	IsActive  bool      `json:"is_active"`
	CreatedBy uuid.UUID `json:"created_by"`
	CreatedAt time.Time `json:"created_at"`

	// Attached products with their flash price. Always non-nil ([] when none).
	Products []FlashSaleProduct `json:"products"`
}

// FlashSaleProduct is one catalog product in a flash sale. Display fields
// (name/slug/image/base_price) are read live from `products`; FlashPrice is the
// absolute discounted VND price for the window.
type FlashSaleProduct struct {
	ProductID  uuid.UUID `json:"product_id"`
	Name       string    `json:"name"`
	Slug       string    `json:"slug"`
	ImageURL   *string   `json:"image_url,omitempty"`
	BasePrice  int       `json:"base_price"`
	FlashPrice int       `json:"flash_price"`
	StockLimit *int      `json:"stock_limit,omitempty"`
	SoldCount  int       `json:"sold_count"`
	SortOrder  int       `json:"sort_order"`
}

// Live reports whether the sale window currently covers now.
func (s FlashSale) Live() bool {
	now := time.Now()
	return s.IsActive && !s.StartsAt.After(now) && s.EndsAt.After(now)
}
