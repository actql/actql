#!/usr/bin/env bash
# A previously prepared controller's ignored emit cannot follow a source switch.
set -euo pipefail

source_sha="${1:?Expected the verified artifact source SHA}"
[[ "$source_sha" =~ ^[0-9a-f]{40}$ ]]
controller_sha=$(git rev-parse HEAD)
if [[ "$source_sha" != "$controller_sha" ]]; then
  git ls-files -z -- '*.mts' |
    while IFS= read -r -d '' input; do
      case "$input" in
        *.d.mts) continue ;;
        *) printf '%s\0' "${input%.mts}.mjs" "${input%.mts}.d.mts" ;;
      esac
    done |
    xargs -0 sh -c 'if [ "$#" -gt 0 ]; then GIT_LITERAL_PATHSPECS=1 git clean -q -fX -- "$@"; fi' sh
fi

git checkout --detach "$source_sha"
if [[ "$source_sha" != "$controller_sha" && -f tsconfig.tooling.json ]]; then
  npm ci --ignore-scripts
  npm run build:typescript
fi
