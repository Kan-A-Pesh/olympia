import { describe, expect, it } from "vitest"
import { deviceIdFromFingerprint, deviceIdSchema, formatFingerprint } from "./device-id.js"
import { commandTopic, dataTopic, identityTopic, parseTopic, producerAcl } from "./topics.js"

const id = deviceIdSchema.parse("gaia-4kqm7x2vhb9rndta")

describe("topics", () => {
  it("builds and parses an identity topic", () => {
    expect(parseTopic(identityTopic(id))).toEqual({ scope: "device", deviceId: id, channel: "identity" })
  })

  it("builds and parses a data topic", () => {
    expect(parseTopic(dataTopic(id, "temp"))).toEqual({
      scope: "device",
      deviceId: id,
      channel: "data",
      streamId: "temp",
    })
  })

  it("builds and parses a command topic", () => {
    expect(parseTopic(commandTopic(id, "interval"))).toEqual({
      scope: "device",
      deviceId: id,
      channel: "cmd",
      streamId: "interval",
    })
  })

  it("rejects foreign and malformed topics", () => {
    expect(parseTopic("homeassistant/sensor/state")).toBeNull()
    expect(parseTopic("olympia/v1/devices/gaia-4kqm7x2vhb9rndta")).toBeNull()
    expect(parseTopic("olympia/v1/devices/gaia-4kqm7x2vhb9rndta/data")).toBeNull()
  })

  it("confines a producer to its own namespace", () => {
    const acl = producerAcl(id)
    expect(acl.readwrite.every((pattern) => pattern.includes(id))).toBe(true)
    expect(acl.read).toEqual([`olympia/v1/devices/${id}/cmd/#`])
  })
})

describe("device identity", () => {
  it("derives a stable id from a fingerprint", () => {
    const hex = "a".repeat(64)
    expect(deviceIdFromFingerprint("gaia", hex)).toBe(deviceIdFromFingerprint("gaia", hex))
  })

  it("derives different ids from different fingerprints", () => {
    expect(deviceIdFromFingerprint("gaia", "a".repeat(64))).not.toBe(deviceIdFromFingerprint("gaia", "b".repeat(64)))
  })

  it("rejects an id that is not fingerprint-shaped", () => {
    expect(() => deviceIdSchema.parse("gaia-notareal")).toThrow()
    expect(() => deviceIdSchema.parse("gaia-iiiiiiiiiiiiiiii")).toThrow()
  })

  it("groups a fingerprint for on-screen comparison", () => {
    expect(formatFingerprint("a1b2c3d4e5f60718")).toBe("A1B2 C3D4 E5F6 0718")
  })
})
