cat > packages/bad-pkg/src/waveform-log.ts <<'INNER'
import { logger } from "./log.js"

export function trace(frame: Uint8Array, password: string): void {
  logger.info(`decoded ${frame.length} samples ✅`)
  logger.log("no level " + password)
  logger.debug({ fingerprint: "abcdef0123456789abcdef" })
}
INNER
