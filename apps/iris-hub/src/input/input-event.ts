export const EV_SYN = 0
export const EV_KEY = 1
export const EV_REL = 2
export const REL_X = 0

export const KEY_RELEASE = 0
export const KEY_PRESS = 1
export const KEY_REPEAT = 2

export type InputEvent = {
  timeMs: number
  type: number
  code: number
  value: number
}

export type WordSize = 32 | 64

export const structSize = (words: WordSize): number => (words === 64 ? 24 : 16)

export function detectWordSize(arch: string = process.arch): WordSize {
  return arch === "arm64" || arch === "x64" || arch === "ppc64" || arch === "s390x" ? 64 : 32
}

export class InputEventParser {
  readonly #size: number
  readonly #words: WordSize
  #pending: Buffer = Buffer.alloc(0)

  constructor(words: WordSize = detectWordSize()) {
    this.#words = words
    this.#size = structSize(words)
  }

  push(chunk: Buffer): InputEvent[] {
    const buffer = this.#pending.length === 0 ? chunk : Buffer.concat([this.#pending, chunk])
    const complete = Math.floor(buffer.length / this.#size)
    const events: InputEvent[] = []

    for (let i = 0; i < complete; i++) {
      events.push(this.#read(buffer, i * this.#size))
    }

    this.#pending = buffer.subarray(complete * this.#size)
    return events
  }

  #read(buffer: Buffer, offset: number): InputEvent {
    if (this.#words === 64) {
      const sec = buffer.readBigInt64LE(offset)
      const usec = buffer.readBigInt64LE(offset + 8)
      return {
        timeMs: Number(sec) * 1000 + Number(usec) / 1000,
        type: buffer.readUInt16LE(offset + 16),
        code: buffer.readUInt16LE(offset + 18),
        value: buffer.readInt32LE(offset + 20),
      }
    }
    return {
      timeMs: buffer.readInt32LE(offset) * 1000 + buffer.readInt32LE(offset + 4) / 1000,
      type: buffer.readUInt16LE(offset + 8),
      code: buffer.readUInt16LE(offset + 10),
      value: buffer.readInt32LE(offset + 12),
    }
  }
}
