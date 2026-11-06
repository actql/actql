///|
/// Measure the SAME original terminal serialization compiler, including its
/// checked Result inventory. Component arrays and their full writer facts are
/// borrowed from the issuer. No Graph wire is reparsed or Model/keyed input
/// fabricated, and this does not grant physical construction capacity.
pub fn measure_prepared_client_serialization_compilation_construction(
  value : PreparedClientProgram,
  component : ClientSerializationPlanGraph,
  manifests : ClientCompilationManifests,
  limits : ClientPureCompilationLimits,
) -> Result[ClientPureCompilationConstruction, ClientValuesExecutablePlanIssue] {
  if !client_pure_compilation_limits_valid(
      limits.max_facts,
      limits.max_witnesses,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    return Err(InvalidLimits)
  }
  guard client_serialization_graph_original_parts(
      component,
      value,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some((nodes, edges, roots)) &&
    roots.length() == @strategy.graph_result_count(value.graph) &&
    component.graph.result_plans.length() == roots.length() &&
    !roots.is_empty() else {
    return Err(TaskGraph(UnsupportedGraph))
  }
  let graph_nodes : Array[(Int, Int, Int)] = []
  let graph_edges : Array[(Int, Int, Int)] = []
  let graph_roots : Array[(Int, Int, Int)] = []
  try {
    for
      (originals, measured) in [
        (nodes, graph_nodes),
        (edges, graph_edges),
        (roots, graph_roots),
      ] {
      for original in originals {
        let writer = @encode.measuring_writer(
          limits.max_wire_bytes,
          limits.max_nodes,
          limits.max_depth,
        )
        @canonical.emit_value(original, writer)
        measured.push(@encode.finish_measurement_usage(writer))
      }
    }
  } catch {
    _ => return Err(Encoding)
  }
  let results : Array[(Int, Int, Int)] = []
  let names : Array[String] = []
  let result_cids : Array[Unit] = []
  for result in 0..<roots.length() {
    let original = component.graph.result_plans[result]
    if !physical_equal(original.owner, value) || original.result != result {
      return Err(TaskGraph(UnsupportedGraph))
    }
    let geometry = match
      measure_prepared_client_result_plan(
        value,
        result,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) {
      Err(issue) => return Err(Material(ResultPlan(issue)))
      Ok(geometry) => geometry
    }
    results.push(geometry)
    names.push(original.result_name)
    result_cids.push(())
  }
  // The serialization issuer already owns these fragments and transformations.
  // This compiler borrows their complete Graph, rather than rebuilding them.
  measure_client_compilation_final_construction(
    value,
    manifests,
    limits.max_facts,
    limits.max_witnesses,
    limits.max_wire_bytes,
    limits.max_nodes,
    limits.max_depth,
    true,
    [],
    [],
    results,
    [],
    names,
    result_cids,
    graph_nodes.map(unknown_client_compilation_geometry),
    graph_edges.map(unknown_client_compilation_geometry),
    graph_roots.map(unknown_client_compilation_geometry),
    [("actql-content/0.1", ())],
  )
}
