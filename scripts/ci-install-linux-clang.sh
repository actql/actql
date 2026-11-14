#!/usr/bin/env bash
set -euo pipefail
# Preserve the signed Ubuntu suites while selecting their canonical mirror.
if [ -f /etc/apt/apt-mirrors.txt ]; then
  printf '%s\n' 'https://archive.ubuntu.com/ubuntu/' | sudo tee /etc/apt/apt-mirrors.txt > /dev/null
fi
apt_options=(-o Acquire::Retries=2 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30)
sudo apt-get "${apt_options[@]}" update --error-on=any
sudo apt-get "${apt_options[@]}" install --yes clang-19
test -x /usr/bin/clang-19
