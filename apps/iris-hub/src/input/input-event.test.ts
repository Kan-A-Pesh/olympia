import { describe, expect, it } from "vitest"
import { EV_KEY, EV_REL, InputEventParser, REL_X, structSize, type WordSize } from "./input-event.js"

function event(words: WordSize, type: number, code: number, value: number, sec = 1, usec = 500_000): Buffer {
  const buffer = Buffer.alloc(structSize(words))
  if (words === 64) {
    buffer.writeBigInt64LE(BigInt(sec), 0)
    buffer.writeBigInt64LE(BigInt(usec), 8)
    buffer.writeUInt16LE(type, 16)
    buffer.writeUInt16LE(code, 18)
    buffer.writeInt32LE(value, 20)
  } else {
    buffer.writeInt32LE(sec, 0)
    buffer.writeInt32LE(usec, 4)
    buffer.writeUInt16LE(type, 8)
    buffer.writeUInt16LE(code, 10)
    buffer.writeInt32LE(value, 12)
  }
  return buffer
}

describe("input event parser", () => {
  it("reads a 64-bit rotation event", () => {
    const [parsed] = new InputEventParser(64).push(event(64, EV_REL, REL_X, 1))
    expect(parsed).toEqual({ timeMs: 1500, type: EV_REL, code: REL_X, value: 1 })
  })

  it("reads a 32-bit rotation event", () => {
    const [parsed] = new InputEventParser(32).push(event(32, EV_REL, REL_X, -1))
    expect(parsed).toEqual({ timeMs: 1500, type: EV_REL, code: REL_X, value: -1 })
  })

  it("reads several events from one chunk", () => {
    const chunk = Buffer.concat([event(64, EV_REL, REL_X, 1), event(64, EV_REL, REL_X, -1)])
    expect(new InputEventParser(64).push(chunk).map((e) => e.value)).toEqual([1, -1])
  })

  it("holds back a partial event until the rest arrives", () => {
    const parser = new InputEventParser(64)
    const full = event(64, EV_KEY, 187, 1)

    expect(parser.push(full.subarray(0, 10))).toHaveLength(0)
    const [parsed] = parser.push(full.subarray(10))
    expect(parsed).toMatchObject({ type: EV_KEY, code: 187, value: 1 })
  })

  it("keeps the remainder across a chunk boundary", () => {
    const parser = new InputEventParser(64)
    const stream = Buffer.concat([event(64, EV_REL, REL_X, 1), event(64, EV_REL, REL_X, 1)])

    expect(parser.push(stream.subarray(0, 30))).toHaveLength(1)
    expect(parser.push(stream.subarray(30))).toHaveLength(1)
  })

  it("reports negative rotation as a signed value", () => {
    const [parsed] = new InputEventParser(64).push(event(64, EV_REL, REL_X, -3))
    expect(parsed?.value).toBe(-3)
  })
})
