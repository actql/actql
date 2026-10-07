# Indexed retained row snapshots

Initial parent: #694 at `68641c33ce24c0e0f53867a4ab6b716ffd657dac`.
Branch: feat/local-indexed-row-snapshots; final target: main. The parent was
observed merged before publication. This is not all Local completion.

## Counterexample and production connection

SnapshotRow previously measured an entire input name and inserted it into a
Map in one resume transition. The independent 256-unit name regression failed
0/1 (`run-8xDcUr`, `focused-test-4v7DzT`) before the implementation change.

The existing BoundedBindingRows owner now builds indexed borrowed entries.
Wide or long-name inputs resolve fields through the existing expression-frame
FieldName cursor, even for a short authored field. This avoids per-row hashing
and collision equality scans without another evaluator or dispatch path.
Conditional columns remain excluded from ordinary expression scope. An explicit
NULL remains a value; an unavailable field remains typed MissingValue.

Input, output and capture name accounting uses one scalar per transition for
long spellings. Snapshot/output construction uses the same cursor before
appending a cell. Value accounting retains atomic successful name charges;
control accounting retains the original scalar UTF-8 byte charge. A temporary
cursor reserves one workspace slot and releases it once. Stop/failure cleanup
retains the input owner and spent work while reclaiming cursor state.

Output-cell sources are resolved once, not by hashing every output name on
each row. Large metadata reserves output_width additional slots before cache
construction. The old metadata footprint is retained only when input/output
and binding counts are all <=8 and all names are <=64 UTF-16 units. This is a
bounded implementation lane, not a new language limit. Existing short-row
exact budgets remain unchanged.

The additive relation_schema.field_reference_name_at accessor borrows an
already admitted Flat/Scoped spelling, avoiding repeated qualification copies.
It confers no read authority. Existing input binding, schema and completion
validation are unchanged. No wire, schema, CID, pin or language changes.

## Independent boundaries

- Nine indexed fields and NULL id: logical work 2/1 and workspace 2/1,
  quanta 1/7/256, typed limits and MissingValue, with zero live roots afterward.
- Name: 63 ASCII + supplementary scalar + 65 non-ASCII scalars = 197 UTF-8
  bytes. Control and Value ceilings 197/196, with scalar-safe progress.
  Failed Value measurement commits zero name bytes; a control failure retains
  its actual consumed work. Cursor workspace 1/0 and repeated close are tested.
- Existing checked/lowered producer-read fixture receives cancellation at
  offset 64 in ChargeInput, SnapshotRow, BuildOutputRow and ChargeCaptureRow.
  Stopped precedes cleanup; the borrowed read remains valid, work is not
  refunded and workspace reaches zero. Exact-phase observation is whitebox,
  not a claim about public Hook phase visibility.
- Existing row and presence caller tests retain their original expectations.
  Selected JS batch passed 112/112 (`run-3Spq6V`, `focused-test-O4MkU9`).

## Public retained Program

The normal Values -> derive -> select producer has nine fields, followed by
two consumer Stages. The installed owner chooses fused producer task 0; the
fixture does not construct internal task state or split the authored chain.
Three explicit Named Results read [{id:1,value:1},{id:2,value:2}] and their
nonnullable Number schema from the real retained Store. Request reuse adds no
dispatch. Post-progress cancellation retains custody until confirmed stop,
publishes none of the Results and reclaims snapshots without extra dispatch.

The first proposed fixture exported a wide intermediate Result between Stages.
It correctly reached the existing projected ProducerRead metadata ceiling of
100, with typed Run(Read(Limit)); this ceiling was not raised or bypassed.
That separate wide-public-intermediate limitation remains. A second fixture
diagnostic selected the wrong task barrier; it was corrected to the actual
fused task, without changing the Program's successful output expectations.
The corrected public case passed 1/1 (`run-dCov85`, `focused-test-6g64Jz`).
The previous public batch passed its six unchanged cases and two evidence
removal cases, but failed the unrelated input-metadata setup. Final integrated
SHA commands and receipts are recorded in the PR rather than relabeling that
failed batch as successful. Diagnostic code was removed.

The resource checker requires common limits, phase-stop and connected public
fixture roles; removing each required role fails its regression.

## Explicit residuals

Initial schema/name arrays, binding/projection maps, source-cache preparation,
sort/key setup and availability validation still have synchronous scans.
This change closes repeated row construction/name charging, not every start
transition or every retained variant. #677's bounded ProducerRead preparation
and Native capacity review are independent; no runtime heap upper bound is
inferred from logical slots. Public exact-phase cancellation, full Core,
Wasm/native execution, physical stop latency, packed/HTTPS and performance
were not verified here. Checkout Host success is not distribution or CI success.
