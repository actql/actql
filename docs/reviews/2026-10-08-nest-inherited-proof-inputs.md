# Nest inherited proof inputs

Adopted main: `ca39ec1a82c89a0e038af3862af4de8a383b26fb`.
Implementation: `a451a89d9b470eeaf5a12e6d8d8488218bf3ffe3`.
Clean JS execution: `df27c6297997fb3f97fc3f4ed1f4760eca083ab2`.

## Actual failure and dependency correction

The real `checkNestObligations()` on adopted main rejects
`proofs/relation-chain/check.mjs` after the independently extended chain checker
lands. Nest's actual derived claim depends on Session, adapter and its own
registered connection; its declared exclusions explicitly reject straight-line
chain proof for its two-input ownership. The historical unchanged-file comparison
was being used as an extra current dependency, unrelated to those guarantees.

Current required common inputs are the four existing bounded Session proof,
checker and toolchain files and its two shared contract fixtures. Their hashes
are unchanged. The gate independently requires all six exact paths and rejects
omission, extra/substituted paths or changed bytes. The real Nest source route,
ordered input ports, retained suites, local residuals and exact fixture scope
remain unchanged. The optional reader is for controlled Node negative fixtures;
normal runners still read actual source bytes.

The original four chain artifact digests stay under
`historicalChainComparison` at the original `22507d140f13ef5e18c9950aa0500bbed8bf40cf`
baseline. Each was checked against the actual Git blob at that baseline. Those
are retrospective comparison metadata, not current premises or an old-format
fallback. No digest is changed to pretend the introduction had different bytes.
No acceptance claim is upgraded and no test is retired.

## Executed limited checks

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  proofs/bounded-session/evidence.test.mjs
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js src/query_integration/local_managed_nest_wbtest.mbt
```

The Node selection passed 84/84 on the working implementation over adopted main
(`run-9WH9jO`), including existing evidence/Events/action-input contracts. New
negative fixtures prove an unrelated chain checker is not read and changed or
missing inherited Session inputs are refused. Mock evidence tests remain gate
contract diagnostics, not physical acceptance.

At the clean JS execution above, the actual registered Nest Host fixture passed
4/4 (`run-hVok0c`, nonzero-test wrapper). It preserves independently authored
parent-major rows, nullable correlation behavior, ordered inputs/projection and
two-consumer ownership. Actual built JS artifact hashes are preserved in the
original archive. This is selected JS execution, not Native/Wasm, packed or full
integration coverage. Unchanged Lean model/consumer bytes were not re-proved.

## Retained history and remaining acceptance

The first 240-second shared-heavy attempt (`run-q0Ktkd`) refused before
execution because B's live five-package producer held the slot. That original
refusal remains in the first archive; it is not a history test failure.

After that slot became free, the same existing read-only command passed at
published clean source `a34fd425eceb94095a796c641729a2274345b8ae` under
`run-h2zQvH` (82.3 seconds, exit 0, complete streams). It checked 239 declarations,
195 integrations and 89 protected files, including the actual Nest
source/parent/blob/mode declaration. The deterministic manifest is 1,468,877
bytes, SHA-256 `2666087972d6145da8d8ba3eea2d1a3ac520842ab7758c6c3e77f9cc9061ce85`.
No tracked/ignored history manifest was generated and no history was rewritten.
The later publication changes only this review and its immutable text archive.

[Actual retained-history originals](evidence/2026-10-08-nest-inherited-history-a34fd425e.json.gz)
preserve the unmodified guard summary, complete stdout and outer command log.
Raw JSON: 3,148,709 bytes, SHA-256
`ecd944a41814e5cca3774d284350fbc3748f17ebe1e39cfc4b3a4263fee099b1`.
Gzip: 351,064 bytes, SHA-256
`c74e9cf672f0ada0f173b4c61eee7fac07038c6b9995c0dbaa74c31baf24cc68`.

No hosted CI was run, and local logs are not Actions originals. Cross-main
qualification, ordinary-PR reuse and authentication/transfer-inclusive net CI
savings remain external acceptance work. No merge or reuse permission follows
from this correction.

## Preserved originals

[Compressed original evidence](evidence/2026-10-08-nest-inherited-inputs-df27c6297.json.gz)
contains the before-main refusal, unmodified Node/JS logs and guard/focused
receipts, historical Git-byte comparisons, full current source identity and
built JS artifact digests. Binary bytes remain in the local build; this is a
text/report archive.

Raw JSON: 733,534 bytes, SHA-256 `4d64c81757b72abe07e2c883df0cf096b5f4c20ce53382c01b04b20af162294f`.
Gzip: 222,042 bytes, SHA-256 `3914f5c06edacbbbe92afd2348236e03b81ff6c7887084ab827513657032cb4e`.
