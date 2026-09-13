///|
fn proof_unit(witness : @wire.WireWitness) -> String {
  match @wire.unit(witness) {
    Rows => "rows"
    DistinctKeys => "distinct_keys"
    EffectItems => "effect_items"
    Bytes => "bytes"
    ArrayItems => "array_items"
    Nodes => "nodes"
    Edges => "edges"
    Paths => "paths"
    MatchesPerKey => "matches_per_key"
  }
}

///|
// Low-level preimage emission only. The conversion traversal supplies rebuilt
// input identities after validating their source correspondence; this function
// is not an admission of independently supplied input evidence.
fn emit_unit_output_proof(
  location : UnitOperationSource,
  bound : @step_bounds.StepBound,
  inputs : Array[String],
  writer : @encode.Writer,
  budget : IdentityBudget,
) -> Unit raise UnitBuildFailure {
  if !physical_equal(location.pipeline, @step_bounds.checked_pipeline(bound)) ||
    location.source_ordinal != @step_bounds.checked_step(bound) {
    raise ForeignOwner
  }
  let witness = @wire.program_proof_witness(@step_bounds.checked_proof(bound))
  let subject = unit_operation_subject(location, budget)
  identity_charge(budget, inputs.length())
  let ordered = inputs.map(cid => (cid, ()))
  identity_sort(ordered, budget)
  identity_charge(budget, ordered.length())
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "inputs")
    @encode.begin_array(writer)
    // Repeated operand occurrences survive canonical sorting.
    for (cid, _) in ordered {
      @encode.string_value(writer, cid)
    }
    @encode.end_array(writer)
    @encode.key(writer, "law_id")
    @encode.string_value(writer, @law.name(@wire.law(witness)))
    @encode.key(writer, "semantic_ref")
    @encode.string_value(writer, subject)
    @encode.key(writer, "unit")
    @encode.string_value(writer, proof_unit(witness))
    @encode.key(writer, "value")
    @encode.number_value(writer, @wire.value(witness).to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-bound-proof/0.1")
    @encode.end_object(writer)
  } catch {
    e => raise Encoding(e)
  }
}
