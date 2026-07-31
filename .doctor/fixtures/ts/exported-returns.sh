cat > packages/bad-pkg/src/exported-returns.ts <<'INNER'
export function widen(value: number) {
  return value * 2
}
INNER
