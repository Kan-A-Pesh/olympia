import { describe, expect, it } from "vitest"
import { SigrokStreamParser } from "./parser.js"
import { ANALOG_BIAS, parseCalibration, parseIdentity, toVolts } from "./protocol.js"

const encode = (...values: number[]): Uint8Array =>
  Uint8Array.from(values.map((v) => (v & 0x7f) | ANALOG_BIAS))

const ascii = (text: string): Uint8Array =>
  Uint8Array.from([...text].map((c) => c.charCodeAt(0)))

const concat = (...parts: Uint8Array[]): Uint8Array => {
  const total = parts.reduce((sum, p) => sum + p.length, 0)
  const out = new Uint8Array(total)
  let offset = 0
  for (const part of parts) {
    out.set(part, offset)
    offset += part.length
  }
  return out
}

describe("identité", () => {
  it("décode la réponse du firmware", () => {
    expect(parseIdentity("SRPICO,A031D21,02")).toEqual({
      analogChannels: 3,
      analogBytesPerSample: 1,
      digitalChannels: 21,
      version: "02",
    })
  })

  it("accepte une réponse sans terminateur, comme l envoie le firmware", () => {
    expect(parseIdentity("SRPICO,A001D32,02").digitalChannels).toBe(32)
  })

  it("rejette une réponse étrangère", () => {
    expect(() => parseIdentity("PONG")).toThrow(/identité illisible/)
  })
})

describe("calibration", () => {
  it("convertit les microvolts en volts", () => {
    expect(parseCalibration("25700x0")).toEqual({ scaleV: 0.0257, offsetV: 0 })
  })

  it("accepte un décalage négatif", () => {
    expect(parseCalibration("25700x-1650000").offsetV).toBe(-1.65)
  })

  it("rejette une réponse malformée", () => {
    expect(() => parseCalibration("beaucoup")).toThrow(/calibration illisible/)
    expect(() => parseCalibration("25700")).toThrow(/calibration illisible/)
  })

  it("convertit un octet brut en volts", () => {
    const calibration = { scaleV: 0.0257, offsetV: 0 }
    expect(toVolts(ANALOG_BIAS, calibration)).toBe(0)
    expect(toVolts(ANALOG_BIAS + 127, calibration)).toBeCloseTo(3.2639, 4)
  })
})

describe("flux analogique", () => {
  it("décode une voie", () => {
    const parser = new SigrokStreamParser({ analogChannels: 1 })
    const { analog } = parser.push(encode(0, 10, 20, 30))
    expect(Array.from(analog[0]!)).toEqual([0x80, 0x8a, 0x94, 0x9e])
  })

  it("démultiplexe trois voies entrelacées", () => {
    const parser = new SigrokStreamParser({ analogChannels: 3 })
    const { analog } = parser.push(encode(1, 2, 3, 4, 5, 6))
    expect(Array.from(analog[0]!)).toEqual([0x81, 0x84])
    expect(Array.from(analog[1]!)).toEqual([0x82, 0x85])
    expect(Array.from(analog[2]!)).toEqual([0x83, 0x86])
  })

  it("garde un instant coupé en travers de deux morceaux", () => {
    const parser = new SigrokStreamParser({ analogChannels: 3 })
    const stream = encode(1, 2, 3, 4, 5, 6)

    const first = parser.push(stream.subarray(0, 4))
    expect(first.analog[0]!.length).toBe(1)

    const second = parser.push(stream.subarray(4))
    expect(Array.from(second.analog[1]!)).toEqual([0x85])
  })

  it("réserve les octets numériques avant les voies analogiques", () => {
    const parser = new SigrokStreamParser({ analogChannels: 1, digitalChannels: 7 })
    const { analog } = parser.push(encode(0x7f, 5, 0x7f, 6))
    expect(Array.from(analog[0]!)).toEqual([0x85, 0x86])
  })
})

describe("fin de capture", () => {
  it("reconnaît la fin annoncée et compare les compteurs", () => {
    const parser = new SigrokStreamParser({ analogChannels: 1 })
    const result = parser.push(concat(encode(1, 2, 3, 4), ascii("$4+")))

    expect(result.completed).toEqual({ declaredBytes: 4, receivedBytes: 4 })
    expect(parser.isFinished).toBe(true)
  })

  it("signale un écart entre octets annoncés et reçus", () => {
    const parser = new SigrokStreamParser({ analogChannels: 1 })
    const result = parser.push(concat(encode(1, 2), ascii("$4096+")))
    expect(result.completed?.declaredBytes).toBe(4096)
    expect(result.completed?.receivedBytes).toBe(2)
  })

  it("distingue un abandon d une fin propre", () => {
    const parser = new SigrokStreamParser({ analogChannels: 1 })
    const result = parser.push(concat(encode(1, 2), ascii("!!!")))

    expect(result.completed).toBeUndefined()
    expect(result.aborted?.byte).toBe("!".charCodeAt(0))
  })

  it("ne décode plus rien après la fin", () => {
    const parser = new SigrokStreamParser({ analogChannels: 1 })
    parser.push(concat(encode(1), ascii("$1+")))
    expect(parser.push(encode(9, 9)).analog[0]!.length).toBe(0)
  })
})

describe("garde-fous", () => {
  it("refuse un reste démesuré plutôt que de gonfler indéfiniment", () => {
    const parser = new SigrokStreamParser({ analogChannels: 3, maxPendingBytes: 8 })
    parser.push(encode(1, 2))
    expect(() => parser.push(encode(...Array(20).fill(1)))).toThrow(/octets en attente/)
  })

  it("refuse une configuration sans aucune voie", () => {
    expect(() => new SigrokStreamParser({ analogChannels: 0 })).toThrow(/aucune voie/)
  })
})
