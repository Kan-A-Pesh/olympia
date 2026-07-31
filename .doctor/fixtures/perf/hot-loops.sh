cat > packages/bad-pkg/src/perf-hot-loops.ts <<'INNER'
export function scan(samples: Uint16Array, out: Map<string, number>): void {
  for (let i = 0; i < samples.length; i++) {
    const boxed = new Object()
    out.set(`k${i}`, i)
    const later = () => i
    createHash("sha1").update(String(i))
  }
}
INNER
