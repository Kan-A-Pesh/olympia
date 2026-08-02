import { readFileSync, writeFileSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { dirname, join } from "node:path"

const here = dirname(fileURLToPath(import.meta.url))
const obj = readFileSync(join(here, "iris-hub-case.obj"), "utf8")

const STROKE = {
  base: "#8b9098",
  cradle: "#5f646b",
  "edp-slot": "#e45a40",
  screen: "#2b3038",
  encoders: "#c9a83d",
  pad: "#4a8ccc",
  usb: "#3faa79",
  split: "#d05fd0",
  internals: "#7a6a52",
  feet: "#7a8590",
}

const verts = []
const edgesByGroup = new Map()
let group = "base"

for (const line of obj.split("\n")) {
  if (line.startsWith("v ")) {
    const [, x, y, z] = line.split(/\s+/)
    verts.push([Number(x), Number(y), Number(z)])
  } else if (line.startsWith("g ")) {
    group = line.slice(2).trim()
    if (!edgesByGroup.has(group)) edgesByGroup.set(group, new Set())
  } else if (line.startsWith("f ")) {
    const idx = line.slice(2).trim().split(/\s+/).map((n) => Number(n.split("/")[0]) - 1)
    const set = edgesByGroup.get(group)
    for (let i = 0; i < idx.length; i++) {
      const a = idx[i]
      const b = idx[(i + 1) % idx.length]
      if (a === b) continue
      set.add(a < b ? `${a}:${b}` : `${b}:${a}`)
    }
  }
}

const PROJECTIONS = {
  face: ([x, y]) => [x, -y],
  profil: ([, y, z]) => [z, -y],
  dessus: ([x, , z]) => [x, z],
  iso: ([x, y, z]) => {
    const a = Math.PI / 6
    return [(x - z) * Math.cos(a), -y + (x + z) * Math.sin(a) * 0.5]
  },
}

function renderView(name, project, width, height) {
  const paths = []
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity

  for (const [g, edges] of edgesByGroup) {
    const segs = []
    for (const key of edges) {
      const [a, b] = key.split(":").map(Number)
      const p = project(verts[a])
      const q = project(verts[b])
      for (const [px, py] of [p, q]) {
        if (px < minX) minX = px
        if (px > maxX) maxX = px
        if (py < minY) minY = py
        if (py > maxY) maxY = py
      }
      segs.push(`M${p[0].toFixed(1)} ${p[1].toFixed(1)}L${q[0].toFixed(1)} ${q[1].toFixed(1)}`)
    }
    paths.push({ g, d: segs.join("") })
  }

  const pad = 20
  const sx = (width - pad * 2) / (maxX - minX)
  const sy = (height - pad * 2) / (maxY - minY)
  const s = Math.min(sx, sy)
  const tx = pad - minX * s
  const ty = pad - minY * s

  const body = paths
    .map(({ g, d }) => `<path d="${d}" stroke="${STROKE[g] ?? "#888"}" stroke-width="${(0.9 / s).toFixed(3)}" fill="none"/>`)
    .join("\n    ")

  return `<g transform="translate(${tx.toFixed(1)} ${ty.toFixed(1)}) scale(${s.toFixed(4)})">
    ${body}
  </g>
  <text x="10" y="18" fill="#9aa0a8" font-family="ui-monospace,monospace" font-size="12">${name}</text>`
}

const W = 520
const H = 380
const views = Object.entries(PROJECTIONS)
const cells = views.map(([name, project], i) => {
  const col = i % 2
  const row = Math.floor(i / 2)
  return `<g transform="translate(${col * W} ${row * H})">
  <rect width="${W}" height="${H}" fill="#14161a" stroke="#2a2e34"/>
  ${renderView(name, project, W, H)}
  </g>`
})

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${W * 2}" height="${H * 2}" viewBox="0 0 ${W * 2} ${H * 2}">
<rect width="100%" height="100%" fill="#14161a"/>
${cells.join("\n")}
</svg>
`

writeFileSync(join(here, "wireframe.svg"), svg)
console.log(`wireframe.svg — ${verts.length} sommets, ${edgesByGroup.size} groupes`)
