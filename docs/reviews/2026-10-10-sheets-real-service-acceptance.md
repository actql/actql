# Sheets real-service acceptance: fixed-artifact handoff

## Completion unit

The existing finite typed Source and collection-only approved append passed
real Google acceptance on 2026-10-10. The installation was outside the checkout;
product imports resolved only from official RC package exports. No connector,
approval, scheduler, credential owner or Ledger was reimplemented for this run.
No product defect requiring a code change was found in this vertical acceptance.

The [operator example](../../examples/sheets/README.md) exposes the actual
installation, account/reviewer registration, ordinary read/create Programs and
same-Run restart sequence. This handoff does not claim Hosted Cloud, Native
Sheets, row-addressed writes, arbitrary queries, registry publication or CI.

## Frozen source and artifacts

- Adopted main: `ab69cd06a94b1c5a998521435e61c9f201a5c9a9`.
- Normal merge / verified product source:
  `6fcbe314160e56c603118baa083d4d19f9a5e335`.
- Release generation: `normal-prepack-then-metadata-and-license-only`;
  Node 24.21.0, npm 11.19.0, pinned Moon 0.1.20260904, macOS arm64.
- `package-release.mjs prepare` and `verify` succeeded (`run-WffzaC`).
  The four local archives were installed offline with consumer scripts disabled.
  Normal producer prepack was not bypassed.
- After acceptance, all four archive digests and **285 installed files** matched
  the frozen release manifest. No product adapter overlay was applied.

| Official RC package | Version | Archive SHA-256 |
| --- | --- | --- |
| `@actql/client-wire` | 0.0.1 | `8b8cc0f62a862e9d0535a12b3193198d2883b52955f220243b40dfa3f45dfb70` |
| `@actql/sdk` | 0.0.1 | `a3f7f5bab95bb950465522318fa171583179956361027984ff0250ec79093988` |
| `@actql/local-node` | 0.0.1 | `0c702e09f83c63f61ff64ebe0923f0e22e5aaca7748e9c0a7aaa0c826170e654` |
| `@actql/node` | 0.0.1 | `930f3b02ad4d16434b9cd5528e58a10792fe88a85ac83a933ac637bd5da23b9c` |

The later documentation/example commit is **not** the artifact generation SHA.
The [sanitized evidence index](2026-10-10-sheets-real-service-evidence.json)
retains immutable receipt IDs, summary hashes, commands and source/dirty-state
facts without private resource IDs, personal paths or credentials. Original
command receipts, release manifest, private journals and saved responses remain
in the operator's isolated installation; they are not public fixtures.

## Real Google acceptance

The resource owner authorized one synthetic Spreadsheet, separate numeric read
and append tabs, read-only finite rectangles, and two total appended rows.
The existing service-account file was used by operator token tooling; tokens
stayed in memory. The file/key were not copied into Git or public evidence.

| Actual public path | Independent check | Result / receipts |
| --- | --- | --- |
| Local and HTTPS read, A2:C4 | Literal `=literal`, zero/false, decomposed Unicode, duplicate and row order; header/out-of-range row absent | Passed: `zhfkZ7`, `tzylcG` |
| Local and HTTPS read, A6:C7 | One `missing` row with nullable Number/Boolean as NULL; all-blank row excluded | Passed: `SWx13e`, `hhxzD4` |
| Local and HTTPS read, A7:C7 | Empty Named Result `[]` | Passed: `6ElTN3`, `yImWvQ` |
| Local and HTTPS read, A2:C7 | Formula without effective value fails; no Result publication | Expected refusal: `rkPZbH`, `6VYVRC` |
| Local and HTTPS read, A8:C8 | Divide-by-zero cell fails; no Result publication | Expected refusal: `mrugVB`, `UAEIgp` |
| HTTPS append, original submission | One common two-row Set approval; waiting before any append claim | Passed: `YLzecp` |
| Fresh-process approval | Same Run/target/values; committed answer, still zero append claims | Passed: `tZ81E1` |
| Fresh-process same-Run execution | Exactly two append claims, successful saved acknowledgements, independent Named Result | Passed: `M2domk` |
| Fresh-process saved-success replay | Same Result; **all** credential-use counts unchanged from before opening Host | Passed: `ao8OrY` |
| Read-only Google inspection | Exactly two literal Text/zero/false rows; no formula; no added append | Passed; readback receipt hash in evidence index |

Read cases used distinct admitted profiles and Stores. Successful read cases
also repeated Result reads and the original submission without additional
acquisition claims. Append processes closed their own Client/Host before exit;
bounded supervisors recorded completion and released their own worktree locks.

Append credential-use counts were **0 → 0 → 2 → 2** across submission, approval,
execution and replay. The journal records durable use claims; counts alone are
not physical application evidence. Actual saved Google acknowledgements and
read-only typed-cell inspection are separate evidence. Equal rows were never
used to settle an unknown append or invent row IDs.

### Observed empty-formula distinction

The original preparation assumed A2:C7 would contain an evaluated empty Text
row. Actual Google returned `userEnteredValue.formulaValue: "=\"\""` for A5
but omitted `effectiveValue`. The existing codec correctly refuses that
`MissingEffectiveValue` distinction rather than converting it to blank, NULL
or reconstructed Text. Normal success therefore binds A2:C4; A2:C7 is a
separate expected-refusal installation, not a replaced success expectation.
The API response's typed `DIVIDE_BY_ZERO` was also observed directly.

Public failure assertions cover failed status and unavailable Result. They
do not independently assert the full typed terminal cause. Existing pure
codec tests separately pin `MissingEffectiveValue` and `CellError`;
controlled-service tests cover a real empty `stringValue`. This campaign does
not claim real-Google empty-string success when that value was not returned.

## Controlled-service faults on the same installed cohort

The unchanged authored packed fixture and TLS helper were copied outside the
checkout; no new package build or replacement product implementation was used.
The nonzero-test wrapper selected these cases:

```sh
node --test --test-name-pattern='Sheets (Local append|lost acknowledgement|cancel while|cleanup retry|provider 503|evaluated formula errors)' \
  adapters/connectors/sheets/test/sheets-packed.fixture.mjs
node --test --test-name-pattern='Sheets (revoked account|changed numeric tab)' \
  adapters/connectors/sheets/test/sheets-packed.fixture.mjs
```

The commands ran with the existing execution reporter and bounded worktree
supervisor. Six cases passed (`focused-test-XJRDaT`, `run-WcLZKA`); two authority
cases passed (`focused-test-T5nVoW`, `run-u52ZXt`). These establish Local append,
unknown non-resend across reconciliation/new process, cancellation while a
physical reply is pending, provider 503, same-owner Ledger close retry, cell
error nonpublication, revoked account and changed numeric target refusal.
They are **controlled-service** evidence, not Google fault injection.
Their external scratch receipts have no Git source identity; correspondence
comes from the retained release/installation manifest and installed-file audit.

The published example was then copied byte-for-byte into that installation
and used for saved Google Result replay only (`published-example-PLA1yq`,
`run-NGeeKV`). It passed without added read/append credential uses. That receipt
records a dirty documentation/example tree, not a pristine new-SHA product
build. The original live read/write used the equivalent private operator
harness; setup/token-supply code differs from the generic published example.

## Safety, remaining limits and handoff

- The campaign write cap is exhausted. Both appended rows and the Spreadsheet
  remain intact. No uncertain real write, retry, deletion or other Google
  resource operation was performed. The resource owner decides later cleanup.
- Preserve original Run/submission references, Stores, credential/Effect/
  Checkpoint journals, saved responses, signing keys and immutable receipts.
  These are not disposable build artifacts.
- Real Google write used HTTPS. Local write, in-flight cancellation, response
  loss, revocation and cleanup failure/retry used the controlled service.
  No real-service uncertainty was manufactured or settled by readback.
- The user explicitly allowed bypassing the shared heavy verification lock
  for this acceptance. Only the caller's bounded worktree lock was acquired;
  no other participant's lock/process was changed.
- CI remains stopped; no CI rerun, deployment, Preview change, registry publish,
  full Core, Native/Wasm or performance campaign was added. Prior-SHA tests in
  the original completion record remain prior-SHA evidence.
- Integration review and merge remain the integration owner's responsibility.
  This closes the finite Node Sheets public-use acceptance unit, not every
  Connector operation or every supported Host.
