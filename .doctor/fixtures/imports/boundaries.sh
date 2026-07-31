cat > packages/bad-pkg/src/cross.ts <<'INNER'
import { thing } from "@olympia/bad-app"
export const used = thing
INNER
