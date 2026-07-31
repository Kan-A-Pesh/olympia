mkdir -p apps/bad-app/src
cat > apps/bad-app/src/bad-driver.ts <<'INNER'
export class BadDriver {
  readonly registry = new Map<string, string>()
  opened = false

  start(kind: string): void {
    this.open(kind)
  }

  stop(): void {
    this.opened = false
  }

  register(kind: string): void {
    this.registry.set(kind, kind)
  }

  resolve(kind: string): void {
    const driver = this.registry.get(kind)
    if (!driver) {
      return
    }
    try {
      this.open(driver)
    } catch (cause) {
      this.opened = false
    }
  }

  open(kind: string): void {
    this.opened = kind.length > 0
  }
}
INNER
