#!/usr/bin/env bash
set -euo pipefail
# Report only closed preparation stages, preserving the original failing status.
clang_preparation_stage=require-ubuntu-sources
clang_preparation_failed() {
  local primary_status="$1"
  printf 'ActQL Linux compiler preparation failed: stage=%s status=%s\n' \
    "$clang_preparation_stage" "$primary_status" >&2 || :
  exit "$primary_status"
}
trap 'clang_preparation_failed "$?"' ERR
if [ "$#" -ne 0 ]; then
  clang_preparation_stage=select-clang-profile
  test "$#" -eq 1
  test "$1" = --packed-query-native
fi
# This compiler comes from Ubuntu. An unrelated image repository must not
# participate in its acquisition; retain the image's signed Ubuntu suites.
ubuntu_sources=/etc/apt/sources.list.d/ubuntu.sources
test -s "$ubuntu_sources"
# Preserve the signed Ubuntu suites while selecting their canonical mirror.
if [ -f /etc/apt/apt-mirrors.txt ]; then
  clang_preparation_stage=select-ubuntu-mirror
  printf '%s\n' 'https://archive.ubuntu.com/ubuntu/' | sudo tee /etc/apt/apt-mirrors.txt > /dev/null
fi
apt_options=(-o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30
  -o "Dir::Etc::sourcelist=$ubuntu_sources" -o Dir::Etc::sourceparts=-)
clang_preparation_stage=update-ubuntu-index
sudo apt-get "${apt_options[@]}" update --error-on=any
if [ "$#" -eq 1 ]; then
  clang_preparation_stage=resolve-clang-version
  clang_version="$(LC_ALL=C apt-cache "${apt_options[@]}" policy clang-19 |
    awk '$1 == "Candidate:" { print $2 }')"
  test -n "$clang_version"
  test "$clang_version" != '(none)'
  # Keep Clang's resource runtime while omitting the additional LLVM development tools.
  clang_preparation_stage=install-clang
  sudo apt-get "${apt_options[@]}" install --yes --no-install-recommends \
    "clang-19=$clang_version" "libclang-rt-19-dev=$clang_version"
else
  clang_preparation_stage=install-clang
  sudo apt-get "${apt_options[@]}" install --yes clang-19
fi
clang_preparation_stage=verify-selected-clang
test -x /usr/bin/clang-19
