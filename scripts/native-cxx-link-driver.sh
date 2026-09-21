#!/usr/bin/env bash
set -euo pipefail

for argument in "$@"; do
  if [[ "$argument" == "-c" ]]; then
    exec "${CC:-cc}" "$@"
  fi
done

arguments=()
for argument in "$@"; do
  if [[ "$argument" == *.c ]]; then
    arguments+=("-x" "c" "$argument" "-x" "none")
  else
    arguments+=("$argument")
  fi
done

exec "${CXX:-c++}" "${arguments[@]}"
