# F04: typed Vectors NEAREST roles

This is the existing F04 completion unit, not a new language profile. Each side
retains an optional complete KEY/VECTOR pair in the AST. Relation inputs require
an explicit pair. Typed Vectors retain their admitted identity and component
roles; an explicit pair must restate those roles exactly and in order.

The source dispatcher checks the real prefix Carrier and reuses the installed
input binding owner. Machine NEAREST still receives candidates as its current
input and queries in its `queries` argument. Typed Vectors are passed directly;
the existing `vectors` bridge supplies ordinary rows only for KEEP. No identity,
Source, checker, evaluator, or runtime owner is replaced.

The continuation installs a new output scope and retains lexical peer inputs.
It does not restore input aliases removed by NEAREST. Ordered composite Vectors
identities use the common positional object members (`0`, `1`, ...) when creating
the named output key objects. Composite Relation conversion remains unsupported
by the current scalar-id `to_vectors` entry and is not silently approximated.

## Evidence and remaining acceptance

- Baseline `44e16b9eb23193f62e18d366d20d265d5b667153`: `run-xNs4Ix`
  discovered two parser cases; omitted roles failed, malformed pair refusal passed.
- Working source: `run-q7Zfn7`, JS 14/14, existing Relation and optional-role AST.
- Initial typed bridge: `run-hFhATL`, 0/1, common `InvalidBody`; putting the bridge
  and SELECT in separate existing Program steps corrected that boundary.
- Working source: `run-OE43O8`, 1/1, four independently selected operand kinds.
- Working source: `run-kONCqW`, 16/16, exact restatement, fresh output scope,
  normalized input and shared original producer; `run-pnrOAP`, 17/17, adds the
  ordered composite Carrier/lowering control. These are checker/lowering tests,
  not runtime values or public E2E evidence.
- `run-qFzsMM`: changed-file pinned formatting; `run-F3lH4B`: generated affected
  Query interfaces. Both completed with exit 0.
- `run-qS5rJd`: working-source JS 18/18 adds a handwritten complete machine
  Program and compares full checked output contracts with its source counterpart.
- `run-X84Dat`: affected Query syntax/program/source API consumption compiled
  on JS/Wasm/Native. This is compilation, with Native/Wasm execution 0.
- `run-csgNzt`: Node 79/80; a second current-grammar assertion still named the
  retained Lag grammar. The independent NEAREST preimage supplies its new
  grammar CID; the old Lag fixture itself remains byte-identical.
- `run-FNGevs`: fixed `db863df472f4d0e61e8c6206f05596fad1018b4b`, JS
  27/28, subsequent steps unexecuted. The strengthened removed-receiver test
  incorrectly expected the column resolver's issue instead of the ordinary
  expression owner's adopted `UnknownReference` diagnostic with authored origin.
  `run-Igyt13` was a diagnostic-test compilation failure (execution 0);
  `run-usIS51` retained the actual Expression rejection. The corrected assertion
  follows `query_expression/lower_test.mbt`'s existing contract, changes no product
  condition, and does not accept arbitrary failure as success.

Original raw receipts and output remain under this worktree's `_build`; failure
records are not replaced by later success. Each working-source receipt includes
its selected command. Fixed-HEAD checks will be recorded separately.

Public Source/Host Local/HTTPS acceptance remains unexecuted. Empty inputs, ties,
NULL/type failures, result rows/full schemas, resend/attach and cleanup still need
the original finite public matrix. F01–03 are separately integrated and retain
their pending public acceptance. This unit adds no Heavy reservation or global
Core/CI gate and does not complete F04/P2 by parser or checker success alone.

`independent.program.json`, `input-contracts.json`, the four `.sql` inputs and
`expected.json` are independent prepared controls, not execution receipts. The
existing public consumer is reused by `nearest-carrier-public-input.mjs`; its
ten submitted SQL/AQL-text recipes retain the old independent KEEP rows and
complete schema, with five exact invalid-input refusal recipes. This preparation
does not install sources or run a Host. Flat ordinary Relation operations before
a typed candidate, typed set heads, and composite Relation conversion remain
explicit connection gaps, not completed cases or alternative language rules.
