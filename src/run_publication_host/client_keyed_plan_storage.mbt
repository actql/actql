///|
// Actual immutable checked counts, before the acquisition/sequence/role/field
// holders are built. The same collection owner includes old/new Array/Map
// backing. Policy walks and writers are separately funded before their entry.
fn client_keyed_plan_metadata_storage(
  occurrence : ClientInferOccurrence,
) -> @execution.PreparationRepresentationUnits? {
  guard client_composed_keyed_source_coordinates(occurrence.owner)
    is Ok(Some((stage, input, join))) &&
    stage == occurrence.stage &&
    join < occurrence.step &&
    @lower.node_at(@lower.bound_preparation(occurrence.preparation), join)
    is Some(_) else {
    return None
  }
  let program = @strategy.graph_program(occurrence.owner.graph)
  let mut selected = None
  for index in 0..<@checked.source_execution_count(program) {
    let original = @checked.source_execution_at(program, index).unwrap()
    let subject = @checked.source_execution_subject(original)
    if subject.stage == stage &&
      subject.input == input &&
      @checked.source_execution_kind(original) is @checked.KeyedRequest(binding) {
      selected = Some(binding)
    }
  }
  guard selected is Some(binding) &&
    @acquisition.keyed_join_left(binding.join) is @pipeline.Step(left_step) &&
    @lower.node_at(@lower.bound_preparation(occurrence.preparation), left_step)
    is Some(left) &&
    @pipeline.input_at(
      @lower.pipeline(@lower.bound_preparation(occurrence.preparation)),
      input,
    )
    is Some((_, right)) &&
    @carrier.relation_rows(@lower.node_output_carrier(left)) is Some(left_rows) &&
    @carrier.complete_schema(left_rows) is Some(left_schema) &&
    @carrier.relation_rows(right) is Some(right_rows) &&
    @carrier.complete_schema(right_rows) is Some(right_schema) else {
    return None
  }
  let template = @acquisition.keyed_join_request(binding.join)
  let request = @acquisition.parameterized_keyed_request(template)
  let correlation = @acquisition.keyed_request_correlation(request)
  let roles = @environment.source_correlation_pair_count(correlation).to_int64() +
    @acquisition.parameterized_keyed_request_field_count(template).to_int64()
  let ports = @pipeline.input_count(
    @lower.pipeline(@lower.bound_preparation(occurrence.preparation)),
  ).to_int64()
  let fields = @schema.field_count(left_schema).to_int64() +
    @schema.field_count(right_schema).to_int64()
  guard @shape.collection_construction_extent({
      // Fragment inputs (7 references/3 words), barrier inputs (14 references),
      // component (5 refs including original barrier document), lookup Fragment
      // (6 refs), acquisition/Effect view,
      // the selected pair/Option and each role tuple/two possible Options.
      records: 10L + 3L * roles,
      record_references: 7L + 14L + 5L + 6L + 16L + 4L + 5L * roles,
      record_words: 3L + 4L,
      reference_arrays: 4L,
      reference_items: roles + fields,
      scalar_arrays: 2L,
      scalar_items: 2L * ports,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(collections) else {
    return None
  }
  // The exact same task/join labels are emitted by both constructors. Decimal
  // labels are measured from these actual Ints, not a user row/byte ceiling.
  let prefix = "task_" +
    occurrence.task.to_string() +
    "_lookup_" +
    join.to_string()
  Some({
    record_headers: collections.record_headers,
    reference_slots: collections.reference_slots,
    scalar_words: collections.scalar_words,
    owned_utf16_units: 3L * prefix.length().to_int64() +
    "_left_joined".length().to_int64(),
    owned_wire_bytes: 0L,
  })
}
