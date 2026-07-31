cat > packages/bad-pkg/src/perf-codec.ts <<'INNER'
export function drawFrame(span: number): number {
  const scratch = new Float32Array(span)
  return scratch.length
}
INNER
