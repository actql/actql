# Values JOIN: independent topology and original derived ceiling

The original checkpoint's three `values_join_ceiling_test` failures were not all
fixture-only. Keep both concerns separate.

The old complete Program put each original Values input in its own Stage and
imported both Results. The adopted shared input binder retains those two seeds
in the current Unit. Preserve the old complete staged oracle as
`staged_values_join_ceiling_control` and continue checking it. Add an independently
authored complete current Program with the same rows, schema, keys, SELECT,
ceiling and public fields. Only Stage layout and private bindings differ.

The initial migration selection (`run-ynb5Ky`) was 6/7: explicit ceilings 1, 5
and 10 passed, but the omitted ceiling became 1000 instead of the old derived
4. The original 2-by-2 Values formula was lost when the shared binder converted
the inputs to StepReferences and `compile_join_steps` used only the configured
default. Do not adjust the expected 4 to this observed output.

Extract the unchanged old Values formula into one private helper, reused by the
standalone path and the shared single-JOIN path. Derive it from the original
Values inputs before binding. Pass only that derived bound to the existing JOIN
lowerer; explicit ceilings still take precedence. Unknown Sources, StageResult
inputs, JOIN chains and transformed inputs keep their existing bound owners.
The original overflow, empty-side, outer-JOIN and admission checks remain in the
same formula. No new bound law, Owner, schema, ABI, pin or cap is introduced.

The additional refusal uses the same two-by-two inputs with frontend maximum 2:
the original derived 4 must refuse, not be replaced by 2. Existing explicit low
ceiling 1 remains valid and explicit 11 still rejects under maximum 10.

Use the existing bounded nonzero runner on `values_join_ceiling_test`,
`installed_values_binding_test`, and `with_join_dispatch_scope_test`: non-Heavy,
60 seconds, TERM grace 5. The working-source formula repair initially passed
10/10 before the additional maximum-2 refusal. Fixed-source evidence is reported
separately in the PR and workspace handoff.

No public Local/HTTPS or installed scenario was executed (new E2E 0), nor any
full Core, producer/consumer, Hosted CI or target runtime campaign. The original
G checkpoint remains failed; this unit closes only its three named Values-bound
cases. Other JOIN golden failures require their own independent scope review.
