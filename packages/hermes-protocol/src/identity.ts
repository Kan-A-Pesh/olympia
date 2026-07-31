import { z } from "zod"
import { deviceIdSchema } from "./device-id.js"

export const PROTOCOL = "hermes/1" as const

const identifier = z
  .string()
  .min(1)
  .max(32)
  .regex(/^[a-z0-9][a-z0-9_-]*$/)

const streamBase = {
  id: identifier,
  label: z.string().min(1).max(48),
}

export const scalarStreamSchema = z.object({
  ...streamBase,
  type: z.literal("scalar"),
  unit: z.string().max(8),
  range: z.tuple([z.number(), z.number()]).optional(),
  precision: z.number().int().min(0).max(6).default(2),
})

export const seriesStreamSchema = z.object({
  ...streamBase,
  type: z.literal("series"),
  unit: z.string().max(8),
  range: z.tuple([z.number(), z.number()]).optional(),
  window: z.number().int().positive().max(86_400),
})

export const waveformStreamSchema = z.object({
  ...streamBase,
  type: z.literal("waveform"),
  unit: z.string().max(8).default("V"),
  channels: z.array(z.object({ label: z.string().max(24), color: z.string().max(16).optional() })).min(1).max(8),
  maxSampleRate: z.number().positive(),
})

export const textStreamSchema = z.object({
  ...streamBase,
  type: z.literal("text"),
})

export const externalStreamSchema = z.object({
  ...streamBase,
  type: z.literal("stream"),
  media: z.enum(["rtsp", "webrtc", "mjpeg", "hls"]),
  url: z.string().url(),
  fingerprint: z.string().min(16).max(128),
})

export const streamSchema = z.discriminatedUnion("type", [
  scalarStreamSchema,
  seriesStreamSchema,
  waveformStreamSchema,
  textStreamSchema,
  externalStreamSchema,
])

const controlBase = {
  id: identifier,
  label: z.string().min(1).max(32),
}

export const rangeControlSchema = z.object({
  ...controlBase,
  type: z.literal("range"),
  unit: z.string().max(8).default(""),
  min: z.number(),
  max: z.number(),
  step: z.number().positive(),
  value: z.number(),
})

export const enumControlSchema = z.object({
  ...controlBase,
  type: z.literal("enum"),
  options: z.array(z.object({ value: z.string().max(32), label: z.string().max(32) })).min(2).max(32),
  value: z.string().max(32),
})

export const toggleControlSchema = z.object({
  ...controlBase,
  type: z.literal("toggle"),
  value: z.boolean(),
})

export const controlSchema = z.discriminatedUnion("type", [
  rangeControlSchema,
  enumControlSchema,
  toggleControlSchema,
])

export const deviceIdentitySchema = z.object({
  deviceId: deviceIdSchema,
  name: z.string().min(1).max(48),
  kind: identifier,
  firmware: z.string().max(24),
  protocol: z.string().regex(/^hermes\/\d+$/),
  streams: z.array(streamSchema).min(1).max(16),
  controls: z.array(controlSchema).max(8).default([]),
})

export const deviceStatusSchema = z.object({
  online: z.boolean(),
  since: z.number().int().nonnegative().optional(),
})

export const scalarSampleSchema = z.object({
  t: z.number().int().nonnegative(),
  v: z.number(),
})

export const seriesSampleSchema = z.object({
  points: z.array(z.tuple([z.number().int().nonnegative(), z.number()])).max(4096),
})

export const textSampleSchema = z.object({
  t: z.number().int().nonnegative(),
  text: z.string().max(512),
})

export const commandSchema = z.object({
  value: z.union([z.number(), z.string(), z.boolean()]),
})

export type Stream = z.infer<typeof streamSchema>
export type StreamKind = Stream["type"]
export type Control = z.infer<typeof controlSchema>
export type DeviceIdentity = z.infer<typeof deviceIdentitySchema>
export type DeviceStatus = z.infer<typeof deviceStatusSchema>
export type ScalarSample = z.infer<typeof scalarSampleSchema>
export type SeriesSample = z.infer<typeof seriesSampleSchema>
export type TextSample = z.infer<typeof textSampleSchema>
export type Command = z.infer<typeof commandSchema>

export function isProtocolCompatible(protocol: string): boolean {
  return protocol === PROTOCOL
}
