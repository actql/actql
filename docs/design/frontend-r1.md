# Frontend r1: structural source before query sugar

Frontend r1 adds representations of the existing Program. It does not add an
execution engine, an alternative checker, or authority to acquire inputs or
apply Effects. The [adopted profile](../../spec/frontend/frontend-profile-r1.json)
separates accepted, restricted and rejected surfaces from implementation and
execution evidence. `supported` in the imported design means adoption, not
installed functionality. The [baseline and acceptance index](../../spec/frontend/README.md)
record delivery evidence separately.

## One Program and one operation vocabulary

JSON and YAML remain compatible. Structural text represents the complete
closed Program envelope: metadata, IDs, parameters, opaque bindings, stages,
inputs, explicit steps, Results and Effects. Expression strings inside JSON
bodies retain the existing expression grammar. Object order is immaterial;
array order and explicit steps are preserved. Missing optional members and
explicitly empty permitted members are not conflated. An empty Effect map can
be represented by `EFFECTS {};`.

`STEP` carries an ordinary JSON step, including its metadata and output name.
`OP` selects a name from the existing closed operation inventory. The minimum
structural `DATA` form chains only native operations, for example
`DATA x = OP values {...};` and `DATA y = FROM x |> OP filter {...};`.
These are illustrative productions, not executable fixtures. `WHERE`, `SELECT`,
query expressions, domain aliases and `MATCH` are separate later work.
Unknown operations are rejected rather than forwarded to a Host.

The minimal formatter reconstructs the admitted structure, including unused
steps and explicit no-ops. It does not optimize the Program or preserve comments
and whitespace. It does not use the metadata-stripped identity projection as
its source. Source text and semantic identity are distinct: trivia can change
source positions without changing the canonical Program.

## Bounded construction and origins

The frontend constructs the JSON-model source through a bounded builder and
ordinary admission. No public unchecked Program constructor is introduced.
Caller-supplied node counts, depths or byte counts are not trusted. Duplicate
keys, including normalization collisions, are rejected before they can be
collapsed into a map. Construction fails without publishing a partial Program
when a limit would be exceeded.

The existing `source_map.admit` traversal supplies owner-bound annotations and
ordinary `decode_core` admission. The builder retains origins through the
existing source-map mechanism rather than creating a second cursor identity
system. `stage_syntax` remains the Program issuer; `program_check.check_parsed`
and `check_parsed_with_evidence` remain the semantic checker entries.

Origins refer to original UTF-8 input before NFC and line-ending normalization.
Byte offsets, Unicode scalar columns and UTF-16 positions are distinct. Invalid
or out-of-range spans and annotations from another admitted owner are rejected.
Generated nodes retain their originating source range and generated-node role;
they do not claim an invented textual token range.

## Identity and execution boundaries

Canonical equivalence is compared under the same applicable contract pins.
Program IDs, Effect names, explicit steps and semantic array order remain
significant according to their existing contracts. A changed Grammar Manifest
can change dependent compilation identities; frontend equivalence is not a
promise that all Plan identities survive a grammar change.

The Grammar Manifest binds the structural EBNF and the structural source rules
separately from the existing Program source grammar and expression contracts.
This binds lexical, lowering and formatter obligations without changing the
Program schema. Its pins, dependent artifacts and independent vectors change
together with those obligations.
All owned contracts remain on the initial 0.1 baseline.

Pure checking performs no provider I/O. Execution uses the normal Host and
existing checked owners, retaining Effect declarations and acquisition
boundaries. Source translation does not prove backend support for an operation.
The 72-operation language inventory and Local execution-path accounting count
different things.

The lightweight transport SDK does not depend on the parser or Core. Existing
`aql`, `start`, `attach` and Result behavior stays intact. Structural tests can
use an ordinary Host adapter before full source-format routing is packaged.
No second Run API, SQL engine, retry mechanism or Effect scheduler is needed.

## Later profiles

Query, Pipe and limited graph patterns lower into the same Program after the
structural representation is complete. The profile registry records their
preconditions and rejection reasons. Restricted syntax is not expanded by
guessing schema, inserting casts, hiding acquisition, approximating computation,
or treating a runtime capability declaration as execution evidence.

Known gaps in the imported acceptance matrix are explicit fixture requirements
in the registry. They remain work to do; an empty evidence array is never a pass.
