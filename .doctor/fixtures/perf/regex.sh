cat > packages/bad-pkg/src/perf-regex.ts <<'INNER'
export function each(items: string[]): string {
  for (const item of items) {
    const re = new RegExp("^a+$")
    if (/(a+)+$/.test(item)) return item
  }
  return ""
}
INNER

cat > packages/bad-pkg/src/waveform-parse.ts <<'INNER'
export function parseLabel(raw: string): string {
  return raw.replace(/[^a-z]+/g, "")
}
INNER
