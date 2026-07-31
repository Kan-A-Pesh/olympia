cat > apps/bad-app/src/approve.ts <<'INNER'
import { readFileSync } from "node:fs"

export const brokerHost = process.env.BROKER_HOST ?? "localhost"

export function approve(query: { deviceId: string }, expected: string) {
  const fingerprint = readFileSync(`/etc/mosquitto/approved.d/${query.deviceId}.pem`, "utf8")
  return fingerprint === expected
}
INNER
