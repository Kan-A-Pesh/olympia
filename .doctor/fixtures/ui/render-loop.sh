mkdir -p apps/bad-app/src/render
cat > apps/bad-app/src/render/trace.ts <<'INNER'
export function drawFrame(canvas: HTMLCanvasElement) {
  const ctx = canvas.getContext("2d")
  canvas.width = window.innerWidth
  const points = samples.map((s) => s * 2)
  const label = points.length.toFixed(2)
  document.querySelector(".legend").textContent = label
  requestAnimationFrame(() => drawFrame(canvas))
}
setInterval(() => drawFrame(node), 16)
INNER
cat > apps/bad-app/src/render/second-loop.ts <<'INNER'
export function startCursor() {
  requestAnimationFrame(startCursor)
}
INNER
