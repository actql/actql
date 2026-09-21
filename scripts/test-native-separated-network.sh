#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" || "$(uname -m)" != "x86_64" ]]; then
  echo "separated-network native tests require Linux x86_64" >&2
  exit 1
fi

for command in ip iptables curl python3 sudo; do
  command -v "$command" >/dev/null
done

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
scratch_root="${ACTQL_TEST_SCRATCH_ROOT:-$repository_root/.native-network}"
site_user="${ACTQL_TEST_NATIVE_SITE_USER:-$(id -un)}"
suffix="$$"
source_namespace="actql-src-$suffix"
destination_namespace="actql-dst-$suffix"
source_host_interface="as-h-$suffix"
source_site_interface="as-s-$suffix"
destination_host_interface="ad-h-$suffix"
destination_site_interface="ad-s-$suffix"
source_host_ip="10.231.1.1"
source_site_ip="10.231.1.2"
destination_host_ip="10.231.2.1"
destination_site_ip="10.231.2.2"
probe_port="$((39000 + suffix % 1000))"
transfer_port="$((40000 + suffix % 1000))"
source_probe_pid=""
destination_probe_pid=""

cleanup() {
  set +e
  if [[ -n "$source_probe_pid" ]]; then
    kill "$source_probe_pid" 2>/dev/null
  fi
  if [[ -n "$destination_probe_pid" ]]; then
    kill "$destination_probe_pid" 2>/dev/null
  fi
  sudo iptables -D FORWARD -i "$source_host_interface" \
    -o "$destination_host_interface" -j REJECT 2>/dev/null
  sudo iptables -D FORWARD -i "$destination_host_interface" \
    -o "$source_host_interface" -j REJECT 2>/dev/null
  sudo iptables -D FORWARD -i "$source_host_interface" \
    -o "$destination_host_interface" -p tcp \
    -d "$destination_site_ip" --dport "$transfer_port" \
    -j ACCEPT 2>/dev/null
  sudo ip netns exec "$destination_namespace" iptables -D INPUT \
    -p tcp -s "$source_site_ip" --dport "$transfer_port" \
    -j ACCEPT 2>/dev/null
  sudo ip netns delete "$source_namespace" 2>/dev/null
  sudo ip netns delete "$destination_namespace" 2>/dev/null
}
trap cleanup EXIT

mkdir -p "$scratch_root/direct" "$scratch_root/store" \
  "$scratch_root/bundle" "$scratch_root/probes"

sudo ip netns add "$source_namespace"
sudo ip netns add "$destination_namespace"
sudo ip link add "$source_host_interface" type veth \
  peer name "$source_site_interface"
sudo ip link set "$source_site_interface" netns "$source_namespace"
sudo ip link add "$destination_host_interface" type veth \
  peer name "$destination_site_interface"
sudo ip link set "$destination_site_interface" \
  netns "$destination_namespace"

sudo ip address add "$source_host_ip/24" dev "$source_host_interface"
sudo ip link set "$source_host_interface" up
sudo ip address add "$destination_host_ip/24" \
  dev "$destination_host_interface"
sudo ip link set "$destination_host_interface" up

sudo ip netns exec "$source_namespace" \
  ip address add "$source_site_ip/24" dev "$source_site_interface"
sudo ip netns exec "$source_namespace" ip link set lo up
sudo ip netns exec "$source_namespace" \
  ip link set "$source_site_interface" up
sudo ip netns exec "$source_namespace" \
  ip route add default via "$source_host_ip"

sudo ip netns exec "$destination_namespace" \
  ip address add "$destination_site_ip/24" dev "$destination_site_interface"
sudo ip netns exec "$destination_namespace" ip link set lo up
sudo ip netns exec "$destination_namespace" \
  ip link set "$destination_site_interface" up
sudo ip netns exec "$destination_namespace" \
  ip route add default via "$destination_host_ip"

for namespace in "$source_namespace" "$destination_namespace"; do
  sudo ip netns exec "$namespace" iptables -P INPUT DROP
  sudo ip netns exec "$namespace" iptables -A INPUT -i lo -j ACCEPT
  sudo ip netns exec "$namespace" iptables -A INPUT \
    -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
  sudo ip netns exec "$namespace" iptables -P OUTPUT ACCEPT
done

sudo iptables -I FORWARD 1 -i "$source_host_interface" \
  -o "$destination_host_interface" -j REJECT
sudo iptables -I FORWARD 1 -i "$destination_host_interface" \
  -o "$source_host_interface" -j REJECT

sudo ip netns exec "$source_namespace" sudo --user="$site_user" \
  python3 -m http.server "$probe_port" --bind "$source_site_ip" \
  >"$scratch_root/probes/source.log" 2>&1 &
source_probe_pid="$!"
sudo ip netns exec "$destination_namespace" sudo --user="$site_user" \
  python3 -m http.server "$probe_port" --bind "$destination_site_ip" \
  >"$scratch_root/probes/destination.log" 2>&1 &
destination_probe_pid="$!"
sleep 1
kill -0 "$source_probe_pid"
kill -0 "$destination_probe_pid"

if curl --silent --show-error --connect-timeout 1 \
    "http://$source_site_ip:$probe_port/" >/dev/null 2>&1; then
  echo "source Site unexpectedly accepted host inbound traffic" >&2
  exit 1
fi
if curl --silent --show-error --connect-timeout 1 \
    "http://$destination_site_ip:$probe_port/" >/dev/null 2>&1; then
  echo "destination Site unexpectedly accepted host inbound traffic" >&2
  exit 1
fi
if sudo ip netns exec "$source_namespace" sudo --user="$site_user" \
    curl --silent --show-error --connect-timeout 1 \
    "http://$destination_site_ip:$probe_port/" >/dev/null 2>&1; then
  echo "source Site unexpectedly reached destination Site directly" >&2
  exit 1
fi
if sudo ip netns exec "$destination_namespace" sudo --user="$site_user" \
    curl --silent --show-error --connect-timeout 1 \
    "http://$source_site_ip:$probe_port/" >/dev/null 2>&1; then
  echo "destination Site unexpectedly reached source Site directly" >&2
  exit 1
fi

common_environment=(
  "ACTQL_TEST_NATIVE_HTTP_HOST=$source_host_ip"
  "ACTQL_TEST_NATIVE_SITE_NETNS=$source_namespace"
  "ACTQL_TEST_NATIVE_SITE_USER=$site_user"
  "ACTQL_TEST_NATIVE_DESTINATION_NETNS=$destination_namespace"
  "ACTQL_TEST_NATIVE_DESTINATION_USER=$site_user"
  "ACTQL_TEST_NATIVE_DESTINATION_HOST=$destination_site_ip"
  "ACTQL_TEST_NATIVE_TRANSFER_PORT=$transfer_port"
)

sudo iptables -I FORWARD 1 -i "$source_host_interface" \
  -o "$destination_host_interface" -p tcp \
  -d "$destination_site_ip" --dport "$transfer_port" -j ACCEPT
sudo ip netns exec "$destination_namespace" iptables -I INPUT 1 \
  -p tcp -s "$source_site_ip" --dport "$transfer_port" -j ACCEPT
env "${common_environment[@]}" \
  "ACTQL_TEST_SCRATCH_ROOT=$scratch_root/direct" \
  ACTQL_TEST_NATIVE_APPLICATION_OUTPUT_ROUTE=direct \
  node "$repository_root/scripts/test-native-http-client.mjs"
sudo iptables -D FORWARD -i "$source_host_interface" \
  -o "$destination_host_interface" -p tcp \
  -d "$destination_site_ip" --dport "$transfer_port" -j ACCEPT
sudo ip netns exec "$destination_namespace" iptables -D INPUT \
  -p tcp -s "$source_site_ip" --dport "$transfer_port" -j ACCEPT

env "${common_environment[@]}" \
  "ACTQL_TEST_SCRATCH_ROOT=$scratch_root/store" \
  ACTQL_TEST_NATIVE_APPLICATION_OUTPUT_ROUTE=store \
  node "$repository_root/scripts/test-native-http-client.mjs"

env "${common_environment[@]}" \
  "ACTQL_TEST_SCRATCH_ROOT=$scratch_root/bundle" \
  node "$repository_root/scripts/test-native-runtime-bundle-cli.mjs"
