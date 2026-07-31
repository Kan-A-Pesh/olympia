import { z } from "zod"

const ALPHABET = "0123456789abcdefghjkmnpqrstvwxyz"
const ID_LENGTH = 16

export const deviceIdSchema = z
  .string()
  .regex(new RegExp(`^[a-z][a-z0-9]{0,15}-[${ALPHABET}]{${ID_LENGTH}}$`))
  .brand<"DeviceId">()

export type DeviceId = z.infer<typeof deviceIdSchema>

function toBase32(bytes: Uint8Array, length: number): string {
  let bits = 0
  let value = 0
  let out = ""
  for (const byte of bytes) {
    value = (value << 8) | byte
    bits += 8
    while (bits >= 5) {
      out += ALPHABET[(value >>> (bits - 5)) & 31]
      bits -= 5
      if (out.length === length) return out
    }
  }
  if (bits > 0 && out.length < length) out += ALPHABET[(value << (5 - bits)) & 31]
  return out.slice(0, length)
}

async function sha256(data: Uint8Array): Promise<Uint8Array> {
  const digest = await globalThis.crypto.subtle.digest("SHA-256", data as BufferSource)
  return new Uint8Array(digest)
}

export async function fingerprint(publicKeyDer: Uint8Array): Promise<string> {
  const digest = await sha256(publicKeyDer)
  return Array.from(digest, (b) => b.toString(16).padStart(2, "0")).join("")
}

export async function deviceIdFrom(prefix: string, publicKeyDer: Uint8Array): Promise<DeviceId> {
  const digest = await sha256(publicKeyDer)
  return deviceIdSchema.parse(`${prefix}-${toBase32(digest, ID_LENGTH)}`)
}

export function deviceIdFromFingerprint(prefix: string, hex: string): DeviceId {
  const bytes = new Uint8Array(hex.length / 2)
  for (let i = 0; i < bytes.length; i++) bytes[i] = Number.parseInt(hex.slice(i * 2, i * 2 + 2), 16)
  return deviceIdSchema.parse(`${prefix}-${toBase32(bytes, ID_LENGTH)}`)
}

export function formatFingerprint(hex: string): string {
  return (hex.match(/.{1,4}/g) ?? []).join(" ").toUpperCase()
}
