mkdir -p apps/bad-app/src/migrations
cat > apps/bad-app/src/migrations/create-tables.sql <<'INNER'
CREATE TABLE measurements (id INTEGER PRIMARY KEY, frame BLOB);
INNER
