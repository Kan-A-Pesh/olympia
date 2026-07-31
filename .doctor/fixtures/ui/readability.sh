mkdir -p apps/bad-app/src/ui
cat > apps/bad-app/src/ui/tiny-tile.tsx <<'INNER'
export function TinyTile() {
  return <span className="text-xs" style={{ fontSize: "11px", width: "320px" }}>x</span>
}
INNER
cat > apps/bad-app/src/ui/tiny-tile.css <<'INNER'
.reading { font-size: 0.75rem; }
.device-status.offline { color: #f00; }
.spinner { animation: turn 1s linear infinite; }
INNER
