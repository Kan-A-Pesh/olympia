import { createReadStream } from "node:fs"
import { EventEmitter } from "node:events"
import { EV_KEY, EV_REL, InputEventParser, KEY_PRESS, KEY_REPEAT, REL_X } from "./input-event.js"

export const DIRECTIONS = ["nw", "n", "ne", "w", "e", "sw", "s", "se"] as const
export type Direction = (typeof DIRECTIONS)[number]

export interface PanelLayout {
  encoders: string[]
  keys: string
  directions: Record<number, Direction>
  pushes: Record<number, number>
}

export const DEFAULT_LAYOUT: PanelLayout = {
  encoders: [
    "/dev/input/by-path/platform-rotary@4-event",
    "/dev/input/by-path/platform-rotary@5-event",
    "/dev/input/by-path/platform-rotary@13-event",
    "/dev/input/by-path/platform-rotary@26-event",
  ],
  keys: "/dev/input/by-path/platform-olympia-keys-event",
  directions: { 71: "nw", 72: "n", 73: "ne", 75: "w", 77: "e", 79: "sw", 80: "s", 81: "se" },
  pushes: { 183: 0, 184: 1, 185: 2, 186: 3 },
}

export type PanelEvent =
  | { type: "rotate"; encoder: number; delta: number }
  | { type: "navigate"; direction: Direction; repeat: boolean }
  | { type: "push"; encoder: number }

export class ControlPanel extends EventEmitter<{ input: [PanelEvent]; error: [Error] }> {
  readonly #layout: PanelLayout
  readonly #closers: Array<() => void> = []

  constructor(layout: PanelLayout = DEFAULT_LAYOUT) {
    super()
    this.#layout = layout
  }

  open(): void {
    this.#layout.encoders.forEach((path, index) => {
      this.#watch(path, (event) => {
        if (event.type === EV_REL && event.code === REL_X) {
          this.emit("input", { type: "rotate", encoder: index, delta: event.value })
        }
      })
    })

    this.#watch(this.#layout.keys, (event) => {
      if (event.type !== EV_KEY) return
      if (event.value !== KEY_PRESS && event.value !== KEY_REPEAT) return

      const direction = this.#layout.directions[event.code]
      if (direction) {
        this.emit("input", { type: "navigate", direction, repeat: event.value === KEY_REPEAT })
        return
      }

      const encoder = this.#layout.pushes[event.code]
      if (encoder !== undefined && event.value === KEY_PRESS) {
        this.emit("input", { type: "push", encoder })
      }
    })
  }

  close(): void {
    for (const close of this.#closers) close()
    this.#closers.length = 0
  }

  #watch(path: string, handle: (event: { type: number; code: number; value: number }) => void): void {
    const parser = new InputEventParser()
    const stream = createReadStream(path)

    stream.on("data", (chunk) => {
      for (const event of parser.push(chunk as Buffer)) handle(event)
    })
    stream.on("error", (cause) => {
      this.emit("error", new Error(`input device unavailable: ${path}`, { cause }))
    })

    this.#closers.push(() => stream.close())
  }
}

const DELTA: Record<Direction, [number, number]> = {
  nw: [-1, -1],
  n: [0, -1],
  ne: [1, -1],
  w: [-1, 0],
  e: [1, 0],
  sw: [-1, 1],
  s: [0, 1],
  se: [1, 1],
}

export function step(direction: Direction): [dx: number, dy: number] {
  return DELTA[direction]
}
