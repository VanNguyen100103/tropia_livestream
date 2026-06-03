package config

import "testing"

func TestRequireDatabaseTLS(t *testing.T) {
	cases := []struct {
		name    string
		url     string
		wantErr bool
	}{
		// In-cluster / dev: always allowed regardless of sslmode.
		{"localhost no sslmode", "postgres://u:p@localhost:5432/db", false},
		{"localhost disable", "postgres://u:p@localhost:5432/db?sslmode=disable", false},
		{"k8s service single-label", "postgres://u:p@pgbouncer:6432/db?sslmode=disable", false},
		{"k8s fqdn", "postgres://u:p@db.svc.cluster.local:5432/db?sslmode=disable", false},
		{"loopback v4", "postgres://u:p@127.0.0.1:5432/db?sslmode=disable", false},

		// External hosts must have TLS.
		{"supabase require", "postgres://u:p@db.x.supabase.co:5432/db?sslmode=require", false},
		{"supabase verify-full", "postgres://u:p@db.x.supabase.co:5432/db?sslmode=verify-full", false},
		{"supabase disable", "postgres://u:p@db.x.supabase.co:5432/db?sslmode=disable", true},
		{"supabase prefer", "postgres://u:p@db.x.supabase.co:5432/db?sslmode=prefer", true},
		{"supabase missing sslmode", "postgres://u:p@db.x.supabase.co:5432/db", true},
		{"rds disable", "postgres://u:p@rds.amazonaws.com:5432/db?sslmode=disable", true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			err := requireDatabaseTLS(tc.url)
			if (err != nil) != tc.wantErr {
				t.Fatalf("requireDatabaseTLS(%q) err=%v wantErr=%v", tc.url, err, tc.wantErr)
			}
		})
	}
}
