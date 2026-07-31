cat > packages/bad-pkg/src/perf-samples.ts <<'INNER'
export type Trace = {
  samples: number[]
}

export function copy(samples: Uint8Array) {
  const plain = Array.from(samples)
  const spread = [...samples]
  const doubled = samples.map((s) => s * 2)
  const head = samples.slice(0, 10)
  return structuredClone({ plain, spread, doubled, head })
}
INNER
