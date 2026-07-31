mkdir -p hardware/bad-case/stl hardware/bad-bom
cat > hardware/bad-case/stl/oversize.stl <<'INNER'
solid oversize
facet normal 0 0 0
 outer loop
  vertex 0 0 0
  vertex 300 0 0
  vertex 0 40 12
 endloop
endfacet
endsolid oversize
INNER
node -e '
const fs = require("node:fs")
const buf = Buffer.alloc(84)
buf.writeUInt32LE(999999, 80)
fs.writeFileSync("hardware/bad-bom/dense.stl", buf)
'
cat > hardware/bad-bom/bom.csv <<'INNER'
ref,designation,fournisseur
M3,vis tete cylindrique,TME
INNER
cat > hardware/bad-bom/assembly.md <<'INNER'
# Montage

1. Poser la platine, serrer les vis fournies.
INNER
cat > hardware/bad-case/README.md <<'INNER'
# bad-case

Plateau utile 120 x 40 pour la carte driver.

| Paramètre | Valeur |
|---|---|
| `edp_flex_length` | ? |
INNER
