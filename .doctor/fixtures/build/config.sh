mkdir -p apps/bad-app/src
cat > apps/bad-app/src/broker.ts <<'INNER'
export const brokerUrl = "mqtts://localhost:8883"
export const httpPort = 8080
export const apiToken = process.env.API_TOKEN ?? "fallback-token-value"
INNER
