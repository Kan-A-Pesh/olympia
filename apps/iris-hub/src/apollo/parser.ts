import { HubError } from "../error.js"
import { DATA_FLOOR, END_MARKER, sliceBytes } from "./protocol.js"

export const MAX_PENDING_BYTES = 1 << 20

export type ParserOptions = {
  analogChannels: number
  digitalChannels?: number
  maxPendingBytes?: number
}

export type ParseResult = {
  /** Un tableau d échantillons bruts par voie analogique, dans l ordre des voies. */
  analog: Uint8Array[]
  /** Renseigné quand l appareil a annoncé la fin de la capture. */
  completed?: { declaredBytes: number; receivedBytes: number }
  /** Renseigné quand l appareil a interrompu la capture de lui-même. */
  aborted?: { byte: number }
}

/**
 * Décodeur du flux sigrok-pico, en mode analogique.
 *
 * Le flux n a pas de délimiteur de trame : chaque instant occupe un nombre
 * fixe d octets, et tout octet sous 0x30 marque la fin. Le décodeur conserve
 * donc son reste entre deux morceaux — un instant peut être coupé en deux par
 * la couche USB.
 *
 * Le RLE n existe pas dès qu une voie analogique est active, ce qui rend le
 * décodage purement positionnel.
 */
export class SigrokStreamParser {
  readonly #sliceBytes: number
  readonly #analogChannels: number
  readonly #maxPending: number

  #pending: Uint8Array = new Uint8Array(0)
  #trailer = ""
  #isFinished = false
  #receivedBytes = 0

  constructor(options: ParserOptions) {
    this.#analogChannels = options.analogChannels
    this.#sliceBytes = sliceBytes(options.analogChannels, options.digitalChannels ?? 0)
    this.#maxPending = options.maxPendingBytes ?? MAX_PENDING_BYTES

    if (this.#sliceBytes === 0) {
      throw new HubError("PROTOCOL_UNEXPECTED", "aucune voie activée, rien à décoder")
    }
  }

  get isFinished(): boolean {
    return this.#isFinished
  }

  get receivedBytes(): number {
    return this.#receivedBytes
  }

  push(chunk: Uint8Array): ParseResult {
    if (this.#isFinished) return this.#finishedResult()

    const buffer = this.#concat(chunk)
    let cursor = 0
    let dataEnd = buffer.length
    let terminator = -1

    for (let i = 0; i < buffer.length; i++) {
      const byte = buffer[i] ?? 0
      if (byte < DATA_FLOOR) {
        dataEnd = i
        terminator = i
        break
      }
    }

    const usable = dataEnd - (dataEnd % this.#sliceBytes)
    const sliceCount = usable / this.#sliceBytes
    const analog = Array.from(
      { length: this.#analogChannels },
      () => new Uint8Array(sliceCount),
    )

    const digitalBytes = this.#sliceBytes - this.#analogChannels
    for (let slice = 0; slice < sliceCount; slice++) {
      const base = cursor + slice * this.#sliceBytes + digitalBytes
      for (let channel = 0; channel < this.#analogChannels; channel++) {
        analog[channel]![slice] = buffer[base + channel] ?? 0
      }
    }
    cursor += usable
    this.#receivedBytes += usable

    if (terminator === -1) {
      this.#pending = buffer.subarray(cursor)
      return { analog }
    }

    return { analog, ...this.#terminate(buffer, terminator) }
  }

  #terminate(buffer: Uint8Array, terminator: number): Partial<ParseResult> {
    const byte = buffer[terminator] ?? 0
    this.#isFinished = true
    this.#pending = new Uint8Array(0)

    if (byte !== END_MARKER) {
      return { aborted: { byte } }
    }

    this.#trailer = String.fromCharCode(...buffer.subarray(terminator))
    const declared = /\$(\d+)\+/.exec(this.#trailer)
    return {
      completed: {
        declaredBytes: declared ? Number(declared[1]) : Number.NaN,
        receivedBytes: this.#receivedBytes,
      },
    }
  }

  #finishedResult(): ParseResult {
    return { analog: Array.from({ length: this.#analogChannels }, () => new Uint8Array(0)) }
  }

  #concat(chunk: Uint8Array): Uint8Array {
    if (this.#pending.length === 0) return chunk

    const total = this.#pending.length + chunk.length
    if (total > this.#maxPending) {
      throw new HubError(
        "PROTOCOL_FRAME_TOO_LARGE",
        `${total} octets en attente pour un plafond de ${this.#maxPending}`,
      )
    }

    const merged = new Uint8Array(total)
    merged.set(this.#pending, 0)
    merged.set(chunk, this.#pending.length)
    return merged
  }
}
