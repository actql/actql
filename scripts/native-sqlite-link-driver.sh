#!/usr/bin/env bash
set -euo pipefail

# Moon emits dependency archives before consumer archives (SQLite/HTTP)
# that reference their C symbols. GNU ld must rescan that group; Darwin already rescans it.
for argument in "$@"; do
  if [[ "$argument" == "-c" ]]; then
    exec "${CC:-cc}" "$@"
  fi
done
if [[ "$(uname -s)" == "Linux" ]]; then
  exec "${CC:-cc}" -Wl,--start-group "$@" -Wl,--end-group
fi
exec "${CC:-cc}" "$@"
