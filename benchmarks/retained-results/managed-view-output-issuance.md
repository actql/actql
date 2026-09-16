# Managed view output issuance boundary

The checked preservation plan now connects to the existing managed output
receipt and retention path through a Host-installed, one-use issuance port.
This is a common boundary implementation, not yet production DuckDB/Local
output emission or a performance acceptance result.

## Trust and binding

Only the installed Host implementation may install the verifier. Its proof must
bind the actual attempt, execution of the checked plan, row correspondence,
output generation and any newly computed column's required validation. A
caller-supplied facts record, matching schema, or static preservation plan is
not sufficient. The port checks the exact owner/target, live receiving input,
and any transferred consumer ledger's use-site identity.

Core checks universal inherited bounds and NULL absence after selection; on
all-row/permutation paths it also checks exact inherited column totals. New
columns and selected exact totals remain the adopted verifier's responsibility.
Core does not independently prove these content assertions. No new backend
certification or machine-checked execution claim is made.

Install retention against the same stream before reserving it for issuance.
Reservation excludes ordinary append/finish and a second issuance port.
Verification is one-use, rejects stale input and reentrant cancellation, and
creates no receipt on failure. The retention verifier must then establish that
its sealed material represents precisely that receipt. This still does not
replace common completion, authorization or consumer pin acquisition.

## Accounting and failure

Exact output rows and per-column value bytes/nodes are charged to the same
remaining logical ledger, including repeated copied columns. Successful
issuance does not reset the input's charges. Reported admission work is distinct
from that logical measurement; Core does not execute a redundant cell loop.
The adopted implementation must account for its actual validation, copying,
storage and execution through its applicable resource contracts.

When summaries cannot establish the configured ceilings, issuance returns
`OutputRepresentationRequired`, not a fabricated first offending row. This
failed port is terminal; a caller must not silently retry execution or reset
budgets. Ordered diagnostic/fallback integration is still required before this
path is enabled generally.

The boundary fixture composes select/filter/derive/sort/take, reports copied
and new-column measurements, preserves input-plus-output charges, and connects
the resulting receipt to independent retention. It also exercises foreign
binding, duplicate installation, failed verification, revoked input,
inconsistent inherited totals, insufficient output budget, cancellation and
reentrant finish/cancel. The fixture's proof token models an adopted issuer;
it is explicitly not evidence that DuckDB executed this transformation chain.

Required next work: install this boundary in actual adopted output producers,
validate their content/measurement correspondence with independent cases, then
measure eliminated admission/encoding passes on the registered large cases.
Old contracts, identity preimages, pins and performance gates are unchanged.

Verification: execution_relation passed 433 tests on each of JS, Wasm and
Native. The new tests are issuer/retention boundary tests; they do not replace
the outstanding real-producer and end-to-end performance gates.
