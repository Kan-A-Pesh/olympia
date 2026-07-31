cat > packages/bad-pkg/src/nonce.ts <<'INNER'
export function nonce(): string {
  return Math.random().toString(36).slice(2)
}

export function stamp(): number {
  return Date.now()
}

export function legacy(size: number): Buffer {
  return new Buffer(size)
}
INNER
{
  i=1
  while [ "$i" -le 25 ]; do
    printf 'export type Shape%s = { a: number }\n' "$i"
    i=$((i + 1))
  done
} > packages/bad-pkg/src/god-file.ts
