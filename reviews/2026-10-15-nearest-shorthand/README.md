# Short NEAREST and retained candidate body

Parent: main `767b1f1bde718ae2d62d4da7db955ea2cb2d9e63`, including merged #2069.
The adopted decision is the workspace `reviews/2026-10-14-nearest-shorthand-disposition.md`.

New text accepts `FROM questions |> NEAREST corpus USING (query_vec) K 3 AS hit`.
Omitted metric is exact cosine. Omitted KEEP preserves all current visible query
columns in their declaration order, followed by the hit. Explicit KEEP (*) still
selects both scopes and rejects collisions. Stored Programs and Runs are unchanged.

Relations resolve roles through Common `check_nearest_source`, using the actual
checked target's candidate key evidence and closed schema. Missing/ambiguous
information, including the existing numeric/composite implicit-key gap, refuses.
No field-spelling heuristic or foreign producer proof is used. USING expressions
retain the ordinary expression owner. Typed Vectors roles remain authoritative.

An unambiguously resolved candidate body column becomes hit.body through the
same retained producer and many-to-one correspondence join. Its exact type and
nullability remain Common's responsibility. Other payload uses explicit KEEP;
body cannot overwrite query_key, candidate_key, score or rank. Absent body is not
manufactured. Query aliases do not reopen an old operand scope.

A directly following pure hit-only SELECT permits elision of an unobservable
query Vectors-to-rows correspondence. Collision checking and exact admitted
visible-field checking precede that elision. Input/role/uniqueness obligations
remain with the original Common nearest operation. Explicit KEEP, wildcard,
aggregation, analytic, arbitrary calls and intervening operations are not pruned.
The original set-head counterexample retains its 10,000-work ceiling. Its wider
unobserved default materialization failed Common BudgetExceeded before repair.

The existing normal four-package harness retains its original ten Carrier cases
and five refusals. The closed shorthand matrix adds six authored text cases,
one independent ordinary JSON Program, and four refusals. It uses the original
installed Source fixture, original rows, checked f32 schemas, keys and acquisition
owners. Corpus body is an ordinary label AS body projection, not a new supplier.
Each Source text execution must acquire both original Sources once; JSON acquires
none. Attach/resend/lookup/reread must not fetch again. Full ordered schemas,
values, refusal codes and cleanup are audited against independent declarations.
Public execution is unverified until the corresponding actual receipts complete.

Historical manifests and failures are retained. The inherited structural-text
normative bytes have SHA-256 5d2f2432181664678b364fc97c3545d1740b004cd7b073c4bf0d8181c30dcaae
at main767 and this branch; main767's stored structural rules pin was stale.
Ordinary manifest generation aligns that inherited pin without editing the document.
The earlier initial-FROM vector is retained separately from main767's full preimage.

The installed 4008 failure was isolated to the existing multi-captured Ledger:
15 tasks have 16 receiving input ports. The existing one-million-byte transfer
envelope is reserved for each real checked port, retaining the task-count floor
and original Source allowances. Memory/execution ceilings and per-unit envelopes
are unchanged. The old short allowance remains a typed TransferLimit control.

At source 202063 the original ten Carrier cases and default shorthand passed
both transports. The next fixture incorrectly submitted a bare FROM form as SQL.
The established public SQL selector requires SELECT or WITH; bare FROM remains
text. Only that authored fixture now starts with SELECT *, retaining its exact
metric, roles, KEEP, ordering, input, independent rows, schemas and counts. The
original failed cohort and its partial receipts remain separate evidence.
