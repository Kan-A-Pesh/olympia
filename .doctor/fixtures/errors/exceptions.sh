cat > packages/bad-pkg/src/err-exceptions.ts <<'INNER'
export class DeviceError extends Error {
  readonly code = "DEVICE_DOWN"
}

export class ProbeError extends Error {
  readonly code = "DEVICE_DOWN"
}

export class QuietError {
  readonly label = "quiet"
}

export type Outcome = { ok: true; value: number } | { ok: false }

export function boom(token: string): number {
  try {
    return risky()
  } catch (e) {
    throw new Error(`bad token ${token}: ${e.message}`)
  }
}

export function show(err: Error): string {
  return `crash ${err.stack}`
}

export function quiet(): number | null {
  try {
    return risky()
  } catch (e) {
    return null
  }
}
INNER

cat > packages/bad-pkg/src/mqtt-transport.ts <<'INNER'
export function connect(): void {
  try {
    open()
  } catch (err) {
    return
  }
}
INNER
