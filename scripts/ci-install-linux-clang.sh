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
clang_preparation_stage=select-clang-profile
test "$#" -eq 0
clang_preparation_stage=require-ubuntu-sources
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
clang_preparation_stage=install-clang
sudo apt-get "${apt_options[@]}" install --yes clang-19
clang_preparation_stage=verify-selected-clang
test -x /usr/bin/clang-19
