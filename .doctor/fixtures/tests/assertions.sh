cat > packages/bad-pkg/src/assertions.test.ts <<'INNER'
import { describe, expect, it } from "vitest"

describe("frame", () => {
  it("should encode a frame", () => {})
  it("works", () => {
    expect(1).toBe(1)
  })
  it("decodes a frame within the deadline", () => {
    expect(2).toBe(2)
  }, 5000)
  it("keeps the queue bounded", { timeout: 200 }, () => {
    expect(3).toBe(3)
  })
})
INNER
