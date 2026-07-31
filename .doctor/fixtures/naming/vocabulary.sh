mkdir -p apps/bad-app/src/common
cat > apps/bad-app/src/common/date-helpers.ts <<'INNER'
export const SEED = 1
INNER
cat > apps/bad-app/src/vocabulary.ts <<'INNER'
export type DeviceInfo = {
  deviceID: string
  errMessage: string
}

export const tile = [1, 2, 3]

export function readTile(): number {
  const q = 3
  return q
}

export function getKind(): string {
  return "scope"
}

export async function payload(): Promise<string> {
  return "x"
}

export const errorHandler = (): void => undefined

export function shout(bus: { emit: (name: string) => void }): void {
  bus.emit("connect")
}
INNER
