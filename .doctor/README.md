# doctor

Checks déterministes, un par convention. `FAIL` bloque, `WARN` informe, `OK` passe.

```sh
pnpm doctor              # toute la suite
pnpm doctor hardware     # filtre par nom
pnpm doctor:selftest     # vérifie que les checks attrapent leurs violations
```

Le crochet de pré-validation lance `run.sh` avant chaque commit
(`git config core.hooksPath .githooks`, déjà fait à l'installation).

## Écrire un check

`set -euo pipefail`, sortie `FAIL:` / `WARN:` / `OK:`, `exit 1` si au moins un `FAIL`.
Chaque violation est préfixée du numéro de check du catalogue.

Trois règles non négociables :

- **Jamais un processus par fichier.** `wc -l fichier1 fichier2 …`, ou un seul `node -e`.
  Un `wc` par fichier transforme un check d'une seconde en trois minutes.
- **`grep -E` uniquement.** Pas de `-P`, pas de drapeau GNU : la suite tourne sur macOS.
- **Aucune cible, sortie `OK`.** Beaucoup de checks ne trouveront rien pendant des mois.
  Un `find` vide ne doit pas produire d'échec, sinon la suite reste rouge et plus personne
  ne la lit.

Ajouter le check à `selftest.sh` : un check qui n'attrape rien sur les fixtures ne protège
rien.
