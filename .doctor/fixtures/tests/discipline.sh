cat > packages/bad-pkg/src/flags.test.ts <<'INNER'
import { describe, it } from "vitest"
describe("x", () => {
  it.only("does nothing", () => {})
  it("dup", () => {})
  it("dup", () => {})
})
INNER
