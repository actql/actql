# Borrowed qualified record-name emission

## Scope and ownership

This component originally started at #576,
`168d56827aacd29d10e547eb3d0505ceff7804be`. The parent is now adopted on
main, including its field-binding and Object/JSON name corrections. The final
merge destination is main.

The stepped record append's BeginField previously called `reference_name()`
before constructing its String emitter. For a qualified field this concatenated
`left.` or `right.` with the complete retained spelling in one transition.
Stepping the subsequent emission did not bound that earlier allocation/copy.

The existing encode_core StringEmitCursor now supports two borrowed segments
through `start_prefixed_string_value`. BeginField passes the existing virtual
RecordName's prefix and text without assembling another String. The same
writer, scalar escaping, aggregate byte/node/depth checks, hash sink and
exclusive unfinished-string custody remain authoritative. This is not a
second serializer or finalizable document. Ordinary `start_string_value`
uses the same path with an empty prefix.

Each advance inspects at most 64 UTF-16 units, completing a crossing surrogate
pair. The segment boundary is not a Unicode boundary: a high surrogate at the
end of the prefix and its low surrogate at the start of text form one scalar.
Unpaired surrogates retain typed refusal and original output-limit precedence.
The combined length is checked before String-node admission.

The extra borrowed prefix root fits within the already reserved fixed name
custody. It replaces the borrowed virtual-name state, not a new proportional
buffer or second cursor. The existing append reservation, logical construction
work and poll count are unchanged. Empty-prefix callers retain their original
emission schedule. The append owner still retains prior committed records
through provisional cancellation; its separate builder cleanup reclaims them.

## Independent evidence

- `[["left.<130 a>",1]]` needs 143/142 wire bytes, construction 6/5 and
  workspace 28/27: fixed/name cursor 16, one field's three slots, depth-two
  stacks six, and the retained row three. Limit failures keep zero new records
  and pending cleanup custody.
- Literal escaped output fixes 81 bytes and one scalar node across text,
  measurement, hash and buffered-hash sinks. A surrogate crossing the 64-unit
  boundary completes in that poll, preserving the previous 65-unit position.
- Segment-crossing surrogate pairs, empty segments, exact/one-short bytes,
  invalid Unicode, unfinished-writer interleaving and repeated cancellation
  have explicit tests. Cursor fixtures inspect the borrowed segments; replacing
  them with an eager combined String would violate those expectations.
- Cancellation during qualified-name emission retains the prior row and its
  bytes, removes provisional writer/name custody once, and releases earlier
  records only through separate builder cancellation.
- Required Pool evidence now includes common sink/Unicode and retained
  qualified-name limit/cleanup fixtures. Missing roles or a foreign suite are
  rejected. Adding the exact encode_core suite mapping preserves target/path
  checks; it does not admit arbitrary evidence suites.

## Executed candidate checks

The focused JS selection passed 93/93 (`run-JBQeAT`,
`focused-test-3XEnk7`): encode_core, managed_record_storage/runtime and both
Pool field-binding consumer fixtures. Existing independent Pool control and
workspace bounds remain unchanged.

After rebuilding only local-node/run-host-core from these source inputs, the
existing public retained Pool field-binding and Object-name cases plus gate
mutations passed 3/3 (`run-GA9pi0`, `focused-test-wX791k`). These real Store
cases retain the explicit producer/two-consumer Result, request-reuse and
in-flight cancellation checks. Their published fields are unqualified; they
are common-emitter integration regression evidence, not a new qualified-field
public Program or packed/HTTP acceptance claim.

The actual resource checker initially refused the unregistered encode_core
evidence suite. After adding its exact package mapping and foreign-suite
negative test, it passed without asserting full-boundary completion. The
selected gate test passed 1/1 (`run-XSHMVq`, `focused-test-U7tvsR`).

`moon info --target js,wasm,native src/encode_core` regenerated the one added
API and reported no backend divergence. This is interface inspection, not
Wasm/native execution. Node Host and Workers fixture freshness checks passed
without generated changes. Changed MoonBit files were formatted individually;
`git diff --check` passed. Clean committed-SHA receipts are recorded in the PR.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js \
  src/encode_core src/managed_record_storage src/managed_record_runtime \
  src/local_veca/pool_field_binding_wbtest.mbt \
  src/query_integration/pool_field_binding_wbtest.mbt
moon info --target js,wasm,native src/encode_core
npm run build:runtime-packages -- local-node run-host-core
node scripts/local-checks.mjs test node --timeout-seconds 90 -- \
  --test-name-pattern 'retained field binding|typed Object name admission|Pool output' \
  adapters/host-node/public-pool-key-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs
node scripts/check-local-resource-accounting.mjs
```

## Residuals

This closes qualified-name assembly in stepped record append only. Preparation
and Pool input/output matching still have independent whole-name scans.
Legacy synchronous append/serialization, declared Object name normalization,
StringBuilder final assembly, aggregate intermediate-byte accounting and
whole-Run physical Ledger evidence remain separate. New qualified public
Program acceptance, full fault/retry, packed Local/HTTP, Wasm/native execution
and required CI are not established by these focused checks.
