import fs from "node:fs"
import path from "node:path"
import { builtinModules } from "node:module"

const env = (name, fallback) => {
  const raw = process.env[name]
  return raw === undefined || raw === "" ? fallback : raw
}
const num = (name, fallback) => {
  const v = Number(env(name, String(fallback)))
  return Number.isFinite(v) ? v : fallback
}

const MAX_COMPLEXITY = num("DOCTOR_MAX_COMPLEXITY", 10)
const MAX_FUNCTION_LINES = num("DOCTOR_MAX_FUNCTION_LINES", 60)
const MAX_NESTING = num("DOCTOR_MAX_NESTING", 4)
const DUP_LINES = num("DOCTOR_DUP_LINES", 12)
const EXTRA_ROOTS = env("DOCTOR_GRAPH_ROOTS", "").split(/[:,\s]+/).filter(Boolean)
const TOOLCHAIN = new RegExp(
  env(
    "DOCTOR_GRAPH_TOOLCHAIN",
    "^(@types/|@vitest/|typescript$|vitest$|turbo$|tsx$|vite$|eslint|prettier|rollup|esbuild|tsup)",
  ),
)
const CHECK_UNTESTED = env("DOCTOR_GRAPH_UNTESTED_EXPORTS", "0") === "1"

const BUILTINS = new Set([...builtinModules, ...builtinModules.map((m) => `node:${m}`)])
const KEYWORDS = new Set([
  "if", "for", "while", "switch", "catch", "return", "typeof", "new", "await", "void", "delete",
  "do", "else", "case", "in", "of", "yield", "function", "import", "export", "throw", "instanceof",
  "as", "satisfies", "keyof", "extends", "implements", "const", "let", "var", "class", "type",
])
const REGEX_PREFIX_WORDS = new Set([
  "return", "typeof", "instanceof", "new", "delete", "void", "throw", "case", "in", "of", "do",
  "else", "yield", "await",
])

const scan = (src) => {
  const out = src.split("")
  const bare = src.split("")
  const literals = []
  const modes = [{ kind: "code", depth: 0, inTemplate: false }]
  const blank = (a, b, comment) => {
    for (let k = a; k < b && k < src.length; k++) {
      if (out[k] !== "\n") out[k] = " "
      if (comment && bare[k] !== "\n") bare[k] = " "
    }
  }
  const regexAllowed = (at) => {
    let j = at - 1
    while (j >= 0 && /\s/.test(out[j])) j--
    if (j < 0) return true
    const c = out[j]
    if (/[)\]]/.test(c)) return false
    if (/[\w$]/.test(c)) {
      let k = j
      while (k >= 0 && /[\w$]/.test(out[k])) k--
      return REGEX_PREFIX_WORDS.has(out.slice(k + 1, j + 1).join(""))
    }
    return true
  }

  let i = 0
  while (i < src.length) {
    const m = modes[modes.length - 1]
    const c = src[i]

    if (m.kind === "template") {
      if (c === "\\") { blank(i, i + 2); i += 2; continue }
      if (c === "`") { modes.pop(); i++; continue }
      if (c === "$" && src[i + 1] === "{") { modes.push({ kind: "code", depth: 0, inTemplate: true }); i += 2; continue }
      if (c !== "\n") out[i] = " "
      i++
      continue
    }

    if (c === "/" && src[i + 1] === "/") {
      let j = i
      while (j < src.length && src[j] !== "\n") j++
      blank(i, j, true)
      i = j
      continue
    }
    if (c === "/" && src[i + 1] === "*") {
      const end = src.indexOf("*/", i + 2)
      const j = end < 0 ? src.length : end + 2
      blank(i, j, true)
      i = j
      continue
    }
    if (c === '"' || c === "'") {
      let j = i + 1
      while (j < src.length && src[j] !== c && src[j] !== "\n") j += src[j] === "\\" ? 2 : 1
      blank(i + 1, j)
      i = Math.min(j + 1, src.length)
      continue
    }
    if (c === "`") { modes.push({ kind: "template" }); i++; continue }
    if (c === "/" && regexAllowed(i)) {
      let j = i + 1
      let inClass = false
      let closed = false
      while (j < src.length && src[j] !== "\n") {
        const d = src[j]
        if (d === "\\") { j += 2; continue }
        if (inClass) { if (d === "]") inClass = false; j++; continue }
        if (d === "[") { inClass = true; j++; continue }
        if (d === "/") { closed = true; break }
        j++
      }
      if (closed) {
        let k = j + 1
        while (k < src.length && /[a-z]/.test(src[k])) k++
        literals.push({ kind: "regex", value: src.slice(i + 1, j), at: i })
        blank(i + 1, j)
        i = k
        continue
      }
    }
    if (c === "{") { m.depth++; i++; continue }
    if (c === "}") {
      if (m.depth === 0 && m.inTemplate) { modes.pop(); i++; continue }
      m.depth--
      i++
      continue
    }
    i++
  }
  return { code: out.join(""), bare: bare.join(""), literals }
}

const lineIndex = (text) => {
  const starts = [0]
  for (let i = 0; i < text.length; i++) if (text[i] === "\n") starts.push(i + 1)
  return (idx) => {
    let lo = 0
    let hi = starts.length - 1
    while (lo < hi) {
      const mid = (lo + hi + 1) >> 1
      if (starts[mid] <= idx) lo = mid
      else hi = mid - 1
    }
    return lo + 1
  }
}

const bracketMap = (code) => {
  const inner = new Array(code.length).fill("")
  const depth = new Int32Array(code.length)
  const stack = []
  for (let i = 0; i < code.length; i++) {
    const c = code[i]
    if (c === "(" || c === "[" || c === "{") { inner[i] = stack[stack.length - 1] ?? ""; depth[i] = stack.length; stack.push(c); continue }
    if (c === ")" || c === "]" || c === "}") { stack.pop(); inner[i] = stack[stack.length - 1] ?? ""; depth[i] = stack.length; continue }
    inner[i] = stack[stack.length - 1] ?? ""
    depth[i] = stack.length
  }
  return { inner, depth }
}

const matching = (code, open) => {
  const pairs = { "(": ")", "[": "]", "{": "}" }
  const close = pairs[code[open]]
  let depth = 0
  for (let i = open; i < code.length; i++) {
    if (code[i] === code[open]) depth++
    else if (code[i] === close) {
      depth--
      if (depth === 0) return i
    }
  }
  return -1
}

const IMPORT_FROM = /(^|[\n;])[ \t]*import\s+([^;'"`]*?)\s*from\s*["']([^"']+)["']/g
const IMPORT_BARE = /(^|[\n;])[ \t]*import\s*["']([^"']+)["']/g
const EXPORT_FROM = /(^|[\n;])[ \t]*export\s+(\*(?:\s+as\s+[\w$]+)?|\{[^}]*\})\s*from\s*["']([^"']+)["']/g
const IMPORT_DYNAMIC = /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g
const EXPORT_DECL =
  /(^|[\n;])[ \t]*export\s+(?:default\s+)?(?:async\s+)?(?:const|let|var|function\s*\*?|class|type|enum|interface)\s+([A-Za-z_$][\w$]*)/g
const EXPORT_LIST = /(^|[\n;])[ \t]*export\s*\{([^}]*)\}\s*(?!from)/g

const parseBindings = (clause) => {
  const bindings = []
  const typeOnly = /^\s*type\s/.test(clause)
  const body = clause.replace(/^\s*type\s+/, "")
  const braced = body.match(/\{([^}]*)\}/)
  const outside = body.replace(/\{[^}]*\}/, "").replace(/,\s*$/, "").trim()

  if (outside) {
    const ns = outside.match(/^\*\s+as\s+([\w$]+)/)
    if (ns) bindings.push({ local: ns[1], imported: "*", typeOnly, kind: "namespace" })
    else {
      const def = outside.replace(/,$/, "").trim()
      if (/^[\w$]+$/.test(def)) bindings.push({ local: def, imported: "default", typeOnly, kind: "default" })
    }
  }
  if (braced) {
    for (const piece of braced[1].split(",")) {
      const raw = piece.trim()
      if (!raw) continue
      const t = typeOnly || /^type\s+/.test(raw)
      const cleaned = raw.replace(/^type\s+/, "")
      const [imported, local] = cleaned.split(/\s+as\s+/).map((s) => s.trim())
      if (!imported) continue
      bindings.push({ local: local || imported, imported, typeOnly: t, kind: "named" })
    }
  }
  return { bindings, typeOnly }
}

const collectImports = (code, lineOf) => {
  const imports = []
  const spans = []
  for (const re of [IMPORT_FROM, IMPORT_BARE, EXPORT_FROM, IMPORT_DYNAMIC]) re.lastIndex = 0

  for (const m of code.matchAll(IMPORT_FROM)) {
    const start = m.index + m[1].length
    const { bindings, typeOnly } = parseBindings(m[2] ?? "")
    imports.push({
      specifier: m[3], line: lineOf(start), bindings, typeOnly,
      clause: m[2] ?? "", kind: "import", start, end: m.index + m[0].length,
    })
    spans.push([start, m.index + m[0].length])
  }
  for (const m of code.matchAll(IMPORT_BARE)) {
    const start = m.index + m[1].length
    imports.push({ specifier: m[2], line: lineOf(start), bindings: [], typeOnly: false, kind: "side-effect", start, end: m.index + m[0].length })
    spans.push([start, m.index + m[0].length])
  }
  for (const m of code.matchAll(EXPORT_FROM)) {
    const start = m.index + m[1].length
    const star = m[2].startsWith("*")
    const names = star ? [] : parseBindings(m[2]).bindings
    imports.push({
      specifier: m[3], line: lineOf(start), bindings: names, typeOnly: false,
      kind: star ? "star-reexport" : "reexport", start, end: m.index + m[0].length,
    })
    spans.push([start, m.index + m[0].length])
  }
  for (const m of code.matchAll(IMPORT_DYNAMIC)) {
    imports.push({ specifier: m[1], line: lineOf(m.index), bindings: [], typeOnly: false, kind: "dynamic", start: m.index, end: m.index + m[0].length })
  }
  return { imports, spans }
}

const collectExports = (code, lineOf) => {
  const exports = []
  for (const m of code.matchAll(EXPORT_DECL)) {
    const kindWord = m[0].match(/\b(const|let|var|function|class|type|enum|interface)\b/)
    exports.push({ name: m[2], line: lineOf(m.index), kind: kindWord ? kindWord[1] : "const", at: m.index })
  }
  for (const m of code.matchAll(EXPORT_LIST)) {
    for (const piece of m[2].split(",")) {
      const raw = piece.trim().replace(/^type\s+/, "")
      if (!raw) continue
      const parts = raw.split(/\s+as\s+/).map((s) => s.trim())
      const name = parts[1] || parts[0]
      if (/^[\w$]+$/.test(name)) exports.push({ name, line: lineOf(m.index), kind: "list", at: m.index })
    }
  }
  return exports
}

const MEMBER_MODIFIERS = new Set([
  "get", "set", "async", "static", "override", "readonly", "public", "private", "protected", "abstract",
])
const IDENT_START = /[A-Za-z_$#]/
const readIdentBack = (code, at) => {
  let j = at
  while (j >= 0 && /[\w$#]/.test(code[j])) j--
  return { text: code.slice(j + 1, at + 1), before: j }
}
const skipBack = (code, at) => {
  let j = at
  while (j >= 0 && /\s/.test(code[j])) j--
  return j
}
const skipFwd = (code, at) => {
  let j = at
  while (j < code.length && /\s/.test(code[j])) j++
  return j
}

const bodyStartAfterParams = (code, closeParen) => {
  let j = skipFwd(code, closeParen + 1)
  if (code[j] === "=" && code[j + 1] === ">") return { arrow: true, at: skipFwd(code, j + 2) }
  if (code[j] === "{") return { arrow: false, at: j }
  if (code[j] === ":") {
    let depth = 0
    for (let k = j + 1; k < code.length; k++) {
      const c = code[k]
      if (depth === 0 && c === "{") {
        let at = k
        for (;;) {
          const close = matching(code, at)
          if (close < 0) break
          const next = skipFwd(code, close + 1)
          if (code[next] !== "{") break
          at = next
        }
        return { arrow: false, at }
      }
      if (depth === 0 && c === "=" && code[k + 1] === ">") return { arrow: true, at: skipFwd(code, k + 2) }
      if (depth === 0 && (c === ";" || c === ")")) return null
      if ("([{<".includes(c)) depth++
      else if (")]}>".includes(c)) depth--
      if (depth < 0) return null
    }
    return null
  }
  return null
}

const spanEnd = (code, body) => {
  if (code[body.at] === "{") {
    const end = matching(code, body.at)
    return end < 0 ? code.length : end + 1
  }
  let depth = 0
  for (let k = body.at; k < code.length; k++) {
    const c = code[k]
    if ("([{".includes(c)) depth++
    else if (")]}".includes(c)) { if (depth === 0) return k; depth-- }
    else if (depth === 0 && (c === ";" || c === "\n")) return k
  }
  return code.length
}

const splitParams = (text) => {
  const parts = []
  let depth = 0
  let current = ""
  for (const c of text) {
    if ("([{<".includes(c)) depth++
    else if (")]}>".includes(c)) depth--
    if (c === "," && depth === 0) { parts.push(current); current = ""; continue }
    current += c
  }
  parts.push(current)
  return parts.map((p) => p.trim()).filter(Boolean)
}

const collectFunctions = (code, lineOf) => {
  const functions = []
  for (let i = 0; i < code.length; i++) {
    if (code[i] !== "(") continue
    const close = matching(code, i)
    if (close < 0) continue

    const beforeParen = skipBack(code, i - 1)
    if (beforeParen < 0) continue

    let kind = null
    let name = ""
    if (/[\w$#]/.test(code[beforeParen])) {
      const ident = readIdentBack(code, beforeParen)
      if (!IDENT_START.test(ident.text[0] ?? "") || KEYWORDS.has(ident.text)) continue
      const prev = skipBack(code, ident.before)
      const prevIdent = prev >= 0 && /[\w$]/.test(code[prev]) ? readIdentBack(code, prev) : null
      if (prevIdent && prevIdent.text === "function") {
        kind = "function"
        name = ident.text
      } else if (prevIdent && MEMBER_MODIFIERS.has(prevIdent.text)) {
        kind = "method"
        name = ident.text
      } else if (prev < 0 || /[;{}]/.test(code[prev]) || code.slice(code.lastIndexOf("\n", ident.before) + 1, ident.before + 1).trim() === "") {
        kind = "method"
        name = ident.text
      } else continue
    } else if (/[=,(]/.test(code[beforeParen]) || code[beforeParen] === ">") {
      let j = beforeParen
      if (/[\w$]/.test(code[skipBack(code, j)] ?? "")) continue
      if (code[j] === "=" && code[j - 1] !== "=" && code[j + 1] !== "=") {
        const nameEnd = skipBack(code, j - 1)
        if (nameEnd < 0 || !/[\w$]/.test(code[nameEnd])) continue
        const ident = readIdentBack(code, nameEnd)
        const declEnd = skipBack(code, ident.before)
        const decl = declEnd >= 0 && /[\w$]/.test(code[declEnd]) ? readIdentBack(code, declEnd).text : ""
        if (decl !== "const" && decl !== "let" && decl !== "var") continue
        kind = "arrow"
        name = ident.text
      } else continue
    } else continue

    const body = bodyStartAfterParams(code, close)
    if (!body) continue
    if (kind === "method" && body.arrow) continue

    const end = spanEnd(code, body)
    functions.push({
      name, kind, start: i, close, bodyAt: body.at, arrow: body.arrow, end,
      line: lineOf(i), endLine: lineOf(end),
      params: splitParams(code.slice(i + 1, close)),
    })
  }
  return functions
}

const input = fs.readFileSync(0, "utf8")
const allFiles = input.split("\n").filter(Boolean)
const isModule = (f) => /^(apps|packages)\/[^/]+\/src\/.+\.ts$/.test(f) && !/\.d\.ts$/.test(f)
const moduleFiles = allFiles.filter(isModule)
const manifestFiles = allFiles.filter((f) => /^(apps|packages)\/[^/]+\/package\.json$/.test(f))

const fails = []
const warns = []
const fail = (line) => fails.push(line)
const warn = (line) => warns.push(line)

if (moduleFiles.length === 0) {
  console.log("OK: aucun module à analyser")
  process.exit(0)
}

const readJson = (file) => {
  try { return JSON.parse(fs.readFileSync(file, "utf8")) } catch { return null }
}

const rootPkg = allFiles.includes("package.json") ? readJson("package.json") : null
const rootDeps = new Set([
  ...Object.keys(rootPkg?.dependencies ?? {}),
  ...Object.keys(rootPkg?.devDependencies ?? {}),
])

const packages = new Map()
for (const file of manifestFiles) {
  const dir = path.dirname(file)
  const pkg = readJson(file)
  if (!pkg) continue
  packages.set(dir, {
    dir, file, pkg,
    name: typeof pkg.name === "string" ? pkg.name : dir,
    deps: new Set(Object.keys(pkg.dependencies ?? {})),
    devDeps: new Set(Object.keys(pkg.devDependencies ?? {})),
    peerDeps: new Set(Object.keys(pkg.peerDependencies ?? {})),
    optDeps: new Set(Object.keys(pkg.optionalDependencies ?? {})),
  })
}
const byName = new Map([...packages.values()].map((p) => [p.name, p]))

const ownerOf = (file) => {
  const dir = file.split("/").slice(0, 2).join("/")
  return packages.get(dir) ?? null
}

const modules = new Map()
for (const file of moduleFiles) {
  let raw
  try { raw = fs.readFileSync(file, "utf8") } catch { continue }
  const { code, bare, literals } = scan(raw)
  const lineOf = lineIndex(code)
  const { imports, spans } = collectImports(bare, lineOf)
  const body = spans.reduce((acc, [a, b]) => acc.slice(0, a) + acc.slice(a, b).replace(/[^\n]/g, " ") + acc.slice(b), code)
  modules.set(file, {
    file, raw, code, body, literals, lineOf, imports,
    exports: collectExports(code, lineOf),
    functions: collectFunctions(code, lineOf),
    brackets: bracketMap(code),
    owner: ownerOf(file),
    isTest: /\.test\.ts$/.test(file),
  })
}

const packageNameOf = (specifier) => {
  const parts = specifier.split("/")
  return specifier.startsWith("@") ? parts.slice(0, 2).join("/") : parts[0]
}

const distToSrc = (entry) => {
  const clean = entry.replace(/^\.\//, "")
  return clean
    .replace(/^dist\//, "src/")
    .replace(/\.d\.ts$/, ".ts")
    .replace(/\.(m|c)?js$/, ".ts")
}

const resolveInternal = (from, specifier) => {
  if (specifier.startsWith(".")) {
    const base = path.posix.join(path.posix.dirname(from), specifier)
    const candidates = [
      base.replace(/\.js$/, ".ts"),
      base.replace(/\.js$/, ".tsx"),
      base,
      `${base}.ts`,
      `${base}/index.ts`,
      `${base.replace(/\.js$/, "")}/index.ts`,
    ]
    for (const c of candidates) if (modules.has(c)) return c
    return null
  }
  const name = packageNameOf(specifier)
  const target = byName.get(name)
  if (!target) return null
  const sub = specifier.slice(name.length).replace(/^\//, "")
  if (sub) {
    for (const c of [`${target.dir}/src/${sub}.ts`, `${target.dir}/src/${sub}/index.ts`, `${target.dir}/src/${sub}`]) {
      if (modules.has(c)) return c
    }
  }
  const entries = []
  const walkExports = (node) => {
    if (typeof node === "string") entries.push(node)
    else if (node && typeof node === "object") for (const v of Object.values(node)) walkExports(v)
  }
  walkExports(target.pkg.exports)
  for (const field of ["main", "module", "types"]) if (typeof target.pkg[field] === "string") entries.push(target.pkg[field])
  for (const e of entries) {
    const c = `${target.dir}/${distToSrc(e)}`
    if (modules.has(c)) return c
  }
  const index = `${target.dir}/src/index.ts`
  return modules.has(index) ? index : null
}

for (const mod of modules.values()) {
  mod.edges = []
  for (const imp of mod.imports) {
    imp.internal = resolveInternal(mod.file, imp.specifier)
    imp.external = !imp.specifier.startsWith(".") && !imp.internal
    if (imp.internal) mod.edges.push(imp)
  }
}

const escapeName = (name) => name.replace(/[$]/g, "\\$")
const occurrences = (text, name) => {
  const out = []
  const re = new RegExp(`(?<![\\w$.#])${escapeName(name)}(?![\\w$])`, "g")
  let m
  while ((m = re.exec(text)) !== null) out.push(m.index)
  return out
}

const colours = new Map()
const stack = []
const cycles = []
const visit = (file) => {
  colours.set(file, "grey")
  stack.push(file)
  for (const edge of modules.get(file).edges) {
    const next = edge.internal
    if (!modules.has(next)) continue
    const colour = colours.get(next)
    if (colour === "grey") {
      const at = stack.indexOf(next)
      cycles.push([...stack.slice(at), next])
    } else if (colour === undefined) visit(next)
  }
  stack.pop()
  colours.set(file, "black")
}
for (const file of [...modules.keys()].sort()) if (!colours.has(file)) visit(file)

const seenCycles = new Set()
for (const cycle of cycles) {
  const key = [...cycle].slice(0, -1).sort().join(">")
  if (seenCycles.has(key)) continue
  seenCycles.add(key)
  fail(`64 cycle d'import : ${cycle.join(" → ")}`)
}

const importedNames = new Map()
const starReexports = new Map()
for (const mod of modules.values()) {
  for (const imp of mod.imports) {
    if (!imp.internal) continue
    if (imp.kind === "star-reexport") {
      if (!starReexports.has(mod.file)) starReexports.set(mod.file, [])
      starReexports.get(mod.file).push(imp.internal)
      continue
    }
    if (!importedNames.has(imp.internal)) importedNames.set(imp.internal, new Set())
    for (const b of imp.bindings) importedNames.get(imp.internal).add(b.imported)
  }
}

for (const mod of modules.values()) {
  for (const imp of mod.imports) {
    if (imp.kind === "side-effect" || imp.kind === "dynamic") continue
    for (const b of imp.bindings) {
      if (b.local.startsWith("_")) continue
      if (occurrences(mod.body, b.local).length === 0) {
        fail(`65 ${mod.file}:${imp.line} — import "${b.local}" inutilisé`)
      }
    }
  }
}

const usedExternal = new Map()
for (const mod of modules.values()) {
  const owner = mod.owner
  for (const imp of mod.imports) {
    const spec = imp.specifier
    if (spec.startsWith(".")) {
      if (!imp.internal) fail(`423 ${mod.file}:${imp.line} — import "${spec}" ne résout aucun module`)
      continue
    }
    const name = packageNameOf(spec)
    if (BUILTINS.has(name) || BUILTINS.has(spec)) continue
    if (!owner) continue
    if (!usedExternal.has(owner.dir)) usedExternal.set(owner.dir, new Map())
    const seen = usedExternal.get(owner.dir)
    if (!seen.has(name)) seen.set(name, { runtime: false, line: imp.line, file: mod.file })
    if (!mod.isTest) seen.get(name).runtime = true

    const declared = owner.deps.has(name) || owner.devDeps.has(name) || owner.peerDeps.has(name) || owner.optDeps.has(name)
    if (!declared) {
      if (byName.has(name)) fail(`75 ${mod.file}:${imp.line} — "${name}" absent des dépendances de ${owner.file}`)
      else if (!rootDeps.has(name)) fail(`76/423 ${mod.file}:${imp.line} — dépendance fantôme "${name}", absente de ${owner.file}`)
      continue
    }
    if (!mod.isTest && !owner.deps.has(name) && !owner.peerDeps.has(name) && !owner.optDeps.has(name) && owner.devDeps.has(name)) {
      fail(`98 ${mod.file}:${imp.line} — "${name}" utilisé à l'exécution mais rangé en devDependencies`)
    }
  }
}

for (const owner of packages.values()) {
  const used = usedExternal.get(owner.dir) ?? new Map()
  const hasModules = [...modules.values()].some((m) => m.owner === owner)
  if (!hasModules) continue
  for (const dep of owner.deps) {
    if (!used.has(dep)) fail(`422 ${owner.file} — dépendance "${dep}" déclarée mais jamais importée`)
  }
  for (const dep of owner.devDeps) {
    if (TOOLCHAIN.test(dep) || used.has(dep)) continue
    fail(`422 ${owner.file} — devDependency "${dep}" déclarée mais jamais importée`)
  }
}

const roots = new Set()
const rootsByPackage = new Map()
const addRoot = (file, ownerDir) => {
  if (!modules.has(file)) return
  roots.add(file)
  const dir = ownerDir ?? file.split("/").slice(0, 2).join("/")
  if (!rootsByPackage.has(dir)) rootsByPackage.set(dir, new Set())
  rootsByPackage.get(dir).add(file)
}
for (const owner of packages.values()) {
  const entries = []
  const walkExports = (node) => {
    if (typeof node === "string") entries.push(node)
    else if (node && typeof node === "object") for (const v of Object.values(node)) walkExports(v)
  }
  walkExports(owner.pkg.exports)
  for (const field of ["main", "module", "types"]) if (typeof owner.pkg[field] === "string") entries.push(owner.pkg[field])
  if (typeof owner.pkg.bin === "string") entries.push(owner.pkg.bin)
  else if (owner.pkg.bin && typeof owner.pkg.bin === "object") entries.push(...Object.values(owner.pkg.bin).filter((v) => typeof v === "string"))
  for (const e of entries) addRoot(`${owner.dir}/${distToSrc(e)}`, owner.dir)
  addRoot(`${owner.dir}/src/index.ts`, owner.dir)
}
for (const extra of EXTRA_ROOTS) addRoot(extra)
const entryRoots = new Set(roots)
for (const mod of modules.values()) if (mod.isTest) roots.add(mod.file)

const reachable = new Set()
const walkGraph = (file) => {
  if (reachable.has(file)) return
  reachable.add(file)
  for (const edge of modules.get(file)?.edges ?? []) if (modules.has(edge.internal)) walkGraph(edge.internal)
}
for (const r of roots) walkGraph(r)

const publicModules = new Set()
const walkPublic = (file) => {
  if (publicModules.has(file)) return
  publicModules.add(file)
  for (const target of starReexports.get(file) ?? []) walkPublic(target)
}
for (const r of entryRoots) walkPublic(r)

const analysable = new Set()
for (const owner of packages.values()) {
  const entries = rootsByPackage.get(owner.dir)
  if (entries && entries.size > 0) analysable.add(owner.dir)
}
const skippedPackages = [...packages.values()]
  .filter((p) => !analysable.has(p.dir) && [...modules.values()].some((m) => m.owner === p))
  .map((p) => p.dir)

for (const mod of modules.values()) {
  if (mod.isTest || !mod.owner || !analysable.has(mod.owner.dir)) continue
  if (!reachable.has(mod.file)) fail(`125 ${mod.file} — inatteignable depuis les points d'entrée`)
}

const testCode = [...modules.values()].filter((m) => m.isTest).map((m) => m.body).join("\n")

for (const mod of modules.values()) {
  if (mod.isTest || !mod.owner || !analysable.has(mod.owner.dir)) continue
  const isPublic = publicModules.has(mod.file)
  const consumed = importedNames.get(mod.file) ?? new Set()
  for (const exp of mod.exports) {
    if (isPublic || consumed.has(exp.name)) continue
    if (occurrences(mod.body, exp.name).length > 1) continue
    warn(`124 ${mod.file}:${exp.line} — export "${exp.name}" consommé nulle part`)
  }
  if (!CHECK_UNTESTED) continue
  for (const exp of mod.exports) {
    if (exp.kind !== "function" && exp.kind !== "class") continue
    if (occurrences(testCode, exp.name).length === 0) {
      warn(`154 ${mod.file}:${exp.line} — fonction exportée "${exp.name}" appelée par aucun test`)
    }
  }
}

const TYPE_MARKER_WORDS = new Set(["as", "satisfies"])
const isTernaryColon = (mod, at) => {
  const { depth } = mod.brackets
  const level = depth[at]
  for (let k = at - 1; k >= 0; k--) {
    if (depth[k] < level) return false
    if (depth[k] > level) continue
    const c = mod.body[k]
    if (c === "?" && mod.body[k - 1] !== "?" && mod.body[k + 1] !== "?") return true
    if (c === ";" || c === "{" || c === "}" || c === "\n") return false
  }
  return false
}
const isTypePosition = (mod, at) => {
  const code = mod.body
  const line = code.slice(code.lastIndexOf("\n", at) + 1, at)
  if (/^\s*(export\s+)?type\s+[\w$]+\s*=/.test(line)) return true
  const j = skipBack(code, at - 1)
  if (j < 0) return false
  const c = code[j]
  if (c === "<" && j === at - 1 && j > 0 && /[\w$>\]]/.test(code[j - 1])) return true
  if (c === "|" || c === "&") return true
  if (c === ":") {
    if (isTernaryColon(mod, j)) return false
    const enclosing = mod.brackets.inner[at]
    return enclosing === "(" || enclosing === ""
  }
  if (/[\w$]/.test(c)) return TYPE_MARKER_WORDS.has(readIdentBack(code, j).text)
  return false
}

for (const mod of modules.values()) {
  for (const imp of mod.imports) {
    if (imp.kind !== "import" || imp.typeOnly || imp.bindings.length === 0) continue
    if (imp.bindings.every((b) => b.typeOnly)) continue
    let allTypes = true
    let anyUse = false
    for (const b of imp.bindings) {
      if (b.typeOnly) continue
      for (const at of occurrences(mod.body, b.local)) {
        anyUse = true
        if (!isTypePosition(mod, at)) { allTypes = false; break }
      }
      if (!allTypes) break
    }
    if (allTypes && anyUse) {
      fail(`46 ${mod.file}:${imp.line} — import de "${imp.specifier}" utilisé uniquement comme type, écrire "import type"`)
    }
  }
}

const topLevelHas = (text, ch) => {
  let depth = 0
  for (const c of text) {
    if ("([{<".includes(c)) depth++
    else if (")]}>".includes(c)) depth--
    else if (c === ch && depth === 0) return true
  }
  return false
}

const DECISION = /\b(if|for|while|catch)\s*\(|\bcase\b|\bdo\s*\{/g
const complexityOf = (code, from, to) => {
  const span = code.slice(from, to)
  let count = (span.match(DECISION) ?? []).length
  for (let i = 0; i < span.length; i++) {
    if (span[i] !== "?") continue
    if (span[i - 1] === "?" || span[i + 1] === "?" || span[i + 1] === "." || span[i + 1] === ":") continue
    count++
  }
  return count
}

const BLOCK_BEFORE = /[)>;{}]$/
const nestingOf = (code, from, to) => {
  let depth = 0
  let max = 0
  const kinds = []
  for (let i = from; i < to; i++) {
    const c = code[i]
    if (c === "{") {
      if (i === from) { kinds.push(true); depth = 1; max = 1; continue }
      const j = skipBack(code, i - 1)
      const prev = j < 0 ? ";" : code[j]
      let block = BLOCK_BEFORE.test(prev)
      if (/[\w$]/.test(prev)) block = ["else", "try", "finally", "do"].includes(readIdentBack(code, j).text)
      kinds.push(block)
      if (block) { depth++; if (depth > max) max = depth }
      continue
    }
    if (c === "}") {
      if (kinds.pop()) depth--
      continue
    }
  }
  return Math.max(0, max - 1)
}

for (const mod of modules.values()) {
  for (const fn of mod.functions) {
    const label = fn.name ? `${fn.name}()` : "fonction anonyme"
    const lines = fn.endLine - fn.line + 1
    if (lines > MAX_FUNCTION_LINES) {
      fail(`99 ${mod.file}:${fn.line} — ${label} fait ${lines} lignes (max ${MAX_FUNCTION_LINES})`)
    }
    const complexity = complexityOf(mod.code, fn.bodyAt, fn.end)
    fn.complexity = complexity
    if (complexity > MAX_COMPLEXITY) {
      fail(`101 ${mod.file}:${fn.line} — ${label} a ${complexity} points de décision (max ${MAX_COMPLEXITY})`)
    }
    const nesting = nestingOf(mod.code, fn.bodyAt, fn.end)
    fn.nesting = nesting
    if (nesting > MAX_NESTING) {
      fail(`102 ${mod.file}:${fn.line} — ${label} imbrique ${nesting} niveaux (max ${MAX_NESTING})`)
    }
    for (const param of fn.params) {
      const clean = param.replace(/^(readonly|public|private|protected|override)\s+/g, "").trim()
      if (!clean || clean.startsWith("this:")) continue
      if (topLevelHas(clean, ":") || topLevelHas(clean, "=")) continue
      fail(`35 ${mod.file}:${fn.line} — ${label} paramètre "${clean}" sans type`)
    }
  }
}

for (const mod of modules.values()) {
  const code = mod.code
  for (const m of code.matchAll(/\belse\b/g)) {
    const j = skipBack(code, m.index - 1)
    if (j < 0) continue
    let last = ""
    if (code[j] === "}") {
      let depth = 0
      let open = -1
      for (let k = j; k >= 0; k--) {
        if (code[k] === "}") depth++
        else if (code[k] === "{") { depth--; if (depth === 0) { open = k; break } }
      }
      if (open < 0) continue
      const inner = code.slice(open + 1, j).replace(/\s+$/, "")
      last = inner.slice(inner.lastIndexOf("\n") + 1).trim()
    } else {
      const inner = code.slice(0, j + 1)
      last = inner.slice(Math.max(inner.lastIndexOf("\n"), inner.lastIndexOf(";")) + 1).trim()
    }
    if (/^(return|throw|continue|break)\b/.test(last)) {
      fail(`130 ${mod.file}:${mod.lineOf(m.index)} — "else" après une sortie anticipée`)
    }
  }

  for (const m of code.matchAll(/\bswitch\s*\(/g)) {
    const close = matching(code, m.index + m[0].length - 1)
    if (close < 0) continue
    const open = code.indexOf("{", close)
    if (open < 0) continue
    const end = matching(code, open)
    const block = code.slice(open, end < 0 ? code.length : end)
    if (!/\bdefault\s*:/.test(block) && !/\bnever\b/.test(block)) {
      fail(`133 ${mod.file}:${mod.lineOf(m.index)} — "switch" sans "default" ni garde d'exhaustivité`)
    }
  }
}

const asyncNames = new Map()
for (const mod of modules.values()) {
  const names = new Set()
  for (const m of mod.code.matchAll(/\basync\s+function\s*\*?\s*([\w$]+)/g)) names.add(m[1])
  for (const m of mod.code.matchAll(/\b(?:const|let|var)\s+([\w$]+)\s*(?::[^=\n]*)?=\s*async\b/g)) names.add(m[1])
  for (const m of mod.code.matchAll(/\bfunction\s+([\w$]+)\s*\([^)]*\)\s*:\s*Promise\s*</g)) names.add(m[1])
  asyncNames.set(mod.file, names)
}

for (const mod of modules.values()) {
  const local = new Set(asyncNames.get(mod.file))
  for (const imp of mod.imports) {
    if (!imp.internal) continue
    const target = asyncNames.get(imp.internal)
    if (!target) continue
    for (const b of imp.bindings) if (target.has(b.imported)) local.add(b.local)
  }
  if (local.size === 0) continue
  for (const m of mod.body.matchAll(/(^|[;{}\n])(\s*)([\w$]+)\s*\(/g)) {
    if (!local.has(m[3])) continue
    const at = m.index + m[0].length - 1
    const close = matching(mod.code, at)
    const after = close < 0 ? "" : mod.code.slice(close + 1, close + 8)
    if (/^\s*[.?]/.test(after)) continue
    fail(`117 ${mod.file}:${mod.lineOf(at)} — appel à "${m[3]}" renvoyant une promesse, sans await ni void`)
  }
}

const typeAliasBody = (code, from) => {
  let depth = 0
  let i = from
  while (i < code.length) {
    const c = code[i]
    if ("([{<".includes(c)) depth++
    else if (")]}>".includes(c)) depth--
    if (c === ";" && depth === 0) return code.slice(from, i)
    if (c === "\n" && depth === 0) {
      const trimmed = code.slice(from, i).replace(/\s+$/, "")
      const next = code.slice(i + 1).match(/^\s*/)[0]
      const nextChar = code[i + 1 + next.length] ?? ""
      if (!/[|&=,([<+?:]$/.test(trimmed) && !"|&".includes(nextChar)) return trimmed
    }
    i++
  }
  return code.slice(from)
}

const splitUnion = (text) => {
  const parts = []
  let depth = 0
  let current = ""
  for (const c of text) {
    if ("([{<".includes(c)) depth++
    else if (")]}>".includes(c)) depth--
    if (c === "|" && depth === 0) { parts.push(current); current = ""; continue }
    current += c
  }
  parts.push(current)
  return parts.map((p) => p.trim()).filter(Boolean)
}

for (const mod of modules.values()) {
  for (const m of mod.code.matchAll(/(^|[\n;])[ \t]*(?:export\s+)?type\s+([\w$]+)\s*(?:<[^=]*>)?\s*=/g)) {
    const from = m.index + m[0].length
    const body = typeAliasBody(mod.code, from)
    const members = splitUnion(body)
    if (members.length < 2) continue
    if (!members.every((x) => x.startsWith("{"))) continue
    const bad = members.filter((x) => !/[\w$]+\??\s*:\s*("[^"]*"|'[^']*'|`[^`]*`|-?\d[\d_.]*|true|false)/.test(x))
    if (bad.length > 0) {
      warn(`56 ${mod.file}:${mod.lineOf(m.index + 1)} — union "${m[2]}" sans discriminant littéral`)
    }
  }
}

const groupQuantified = (pattern) => {
  for (let i = 0; i < pattern.length; i++) {
    if (pattern[i] === "\\") { i++; continue }
    if (pattern[i] !== "(") continue
    let depth = 0
    let end = -1
    for (let j = i; j < pattern.length; j++) {
      if (pattern[j] === "\\") { j++; continue }
      if (pattern[j] === "(") depth++
      else if (pattern[j] === ")") { depth--; if (depth === 0) { end = j; break } }
    }
    if (end < 0) continue
    const after = pattern.slice(end + 1)
    if (!/^[*+]|^\{\d+,\}/.test(after)) continue
    const inner = pattern.slice(i + 1, end).replace(/^\?[:=!<]*/, "")
    if (/[*+]|\{\d+,\}/.test(inner) || /^([^|]+)\|\1$/.test(inner)) return inner
  }
  return null
}

for (const mod of modules.values()) {
  const patterns = mod.literals
    .filter((l) => l.kind === "regex")
    .map((l) => ({ value: l.value, line: mod.lineOf(l.at) }))
  for (const m of mod.raw.matchAll(/new\s+RegExp\s*\(\s*["'`]([^"'`]*)["'`]/g)) {
    patterns.push({ value: m[1], line: mod.lineOf(m.index) })
  }
  for (const p of patterns) {
    const inner = groupQuantified(p.value)
    if (inner) fail(`381 ${mod.file}:${p.line} — regex à retour arrière exponentiel : groupe "(${inner})" quantifié`)
  }
}

const REDUNDANT = /\b(?:const|let)\s+[\w$]+\s*:\s*(string|number|boolean)\s*=\s*([^\n;]+)/g
for (const mod of modules.values()) {
  for (const m of mod.code.matchAll(REDUNDANT)) {
    const init = m[2].trim()
    const literal =
      (m[1] === "string" && /^(["'`])/.test(init)) ||
      (m[1] === "number" && /^-?\d/.test(init)) ||
      (m[1] === "boolean" && /^(true|false)\b/.test(init))
    if (literal) warn(`507 ${mod.file}:${mod.lineOf(m.index)} — annotation ": ${m[1]}" déjà déduite du littéral`)
  }
}

const NOISE = /^[\s})\],;]*$/
const windows = new Map()
for (const mod of modules.values()) {
  const kept = []
  mod.code.split("\n").forEach((text, idx) => {
    const trimmed = text.trim()
    if (!trimmed || NOISE.test(trimmed)) return
    kept.push({ text: trimmed.replace(/\s+/g, " "), line: idx + 1 })
  })
  for (let i = 0; i + DUP_LINES <= kept.length; i++) {
    const slice = kept.slice(i, i + DUP_LINES)
    const key = slice.map((l) => l.text).join("\n")
    if (!windows.has(key)) windows.set(key, [])
    windows.get(key).push({ file: mod.file, line: slice[0].line })
  }
}
const reportedDup = new Set()
for (const [, hits] of windows) {
  if (hits.length < 2) continue
  const first = hits[0]
  const second = hits.find((h) => h.file !== first.file || h.line !== first.line)
  if (!second) continue
  const key = `${first.file}|${second.file}`
  if (reportedDup.has(key)) continue
  reportedDup.add(key)
  warn(`105 ${first.file}:${first.line} — bloc de ${DUP_LINES} lignes dupliqué en ${second.file}:${second.line}`)
}

fails.sort()
warns.sort()
for (const line of fails) console.log(`FAIL: ${line}`)
for (const line of warns) console.log(`WARN: ${line}`)

if (fails.length > 0) {
  console.log("")
  console.log(`TOTAL: ${fails.length} violation(s)`)
  process.exit(1)
}

const maxComplexity = Math.max(0, ...[...modules.values()].flatMap((m) => m.functions.map((f) => f.complexity ?? 0)))
const skipped = skippedPackages.length > 0 ? `, 124/125 ignoré pour ${skippedPackages.join(", ")} (aucun point d'entrée déclaré)` : ""
console.log(
  `OK: ${modules.size} modules, ${[...modules.values()].reduce((n, m) => n + m.edges.length, 0)} arêtes, ` +
    `aucun cycle, complexité max ${maxComplexity}${skipped}`,
)
