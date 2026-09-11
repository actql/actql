# Source-bound local Relation inputs

`stage_local_inputs.prepare` reads the actual input slots of one stage retained
by `stage_parameters.Source`. Every non-import slot is passed to the local
Relation declaration reader; unsupported Carrier or Connector declarations fail
explicitly rather than disappearing from coverage. Source-admitted Result and
receipt imports are excluded from this local pass and remain obligations of
their own import checkers. Successful preparation is not evidence that those
imports were resolved or that another stage was checked.

The opaque result retains each name and declaration owner, including unused
local inputs. `input_at` supplies either the exact declared KeyedInput or the
exact CarrierInput, without Host augmentation. The compiler uses these handles
when checking the stage pipeline. Registration arrays can be reordered; input
names, not positions in those arrays, determine the later correspondence.

`attach` requires the same prepared Program source and stage index as the
source-bound pipeline collection. For each local name it verifies the original
pipeline registration variant and its exact Carrier/key owner. Checking only
the derived Carrier would lose key provenance; checking only `input_key` would
also admit a differently registered candidate-key collection. `pipeline_typing`
therefore retains and exposes each original InputContract handle in detached
storage, alongside its existing derived evidence views. The source-only path
does not accept a producer, ranking or candidate-key registration as equivalent
merely because the schema or selected key matches.

This is an ownership restriction on this specific assembly path, not a language
ban on Host evidence or richer input registration. Reconciliation of admitted
Host snapshots against source assertions needs a separate checked owner. Neither
this attachment nor handle equality admits that external evidence, graph Delta
contracts or other separately supplied policies. The final Program boundary must
still integrate those paths and their dependencies.

## Bounds and remaining obligations

Preparation charges stage input enumeration and import-name indexing, then each
local declaration's source nodes as logical work. Node and UTF-8 allowances are
shared across all local declarations, including metadata; depth is measured from
each declaration root. Import bodies and outer input names belong to prior source
admission and the separate import pass, not this local text allowance. The local
reader reports consumed source nodes/text so later fields cannot reset the caps.

Attachment includes all preparation work, the source-bound stage collection's
work, one pipeline input-name registration per input and one owner check per local
declaration. Exact limits succeed and late failures expose no partial attachment.
Independent passes retain their costs; future Program assembly must subtract
shared costs only after checking exact shared owners. These are logical-work and
source-size limits, not runtime row limits or process heap accounting.

Declared key admission and duplicate normalization remain conditional. In
particular, `first_by_order` still requires independent total-order resolution,
the selected raw/normalized input policy and runtime validation before selection.
This attachment neither discharges those requirements nor authorizes execution.
`pipeline_check_context.attach_local_inputs` now joins one such attachment per
stage to the intermediate all-stage context and Result wiring, requiring exact
shared CollectedStage owners and cumulative costs. This is still not the final
lowering-ready compiler output; the obligations above remain unclosed.

Tests cover keyed and unkeyed inputs, unused slots, reordered and mutated caller
arrays, equal-looking reread declarations, dropped keys and candidate-key
substitution, foreign sources, aggregate exact/short budgets and the separation
of local slots from Result/receipt imports.
