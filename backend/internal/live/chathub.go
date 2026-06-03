package live

import (
	"log/slog"
	"sync"
)

// Two broadcast channels in one struct:
//
//   `clients`  — per-session subscribers (chat + stats events for one
//                live session, scoped by session UUID).
//   `globals`  — platform-wide subscribers (Live tab card list).
//                Receive a single "list_change" event whenever any
//                host creates / ends / re-pins a session. Each client
//                then re-fetches the list via REST — we don't push the
//                full list payload over WS because it's bursty and
//                the REST cache already coalesces concurrent loads.
//
// Single-process: a multi-pod deploy needs sticky-session ingress or
// Redis pub/sub fanout (~50 LOC patch). See chathub.go comment.
//
// Scaling note: this is single-process. With multiple backend replicas
// behind k8s, the same session can have viewers connected to different
// pods, and Publish() on pod A won't reach the WS on pod B. Two options
// when scaling out:
//   1. Sticky session on ingress (clientIP / cookie hash) — same
//      session id → same pod. Simple, no inter-pod messaging needed.
//   2. Redis pub/sub fanout — postChat publishes to
//      "chat:session:<id>", every pod subscribes and forwards to its
//      local WS conns. Requires Redis but lets any pod terminate any
//      WS. Recommended once we hit ≥3 pods.
// For the initial WS rollout (1-2 pods, sticky ingress), option 1 is
// enough.
type ChatHub struct {
	mu      sync.RWMutex
	clients map[string]map[*ChatClient]struct{} // sessionID → set of clients
	globals map[*ChatClient]struct{}            // platform-wide subscribers
}

// ChatClient is the server-side handle for one WebSocket viewer. The
// `send` channel is buffered so a slow client doesn't block the hub
// goroutine — if the buffer fills (consumer is stuck), we drop the
// connection rather than back-pressure everyone else.
type ChatClient struct {
	SessionID string
	send      chan []byte
	done      chan struct{}
}

func NewChatHub() *ChatHub {
	return &ChatHub{
		clients: make(map[string]map[*ChatClient]struct{}),
		globals: make(map[*ChatClient]struct{}),
	}
}

// NewGlobalClient registers a subscriber to the platform-wide
// "list_change" feed. Returned client uses the same send/done channels
// as a per-session client — caller drains them the same way. The
// SessionID field is empty so Disconnect() routes back to globals.
func (h *ChatHub) NewGlobalClient(bufSize int) *ChatClient {
	c := &ChatClient{
		SessionID: "",
		send:      make(chan []byte, bufSize),
		done:      make(chan struct{}),
	}
	h.mu.Lock()
	h.globals[c] = struct{}{}
	count := len(h.globals)
	h.mu.Unlock()
	slog.Default().Info("ws: global client connected", "global_clients", count)
	return c
}

// PublishGlobal broadcasts to every global subscriber. Same drop-on-
// slow-consumer policy as Publish.
func (h *ChatHub) PublishGlobal(payload []byte) {
	h.mu.RLock()
	snap := make([]*ChatClient, 0, len(h.globals))
	for c := range h.globals {
		snap = append(snap, c)
	}
	h.mu.RUnlock()

	var dropped []*ChatClient
	for _, c := range snap {
		select {
		case c.send <- payload:
		default:
			dropped = append(dropped, c)
		}
	}
	for _, c := range dropped {
		slog.Default().Warn("ws: dropping slow global client")
		h.Disconnect(c)
	}
}

// NewClient registers a new WebSocket subscriber for `sessionID`. The
// returned client's Send channel emits JSON-encoded chat events; caller
// is responsible for marshalling each one out to the actual WS conn.
// `bufSize` is the send-channel depth — pick a value that absorbs a
// short message burst without dropping (32 covers a typical 10msg/s
// burst with a 3s consumer pause).
func (h *ChatHub) NewClient(sessionID string, bufSize int) *ChatClient {
	c := &ChatClient{
		SessionID: sessionID,
		send:      make(chan []byte, bufSize),
		done:      make(chan struct{}),
	}
	h.mu.Lock()
	if h.clients[sessionID] == nil {
		h.clients[sessionID] = make(map[*ChatClient]struct{})
	}
	h.clients[sessionID][c] = struct{}{}
	count := len(h.clients[sessionID])
	h.mu.Unlock()
	slog.Default().Info("ws: client connected",
		"session", sessionID, "session_clients", count)
	return c
}

// Send returns the channel a reader goroutine should drain to push
// messages onto the WS conn. Closes when Disconnect is called.
func (c *ChatClient) Send() <-chan []byte { return c.send }

// Done signals the WS write goroutine to exit when the hub has
// disconnected this client (e.g. on slow-consumer cleanup).
func (c *ChatClient) Done() <-chan struct{} { return c.done }

// Disconnect removes the client from the hub. Idempotent — calling
// twice is safe (the second close on `done` would panic, so we guard).
// Handles both per-session and global clients (SessionID == "").
func (h *ChatHub) Disconnect(c *ChatClient) {
	h.mu.Lock()
	if c.SessionID == "" {
		delete(h.globals, c)
	} else if set, ok := h.clients[c.SessionID]; ok {
		if _, present := set[c]; present {
			delete(set, c)
			if len(set) == 0 {
				delete(h.clients, c.SessionID)
			}
		}
	}
	h.mu.Unlock()
	select {
	case <-c.done:
		// already closed
	default:
		close(c.done)
		close(c.send)
	}
}

// Publish fans `payload` (already JSON-marshalled by the caller) out to
// every subscriber of `sessionID`. Non-blocking: if a client's send
// buffer is full we mark it for disconnect rather than wait. That way
// one stuck client can't pin the postChat handler.
func (h *ChatHub) Publish(sessionID string, payload []byte) {
	h.mu.RLock()
	set := h.clients[sessionID]
	// Snapshot the client list so we don't hold the lock while sending.
	snap := make([]*ChatClient, 0, len(set))
	for c := range set {
		snap = append(snap, c)
	}
	h.mu.RUnlock()

	var dropped []*ChatClient
	for _, c := range snap {
		select {
		case c.send <- payload:
		default:
			// Client's buffer full → slow consumer. Disconnect it
			// outside the loop so we don't grab the write lock now.
			dropped = append(dropped, c)
		}
	}
	for _, c := range dropped {
		slog.Default().Warn("ws: dropping slow client",
			"session", c.SessionID)
		h.Disconnect(c)
	}
}

// ClientCount returns how many WS subscribers are connected to a
// session. Useful for the host overlay "real viewer count" once we
// trust WS for presence (TODO).
func (h *ChatHub) ClientCount(sessionID string) int {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients[sessionID])
}
