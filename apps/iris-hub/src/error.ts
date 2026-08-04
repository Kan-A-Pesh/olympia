/** Codes d erreur du hub. Stables : ils sont affichés et corrélés avec les traces. */
export const ERROR_CODES = [
  "SERIAL_OPEN_FAILED",
  "SERIAL_CLOSED",
  "SERIAL_OVERFLOW",
  "SERIAL_TIMEOUT",
  "PROTOCOL_UNEXPECTED",
  "PROTOCOL_FRAME_TOO_LARGE",
  "DEVICE_UNKNOWN",
  "DRIVER_FAILED",
] as const

export type ErrorCode = (typeof ERROR_CODES)[number]

export class HubError extends Error {
  readonly code: ErrorCode

  constructor(code: ErrorCode, message: string, options?: { cause?: unknown }) {
    super(message, options)
    this.name = "HubError"
    this.code = code
  }
}

export function isHubError(value: unknown, code?: ErrorCode): value is HubError {
  if (!(value instanceof HubError)) return false
  return code === undefined || value.code === code
}
