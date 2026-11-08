///|
/// Variable collection storage retained by the pure compiler measurement.
/// Counts come from the SAME checked task/Result/publication inventory, never
/// codec maxima or completed output. Repeated port/claim occurrences remain
/// distinct bounds; witness deduplication may retain fewer bodies. This does
/// not cover nested lowering/Carrier helper scratch, work or physical supply.
pub fn prepared_client_pure_measurement_storage(
  value : PreparedClientProgram,
  limits : ClientPureCompilationLimits,
) -> Result[
  @execution.PreparationRepresentationUnits,
  ClientValuesExecutablePlanIssue,
] {
  if !client_pure_compilation_limits_valid(
      limits.max_facts,
      limits.max_witnesses,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    return Err(InvalidLimits)
  }
  match client_pure_measurement_storage_owned(value, []) {
    Some(units) => Ok(units)
    None => Err(Encoding)
  }
}

///|
/// Actual composed inventory storage before its measurement arrays exist.
/// Component trees are borrowed and remain separately backed by their owner.
pub fn prepared_client_model_measurement_storage(
  value : PreparedClientProgram,
  components : Array[ClientInferPlanGraph],
  limits : ClientPureCompilationLimits,
) -> Result[
  @execution.PreparationRepresentationUnits,
  ClientValuesExecutablePlanIssue,
] {
  if !client_pure_compilation_limits_valid(
      limits.max_facts,
      limits.max_witnesses,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    return Err(InvalidLimits)
  }
  match client_pure_measurement_storage_owned(value, components) {
    Some(units) => Ok(units)
    None => Err(Encoding)
  }
}

///|
fn client_pure_compilation_limits_valid(
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  max_facts > 0 &&
  max_witnesses > 0 &&
  max_wire_bytes > 0 &&
  max_nodes > 0 &&
  max_depth > 0
}

///|
/// Storage of the same serialization compiler measurement. The original
/// component arrays remain borrowed; the shared inventory owns only the
/// returned measurement collections, not a second Graph or Model purpose.
pub fn prepared_client_serialization_measurement_storage(
  value : PreparedClientProgram,
  component : ClientSerializationPlanGraph,
  limits : ClientPureCompilationLimits,
) -> Result[
  @execution.PreparationRepresentationUnits,
  ClientValuesExecutablePlanIssue,
] {
  if !client_pure_compilation_limits_valid(
      limits.max_facts,
      limits.max_witnesses,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    return Err(InvalidLimits)
  }
  match
    client_pure_measurement_storage_owned(
      value,
      [],
      serialization=Some(component),
    ) {
    Some(units) => Ok(units)
    None => Err(Encoding)
  }
}

///|
fn client_pure_measurement_storage_owned(
  value : PreparedClientProgram,
  components : Array[ClientInferPlanGraph],
  serialization? : ClientSerializationPlanGraph? = None,
) -> @execution.PreparationRepresentationUnits? {
  let graph = value.graph
  let tasks = @strategy.graph_task_count(graph).to_int64()
  let results = @strategy.graph_result_count(graph).to_int64()
  let edges = @strategy.graph_data_count(graph).to_int64()
  if tasks < 1L || results < 1L || edges < 0L {
    return None
  }
  let mut component_nodes = 0L
  let mut component_edges = 0L
  let mut component_count = components.length().to_int64()
  for component in components {
    guard client_infer_graph_original_parts(
        component, value, 2147483647, 2147483647, 2147483647,
      )
      is Some((nodes, edges, _)) &&
      @execution.checked_preparation_add_product(
        component_nodes,
        nodes.length().to_int64(),
        1L,
      )
      is Some(next_nodes) &&
      @execution.checked_preparation_add_product(
        component_edges,
        edges.length().to_int64(),
        1L,
      )
      is Some(next_edges) else {
      return None
    }
    component_nodes = next_nodes
    component_edges = next_edges
  }
  if serialization is Some(component) {
    guard components.is_empty() &&
      client_serialization_graph_original_parts(
        component, value, 2147483647, 2147483647, 2147483647,
      )
      is Some((nodes, edges, _)) else {
      return None
    }
    component_nodes = nodes.length().to_int64()
    component_edges = edges.length().to_int64()
    component_count = 1L
  }
  let ordinary = tasks - component_count
  if ordinary < 0L {
    return None
  }
  let mut ports = 0L
  for task in 0..<@strategy.graph_task_count(graph) {
    guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
      return None
    }
    let count = client_task_fragment_input_count(
      owner,
      @strategy.graph_task_selected_step(graph, task),
    )
    guard @execution.checked_preparation_add_product(
        ports,
        count.to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    ports = next
  }
  let mut facts = 0L
  let mut witnesses = 0L
  let program = @strategy.graph_program(graph)
  for unit in 0..<@checked.unit_count(program) {
    guard @checked.unit_publication_count(program, unit) is Some(count) &&
      @execution.checked_preparation_add_product(facts, count.to_int64(), 2L)
      is Some(next) else {
      return None
    }
    facts = next
    for index in 0..<count {
      guard @checked.unit_publication_at(program, unit, index)
        is Some(publication) else {
        return None
      }
      for
        claim in [
          @checked.publication_rows(publication),
          @checked.publication_bytes(publication),
        ] {
        let count = @capacity.claim_count(@capacity.limit_claims(claim))
        guard @execution.checked_preparation_add_product(
            witnesses,
            count.to_int64(),
            1L,
          )
          is Some(next) else {
          return None
        }
        witnesses = next
      }
    }
  }
  let task_compiler = component_count != 0L ||
    prepared_client_requires_task_compilation(value)
  let profile = if component_count == 0L { 0L } else { 1L }
  // Fragment holds its initial/projected geometry, Fragment geometry and
  // output-contract geometry. Values aliases the initial/projected tuple.
  // Task's two tuples are a bound even when an unselected task aliases them.
  let task_tuples = if task_compiler { 4L } else { 3L }
  // Each Result holds its six projection geometries, original Plan geometry
  // and max(direct, projected) root. Data edges and fact/witness bodies each
  // hold one three-scalar geometry; graph arrays borrow those same tuples.
  guard @execution.checked_preparation_add_product(0L, ordinary, task_tuples)
    is Some(tuples) &&
    @execution.checked_preparation_add_product(tuples, ports, 1L)
    is Some(tuples) &&
    @execution.checked_preparation_add_product(tuples, results, 8L)
    is Some(tuples) &&
    @execution.checked_preparation_add_product(tuples, edges, 1L)
    is Some(tuples) &&
    @execution.checked_preparation_add_product(tuples, facts, 3L)
    is Some(tuples) &&
    @execution.checked_preparation_add_product(tuples, witnesses, 1L)
    is Some(tuples) &&
    @execution.checked_preparation_add_product(tuples, component_nodes, 1L)
    is Some(tuples) &&
    @execution.checked_preparation_add_product(tuples, component_edges, 1L)
    is Some(tuples) &&
    @execution.checked_preparation_add_product(tuples, tasks, 1L)
    is Some(records) &&
    @execution.checked_preparation_add_product(records, ordinary, 1L)
    is Some(records) &&
    @execution.checked_preparation_add_product(records, results, 1L)
    is Some(records) &&
    @execution.checked_preparation_add_product(records, profile, 1L)
    is Some(records) &&
    @execution.checked_preparation_add_product(0L, tuples, 3L) is Some(words) &&
    @execution.checked_preparation_add_product(0L, ordinary, 8L)
    is Some(references) &&
    @execution.checked_preparation_add_product(references, results, 6L)
    is Some(references) &&
    @execution.checked_preparation_add_product(references, tasks, 3L)
    is Some(references) &&
    @execution.checked_preparation_add_product(references, profile, 1L)
    is Some(references) else {
    return None
  }
  // fragments, Results, projections, names, graph nodes/edges/roots, three
  // fact arrays and two witness arrays; each Fragment owns its port array.
  // The result-CID placeholder array contains inline Unit values, not refs.
  guard @execution.checked_preparation_add_product(15L, ordinary, 1L)
    is Some(arrays) &&
    @execution.checked_preparation_add_product(arrays, profile, 1L)
    is Some(arrays) &&
    @execution.checked_preparation_add_product(0L, ordinary, 2L) is Some(items) &&
    @execution.checked_preparation_add_product(items, tasks, 2L) is Some(items) &&
    @execution.checked_preparation_add_product(items, component_count, 1L)
    is Some(items) &&
    @execution.checked_preparation_add_product(items, component_nodes, 1L)
    is Some(items) &&
    @execution.checked_preparation_add_product(items, component_edges, 1L)
    is Some(items) &&
    @execution.checked_preparation_add_product(items, results, 6L)
    is Some(items) &&
    @execution.checked_preparation_add_product(items, edges, 1L) is Some(items) &&
    @execution.checked_preparation_add_product(items, ports, 1L) is Some(items) &&
    @execution.checked_preparation_add_product(items, facts, 3L) is Some(items) &&
    @execution.checked_preparation_add_product(items, witnesses, 2L)
    is Some(items) &&
    @execution.checked_preparation_add_product(items, profile, 1L)
    is Some(items) &&
    // SAME-emitter construction geometry has nine scalar counts per retained
    // report plus its collection. Variable reports are bounded by the same
    // original tuple occurrences above; ten fixed final/Values report slots
    // cover pipeline/contract and nodes/edges/roots/graph/program/material/
    // manifest/Plan measurements. No policy maximum or second scan is used.
    @execution.checked_preparation_add_product(tuples, 10L, 1L)
    is Some(geometry_reports) &&
    @execution.checked_preparation_add_product(records, geometry_reports, 3L)
    is Some(records) &&
    @execution.checked_preparation_add_product(references, geometry_reports, 4L)
    is Some(references) &&
    @execution.checked_preparation_add_product(references, ordinary, 3L)
    is Some(references) &&
    @execution.checked_preparation_add_product(words, geometry_reports, 9L)
    is Some(words) &&
    @execution.checked_preparation_add_product(items, geometry_reports, 1L)
    is Some(items) &&
    @shape.collection_construction_extent({
      records,
      record_references: references + 9L,
      record_words: words,
      reference_arrays: arrays + 5L,
      reference_items: items,
      scalar_arrays: 1L,
      scalar_items: results,
      maps: 1L,
      map_entries: component_count,
    })
    is Some(collections) else {
    return None
  }
  // Generated task labels stay in Fragment geometry; checked output/Result
  // names and witness CIDs are borrowed. Projection labels are sequential.
  let task_label = if task_compiler {
    client_compilation_task_node_id(@strategy.graph_task_count(graph) - 1)
    .length()
    .to_int64()
  } else {
    0L
  }
  let result_label = client_compilation_result_node_id(
      @strategy.graph_result_count(graph) - 1,
    )
    .length()
    .to_int64()
  let text = if task_compiler {
    guard @execution.checked_preparation_add_product(
        result_label, tasks, task_label,
      )
      is Some(text) else {
      return None
    }
    text
  } else {
    // No generated task label exists in the Values branch. The common
    // checked product intentionally requires a positive coefficient; absence
    // is not represented by inventing a zero-priced storage dimension.
    result_label
  }
  Some({
    record_headers: collections.record_headers,
    reference_slots: collections.reference_slots,
    scalar_words: collections.scalar_words,
    owned_utf16_units: text,
    owned_wire_bytes: 0L,
  })
}
