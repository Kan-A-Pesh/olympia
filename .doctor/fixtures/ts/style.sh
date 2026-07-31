cat > packages/bad-pkg/src/style.ts <<'INNER'
export enum Mode {
  Idle,
  Busy,
}

export type Loose = string | any

export default function boot(mode: Mode) {
  let label = "boot"
  let total = 0
  for (const step of [1, 2]) total += step
  return `${label}:${total}:${lookup(mode)!.id}`
}
INNER
