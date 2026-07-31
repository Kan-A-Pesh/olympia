cat > apps/bad-app/src/store-open.ts <<'INNER'
import Database from "better-sqlite3"

export function openDatabase() {
  const db = new Database("/tmp/olympia.db")
  db.pragma("journal_mode = DELETE")
  return db
}
INNER
