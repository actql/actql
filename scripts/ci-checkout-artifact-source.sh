#!/usr/bin/env bash
# A previously prepared controller's ignored emit cannot follow a source switch.
set -euo pipefail

source_sha="${1:?Expected the verified artifact source SHA}"
[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]]
controller_sha=$(git rev-parse HEAD)
if [[ "$source_sha" != "$controller_sha" ]]; then
  git ls-files -z -- '*.mts' '*.cts' |
    while IFS= read -r -d '' input; do
      case "$input" in
        *.d.mts|*.d.cts) continue ;;
        *.mts) printf '%s\0' "${input%.mts}.mjs" "${input%.mts}.d.mts" ;;
        *.cts) printf '%s\0' "${input%.cts}.cjs" "${input%.cts}.d.cts" ;;
      esac
    done |
    xargs -0 sh -c 'if [ "$#" -gt 0 ]; then GIT_LITERAL_PATHSPECS=1 git clean -q -fX -- "$@"; fi' sh
fi

git checkout --detach "$source_sha"
if [[ "$source_sha" != "$controller_sha" && -f tsconfig.tooling.json ]]; then
  (
    unset GITHUB_TOKEN
    npm ci --ignore-scripts
    npm run build:typescript
  )
fi
