///|
/// Actual occurrence/suffix/port/Result counts before measurement collections
/// or role-pointer Strings exist. Shared collection construction accounts for
/// old/new backing. This is neither codec headroom nor a Resource permission.
pub fn prepared_client_infer_graph_measurement_storage(
  occurrence : ClientInferOccurrence,
) -> @execution.PreparationRepresentationUnits? {
  guard client_infer_occurrence_matches(occurrence, occurrence.owner) &&
    client_infer_occurrence_output_step(occurrence) is Some(terminal) &&
    terminal >= occurrence.step &&
    occurrence.step > 0 &&
    @lower.node_at(
      @lower.bound_preparation(occurrence.preparation),
      occurrence.step,
    )
    is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) else {
    return None
  }
  let count = 1L + (terminal - occurrence.step).to_int64()
  let mut ports = client_task_fragment_input_count(occurrence.preparation, None).to_int64()
  for step in (occurrence.step + 1)..<(terminal + 1) {
    ports += client_task_fragment_input_count(
      occurrence.preparation,
      Some(step),
    ).to_int64()
  }
  let results = @strategy.graph_result_count(occurrence.owner.graph).to_int64()
  let mut role_units = 0L
  for index in 0..<@infer.input_binding_count(infer) {
    role_units += @infer.input_binding_role(
        @infer.input_binding_at(infer, index).unwrap(),
      )
      .length()
      .to_int64()
  }
  // Fragment (four geometry tuples + record + producer tuple), each input
  // contract/edge tuple, possible direct/projected Result geometry and Plan.
  let tuples = 4L * count + 2L * ports + 8L * results + 5L
  guard @shape.collection_construction_extent({
      records: tuples + 2L * count + results,
      record_references: 8L * count + 6L * results + 3L * count,
      record_words: 3L * tuples + count,
      reference_arrays: 9L + count,
      reference_items: 4L * count +
      2L * ports +
      6L * results +
      2L +
      @infer.input_binding_count(infer).to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(collections) else {
    return None
  }
  let label = ("task_" +
    occurrence.task.to_string() +
    "_before_infer_" +
    terminal.to_string())
    .length()
    .to_int64()
  Some({
    record_headers: collections.record_headers,
    reference_slots: collections.reference_slots,
    scalar_words: collections.scalar_words,
    // Both actual pointer-escaping replacements may coexist. Original role
    // names remain borrowed. All generated Fragment labels remain retained.
    owned_utf16_units: 4L * role_units + count * label,
    owned_wire_bytes: 0L,
  })
}
