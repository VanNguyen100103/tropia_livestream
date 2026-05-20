# Database migrations

Schema changes are tracked here as numbered files. Use
[golang-migrate](https://github.com/golang-migrate/migrate) to apply them.

## Layout

```
migrations/
├── 0001_initial_schema.up.sql       Initial 20-table schema + triggers + RPCs
├── 0001_initial_schema.down.sql     Rollback (drops everything)
├── 0002_<name>.up.sql               Future migration
├── 0002_<name>.down.sql             ...
└── ...
```

Each migration is a pair of SQL files:
- `<version>_<name>.up.sql` applies the change.
- `<version>_<name>.down.sql` reverts it.

`golang-migrate` tracks applied versions in a `schema_migrations` table
that it creates automatically on first run.

## Install golang-migrate

| OS | Command |
|---|---|
| Windows (Scoop) | `scoop install migrate` |
| Windows (Choco) | `choco install migrate` |
| macOS | `brew install golang-migrate` |
| Linux | `apt install golang-migrate` (or download release) |
| Manual | https://github.com/golang-migrate/migrate/releases |

Verify: `migrate -version`

## Common tasks

The `Makefile` (Unix-like) and `scripts/migrate.ps1` (Windows) wrap the
common operations and read `DATABASE_URL` from `.env.development`.

```bash
# Apply all pending migrations
make migrate-up
# or on Windows:
.\scripts\migrate.ps1 up

# Roll back the most recent migration
make migrate-down
.\scripts\migrate.ps1 down

# Show current version
make migrate-status
.\scripts\migrate.ps1 status

# Create a new migration pair (e.g. add a phone column)
make migrate-create name=add_phone_to_profiles
.\scripts\migrate.ps1 create add_phone_to_profiles
```

The `create` command produces two empty files like:

```
0002_add_phone_to_profiles.up.sql
0002_add_phone_to_profiles.down.sql
```

Edit them, then `migrate-up`.

## Workflow

1. **Develop locally**: edit Go code, decide DB needs change.
2. **Create migration**: `make migrate-create name=...` (or `.\scripts\migrate.ps1 create ...`).
3. **Write up + down SQL**: forward change in `.up.sql`, exact reversal in `.down.sql`.
4. **Apply**: `make migrate-up`. Postgres now has the new schema.
5. **Test**: run backend, exercise new code path.
6. **Commit**: both `.up.sql` and `.down.sql` go to git.
7. **Deploy**: in CI/CD or `kubectl exec`, run `make migrate-up` against staging/prod.

## Dirty state recovery

If a migration fails mid-way, `golang-migrate` marks the version as
"dirty" and refuses to proceed. Fix the SQL manually in Postgres, then:

```bash
make migrate-force ver=<the_version_that_failed>
```

This marks the version as clean without re-running it.

## Production (Supabase)

The first time you target a Supabase project that already has the schema
applied (e.g. via SQL Editor paste from `init.sql`):

```bash
# Tell migrate "we're already at version 1, don't re-run 0001"
make migrate-force ver=1
```

Subsequent migrations (`0002`, `0003`, ...) will apply normally.

## Notes

- `infra/postgres/init.sql` is kept as a convenience for Docker Compose
  (which runs it on first volume init). It mirrors `0001_initial_schema.up.sql`.
  When you add `0002`+, the **migrations folder becomes the source of truth**
  — re-generate `init.sql` from migrations if you want fresh Docker boots to
  match production.
- Migrations should be **idempotent where possible** (use `IF NOT EXISTS`,
  `IF EXISTS`), but the `schema_migrations` table prevents double-apply.
