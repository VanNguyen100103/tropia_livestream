// Command migrate is an in-tree wrapper around golang-migrate/v4 so
// developers and CI/CD don't need to install the standalone `migrate.exe`
// binary. SQL files live in ./migrations/ and follow the standard
// <version>_<name>.{up,down}.sql convention.
//
// Reads DATABASE_URL from .env.development (or .env) on startup.
//
// Usage:
//   go run ./cmd/migrate up                     # apply all pending
//   go run ./cmd/migrate down 1                 # rollback last N (default 1)
//   go run ./cmd/migrate down all               # rollback EVERYTHING
//   go run ./cmd/migrate version                # show current version
//   go run ./cmd/migrate force 1                # mark version (recover dirty state)
//   go run ./cmd/migrate goto 3                 # migrate to a specific version
//   go run ./cmd/migrate create <name>          # generate empty migration pair
package main

import (
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"strconv"
	"time"

	"github.com/golang-migrate/migrate/v4"
	_ "github.com/golang-migrate/migrate/v4/database/postgres"
	_ "github.com/golang-migrate/migrate/v4/source/file"
	"github.com/joho/godotenv"
)

const migrationsDir = "migrations"

func main() {
	log.SetFlags(0) // tidy CLI output

	if len(os.Args) < 2 {
		printUsage()
		os.Exit(2)
	}

	cmd := os.Args[1]
	args := os.Args[2:]

	// Load env (skip for `create` since it doesn't need a DB).
	if cmd != "create" {
		for _, f := range []string{".env.development", ".env"} {
			if _, err := os.Stat(f); err == nil {
				_ = godotenv.Load(f)
				break
			}
		}
	}

	switch cmd {
	case "up":
		runMigrate(func(m *migrate.Migrate) error { return m.Up() })
	case "down":
		n := 1
		if len(args) > 0 {
			if args[0] == "all" {
				runMigrate(func(m *migrate.Migrate) error { return m.Down() })
				return
			}
			parsed, err := strconv.Atoi(args[0])
			if err != nil {
				log.Fatalf("invalid step count: %v", err)
			}
			n = parsed
		}
		runMigrate(func(m *migrate.Migrate) error { return m.Steps(-n) })
	case "goto":
		if len(args) < 1 {
			log.Fatal("usage: migrate goto <version>")
		}
		v, err := strconv.ParseUint(args[0], 10, 32)
		if err != nil {
			log.Fatalf("invalid version: %v", err)
		}
		runMigrate(func(m *migrate.Migrate) error { return m.Migrate(uint(v)) })
	case "version", "status":
		runMigrate(func(m *migrate.Migrate) error {
			v, dirty, err := m.Version()
			if errors.Is(err, migrate.ErrNilVersion) {
				log.Println("no migrations applied yet")
				return nil
			}
			if err != nil {
				return err
			}
			log.Printf("version=%d dirty=%v", v, dirty)
			return nil
		})
	case "force":
		if len(args) < 1 {
			log.Fatal("usage: migrate force <version>")
		}
		v, err := strconv.Atoi(args[0])
		if err != nil {
			log.Fatalf("invalid version: %v", err)
		}
		runMigrate(func(m *migrate.Migrate) error { return m.Force(v) })
	case "create":
		if len(args) < 1 {
			log.Fatal("usage: migrate create <name>")
		}
		if err := createMigration(args[0]); err != nil {
			log.Fatalf("create: %v", err)
		}
	default:
		printUsage()
		os.Exit(2)
	}
}

func runMigrate(fn func(*migrate.Migrate) error) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL not set (check .env.development)")
	}

	// `file://` source requires forward slashes even on Windows.
	src, err := filepath.Abs(migrationsDir)
	if err != nil {
		log.Fatalf("resolve migrations path: %v", err)
	}
	sourceURL := "file://" + filepath.ToSlash(src)

	m, err := migrate.New(sourceURL, dsn)
	if err != nil {
		log.Fatalf("open migrate: %v", err)
	}
	defer func() {
		if srcErr, dbErr := m.Close(); srcErr != nil || dbErr != nil {
			log.Printf("close: source=%v db=%v", srcErr, dbErr)
		}
	}()

	start := time.Now()
	err = fn(m)
	switch {
	case err == nil:
		log.Printf("✅ ok (%s)", time.Since(start).Round(time.Millisecond))
	case errors.Is(err, migrate.ErrNoChange):
		log.Println("no change — already up to date")
	default:
		log.Fatalf("❌ %v", err)
	}
}

func createMigration(name string) error {
	if err := os.MkdirAll(migrationsDir, 0o755); err != nil {
		return err
	}
	// Find next sequence number.
	entries, err := os.ReadDir(migrationsDir)
	if err != nil {
		return err
	}
	next := 1
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		var n int
		if _, err := fmt.Sscanf(e.Name(), "%04d_", &n); err == nil && n >= next {
			next = n + 1
		}
	}

	prefix := fmt.Sprintf("%04d_%s", next, name)
	upPath := filepath.Join(migrationsDir, prefix+".up.sql")
	downPath := filepath.Join(migrationsDir, prefix+".down.sql")

	for _, p := range []string{upPath, downPath} {
		if _, err := os.Stat(p); err == nil {
			return fmt.Errorf("%s already exists", p)
		}
	}

	upBody := fmt.Sprintf("-- Migration %04d %s — up\n-- TODO: write the forward change\n", next, name)
	downBody := fmt.Sprintf("-- Migration %04d %s — down\n-- TODO: write the exact reversal of the up migration\n", next, name)

	if err := os.WriteFile(upPath, []byte(upBody), 0o644); err != nil {
		return err
	}
	if err := os.WriteFile(downPath, []byte(downBody), 0o644); err != nil {
		return err
	}
	log.Printf("created %s", upPath)
	log.Printf("created %s", downPath)
	return nil
}

func printUsage() {
	fmt.Fprintln(os.Stderr, `Usage: migrate <command> [args]

Commands:
  up                Apply all pending migrations
  down [N|all]      Rollback last N migrations (default 1; "all" for everything)
  goto <version>    Migrate up or down to a specific version
  version           Show current applied version + dirty flag
  status            Alias for "version"
  force <version>   Mark a specific version as applied (recover from dirty state)
  create <name>     Create empty up/down SQL files at the next sequence number

Reads DATABASE_URL from .env.development (except for "create").`)
}
