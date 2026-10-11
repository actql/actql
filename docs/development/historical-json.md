# Historical JSON storage

Historical identities are immutable logical snapshots. Their storage representation
is separate from runtime canonical JSON, CIDs, schema pins and protocol contracts.
The archive preserves every original JSON value and its exact original UTF-8 bytes;
it does not recompute history from current product sources or require Git history.
It works in source archives, shallow clones and offline checkouts.

## Reading and checking

Use `readHistoricalJson(path)` from `scripts/historical-json.mjs` instead of direct
file reads for historical fixtures. Paths registered in the archive resolve there;
unregistered files remain ordinary JSON, so independent feature branches can add
new historical snapshots without immediately converting them. Registered corruption
fails closed. There is no fallback to current contracts or other snapshots.

Run `node scripts/historical-json-archive.mjs check` to verify the complete archive.
`npm run check:historical-json` also runs focused codec tests. The npm lifecycle
script `precheck:expression-syntax` runs it before `check:expression-syntax`, hence
through the existing `check:spec` aggregate and specification CI. Keep npm lifecycle
scripts enabled on this verification chain; `--ignore-scripts` would skip the hook.
Custom invocations that disable lifecycle scripts must run the separate explicit
`npm run check:historical-json` command as well. For local test execution use the
repository's bounded, nonzero-test wrappers described in the local verification
skill.

To inspect original files without Git or network access:

```sh
node scripts/historical-json-archive.mjs export /tmp/actql-history-originals
```

The destination must not already exist. Exports recreate the original logical paths
and exact bytes, including object ordering, two-space indentation and final newline.

## Adding snapshots

Author and independently review the complete fixed historical JSON first. Keep the
independent full-document CID assertions in history tests; never derive expected
identities from current runtime output. Use the shared reader for the new snapshot.
Then append explicitly selected paths:

```sh
node scripts/historical-json-archive.mjs import \
  portability/corpus/historical/pre-example-contract-identities.json \
  portability/corpus/historical/pre-example-preimages.json \
  scripts/fixtures/pre-example-values-identities.json
```

Import checks the previous archive, rejects overwriting existing snapshots, validates
new exact-byte round trips, and preserves previous roots, receipts and objects.
Original input files are retained. After reviewing an export against those inputs
and running affected history tests, remove the duplicate raw files in the same
change. Existing unrelated raw histories need not be migrated. `--initial` is only
for creation of a new archive and refuses an existing archive directory.

Import is deterministic for a given existing archive and set of inputs. New imports
share within their batch; existing objects also reuse identical content addresses.
Previous roots are never rewritten merely to increase compression.

## Archive representation

The `actql-historical-json/0.1` format is a tooling storage format, not a change to
any runtime identity domain. `manifest.json` maps each logical path to a typed root
and raw/canonical byte counts and SHA-256 digests. `receipts.json` independently lists
that immutable inventory and those original digests; full-document CID literals in
existing tests remain the independent acceptance oracle. `objects.json` is a sorted
map of SHA-256 addresses to stored typed nodes, avoiding thousands of small files.

Nodes are `["v", scalar]`, `["a", nodes]`, `["o", [[key, node], ...]]`, or
`["r", sha256]`. All JSON values are tagged, so user keys, tag-like arrays and strings
cannot collide with references. Object entry order is preserved for exact raw-byte
reconstruction. Object addresses hash compact storage-node JSON, including tags and
references; these addresses are not ActQL canonical CIDs. Shared nodes are expanded
into independent values rather than mutable aliases.

Reads check stored hashes and full reconstructed raw and canonical digests. Bounds
cover file size, stored nesting, reference traversal, expanded node visits, logical
pretty-output bytes and depth. Unknown tags, duplicate object keys, missing objects,
cycles, mismatched inventory and modified receipts are errors. Digest checks detect
corruption, not adversarial simultaneous rewriting of every independent pin: review
must retain existing fixed identity assertions and the original digest receipts.
