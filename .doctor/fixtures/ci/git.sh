mkdir -p .githooks coverage hardware/bad-case
printf '#!/usr/bin/env bash\necho pas de checks\n' > .githooks/pre-commit
printf '{ "total": 0 }\n' > coverage/coverage-final.json
printf 'solid bad-case\nendsolid bad-case\n' > hardware/bad-case/panel.stl
