import { describe, expect, it } from "vitest"
import {
  commandSchema,
  controlSchema,
  deviceIdentitySchema,
  deviceStatusSchema,
  isProtocolCompatible,
  scalarSampleSchema,
  seriesSampleSchema,
  streamSchema,
  textSampleSchema,
} from "./identity.js"

const identity = {
  deviceId: "gaia-4kqm7x2vhb9rndta",
  name: "Capteur établi",
  kind: "gaia-sensor",
  firmware: "0.2.1",
  protocol: "hermes/1",
  streams: [{ id: "temp", type: "scalar", label: "Température", unit: "°C", precision: 1 }],
  controls: [],
}

describe("device identity", () => {
  it("accepts a well-formed card", () => {
    expect(deviceIdentitySchema.parse(identity).deviceId).toBe("gaia-4kqm7x2vhb9rndta")
  })

  it("defaults controls to an empty list", () => {
    const { controls, ...withoutControls } = identity
    expect(deviceIdentitySchema.parse(withoutControls).controls).toEqual([])
  })

  it("rejects a device id that is not fingerprint-shaped", () => {
    expect(() => deviceIdentitySchema.parse({ ...identity, deviceId: "gaia-short" })).toThrow()
  })

  it("rejects a protocol string outside the hermes family", () => {
    expect(() => deviceIdentitySchema.parse({ ...identity, protocol: "mqtt/5" })).toThrow()
  })

  it("rejects a device announcing no stream", () => {
    expect(() => deviceIdentitySchema.parse({ ...identity, streams: [] })).toThrow()
  })

  it("rejects a kind that is not an identifier", () => {
    expect(() => deviceIdentitySchema.parse({ ...identity, kind: "Gaia Sensor" })).toThrow()
  })
})

describe("streams", () => {
  it("accepts each stream type", () => {
    const streams = [
      { id: "t", type: "scalar", label: "T", unit: "°C" },
      { id: "p", type: "series", label: "P", unit: "hPa", window: 3600 },
      { id: "w", type: "waveform", label: "W", channels: [{ label: "CH1" }], maxSampleRate: 494_800 },
      { id: "s", type: "text", label: "S" },
      {
        id: "v",
        type: "stream",
        label: "V",
        media: "rtsp",
        url: "rtsp://argos.local/live",
        fingerprint: "a".repeat(64),
      },
    ]
    for (const stream of streams) expect(() => streamSchema.parse(stream)).not.toThrow()
  })

  it("rejects an unknown stream type", () => {
    expect(() => streamSchema.parse({ id: "x", type: "gauge", label: "X" })).toThrow()
  })

  it("rejects a waveform without channels", () => {
    expect(() =>
      streamSchema.parse({ id: "w", type: "waveform", label: "W", channels: [], maxSampleRate: 1 }),
    ).toThrow()
  })

  it("rejects an external stream whose url is not a url", () => {
    expect(() =>
      streamSchema.parse({
        id: "v",
        type: "stream",
        label: "V",
        media: "rtsp",
        url: "argos.local",
        fingerprint: "a".repeat(64),
      }),
    ).toThrow()
  })
})

describe("controls", () => {
  it("accepts each control type", () => {
    const controls = [
      { id: "interval", type: "range", label: "Intervalle", min: 1, max: 300, step: 1, value: 10 },
      { id: "coupling", type: "enum", label: "Couplage", options: [{ value: "ac", label: "AC" }, { value: "dc", label: "DC" }], value: "dc" },
      { id: "run", type: "toggle", label: "Acquisition", value: true },
    ]
    for (const control of controls) expect(() => controlSchema.parse(control)).not.toThrow()
  })

  it("rejects a range control with a non-positive step", () => {
    expect(() =>
      controlSchema.parse({ id: "x", type: "range", label: "X", min: 0, max: 1, step: 0, value: 0 }),
    ).toThrow()
  })

  it("rejects an enum control offering a single option", () => {
    expect(() =>
      controlSchema.parse({ id: "x", type: "enum", label: "X", options: [{ value: "a", label: "A" }], value: "a" }),
    ).toThrow()
  })
})

describe("payloads", () => {
  it("accepts samples and commands", () => {
    expect(() => scalarSampleSchema.parse({ t: 1_785_312_000, v: 23.4 })).not.toThrow()
    expect(() => seriesSampleSchema.parse({ points: [[1_785_312_000, 1013]] })).not.toThrow()
    expect(() => textSampleSchema.parse({ t: 1_785_312_000, text: "armed" })).not.toThrow()
    expect(() => commandSchema.parse({ value: 42 })).not.toThrow()
  })

  it("rejects a negative timestamp", () => {
    expect(() => scalarSampleSchema.parse({ t: -1, v: 0 })).toThrow()
  })

  it("rejects a status without the online flag", () => {
    expect(() => deviceStatusSchema.parse({ since: 1 })).toThrow()
  })

  it("rejects a command carrying a structured value", () => {
    expect(() => commandSchema.parse({ value: { nested: true } })).toThrow()
  })
})

describe("protocol compatibility", () => {
  it("accepts the current version only", () => {
    expect(isProtocolCompatible("hermes/1")).toBe(true)
    expect(isProtocolCompatible("hermes/2")).toBe(false)
  })
})
