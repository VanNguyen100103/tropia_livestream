// Command bake-test runs vod.Bake on an existing session's recording
// without needing to re-record a live. Use it to iterate on the bake
// pipeline quickly:
//
//	go run ./cmd/bake-test <session-id>
//
// It pulls live_sessions.vod_mp4_url, downloads the raw MP4 to a temp
// file, loads chat + events from DB, and runs the bake. The output
// lands at ./bake-out/<session-id>.mp4 so you can play it locally.
package main

import (
	"context"
	"fmt"
	"io"
	"log"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"time"

	"github.com/google/uuid"
	"github.com/joho/godotenv"

	"github.com/tropia/backend/internal/config"
	"github.com/tropia/backend/internal/database"
	"github.com/tropia/backend/internal/live"
	"github.com/tropia/backend/internal/vod"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: bake-test <session-id>")
		os.Exit(2)
	}
	sid, err := uuid.Parse(os.Args[1])
	if err != nil {
		log.Fatalf("invalid session id: %v", err)
	}

	for _, f := range []string{".env.development", ".env"} {
		if _, err := os.Stat(f); err == nil {
			_ = godotenv.Load(f)
			break
		}
	}

	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	ctx := context.Background()
	db, err := database.NewPostgres(ctx, cfg.DatabaseURL)
	if err != nil {
		log.Fatalf("pg: %v", err)
	}
	defer db.Close()

	sessRepo := live.NewSessionRepository(db)
	eventsRepo := live.NewEventRepository(db)

	sess, err := sessRepo.GetByID(ctx, sid)
	if err != nil {
		log.Fatalf("get session: %v", err)
	}
	// Only need vod_mp4_url if we'll be downloading the source. If
	// caller supplied a local FLV path as argv[2], we skip the URL.
	if len(os.Args) < 3 && (sess.VodMp4URL == nil || *sess.VodMp4URL == "") {
		log.Fatalf("session has no vod_mp4_url — supply a local FLV path as 2nd arg")
	}
	if sess.VodMp4URL != nil {
		log.Printf("session: %s | started=%s | vod=%s", sess.Title, sess.StartedAt, *sess.VodMp4URL)
	} else {
		log.Printf("session: %s | started=%s | (no R2 url; using local source)", sess.Title, sess.StartedAt)
	}

	chats, _ := sessRepo.TimelineChats(ctx, sid, 10000)
	evts, _ := eventsRepo.ListBySession(ctx, sid)
	products, _ := sessRepo.ListProducts(ctx, sid)
	log.Printf("loaded: %d chats, %d events, %d products", len(chats), len(evts), len(products))

	var videoDur time.Duration
	if sess.EndedAt != nil {
		videoDur = sess.EndedAt.Sub(sess.StartedAt)
	}

	outDir, _ := filepath.Abs("./bake-out")
	_ = os.MkdirAll(outDir, 0o755)

	// Source: 2nd CLI arg overrides DB lookup. Useful when R2 MP4 was
	// deleted but the FLV still exists in infra/dvr/live/.
	var srcFile string
	if len(os.Args) >= 3 {
		srcFile, err = filepath.Abs(os.Args[2])
		if err != nil {
			log.Fatalf("resolve src: %v", err)
		}
		log.Printf("using local source → %s", srcFile)
	} else {
		srcFile = filepath.Join(outDir, sid.String()+"-src.mp4")
		if err := download(*sess.VodMp4URL, srcFile); err != nil {
			log.Fatalf("download: %v", err)
		}
		log.Printf("downloaded raw → %s", srcFile)
	}

	workDir := filepath.Join(outDir, "work-"+sid.String())
	bakedPath, err := vod.Bake(ctx, vod.BakeInput{
		SessionID:     sid,
		FLVPath:       srcFile, // ffmpeg auto-detects format; MP4/FLV both work
		SessionStart:  sess.StartedAt,
		Chats:         chats,
		Events:        evts,
		Products:      products,
		VideoDuration: videoDur,
		WorkDir:       workDir,
		Logger:        slog.Default(),
	})
	if err != nil {
		log.Fatalf("bake: %v", err)
	}

	final := filepath.Join(outDir, sid.String()+".mp4")
	if err := os.Rename(bakedPath, final); err != nil {
		// Cross-volume rename can fail — fall back to copy.
		if err := copyFile(bakedPath, final); err != nil {
			log.Fatalf("move out: %v", err)
		}
	}
	_ = os.RemoveAll(workDir)
	// Only delete srcFile if we downloaded it ourselves — don't nuke
	// a user-supplied path.
	if len(os.Args) < 3 {
		_ = os.Remove(srcFile)
	}
	log.Printf("DONE → %s", final)
}

func download(url, dst string) error {
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode/100 != 2 {
		return fmt.Errorf("http %d", resp.StatusCode)
	}
	f, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer f.Close()
	_, err = io.Copy(f, resp.Body)
	return err
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, in)
	return err
}
