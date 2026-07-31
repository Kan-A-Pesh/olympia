mkdir -p packages/bad-usage/src
cat > packages/bad-usage/package.json <<'INNER'
{
  "name": "@olympia/bad-usage",
  "type": "module",
  "dependencies": { "zod": "^3.24.0" }
}
INNER
cat > packages/bad-usage/src/index.ts <<'INNER'
import { parse } from "yaml"
export const read = (raw: string): unknown => parse(raw)
INNER
