# Two initial Direct acquisitions followed by keyed lookup

This note describes only the existing profile selector in
`run_publication_host/client_program.mbt` and the corresponding two-acquisition
branch of `prepare_checked_dag_owned` in `physical_strategy/graph.mbt`.

- Responsibility: Keep two independent initial Direct acquisition tasks in the
  existing captured prefix when a later checked operation is keyed lookup.
  Downstream lookup is not a third independent captured task.
- Inputs and outputs: The selector reads the original checked Source execution
  inventory. It selects two only when the initial stages each contain one
  Direct HostCombination. Other profiles retain the existing single-prefix
  selection and still undergo normal graph validation.
- Identity: The graph branch checks each later keyed subject against the exact
  checked Program identity and the original stage/input mode and request.
  Matching wires, schemas, names or coordinates cannot substitute originals.
- Ownership: Checked Program, lowered owners, generated sequences and Source
  requests retain their existing owners. This selection constructs no capture,
  ProducerRead, CompletedOutput, Request, Run or Ledger.
- Synchronization: Selection and graph preparation are synchronous and perform
  no Source/provider I/O. The existing graph constructors and checks remain the
  only path; the Host cannot use this profile number as permission.
- Failure: A later Direct, foreign keyed subject/request, invalid stage, missing
  original input or mismatched graph owner is not admitted by the two-capture
  branch. Initial dependent acquisitions, missing/duplicate ports and invalid
  ordering retain the existing graph refusals.
- Cancellation: No physical operation starts here and no cleanup obligation is
  discharged. Later execution must retain and retire its real original captures
  and computed prefix under the ordinary owners.
- Resources: The selector reuses its existing two-element counter array and
  existing Source inventory traversal. Graph checks use the existing bounded
  work traversal. This change creates no row-count proof, resource allowance or
  worst-case fan-out reservation.
- Extension: The bounded profile remains exactly two initial independent Direct
  tasks. It does not introduce arbitrary acquisition/Compute interleaving or
  support a third independent Direct. Repeated aliases may legitimately share
  one original acquisition; tests must inspect the checked inventory first.
- Verification: Existing ordered-input and Direct selector regressions pass.
  The construction-only diagnostic for the unchanged deal-review declaration
  and SQL observes two Direct stages, keyed task 2/step 1 and Model task 2/step 5,
  with no SERIALIZE. It does not execute Source, Content, Model or Effect and
  does not prove complete README runtime support. Dedicated graph-subject
  identity corruption is not exercised by an equal-wire acquisition-owner test.
