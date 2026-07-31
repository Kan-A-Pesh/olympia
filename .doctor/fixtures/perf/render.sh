cat > packages/bad-pkg/src/perf-render.ts <<'INNER'
export async function drawTrace(ctx: CanvasRenderingContext2D, samples: Uint8Array): Promise<void> {
  const ordered = Array.from(samples).sort()
  const box = ctx.canvas.getBoundingClientRect()
  await Promise.resolve()
  for (const s of ordered) ctx.lineTo(s, box.top + s)
}
INNER
