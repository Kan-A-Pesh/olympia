cat > apps/bad-app/src/gauge-tile.tsx <<'INNER'
export function GaugeTile({ value }: { value: number }) {
  return <div className="tile">{value}</div>
}
INNER
