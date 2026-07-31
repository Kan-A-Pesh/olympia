cat > apps/bad-app/src/units.ts <<'INNER'
export const RECONNECT_DELAY = 250

export type Probe = {
  sampleRate: number
  timeout: number
}

export function arm(duration: number): number {
  return duration
}
INNER
