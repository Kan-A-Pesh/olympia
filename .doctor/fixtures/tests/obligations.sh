cat > packages/bad-pkg/src/frame-codec.ts <<'INNER'
import { z } from "zod"

export const headerSchema = z.object({ id: z.string() })

export function encodeFrame(value: number): string {
  return String(value)
}

export function decodeFrame(text: string): number {
  return Number(text)
}

export function parseHeader(text: string): number {
  return Number(text)
}
INNER
cat > packages/bad-pkg/src/frame-codec.test.ts <<'INNER'
import { describe, expect, it } from "vitest"
import { decodeFrame, encodeFrame, headerSchema, parseHeader } from "./frame-codec.js"

describe("frame codec", () => {
  it("encodes a frame to text", () => {
    expect(encodeFrame(1)).toBe("1")
  })

  it("decodes a frame from text", () => {
    expect(decodeFrame("1")).toBe(1)
  })

  it("reads a header offset", () => {
    expect(parseHeader("2")).toBe(2)
  })

  it("accepts a valid header", () => {
    expect(headerSchema.parse({ id: "a" })).toEqual({ id: "a" })
  })
})
INNER
