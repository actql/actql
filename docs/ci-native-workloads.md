# Native workload platform coverage

The complete Linux workload remains the shared functional owner. The macOS
workload retains platform-sensitive execution and Site/Source smoke coverage.
Moving a duplicate to Linux does not remove its original case or substitute a
portable implementation for a Native physical boundary.

## macOS execution owners

| Retained check | Platform obligation |
| --- | --- |
| Native macOS arm64 profile | Actual architecture and selected Moon toolchain |
| SQLite statement and selected API custody | Original SQLite symbol/statement ownership |
| Retained task file ownership | Native filesystem and retained file lifetime |
| Node-free storage publication and control | Native HTTP, SQLite, crypto, storage and default Query ABI |
| Runtime bundle CLI | Native installation, activation and executable identity |
| Publication Store lock | Real cross-process filesystem locking |
| Cancellation | Actual process cancellation and reconstruction |
| Original HTTP CLI controls | Native command, credential and control ABI |
| Resident Site | Original Site/holder process and publication smoke coverage |
| Resident Source | Actual Source/Task execution smoke coverage |

The existing macOS local execution ownership/cancellation checks also remain.
The two background groups retain their original per-group order, private
scratch directories, environment, failure continuation and mandatory final
join. Inline Site execution remains after successful preparation.

## Duplicates owned by Linux

| Check omitted from macOS | Required Linux owner in `native-workloads` | Original command after the Linux stack limit |
| --- | --- | --- |
| Salesforce Effect preview | `runtime` / `native-preview` | `node scripts/test-native-salesforce-effect-preview.mjs` |
| Observation replay | `resident-controls` / `native-observation` | `node scripts/test-native-resident-site.mjs --observation-replay-only` |
| Release recovery | `resident-controls` / `native-release` | `node scripts/test-native-resident-site.mjs --release-recovery-only` |
| Remote runtime | `runtime` / `native-remote` | `node scripts/test-native-remote-runtime.mjs` |
| Resident Effect computation | Inline `native-effect` | `node scripts/test-native-resident-site.mjs --effect-computation-only` |

The original command/environment hashes remain in
`scripts/fixtures/ci-native-obligations.json`. Its explicit counterpart list is
checked against the actual Linux and macOS selections. The required `native`
aggregate and final `check` gate continue to require the Linux workload.

## Required preparation

The retained consumers still need both Bundle and Site commands, SQLite/Crypto
components, owned HTTP/TLS and the generated portable owners. The macOS
`http-packages` selection also calls `runNativeQueryTests('http-client')`;
removing the Remote fixture alone does not eliminate Query construction.
Consequently `--entries all` remains the required component closure for this
list. No retained consumer is allowed to rebuild a missing prerequisite through
a fallback.

Keep the original two construction lanes, then the original serial Query
constructor. The Query tool home and output tree remain private. Its later
consumer retains the original compiler settings, freshness check and exact
execution selection. Work deadlines and the original 1200-second Site bound
remain unchanged. A successful source check does not establish elapsed-time
targets; full hosted measurements are coordinated separately.
