# Retained Pool member identity scanning

## Scope and production connection

This component follows unmerged #561 at
`beb738b9b79ee48f5cdb351c10fcdbce1ab7e0c7`; eventual merge target: main.
It does not complete all Local retained paths or change language, CID, ordering,
installed limits or authority contracts.

Relation Pool keeps the normative `scalar_count:scalar_text|` representation.
Previously one component poll performed multiple whole-string scans and a
whole-component copy; the final poll synchronously checked the concatenated
key. `value_admission.start_scalar_text` now stages the same spelling and
reuses the existing runtime Text recheck. Each poll visits one frame or at
most 64 UTF-16 units plus a surrogate partner. Completed counts provide scalar
and UTF-8 lengths without another scan. The synchronous scalar conversion
drains the same cursor. The at-most-64-unit leaf fast path is preserved.
Raw Unicode and line endings are never normalized.

Pool owns measurement, scalar-safe chunk copying and final key recheck in
separate phases, charges each poll cumulatively and checks stop between them.
Existing input recheck custody is reused after field binding: no two stacks
are live concurrently. Cleanup retains all children and the output builder
until confirmed stop. No scheduler, ledger or retry owner is added.

## Independently derived boundaries

The core fixture has two keys, a 129-unit Text and number 1. A single Text
key would bypass encoding through the existing native identity optimization.

- Work: numeric one-key baseline 72; second key adds 12; long comparison
  adds 128; input recheck adds 3; encoding measure/copy/final check adds
  4+3+5. Total 227; 226 fails as PoolWorkLimit for quantum 1, 7 and 256.
- Workspace: 21 structural + 20 recheck + 45 append = 86; 85 is refused.
- Member bytes: `1:1|129:` + 129 x's + `|` = 138; 137 rejects only the
  encoded identity as InvalidPoolIdentity at poll 171, before Text copying
  or record collection. The fixture asserts canonical key order (code, id).
- Copy cancellation: encoding begins after 165 polls; the canonical numeric
  key consumes 166, Text measurement ends at 171, and poll 172 copies only
  the first 64 units. Early cleanup is refused, then
  confirmed stop permits one cleanup while the source remains available.
- Shared Unicode fixture: 129 scalars, 130 UTF-16 units, 197/196 UTF-8 bytes;
  surrogate-boundary progress, cancellation and raw composed/decomposed/CRLF.

## Candidate evidence

Focused JS passed 20/20 (`run-stmihN`, `focused-test-xsf2zu`), before the
additional 138/137 operator assertion. Earlier attempts did not pass: one
selected single-Text native identity, one omitted the four-column read's
14 metadata entries, and one expected group at embedding's canonical position.
These failures are not success evidence. Expectations above come from phase
and literal structure, not successful measurements.

The expanded candidate passed 178/178 (`run-1GFrF1`, `focused-test-5QFtio`),
including the 138/137 operator assertion and quantum-independent work limits.
The earlier copy-stop point at 171 was phase entry, before copying. The
strengthened fixture stops at 172 after a fragment has been copied. The
byte-failure observation was reconciled with canonical key order, not used
as a replacement expectation without a phase explanation.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js \
  src/value_admission/scalar_text_steps_wbtest.mbt \
  src/value_admission/canonical_scalar_text_wbtest.mbt \
  src/local_veca/pool_wbtest.mbt src/local_veca/pool_identity_output_wbtest.mbt \
  src/query_integration/pool_member_encoding_wbtest.mbt
npm run build:runtime-packages -- local-node run-host-core
node scripts/local-checks.mjs test node --timeout-seconds 90 -- \
  --test-name-pattern 'composite member encoding' \
  adapters/host-node/public-pool-key-retention.test.mjs
```

Selected runtime preparation passed; bundles remain ignored. Public Host passed
1/1 (`run-pBiMoc`, `focused-test-QlvRUV`): actual installed Local, real Store,
three explicit ordered Named Results, request reuse, and cancellation inside
composite measurement. For 5,000 units, encoding begins after
`23+11+4,999+79 = 5,112`; 5,120 is inside measurement, before copying or output.
The held advance retains resources before stop confirmation; then the test
checks confirmed stop, unavailable results, unchanged dispatch count and final
snapshot reclamation. This is checkout acceptance, not packed distribution.

JS/Wasm/native interfaces were regenerated without reported divergence. That
is compile/interface evidence, not Wasm/native execution. Clean submitted-SHA
checks and CI status are recorded separately in the PR.

## Remaining work

`StringBuilder.to_string()` still assembles the bounded key buffer in one
runtime primitive. This removes algorithmic scans and whole-component copies,
not preemption inside runtime allocation/buffer growth. Physical heap/latency
and aggregate intermediate-byte custody remain separate obligations; a member
byte ceiling is not a whole-Run Ledger proof. Carrier schema lookup, field Map
hashing/name matching, runtime Object-name validation and legacy synchronous
drains remain distinct boundaries. Full Store fault/cleanup retry campaigns,
packed Local/HTTP, Wasm/native execution and final CI remain unverified.
