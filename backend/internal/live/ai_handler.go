package live

import (
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend-go/internal/ai"
	"github.com/tropia/backend-go/internal/httpx"
)

// AIHandler exposes DeepSeek-backed endpoints on top of a live session:
// - POST /streams/:id/ai-suggestions  → 3 short Vietnamese viewer questions
// - POST /streams/:id/ai-reply        → host auto-reply for one viewer question
// - POST /streams/:id/analyze         → sentiment + summary + 4 tips for the session
type AIHandler struct {
	ai   *ai.DeepSeek
	repo *SessionRepository
}

func NewAIHandler(deepseek *ai.DeepSeek, repo *SessionRepository) *AIHandler {
	return &AIHandler{ai: deepseek, repo: repo}
}

func (h *AIHandler) Register(r *gin.RouterGroup, authMw, sellerMw gin.HandlerFunc) {
	authed := r.Group("/streams/:id", authMw)
	authed.POST("/ai-suggestions", h.suggestions)
	authed.POST("/ai-reply", h.reply)

	seller := r.Group("/streams/:id", authMw, sellerMw)
	seller.POST("/analyze", h.analyze)
}

// ---------- helpers ----------

func (h *AIHandler) loadSession(c *gin.Context) (*Session, bool) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid session id", nil))
		return nil, false
	}
	sess, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return nil, false
	}
	return sess, true
}

// productNameForAI picks a representative product to feed to the AI prompt.
// If the session has any pinned product, use that; otherwise the first product;
// otherwise fall back to the client-supplied name.
func (h *AIHandler) productNameForAI(c *gin.Context, sessionID uuid.UUID, fallback string) (name, category string) {
	products, err := h.repo.ListProducts(c.Request.Context(), sessionID)
	if err == nil && len(products) > 0 {
		// Prefer pinned, else first
		for _, p := range products {
			if p.IsPinned {
				cat := ""
				if p.Category != nil {
					cat = *p.Category
				}
				return p.ProductName, cat
			}
		}
		cat := ""
		if products[0].Category != nil {
			cat = *products[0].Category
		}
		return products[0].ProductName, cat
	}
	return fallback, ""
}

// ---------- endpoints ----------

type aiSuggestionsReq struct {
	ProductName    string   `json:"product_name"`
	Category       string   `json:"category"`
	RecentComments []string `json:"recent_comments"`
}

func (h *AIHandler) suggestions(c *gin.Context) {
	sess, ok := h.loadSession(c)
	if !ok {
		return
	}
	var req aiSuggestionsReq
	_ = c.ShouldBindJSON(&req)

	name, category := h.productNameForAI(c, sess.ID, req.ProductName)
	if category == "" {
		category = req.Category
	}
	if name == "" {
		c.Error(httpx.NewValidation("no product to suggest about", nil))
		return
	}

	out, err := h.ai.GetSuggestions(c.Request.Context(), name, category)
	if err != nil {
		c.Error(httpx.NewInternal("ai suggestions", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"suggestions": out})
}

type aiReplyReq struct {
	Question    string `json:"question" binding:"required,min=1,max=500"`
	ProductName string `json:"product_name"`
	Category    string `json:"category"`
}

func (h *AIHandler) reply(c *gin.Context) {
	sess, ok := h.loadSession(c)
	if !ok {
		return
	}
	var req aiReplyReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}

	name, category := h.productNameForAI(c, sess.ID, req.ProductName)
	if category == "" {
		category = req.Category
	}
	if name == "" {
		name = "sản phẩm"
	}

	reply, err := h.ai.GetAutoReply(c.Request.Context(), req.Question, name, category)
	if err != nil {
		c.Error(httpx.NewInternal("ai reply", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"reply": reply})
}

func (h *AIHandler) analyze(c *gin.Context) {
	sess, ok := h.loadSession(c)
	if !ok {
		return
	}
	res, err := h.ai.AnalyzeSentiment(c.Request.Context(), sess.Title, sess.ViewerCount, sess.LikeCount)
	if err != nil {
		c.Error(httpx.NewInternal("ai analyze", err))
		return
	}
	c.JSON(http.StatusOK, res)
}
