#!/usr/bin/env bash
set -euo pipefail

openssl_compile_flags=()
openssl_link_flags=()
if [[ "$(uname -s)" == "Darwin" ]]; then
  openssl_prefix=""
  if command -v brew >/dev/null 2>&1; then
    openssl_prefix="$(brew --prefix openssl@3 2>/dev/null || true)"
  fi
  if [[ -z "$openssl_prefix" ]]; then
    for candidate in /opt/homebrew/opt/openssl@3 /usr/local/opt/openssl@3; do
      if [[ -d "$candidate/include/openssl" ]]; then
        openssl_prefix="$candidate"
        break
      fi
    done
  fi
  if [[ -n "$openssl_prefix" ]]; then
    openssl_compile_flags+=("-I$openssl_prefix/include")
    openssl_link_flags+=("-L$openssl_prefix/lib")
    openssl_link_flags+=("-Wl,-rpath,$openssl_prefix/lib")
  fi
fi

for argument in "$@"; do
  if [[ "$argument" == "-c" ]]; then
    exec "${CC:-cc}" "${openssl_compile_flags[@]}" "$@"
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

exec "${CXX:-c++}" "${openssl_compile_flags[@]}" "${arguments[@]}" \
  "${openssl_link_flags[@]}"
