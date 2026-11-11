///|
/// Actual occurrence/suffix/port/Result counts before measurement collections
/// or role-pointer Strings exist. Shared collection construction accounts for
/// old/new backing. Actual mapping/Fragment lowering bodies use the SAME
/// Request's existing compiler/Plan variable-data envelope, separately grown
/// before entry for each actual preparation call. This metadata is neither
/// codec headroom nor a Resource permission.
pub fn prepared_client_infer_graph_measurement_storage(
  occurrence : ClientInferOccurrence,
  serialization? : ClientSerializationPlanGraph? = None,
  native_keyed? : Bool = false,
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
  let (count, original_ports, content_parts) = match serialization {
    None if native_keyed => {
      guard client_composed_keyed_source_coordinates(occurrence.owner)
        is Ok(Some((stage, _, join))) &&
        stage == occurrence.stage &&
        join < occurrence.step &&
        @lower.node_at(@lower.bound_preparation(occurrence.preparation), join)
        is Some(join_node) else {
        return None
      }
      (
        2L + (terminal - occurrence.step).to_int64(),
        client_task_fragment_input_count(occurrence.preparation, None).to_int64() +
        @lower.node_input_count(join_node).to_int64(),
        // One lookup node, three edges, body/node geometry and their pair.
        7L,
      )
    }
    None =>
      (
        1L + (terminal - occurrence.step).to_int64(),
        client_task_fragment_input_count(occurrence.preparation, None).to_int64(),
        0L,
      )
    Some(component) => {
      guard physical_equal(component.owner, occurrence.owner) &&
        physical_equal(
          @lower.serialization_owner(component.barrier),
          occurrence.preparation,
        ) &&
        component.task == occurrence.task &&
        component.step < occurrence.step &&
        component.graph_roots.is_empty() else {
        return None
      }
      let mut inputs = 0L
      for step in (component.step + 1)..<occurrence.step {
        inputs += client_task_fragment_input_count(
          occurrence.preparation,
          Some(step),
        ).to_int64()
      }
      (
        (terminal - component.step - 1).to_int64(),
        inputs,
        (component.graph_nodes.length() + component.graph_edges.length()).to_int64(),
      )
    }
  }
  let mut ports = original_ports
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
  let tuples = 4L * count + 2L * ports + 8L * results + 5L + content_parts
  guard @shape.collection_construction_extent({
      records: tuples + 2L * count + results,
      record_references: 8L * count + 6L * results + 3L * count + 6L,
      record_words: 3L * tuples + count + 3L,
      reference_arrays: 10L + count,
      reference_items: 5L * count +
      2L * ports +
      6L * results +
      2L +
      @infer.input_binding_count(infer).to_int64() +
      2L * content_parts,
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
    (if serialization is Some(_) {
      "_after_serialize_"
    } else {
      "_before_infer_"
    }) +
    terminal.to_string())
    .length()
    .to_int64()
  let base : @execution.PreparationRepresentationUnits = {
    record_headers: collections.record_headers,
    reference_slots: collections.reference_slots,
    scalar_words: collections.scalar_words,
    // Both actual pointer-escaping replacements may coexist. Original role
    // names remain borrowed. All generated Fragment labels remain retained.
    owned_utf16_units: 4L * role_units + count * label,
    owned_wire_bytes: 0L,
  }
  if !native_keyed {
    return Some(base)
  }
  guard serialization is None &&
    client_keyed_plan_metadata_storage(occurrence) is Some(keyed) else {
    return None
  }
  @execution.compose_preparation_representation([base, keyed])
}
