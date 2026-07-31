mkdir -p packages/bad-pkg/src/tiles
cat > packages/bad-pkg/src/tiles/voltage-tile.tsx <<'INNER'
export function VoltageTile({ reading, device }) {
  const label = reading.value.toFixed(3)
  return (
    <section>
      <h2>Rigol DS1054Z</h2>
      <EncoderKnob label="Time base" />
      <span>{label}</span>
      <span>"V"</span>
      <time>{new Date(reading.at).toLocaleString()}</time>
      {device.isAuthenticated ? <Badge /> : null}
    </section>
  )
}
INNER
cat > packages/bad-pkg/src/tiles/trace-canvas.ts <<'INNER'
export function paintLegend(ctx: CanvasRenderingContext2D) {
  ctx.fillText("legend", 4, 12)
}
INNER
