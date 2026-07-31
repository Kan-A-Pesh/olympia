import { describe, expect, it } from "vitest"
import { decodeWaveform, encodeWaveform, toVolts, type WaveformFrame } from "./waveform.js"

const frame = (overrides: Partial<WaveformFrame> = {}): WaveformFrame => ({
  sampleRateHz: 494_800,
  capturedAt: 1_785_312_000_000,
  bitsPerSample: 8,
  channels: [
    { voltsPerSample: 0.052, offsetVolts: -1.65, samples: Uint8Array.from([0, 64, 128, 192, 255]) },
    { voltsPerSample: 0.22, offsetVolts: -12, samples: Uint8Array.from([10, 20, 30, 40, 50]) },
  ],
  ...overrides,
})

describe("waveform codec", () => {
  it("round-trips a frame", () => {
    const decoded = decodeWaveform(encodeWaveform(frame()))
    expect(decoded.sampleRateHz).toBe(494_800)
    expect(decoded.capturedAt).toBe(1_785_312_000_000)
    expect(decoded.channels).toHaveLength(2)
    expect(Array.from(decoded.channels[0]!.samples)).toEqual([0, 64, 128, 192, 255])
    expect(decoded.channels[1]!.voltsPerSample).toBeCloseTo(0.22, 5)
  })

  it("round-trips 16-bit samples", () => {
    const source = frame({
      bitsPerSample: 16,
      channels: [{ voltsPerSample: 0.001, offsetVolts: 0, samples: Uint16Array.from([0, 4095, 32_768, 65_535]) }],
    })
    const decoded = decodeWaveform(encodeWaveform(source))
    expect(Array.from(decoded.channels[0]!.samples)).toEqual([0, 4095, 32_768, 65_535])
  })

  it("converts samples to volts", () => {
    const decoded = decodeWaveform(encodeWaveform(frame()))
    expect(toVolts(decoded.channels[0]!, 2)).toBeCloseTo(128 * 0.052 - 1.65, 5)
  })

  it("stays compact against JSON", () => {
    const samples = Uint8Array.from({ length: 1000 }, (_, i) => i % 256)
    const encoded = encodeWaveform(
      frame({ channels: [{ voltsPerSample: 0.052, offsetVolts: -1.65, samples }] }),
    )
    expect(encoded.byteLength).toBe(20 + 8 + 1000)
    expect(encoded.byteLength).toBeLessThan(JSON.stringify(Array.from(samples)).length / 3)
  })

  it("rejects channels of differing length", () => {
    const bad = frame({
      channels: [
        { voltsPerSample: 1, offsetVolts: 0, samples: Uint8Array.from([1, 2, 3]) },
        { voltsPerSample: 1, offsetVolts: 0, samples: Uint8Array.from([1, 2]) },
      ],
    })
    expect(() => encodeWaveform(bad)).toThrow(/same sample count/)
  })

  it("rejects foreign payloads", () => {
    expect(() => decodeWaveform(new Uint8Array(40))).toThrow(/not a waveform frame/)
  })

  it("rejects a truncated frame", () => {
    const encoded = encodeWaveform(frame())
    expect(() => decodeWaveform(encoded.slice(0, encoded.byteLength - 3))).toThrow(/size mismatch/)
  })
})
