cat > packages/bad-pkg/src/imports.ts <<'INNER'
import { readFileSync } from "fs"
import { thing } from "../../../elsewhere"
export const used = [readFileSync, thing]
INNER
