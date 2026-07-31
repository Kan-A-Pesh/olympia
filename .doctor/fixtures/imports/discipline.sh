mkdir -p apps/iris-hub/src
cat > apps/iris-hub/src/panel-view.ts <<'INNER'
import { render } from "./render.js"
import { readFileSync } from "node:fs"

export function mount(id: string) {
  const host = document.getElementById(id)
  return render(host, () => import("./tile.js"))
}
INNER
cat > packages/bad-pkg/src/deep-import.ts <<'INNER'
import { thing } from "../../../../shared/thing.js"
export const used = thing
INNER
