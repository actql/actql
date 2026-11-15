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
  client_keyed_plan_metadata_storage_original(
    occurrence.owner,
    occurrence.preparation,
    occurrence.task,
    stage,
    input,
    join,
  )
}

///|
fn client_keyed_plan_metadata_storage_original(
  owner : PreparedClientProgram,
  preparation : @lower.BoundPrepared,
  task : Int,
  stage : Int,
  input : Int,
  join : Int,
  physical_profile? : Bool = true,
) -> @execution.PreparationRepresentationUnits? {
  let program = @strategy.graph_program(owner.graph)
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
    @lower.preparation_carrier_at(
      @lower.bound_preparation(preparation),
      @acquisition.keyed_join_left(binding.join),
    )
    is Some(left) &&
    @pipeline.input_at(
      @lower.pipeline(@lower.bound_preparation(preparation)),
      input,
    )
    is Some((_, right)) &&
    @carrier.relation_rows(left) is Some(left_rows) &&
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
    @lower.pipeline(@lower.bound_preparation(preparation)),
  ).to_int64()
  let fields = @schema.field_count(left_schema).to_int64() +
    @schema.field_count(right_schema).to_int64()
  guard @shape.collection_construction_extent({
      // Fragment inputs (8 references/4 words), barrier inputs (14 references),
      // component (5 refs including original barrier document), lookup Fragment
      // (6 refs), acquisition/Effect view,
      // the selected pair/Option and each role tuple/two possible Options.
      records: 10L + 3L * roles,
      record_references: 8L +
      (if physical_profile { 14L } else { 13L }) +
      5L +
      6L +
      16L +
      4L +
      5L * roles,
      record_words: 4L + 4L,
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
  let prefix = "task_" + task.to_string() + "_lookup_" + join.to_string()
  Some({
    record_headers: collections.record_headers,
    reference_slots: collections.reference_slots,
    scalar_words: collections.scalar_words,
    owned_utf16_units: 3L * prefix.length().to_int64() +
    "_left_joined".length().to_int64(),
    owned_wire_bytes: 0L,
  })
}

///|
/// Before-lowering constructor DATA from the actual checked Source-only join.
/// Variable lowering bodies and actual emitted geometry are quoted separately
/// by the SAME preparation owner, as in the existing Model compiler.
pub fn prepared_client_effect_keyed_plan_measurement_storage(
  effect : PreparedClientEffectComputation,
  keyed : ClientKeyedAcquisition,
  generic? : Bool = false,
) -> @execution.PreparationRepresentationUnits? {
  guard client_keyed_acquisition_matches_effect_program(keyed, effect) &&
    client_keyed_acquisition_coordinates(keyed) is Some((stage, task, join)) &&
    prepared_client_effect_infer_occurrences(effect) is Some([]) else {
    return None
  }
  guard client_keyed_plan_metadata_storage_original(
      client_effect_program_view(effect),
      keyed.owner,
      task,
      stage,
      @acquisition.keyed_join_input(keyed.binding.join),
      join,
      physical_profile=!generic,
    )
    is Some(metadata) &&
    @shape.collection_construction_extent({
      // One measurement holder plus two Fragment measurement records, their
      // geometry triples/producer pairs, and the three node/one pair geometry.
      // The closed Source-only measurement and component variants coexist
      // during issue. Model compiler inputs retain their original layout.
      records: 21L,
      record_references: 29L,
      record_words: 47L,
      reference_arrays: 2L,
      reference_items: 5L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(measurement) else {
    return None
  }
  @execution.compose_preparation_representation([
    metadata,
    {
      record_headers: measurement.record_headers,
      reference_slots: measurement.reference_slots,
      scalar_words: measurement.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ])
}
