cat > packages/bad-pkg/src/creds.ts <<'INNER'
export const url = "mqtt://broker.local:1883"
export const opts = { rejectUnauthorized: false }
INNER
