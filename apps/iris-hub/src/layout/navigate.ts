import { step, type Direction } from "../input/panel.js"

export interface Rect {
  x: number
  y: number
  w: number
  h: number
}

export interface Tile {
  id: string
  rect: Rect
}

const MAX_OFF_AXIS_DEGREES = 44
const CONE = Math.tan((MAX_OFF_AXIS_DEGREES * Math.PI) / 180)
const DRIFT_PENALTY = 2

const centre = (r: Rect): [number, number] => [r.x + r.w / 2, r.y + r.h / 2]

export function navigate(tiles: Tile[], fromId: string, direction: Direction): string | null {
  const from = tiles.find((tile) => tile.id === fromId)
  if (!from) return null

  const [dx, dy] = step(direction)
  const length = Math.hypot(dx, dy)
  const ux = dx / length
  const uy = dy / length
  const [fx, fy] = centre(from.rect)

  let best: string | null = null
  let bestScore = Number.POSITIVE_INFINITY

  for (const tile of tiles) {
    if (tile.id === fromId) continue

    const [cx, cy] = centre(tile.rect)
    const vx = cx - fx
    const vy = cy - fy

    const along = vx * ux + vy * uy
    if (along <= 0) continue

    const across = Math.abs(vx * uy - vy * ux)
    if (across > along * CONE) continue

    const score = along + across * DRIFT_PENALTY
    if (score < bestScore) {
      bestScore = score
      best = tile.id
    }
  }

  return best
}
