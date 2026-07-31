mkdir -p apps/bad-app/src
cat > apps/bad-app/src/daemon-bounded.ts <<'INNER'
export class Hub {
  readonly queue: string[] = []
  readonly sessions = new Map<string, number>()
  readonly devices = new Map<string, number>()
  readonly ringBuffer: number[] = []

  feed(source: { on(event: string, handler: (chunk: Uint8Array) => void): void }): void {
    source.on("data", (chunk) => this.sink.write(chunk))
  }
}
INNER
cat > apps/bad-app/src/settings-store.ts <<'INNER'
export class SettingsStore {
  #values: Record<string, string> = {}

  update(key: string, value: string): void {
    this.#values[key] = value
  }
}
INNER
