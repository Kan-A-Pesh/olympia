import type { DeviceId } from "./device-id.js"

export const ROOT = "olympia"
export const VERSION = "v1"

const BASE = `${ROOT}/${VERSION}`

export const identityTopic = (id: DeviceId): string => `${BASE}/devices/${id}/identity`
export const statusTopic = (id: DeviceId): string => `${BASE}/devices/${id}/status`
export const dataTopic = (id: DeviceId, streamId: string): string => `${BASE}/devices/${id}/data/${streamId}`
export const commandTopic = (id: DeviceId, controlId: string): string => `${BASE}/devices/${id}/cmd/${controlId}`
export const quarantineTopic = (id: DeviceId): string => `${BASE}/quarantine/${id}/identity`

export const ALL_IDENTITIES = `${BASE}/devices/+/identity`
export const ALL_STATUSES = `${BASE}/devices/+/status`
export const ALL_DATA = `${BASE}/devices/+/data/+`
export const ALL_QUARANTINE = `${BASE}/quarantine/+/identity`

export type ParsedTopic =
  | { scope: "device"; deviceId: string; channel: "identity" | "status" }
  | { scope: "device"; deviceId: string; channel: "data" | "cmd"; streamId: string }
  | { scope: "quarantine"; deviceId: string }

export function parseTopic(topic: string): ParsedTopic | null {
  const parts = topic.split("/")
  if (parts[0] !== ROOT || parts[1] !== VERSION) return null

  const [, , scope, deviceId, channel, leaf] = parts
  if (!deviceId) return null

  if (scope === "quarantine" && channel === "identity" && parts.length === 5) {
    return { scope: "quarantine", deviceId }
  }
  if (scope !== "devices") return null

  if ((channel === "identity" || channel === "status") && parts.length === 5) {
    return { scope: "device", deviceId, channel }
  }
  if ((channel === "data" || channel === "cmd") && leaf && parts.length === 6) {
    return { scope: "device", deviceId, channel, streamId: leaf }
  }
  return null
}

export function producerAcl(id: DeviceId): { readwrite: string[]; read: string[] } {
  return {
    readwrite: [`${BASE}/devices/${id}/identity`, `${BASE}/devices/${id}/status`, `${BASE}/devices/${id}/data/#`],
    read: [`${BASE}/devices/${id}/cmd/#`],
  }
}

export function consumerAcl(): { read: string[]; write: string[] } {
  return {
    read: [`${BASE}/devices/+/identity`, `${BASE}/devices/+/status`, `${BASE}/devices/+/data/#`, ALL_QUARANTINE],
    write: [`${BASE}/devices/+/cmd/+`],
  }
}
