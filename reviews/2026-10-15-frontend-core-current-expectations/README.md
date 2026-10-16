# Two current Frontend controls from the fixed ef5606 Core result

The original G `ef5606fe2a598fbb43e89ca53354088bd4c505fc` Core run
`run-Joz4bl` remains 14,669 executed / 14,667 passed / two failed. This change
does not rewrite its raw inventory or claim a new full-Core result. Product
code and original Program/query inputs, limits and owners are unchanged.

## Graph compilation contract identity

The Graph Plan test successfully prepared and compiled the original keyed
parallel-edge Graph, then required an old fixed AoA CID. Its independent
current expectation is the existing canonical machine CID of the normative
`spec/contracts/actql-aoa.json`, not a value extracted from compilation.
`aoa-contract.preimage.json` and `independent-expected.json` retain the exact
canonical body and derivation. The original complete test file is retained.
A Node control verifies the normative source hash and permits exactly that
one literal replacement, preserving all typed Graph port and rejection checks.

## Calendar common preparation

The original selected-profile context control expected Calendar lowering to
return `OperationNotImplemented`. The adopted lowerer now has a real
`CalendarValue` payload and selected managed execution; the independent
`lowering_relation/calendar_preparation_test.mbt` already checks the exact
selected profile, operation and source span. The Frontend context test now
requires ordinary common preparation to succeed, retain the original authored
text and expose one checked Result. Both foreign-environment/nominal Catalog
rejections and all exact selection assertions remain unchanged. This is not
an installed Run or public Calendar execution claim.

## Bounded qualification

The same prior focused Moon budget is retained: non-Heavy270 seconds/TERM5,
child240, JS-j1, exactly one original named test per mode (`calendar`/`graph`).
The independent preimage Node control uses non-Heavy60/TERM5/child30 (`oracle`).

```sh
node reviews/2026-10-15-frontend-core-current-expectations/prepared-checks.mjs <clean-sha> oracle
node reviews/2026-10-15-frontend-core-current-expectations/prepared-checks.mjs <clean-sha> calendar
node reviews/2026-10-15-frontend-core-current-expectations/prepared-checks.mjs <clean-sha> graph
```

These current-source focused checks are not yet executed at preparation. They
are separate from the next shared release cohort and are not new gates for
its unchanged F03/window/Explorer installed cases. No full Core, Native/Wasm,
normal package producer, physical Host/Source/Provider or public E2E is started
by preparing this finite repair.
