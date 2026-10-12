# F03: preserve resolved peers across a Carrier bridge

The existing Vectors/Events bridge passed a singleton current input to Relation continuation. A visible candidate peer consequently disappeared before the existing `nearest_dependencies` resolver. The fixed counterexample returned actual `UnknownRelation` in `run-BnzmFs` (0/1); the first `run-mOyPws` also failed (0/1) but its generic helper did not print the specific cause. Both remain failures.

The fix replaces only the matching current logical input slot in the existing `known` array. Other already resolved lexical peers stay unchanged. It never appends indiscriminate outer inputs, searches again for a compatible producer, changes captured inputs, or creates an execution owner. Shared-input acquisition remains with the existing bind/memo owner.

Independent cases cover flat versus intermediate WITH, inner candidate shadowing and the retained inner predicate, wrong-schema shadow refusal without outer fallback, and two consumers of one original installed Values input. The shared original control emits one Values producer; the distinct-input control emits two. These are Program/topology assertions, not actual Provider call-count observations.

The retained `independent.program.json` predates this fix and supplies the original cosine/K1 contract. The expected row and field order are separately handwritten. Neither is produced from the lowerer's output. The dot/K2/KEEP case is an additional scope control, not a replacement for the cosine contract.

Working-source checks: `run-gb1ocu` passed the first scope counterexample (1/1); `run-pzK4J8` passed 16/16 selected cases including existing nearest and Vectors/Events callers. Exact submitted-HEAD results are reported separately. No installed Local/HTTPS, Native/Wasm execution, full Core, Hosted CI, or Provider was run. New installed public E2E count is 0; the existing F01–F03 public matrix still needs its coordinated allocation.
