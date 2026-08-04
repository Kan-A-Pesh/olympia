import { SerialPort } from "serialport"
import type { DevicePort } from "../driver.js"
import { HubError } from "../error.js"

export const RASPBERRY_PI_VENDOR_ID = "2e8a"
export const DEFAULT_BAUD = 115200
export const OPEN_TIMEOUT_MS = 3000
export const MAX_BUFFERED_BYTES = 1 << 20

export type PortCandidate = {
  path: string
  vendorId: string | undefined
  productId: string | undefined
  serialNumber: string | undefined
}

export type DiscoveryOptions = {
  vendorIds?: readonly string[]
}

export async function discoverPorts(options: DiscoveryOptions = {}): Promise<PortCandidate[]> {
  const wanted = (options.vendorIds ?? [RASPBERRY_PI_VENDOR_ID]).map((id) => id.toLowerCase())
  const ports = await SerialPort.list()

  return ports
    .filter((port) => port.vendorId !== undefined && wanted.includes(port.vendorId.toLowerCase()))
    .map((port) => ({
      path: port.path,
      vendorId: port.vendorId,
      productId: port.productId,
      serialNumber: port.serialNumber,
    }))
}

export type OpenOptions = {
  baud?: number
  maxBufferedBytes?: number
  onDisconnect?: (reason: HubError) => void
}

function openRawPort(path: string, baud: number): Promise<SerialPort> {
  return new Promise<SerialPort>((resolve, reject) => {
    const port = new SerialPort({ path, baudRate: baud, lock: true, autoOpen: false })

    const timer = setTimeout(() => {
      reject(new HubError("SERIAL_TIMEOUT", `ouverture de ${path} expirée`))
    }, OPEN_TIMEOUT_MS)

    port.open((error) => {
      clearTimeout(timer)
      if (error) reject(new HubError("SERIAL_OPEN_FAILED", `ouverture de ${path} refusée`, { cause: error }))
      else resolve(port)
    })
  })
}

function writeTo(port: SerialPort, path: string, payload: Buffer): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    port.write(payload, (error) => {
      if (error) reject(new HubError("SERIAL_CLOSED", `écriture sur ${path} impossible`, { cause: error }))
    })
    port.drain((error) => {
      if (error) reject(new HubError("SERIAL_CLOSED", `vidage de ${path} impossible`, { cause: error }))
      else resolve()
    })
  })
}

/**
 * Ouvre un port en accès exclusif.
 *
 * Toute erreur ou débranchement referme le port et prévient l appelant via
 * onDisconnect, à qui il revient de relancer une découverte après
 * reconnectDelayMs.
 */
export async function openPort(path: string, options: OpenOptions = {}): Promise<DevicePort> {
  const baud = options.baud ?? DEFAULT_BAUD
  const maxBuffered = options.maxBufferedBytes ?? MAX_BUFFERED_BYTES
  const port = await openRawPort(path, baud)

  let isClosed = false
  const handlers: Array<(chunk: Uint8Array) => void> = []

  const close = async (): Promise<void> => {
    if (isClosed) return
    isClosed = true
    await new Promise<void>((resolve) => {
      if (!port.isOpen) return resolve()
      port.close(() => resolve())
    })
  }

  const fail = (error: HubError): void => {
    void close()
    options.onDisconnect?.(error)
  }

  port.on("error", (cause) => {
    fail(new HubError("SERIAL_CLOSED", `le port ${path} a échoué`, { cause }))
  })
  port.on("close", () => {
    if (!isClosed) fail(new HubError("SERIAL_CLOSED", `le port ${path} s est fermé`))
  })

  port.on("data", (chunk: Buffer) => {
    if (chunk.length > maxBuffered) {
      fail(new HubError("SERIAL_OVERFLOW", `${path} a livré ${chunk.length} octets d un coup`))
      return
    }
    const view = new Uint8Array(chunk.buffer, chunk.byteOffset, chunk.length)
    for (const handler of handlers) handler(view)
  })

  return {
    path,

    async write(data: Uint8Array | string): Promise<void> {
      if (isClosed) throw new HubError("SERIAL_CLOSED", `le port ${path} est fermé`)
      await writeTo(port, path, typeof data === "string" ? Buffer.from(data, "ascii") : Buffer.from(data))
    },

    onData(handler: (chunk: Uint8Array) => void): void {
      handlers.push(handler)
    },

    close,
  }
}
