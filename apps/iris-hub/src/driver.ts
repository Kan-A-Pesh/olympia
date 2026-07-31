import type { Command, DeviceIdentity, Stream } from "@olympia/hermes-protocol"

export type SamplePayload =
  | { kind: "scalar"; t: number; v: number }
  | { kind: "series"; points: Array<[number, number]> }
  | { kind: "text"; t: number; text: string }
  | { kind: "waveform"; frame: Uint8Array }

export type Sample = {
  streamId: string
  payload: SamplePayload
}

export type DeviceHandle = {
  readonly identity: DeviceIdentity
  readonly transport: "usb" | "mqtt"
  readonly isAuthenticated: boolean
}

export type DriverContext = {
  emit(sample: Sample): void
  updateIdentity(identity: DeviceIdentity): void
  log(message: string): void
}

export type Driver = {
  readonly kind: string
  readonly matches: (signature: string) => boolean
  start(ctx: DriverContext): Promise<DeviceIdentity>
  applyCommand(controlId: string, command: Command): Promise<void>
  stop(): Promise<void>
}

export type DriverFactory = {
  readonly kind: string
  readonly matches: (signature: string) => boolean
  create(port: DevicePort): Driver
}

export type DevicePort = {
  readonly path: string
  write(data: Uint8Array | string): Promise<void>
  onData(handler: (chunk: Uint8Array) => void): void
  close(): Promise<void>
}

export class DriverRegistry {
  readonly #factories = new Map<string, DriverFactory>()

  register(factory: DriverFactory): void {
    if (this.#factories.has(factory.kind)) {
      throw new Error(`driver already registered for kind "${factory.kind}"`)
    }
    this.#factories.set(factory.kind, factory)
  }

  resolve(signature: string): DriverFactory | undefined {
    for (const factory of this.#factories.values()) {
      if (factory.matches(signature)) return factory
    }
    return undefined
  }

  get kinds(): string[] {
    return [...this.#factories.keys()]
  }
}

export function streamById(identity: DeviceIdentity, streamId: string): Stream | undefined {
  return identity.streams.find((stream) => stream.id === streamId)
}
