///|
/// Complete variable construction inputs for the existing effect-free Values/Task/Model
/// compiler. Every wire extent comes from the original codec. This is sizing
/// DATA, not an issued Plan, admission, work receipt or capacity reservation.
pub(all) struct ClientPureCompilationConstruction {
  limits : ClientPureCompilationLimits
  tasks : Bool
  fragments : Array[ClientTaskFragmentConstruction]
  borrowed_inputs : Array[(Int, Int, Int)]
  results : Array[(Int, Int, Int)]
  projections : Array[ClientResultGraphConstruction]
  nodes : (Int, Int, Int)
  edges : (Int, Int, Int)
  roots : (Int, Int, Int)
  graph : (Int, Int, Int)
  program : (Int, Int, Int)
  material : (Int, Int, Int)
  facts : ClientPublicationPlanFactGeometry
  witnesses : ClientPublicationWitnessGeometry
  fact_manifest : (Int, Int, Int)
  executable_plan : (Int, Int, Int)
} derive(Eq, Debug)

///|
/// Existing installed pure compiler codec configuration. These rejection
/// bounds are independent of Resource capacity and are never work consumed.
pub(all) struct ClientPureCompilationLimits {
  max_facts : Int
  max_witnesses : Int
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
} derive(Eq, Debug)

///|
pub fn client_standard_pure_compilation_limits() -> ClientPureCompilationLimits {
  {
    max_facts: 1000,
    max_witnesses: 10000,
    max_wire_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }
}

///|
// A construction upper bound can include the possible Result projection even
// when the real issuer selects a direct root. The original bounded issuer can
// never retain a successful value larger than its codec limits; clipping this
// SIZING bound does not admit the hypothetical graph or change those limits.
fn client_compilation_successful_geometry(
  value : (Int, Int, Int),
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> (Int, Int, Int) {
  (Int::min(value.0, bytes), Int::min(value.1, nodes), Int::min(value.2, depth))
}

///|
fn measure_client_compilation_array(
  values : Array[(Int, Int, Int)],
) -> (Int, Int, Int) raise @encode.EncodeFailure {
  let writer = @encode.measuring_writer(2147483647, 2147483647, 2147483647)
  client_plan_emit_array(writer, values, (value, writer) => {
    @encode.emit_measurement(writer, value)
  })
  @encode.finish_measurement_usage(writer)
}

///|
fn measure_client_values_fragment_construction(
  value : PreparedClientProgram,
  limits : @lower.SequenceLimits,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[ClientTaskFragmentConstruction, ClientValuesFragmentIssue] {
  let pipeline = match
    measure_prepared_client_values_pipeline(
      value, 0, limits, bytes, nodes, depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(AoA(Pipeline(issue)))
  }
  guard @strategy.graph_task_owner(value.graph, 0) is Some(owner) &&
    @lower.node_at(
      @lower.bound_preparation(owner),
      @pipeline.step_count(@lower.pipeline(@lower.bound_preparation(owner))) - 1,
    )
    is Some(node) &&
    @schema.as_object(@lower.node_output_schema(node)) is Some(row) else {
    return Err(MissingCheckedOutput)
  }
  let node_id = @lower.node_id(node)
  try {
    let contract = @encode.measuring_writer(bytes, nodes, depth)
    @contract.emit_checked(row, contract)
    let output_contract = @encode.finish_measurement_usage(contract)
    let fragment = @encode.measuring_writer(bytes, nodes, depth)
    emit_client_values_fragment_body(
      fragment,
      node_id,
      pipeline,
      (),
      (),
      (value, writer) => @encode.emit_measurement(writer, value),
      measure_client_fragment_cid,
    )
    Ok({
      initial_pipeline: pipeline,
      pipeline,
      fragment: @encode.finish_measurement_usage(fragment),
      input_contracts: [],
      output_contract,
      output_carrier: "relation",
      node_id,
      output_port: node_id,
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Measure all components of the SAME selected pure compiler before issuing
/// their wires, identities and canonical trees. Distinct tasks, Results,
/// repeated input edges and complete Carrier contracts remain distinct inputs.
/// The actual issuer still owns graph/contract/root admission and precedence.
pub fn measure_prepared_client_pure_compilation_construction(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientPureCompilationConstruction, ClientValuesExecutablePlanIssue] {
  measure_prepared_client_compilation_construction_owned(
    value,
    manifests,
    sequence_limits,
    max_facts,
    max_witnesses,
    max_wire_bytes,
    max_nodes,
    max_depth,
    [],
  )
}

///|
/// Measure the actual composed Model compiler from its original component
/// arrays, checked Results and edges. No component wire is parsed or issued.
pub fn measure_prepared_client_model_compilation_construction(
  value : PreparedClientProgram,
  components : Array[ClientInferPlanGraph],
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientPureCompilationConstruction, ClientValuesExecutablePlanIssue] {
  measure_prepared_client_compilation_construction_owned(
    value, manifests, sequence_limits, max_facts, max_witnesses, max_wire_bytes,
    max_nodes, max_depth, components,
  )
}

///|
fn measure_prepared_client_compilation_construction_owned(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  components : Array[ClientInferPlanGraph],
) -> Result[ClientPureCompilationConstruction, ClientValuesExecutablePlanIssue] {
  if !client_pure_compilation_limits_valid(
      max_facts, max_witnesses, max_wire_bytes, max_nodes, max_depth,
    ) {
    return Err(InvalidLimits)
  }
  let tasks = !components.is_empty() ||
    prepared_client_requires_task_compilation(value)
  let graph = value.graph
  let count = @strategy.graph_task_count(graph)
  if count == 0 ||
    count > max_nodes ||
    @strategy.graph_result_count(graph) == 0 ||
    @strategy.graph_program_has_effects(graph) ||
    !@strategy.graph_ordered_inputs_complete(graph) {
    return Err(TaskGraph(UnsupportedGraph))
  }
  let by_task : Map[Int, ClientInferPlanGraph] = Map([])
  if !components.is_empty() {
    guard prepared_client_composed_infer_occurrences(value) is Some(occurrences) &&
      occurrences.length() == components.length() else {
      return Err(TaskGraph(UnsupportedGraph))
    }
    for index in 0..<components.length() {
      let component = components[index]
      if !physical_equal(component.owner, value) ||
        !client_infer_occurrence_matches_plan(occurrences[index], component) ||
        by_task.contains(component.task) {
        return Err(TaskGraph(UnsupportedGraph))
      }
      by_task[component.task] = component
    }
  }
  let fragments : Array[ClientTaskFragmentConstruction] = []
  let borrowed_inputs : Array[(Int, Int, Int)] = []
  let outputs : Array[(String, String, String)] = []
  let inputs : Array[String] = []
  let graph_nodes : Array[(Int, Int, Int)] = []
  let graph_edges : Array[(Int, Int, Int)] = []
  for task in 0..<count {
    if by_task.get(task) is Some(component) {
      guard client_infer_graph_original_parts(
          component, value, max_wire_bytes, max_nodes, max_depth,
        )
        is Some((nodes, edges, roots)) &&
        roots.is_empty() &&
        component.graph.transformations.is_empty() else {
        return Err(TaskGraph(UnsupportedGraph))
      }
      let input = match component.serialization {
        Some(serialization) => serialization.input
        None => component.input
      }
      let mut input_geometry = None
      try {
        for node in nodes {
          let writer = @encode.measuring_writer(
            max_wire_bytes, max_nodes, max_depth,
          )
          @canonical.emit_value(node, writer)
          let geometry = @encode.finish_measurement_usage(writer)
          graph_nodes.push(geometry)
          if @canonical.object_field(node, "node_id")
            is Some(@canonical.String(id)) &&
            id == input.node_id {
            input_geometry = Some(geometry)
          }
        }
        for edge in edges {
          let writer = @encode.measuring_writer(
            max_wire_bytes, max_nodes, max_depth,
          )
          @canonical.emit_value(edge, writer)
          graph_edges.push(@encode.finish_measurement_usage(writer))
        }
      } catch {
        _ => return Err(Encoding)
      }
      guard input_geometry is Some(geometry) else {
        return Err(TaskGraph(UnsupportedGraph))
      }
      borrowed_inputs.push(geometry)
      inputs.push(input.node_id)
      outputs.push(
        (
          component.output.node_id,
          component.output.output_port,
          component.output.output_carrier,
        ),
      )
      continue
    }
    let fragment = if tasks {
      match
        measure_prepared_client_task_fragment_construction(
          value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(TaskGraph(Fragment(issue)))
      }
    } else {
      if task != 0 {
        return Err(Graph(UnsupportedGraph))
      }
      match
        measure_client_values_fragment_construction(
          value, sequence_limits, max_wire_bytes, max_nodes, max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Graph(Fragment(issue)))
      }
    }
    fragments.push(fragment)
    graph_nodes.push(fragment.fragment)
    outputs.push(
      (fragment.node_id, fragment.output_port, fragment.output_carrier),
    )
    inputs.push(fragment.node_id)
  }
  let results : Array[(Int, Int, Int)] = []
  let projections : Array[ClientResultGraphConstruction] = []
  let names : Array[String] = []
  let result_cids : Array[Unit] = []
  let graph_roots : Array[(Int, Int, Int)] = []
  for result in 0..<@strategy.graph_result_count(graph) {
    guard @strategy.graph_result_task(graph, result) is Some(task) &&
      outputs.get(task) is Some((output_node, output_port, _)) else {
      return Err(TaskGraph(UnsupportedGraph))
    }
    let plan = match
      measure_prepared_client_result_plan(
        value, result, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Material(ResultPlan(issue)))
    }
    let (producer_node, producer_port) = match by_task.get(task) {
      Some(component) => {
        guard client_infer_result_producer(
            component.occurrence,
            result,
            component.result_producers,
          )
          is Some((_, node, port, _)) else {
          return Err(TaskGraph(Root(Root(RequiresResultTransformation))))
        }
        (node, port)
      }
      None => (output_node, output_port)
    }
    let projection = match
      measure_prepared_client_result_graph_construction(
        value, result, producer_node, producer_port, 2147483647, 2147483647, 2147483647,
      ) {
      Ok(value) => value
      Err(issue) => return Err(TaskGraph(Root(issue)))
    }
    let (_, _, name, _, _, _) = match
      client_result_plan_originals(value, result) {
      Ok(value) => value
      Err(issue) => return Err(Material(ResultPlan(issue)))
    }
    if names.contains(name) {
      return Err(Material(DuplicateResultName))
    }
    names.push(name)
    result_cids.push(())
    results.push(plan)
    projections.push(projection)
    graph_nodes.push(projection.node)
    graph_edges.push(projection.edge)
    graph_roots.push(
      (
        Int::max(projection.root.0, projection.direct_root.0),
        Int::max(projection.root.1, projection.direct_root.1),
        Int::max(projection.root.2, projection.direct_root.2),
      ),
    )
  }
  try {
    if tasks {
      for index in 0..<@strategy.graph_data_count(graph) {
        guard @strategy.graph_data_at(graph, index) is Some(edge) &&
          outputs.get(@strategy.data_edge_producer(edge))
          is Some((source_node, source_port, source_carrier)) &&
          inputs.get(@strategy.data_edge_consumer(edge)) is Some(destination) &&
          client_task_edge_input(graph, edge) is Some((input_name, _)) else {
          return Err(TaskGraph(InvalidEdge))
        }
        let writer = @encode.measuring_writer(
          2147483647, 2147483647, 2147483647,
        )
        emit_client_compilation_data_edge(
          writer,
          source_carrier,
          (),
          source_node,
          source_port,
          destination,
          input_name,
          measure_client_fragment_cid,
        )
        graph_edges.push(@encode.finish_measurement_usage(writer))
      }
    }
    measure_client_compilation_final_construction(
      value,
      manifests,
      max_facts,
      max_witnesses,
      max_wire_bytes,
      max_nodes,
      max_depth,
      tasks,
      fragments,
      borrowed_inputs,
      results,
      projections,
      names,
      result_cids,
      graph_nodes,
      graph_edges,
      graph_roots,
      if components.is_empty() {
        []
      } else {
        client_multi_infer_required_profiles(
          (),
          content_contract=if components.any(component => {
              component.serialization is Some(_)
            }) {
            Some(())
          } else {
            None
          },
        )
      },
    )
  } catch {
    _ => Err(Encoding)
  }
}

///|
// Shared final measurement for the actual compiler. The caller supplies its
// already checked original component geometry; no source classification,
// graph admission, parser or capacity issuer is introduced here.
fn measure_client_compilation_final_construction(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  tasks : Bool,
  fragments : Array[ClientTaskFragmentConstruction],
  borrowed_inputs : Array[(Int, Int, Int)],
  results : Array[(Int, Int, Int)],
  projections : Array[ClientResultGraphConstruction],
  names : Array[String],
  result_cids : Array[Unit],
  graph_nodes : Array[(Int, Int, Int)],
  graph_edges : Array[(Int, Int, Int)],
  graph_roots : Array[(Int, Int, Int)],
  required_profiles : Array[(String, Unit)],
) -> Result[ClientPureCompilationConstruction, ClientValuesExecutablePlanIssue] {
  try {
    let nodes = measure_client_compilation_array(graph_nodes)
    let edges = measure_client_compilation_array(graph_edges)
    let roots = measure_client_compilation_array(graph_roots)
    let graph_writer = @encode.measuring_writer(
      2147483647, 2147483647, 2147483647,
    )
    let emitted : Result[Unit, Unit] = emit_client_compilation_graph(
      graph_writer,
      writer => {
        for edge in graph_edges {
          @encode.emit_measurement(writer, edge)
        }
        Ok(())
      },
      writer => {
        for node in graph_nodes {
          @encode.emit_measurement(writer, node)
        }
      },
      writer => {
        for root in graph_roots {
          @encode.emit_measurement(writer, root)
        }
        Ok(())
      },
    )
    ignore(emitted)
    let graph_geometry = client_compilation_successful_geometry(
      @encode.finish_measurement_usage(graph_writer),
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    let program_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    @syntax.emit_metadata_stripped_program(value.source, program_writer)
    let program = @encode.finish_measurement_usage(program_writer)
    let material_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_client_execution_material_body(
      material_writer,
      value,
      manifests,
      program,
      (),
      (),
      names,
      result_cids,
      [],
      None,
      (value, writer) => @encode.emit_measurement(writer, value),
      measure_client_fragment_cid,
    )
    let material = @encode.finish_measurement_usage(material_writer)
    let facts = match
      measure_prepared_client_publication_plan_facts(
        value, max_facts, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Facts(issue))
    }
    let witnesses = match
      measure_prepared_client_publication_witnesses(
        value, max_witnesses, max_wire_bytes, max_nodes, max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Witnesses(issue))
    }
    let manifest_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_client_plan_fact_manifest_body(
      manifest_writer,
      facts.entries,
      (),
      (value, writer) => @encode.emit_measurement(writer, value),
      measure_client_fragment_cid,
    )
    let fact_manifest = @encode.finish_measurement_usage(manifest_writer)
    let plan_writer = @encode.measuring_writer(
      2147483647, 2147483647, 2147483647,
    )
    emit_client_executable_plan_body(
      plan_writer,
      {
        fact_values: facts.entries,
        limit_values: facts.limits,
        binding_values: facts.bindings,
        witness_values: witnesses.bodies,
        nodes,
        edges,
        roots,
        material_value: material,
        manifest_cid: (),
        required_profiles,
      },
      Some(()),
      (value, writer) => @encode.emit_measurement(writer, value),
      measure_client_fragment_cid,
    )
    Ok({
      limits: {
        max_facts,
        max_witnesses,
        max_wire_bytes,
        max_nodes,
        max_depth,
      },
      tasks,
      fragments,
      borrowed_inputs,
      results,
      projections,
      nodes,
      edges,
      roots,
      graph: graph_geometry,
      program,
      material,
      facts,
      witnesses,
      fact_manifest,
      executable_plan: client_compilation_successful_geometry(
        @encode.finish_measurement_usage(plan_writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      ),
    })
  } catch {
    _ => Err(Encoding)
  }
}
