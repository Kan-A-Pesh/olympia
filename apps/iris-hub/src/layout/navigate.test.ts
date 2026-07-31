import { describe, expect, it } from "vitest"
import { navigate, type Tile } from "./navigate.js"

const quadrants: Tile[] = [
  { id: "tl", rect: { x: 0, y: 0, w: 960, h: 540 } },
  { id: "tr", rect: { x: 960, y: 0, w: 960, h: 540 } },
  { id: "bl", rect: { x: 0, y: 540, w: 960, h: 540 } },
  { id: "br", rect: { x: 960, y: 540, w: 960, h: 540 } },
]

describe("spatial navigation", () => {
  it("moves along the cardinal axes", () => {
    expect(navigate(quadrants, "tl", "e")).toBe("tr")
    expect(navigate(quadrants, "tl", "s")).toBe("bl")
    expect(navigate(quadrants, "br", "w")).toBe("bl")
    expect(navigate(quadrants, "br", "n")).toBe("tr")
  })

  it("moves along the diagonals", () => {
    expect(navigate(quadrants, "tl", "se")).toBe("br")
    expect(navigate(quadrants, "br", "nw")).toBe("tl")
    expect(navigate(quadrants, "tr", "sw")).toBe("bl")
  })

  it("returns null at the edge rather than wrapping", () => {
    expect(navigate(quadrants, "tl", "n")).toBeNull()
    expect(navigate(quadrants, "tl", "w")).toBeNull()
    expect(navigate(quadrants, "br", "se")).toBeNull()
  })

  it("prefers the aligned tile over a nearer but strongly drifting one", () => {
    const tiles: Tile[] = [
      { id: "focus", rect: { x: 0, y: 400, w: 200, h: 200 } },
      { id: "aligned", rect: { x: 400, y: 400, w: 200, h: 200 } },
      { id: "drifting", rect: { x: 250, y: 200, w: 200, h: 200 } },
    ]
    expect(navigate(tiles, "focus", "e")).toBe("aligned")
  })

  it("excludes a tile sitting exactly on the diagonal boundary", () => {
    expect(navigate(quadrants, "tl", "se")).toBe("br")
    expect(navigate(quadrants, "tl", "e")).toBe("tr")
    expect(navigate(quadrants, "tl", "s")).toBe("bl")
  })

  it("ignores tiles outside the directional cone", () => {
    const tiles: Tile[] = [
      { id: "focus", rect: { x: 0, y: 0, w: 100, h: 100 } },
      { id: "steep", rect: { x: 50, y: 2000, w: 100, h: 100 } },
    ]
    expect(navigate(tiles, "focus", "e")).toBeNull()
    expect(navigate(tiles, "focus", "s")).toBe("steep")
  })

  it("picks the nearest tile when several are aligned", () => {
    const tiles: Tile[] = [
      { id: "focus", rect: { x: 0, y: 0, w: 100, h: 100 } },
      { id: "near", rect: { x: 200, y: 0, w: 100, h: 100 } },
      { id: "far", rect: { x: 800, y: 0, w: 100, h: 100 } },
    ]
    expect(navigate(tiles, "focus", "e")).toBe("near")
  })

  it("returns null for an unknown origin", () => {
    expect(navigate(quadrants, "nope", "e")).toBeNull()
  })

  it("returns null when it is the only tile", () => {
    expect(navigate([{ id: "solo", rect: { x: 0, y: 0, w: 1920, h: 1080 } }], "solo", "e")).toBeNull()
  })
})
