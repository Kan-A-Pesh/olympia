mkdir -p packages/graph-pkg/src packages/graph-lib/src

cat > packages/graph-pkg/package.json <<'INNER'
{
  "name": "@olympia/graph-pkg",
  "type": "module",
  "exports": { ".": { "default": "./dist/index.js" } },
  "files": ["dist"],
  "scripts": { "build": "tsc", "test": "vitest run", "typecheck": "tsc --noEmit" },
  "dependencies": { "left-pad": "^1.3.0" },
  "devDependencies": { "zod": "^3.24.0" }
}
INNER

cat > packages/graph-lib/package.json <<'INNER'
{
  "name": "@olympia/graph-lib",
  "type": "module",
  "exports": { ".": { "default": "./dist/index.js" } },
  "files": ["dist"],
  "scripts": { "build": "tsc", "test": "vitest run", "typecheck": "tsc --noEmit" }
}
INNER

printf 'export const helper = (): number => 1\n' > packages/graph-lib/src/index.ts

printf 'export * from "./cycle-a.js"\n' > packages/graph-pkg/src/index.ts

cat > packages/graph-pkg/src/cycle-a.ts <<'INNER'
import { beta } from "./cycle-b.js"
import { dead } from "./dead.js"
import { helper } from "@olympia/graph-lib"
import { z } from "zod"
export const alpha = (): number => beta() + helper() + z.number().parse(dead())
INNER

cat > packages/graph-pkg/src/cycle-b.ts <<'INNER'
import { alpha } from "./cycle-a.js"
import { padStart } from "./missing-import.js"
export const beta = (): number => (alpha ? 1 : padStart)
INNER

cat > packages/graph-pkg/src/dead.ts <<'INNER'
export function dead(): number {
  return 1
}

export const neverUsed = 2
INNER

printf 'export const unreachable = 1\n' > packages/graph-pkg/src/orphan.ts

cat > packages/graph-pkg/src/types.ts <<'INNER'
export type Shape = { width: number }
export const area = (s: Shape): number => s.width
INNER

cat > packages/graph-pkg/src/smells.ts <<'INNER'
import { Shape } from "./types.js"
import { area } from "./types.js"
import { dead } from "./dead.js"
import { readFile } from "node:fs/promises"
import { render } from "preact"

export type Payload = { a: number } | { b: string }

const size: number = 12
const shape: Shape = { width: 1 }

export async function load(path: string): Promise<string> {
  return String(await readFile(path))
}

export function classify(value, mode: string): string {
  load(mode)
  switch (mode) {
    case "a":
      return "a"
  }
  if (value > size) {
    return "big"
  } else {
    return "small"
  }
}

export const RISKY = /^(\w+\s?)+$/
export const drawn = render
export const measured = area(shape)
INNER

cat > packages/graph-pkg/src/deep.ts <<'INNER'
export function tangle(values: number[], mode: string): number {
  let total = 0
  for (const value of values) {
    if (value > 0) {
      for (let i = 0; i < value; i++) {
        if (i % 2 === 0) {
          while (total < 10) {
            total += mode === "a" ? 1 : 2
          }
        }
      }
    }
    if (value < 0) total -= 1
    if (value === 0) total += 1
    if (mode === "b") total += 2
    if (mode === "c") total += 3
    if (mode === "d") total += 4
    if (mode === "e") total += 5
    if (mode === "f") total += 6
    if (mode === "g") total += 7
  }
  return total
}
INNER

{
  printf 'export function sprawl(seed: number): number {\n'
  printf '  let total = seed\n'
  i=0
  while [ "$i" -lt 70 ]; do
    printf '  total += %d\n' "$i"
    i=$((i + 1))
  done
  printf '  return total\n'
  printf '}\n'
} > packages/graph-pkg/src/sprawl.ts

block() {
  printf 'export function %s(seed: number): number {\n' "$1"
  i=0
  while [ "$i" -lt 14 ]; do
    printf '  const step%d = seed * %d + 7\n' "$i" "$i"
    i=$((i + 1))
  done
  printf '  return step0\n'
  printf '}\n'
}
block dupA > packages/graph-pkg/src/dup-a.ts
block dupB > packages/graph-pkg/src/dup-b.ts
