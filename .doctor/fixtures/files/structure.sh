printf 'export * from "./thing.js"\n' > apps/bad-app/src/index.ts
printf 'export const thing = 1\n' > apps/bad-app/src/thing.ts
printf 'import { it, expect } from "vitest"\nit("x", () => { expect(1).toBe(1) })\n' > packages/bad-pkg/src/orphan.test.ts
