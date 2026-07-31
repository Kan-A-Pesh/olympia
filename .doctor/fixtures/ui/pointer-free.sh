mkdir -p apps/bad-app/src/ui
cat > apps/bad-app/src/ui/pointer-tile.tsx <<'INNER'
export function PointerTile() {
  return (
    <div
      title="voltage"
      tabIndex={3}
      style={{ cursor: "pointer" }}
      onMouseEnter={() => reveal()}
      onClick={() => open()}
    >
      <span className="hover:opacity-100 outline-none">x</span>
    </div>
  )
}
INNER
cat > apps/bad-app/src/ui/pointer-tile.css <<'INNER'
.tile .badge { opacity: 0; }
.tile:hover .badge { opacity: 1; }
.tile { cursor: pointer; }
.tile:focus { outline: none; }
.tile-body { outline: 0; }
INNER
