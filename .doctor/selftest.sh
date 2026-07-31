#!/usr/bin/env bash
# selftest.sh — vérifie que chaque check attrape une vraie violation
#
# Fabrique un dépôt jetable contenant des fixtures qui violent les règles, puis confirme
# que le check correspondant sort bien en échec. Un check qui ne signale rien ici est un
# check qui ne protège rien.
set -uo pipefail

DOCTOR_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURE="$(mktemp -d)"
trap 'rm -rf "$FIXTURE"' EXIT

mkdir -p "$FIXTURE"/{apps/bad-app/src,packages/bad-pkg/src,hardware/bad-case}
cd "$FIXTURE"

cat > packages/bad-pkg/src/Bad_Name.ts <<'EOF'
import { readFileSync } from "fs"
import { thing } from "../../../elsewhere"
export interface Legacy { value: any }
export let mutable = 1
export class Base extends Thing {
  private secret = "x"
  constructor(private readonly dep: string) { super() }
}
function bad() {
  var x = 1
  console.log(x)
  try { JSON.parse("{}") } catch (e) {}
  throw "not an error"
  const password = "hunter2000000000000"
}
EOF
printf 'export const NO_NEWLINE = 1' > packages/bad-pkg/src/trailing.ts
printf 'export const A = 1   \n' > packages/bad-pkg/src/spaces.ts
printf 'export const B = 1\r\n' > packages/bad-pkg/src/crlf.ts
: > packages/bad-pkg/src/empty.ts
cat > packages/bad-pkg/src/marker.ts <<'EOF'
export const C = 1
EOF
echo "// TODO: finish this" >> packages/bad-pkg/src/marker.ts
cat > packages/bad-pkg/package.json <<'EOF'
{ "name": "wrong-name", "dependencies": { "@olympia/other": "^1.0.0" } }
EOF
cat > packages/bad-pkg/tsconfig.json <<'EOF'
{ "compilerOptions": { "outDir": "build", "allowJs": true } }
EOF
cat > packages/bad-pkg/src/flags.test.ts <<'EOF'
import { describe, it } from "vitest"
describe("x", () => {
  it.only("does nothing", () => {})
  it("dup", () => {})
  it("dup", () => {})
})
EOF
cat > hardware/bad-case/bad.dts <<'EOF'
/ {
	keys {
		key-a { linux,code = <30>; gpios = <&gpio 4 1>; };
		key-b { linux,code = <30>; gpios = <&gpio 4 1>; };
		key-c { linux,code = <31>; gpios = <&gpio 99 1>; };
	};
	pins { brcm,pins = <4 5>; };
};
EOF
cat > hardware/bad-case/bad.snippet <<'EOF'
dtoverlay=rotary-encoder,pin_b=17,relative_axis=1
dtoverlay=rotary-encoder,pin_a=5,pin_b=6
dtoverlay=rotary-encoder,pin_a=5,pin_b=9
EOF
cat > apps/bad-app/src/index.ts <<'EOF'
export * from "./thing.js"
EOF
cat > apps/bad-app/src/thing.ts <<'EOF'
export const thing = 1
EOF
cat > packages/bad-pkg/src/orphan.test.ts <<'EOF'
import { it, expect } from "vitest"
it("tests nothing that exists", () => { expect(1).toBe(1) })
EOF
cat > packages/bad-pkg/src/leak.ts <<'EOF'
export const topic = "olympia/v1/devices/x/identity"
EOF
cat > packages/bad-pkg/src/cross.ts <<'EOF'
import { thing } from "@olympia/bad-app"
export const used = thing
EOF
cat > packages/bad-pkg/src/names.ts <<'EOF'
export type ILegacy = { visible: boolean }
export type ThingType = { notReady: boolean }
EOF
printf 'node_modules/\n' > .gitignore

git init -q . && git add -A >/dev/null 2>&1

export DOCTOR_ROOT="$FIXTURE"

EXPECTED=(
  "files/encoding"
  "files/naming"
  "files/size"
  "hardware/gpio"
  "monorepo/manifests"
  "quality/banned-calls"
  "quality/markers"
  "repo/artifacts"
  "security/secrets"
  "tests/discipline"
  "ts/banned-syntax"
  "ts/classes"
  "ts/tsconfig"
  "imports/paths"
  "files/structure"
  "hermes/protocol"
  "imports/boundaries"
  "naming/identifiers"
)

BLIND=()
for check in "${EXPECTED[@]}"; do
  if bash "$DOCTOR_DIR/scripts/$check.sh" >/dev/null 2>&1; then
    BLIND+=("$check")
    printf '✗ %s — n a rien détecté sur les fixtures\n' "$check"
  else
    printf '✓ %s\n' "$check"
  fi
done

printf '\n%d/%d checks ont attrapé leur violation\n' \
  "$(( ${#EXPECTED[@]} - ${#BLIND[@]} ))" "${#EXPECTED[@]}"

if [[ ${#BLIND[@]} -gt 0 ]]; then
  printf 'Aveugles : %s\n' "${BLIND[*]}"
  exit 1
fi
