# Stable sorting and order evidence

The normative owners are [sort](../spec/language.md#sort) and the
[shared RelA primitive laws](../../spec/dependencies/aoa-rela-primitive-laws.json).
`REL.orderByStable` compares explicit keys first and uses input-relative order
only when every key compares equal. It never appends value identity. Empty
keys preserve every occurrence, including duplicate rows; explicit null placement
is independent of direction, with omitted primitive null placement defaulting
to last. The explicit authoring form still requires `nulls`.

The compiler owns candidate-key selection, appending missing fields and recording
completion. Lowering consumes those keys and records rather than repeating
inference. An admitted total input witness can instead justify stable tie
resolution where the consumer permits it; it appends no hidden key. Physical
enumeration is not such a witness. Empty authored sort adds no evidence and
does not trigger candidate-key completion, though later consumers retain their
own permitted completion rules.

## Reference compatibility and proof scope

This corrects a shared-law inconsistency with ActQL, not a report that reference
executors already conform. At AoA revision
`dbab4fe8c1d624d81ed967f90e2abe742163f84f`,
`packages/rela/src/exec-js.ts` appends valueCID for tied keys, and
`packages/rela/test/order-runtime-contract.spec.ts` expects permutation-invariant
CID tie-breaking. Those tests are incompatible with the stable-input rule.
Backends implementing that tie-break need an explicit correction before claiming
support, including paths normalized through `REL.orderByStable` such as topk.

At aoa-mechanized revision `26139fa908b49d14509aa0c211ecea25b8efb119`,
`AoaMechanized/RelA/OrderByStable.lean` proves length preservation only.
The underlying `orderByStableRows` in `RelA/Core.lean` is an identity-function
model that ignores its key. Neither it nor topk's decomposition theorem proves
the key-ordering or stability behavior of an executable sorting implementation.
The shared entry therefore declares specification-only status, records these
limited references, and lists key ordering and stable ties as proof obligations.

The [fixed corpus](../../portability/corpus/stable-sort-laws.json) specifies
occurrence order separately from compiler evidence decisions. Its independent
numeric/null oracle checks fixtures, not a backend implementation or a general
typed comparator. Evidence cases assume an eligible candidate or an admitted
prior total witness as stated; they do not establish those premises from raw
rows. Product compiler checks remain separate from execution conformance.
