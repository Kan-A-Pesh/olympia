mkdir -p apps/bad-app/src/store
cat > apps/bad-app/src/report-query.ts <<'INNER'
export const report = (key: string) => `SELECT * FROM settings WHERE key = ${key}`
INNER
cat > apps/bad-app/src/store/writes.ts <<'INNER'
export const insert = "INSERT INTO settings (key, value) VALUES (1, 2)"
export const update = "UPDATE settings SET value = 3"
export const remove = "DELETE FROM settings WHERE key = 4"
INNER
cat > apps/bad-app/src/store/sync.ts <<'INNER'
export const flush = (db: Db) =>
  db.transaction(async () => {
    db.prepare("UPDATE settings SET value = ? WHERE key = ?").run(1, 2)
    await fetch("https://example.test/sync")
  })()
INNER
