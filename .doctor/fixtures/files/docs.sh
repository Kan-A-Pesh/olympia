[ -f packages/bad-pkg/package.json ] || printf '{ "name": "bad-pkg" }\n' > packages/bad-pkg/package.json
printf '# bad-pkg\n' > packages/bad-pkg/README.md
