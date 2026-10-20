///|
/// Compilation material for one checked Content barrier. The original input
/// fragment remains pure AoA; byte generation, policy and custody do not become
/// a synthetic REL.serialize operation or a caller-created Values completion.
pub struct ClientSerializationPlanGraph {
  owner : PreparedClientProgram
  task : Int
  step : Int
  barrier : @lower.PreparedSerialization
  input : ClientTaskFragmentNode
  output : ClientTaskFragmentNode
  graph : ClientTaskPlanGraph
  policy : @publication.CapturedEffectDependencyBody
  max_rows : Int
  max_bytes : Int
}

///|
pub(all) enum ClientSerializationPlanGraphIssue {
  InvalidLimits
  UnsupportedGraph
  UnsupportedOrder
  Policy(ClientCompiledRunIssue)
  PolicyClosure(@checked.LocalDependencyBodyIssue)
  SourcePolicy(@checked.UnitBuildFailure)
  Preparation(ClientSerializationPreparationIssue)
  Input(ClientSerializationPrefixIssue)
  Root(ClientResultPlanPartsIssue)
  Encoding
}

///|
pub fn client_serialization_plan_graph_wire(
  value : ClientSerializationPlanGraph,
) -> String {
  value.graph.wire
}

///|
pub fn client_serialization_plan_graph_coordinates(
  value : ClientSerializationPlanGraph,
) -> (Int, Int) {
  (value.task, value.step)
}

///|
/// The first installed component has a source-free checked Compute prefix and
/// terminal Serialize. Acquired inputs and later Compute/Model components must
/// supply their real producer bindings; this issuer never fabricates them.
/// Host ceilings are plan-bound quantities, not proof of an actual row count.
pub fn issue_prepared_client_serialization_plan_graph(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  source_free_policy : @publication.CapturedEffectDependencyBody,
  max_rows : Int,
  max_bytes : Int,
  max_preparation_work : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientSerializationPlanGraph, ClientSerializationPlanGraphIssue] {
  issue_source_free_client_serialization_plan_graph(
    owner, task, step, source_free_policy, max_rows, max_bytes, max_preparation_work,
    sequence_limits, max_wire_bytes, max_nodes, max_depth, true,
  )
}

///|
/// A checked intermediate component has no invented public Result roots.
/// Its caller must incorporate the actual Content port and dependency edges
/// into the enclosing Plan, and retain this owner through physical generation.
/// This is not standalone Run admission or permission to publish that prefix.
pub fn issue_prepared_client_serialization_plan_component(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  source_free_policy : @publication.CapturedEffectDependencyBody,
  max_rows : Int,
  max_bytes : Int,
  max_preparation_work : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientSerializationPlanGraph, ClientSerializationPlanGraphIssue] {
  issue_source_free_client_serialization_plan_graph(
    owner, task, step, source_free_policy, max_rows, max_bytes, max_preparation_work,
    sequence_limits, max_wire_bytes, max_nodes, max_depth, false,
  )
}

///|
fn issue_source_free_client_serialization_plan_graph(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  source_free_policy : @publication.CapturedEffectDependencyBody,
  max_rows : Int,
  max_bytes : Int,
  max_preparation_work : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  include_results : Bool,
) -> Result[ClientSerializationPlanGraph, ClientSerializationPlanGraphIssue] {
  if max_rows < 0 ||
    max_bytes < 0 ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return Err(InvalidLimits)
  }
  if @strategy.graph_task_count(owner.graph) != 1 ||
    task != 0 ||
    !@strategy.graph_source_free_inputs_complete(owner.graph) ||
    @strategy.graph_program_has_effects(owner.graph) {
    return Err(UnsupportedGraph)
  }
  // The explicit Host unknown-provenance policy original is admitted through
  // the existing owner. A valid CID or a generic dependency body is not enough.
  let policy = match
    admit_source_free_result_policy_body(
      @publication.captured_effect_dependency_body_cid(source_free_policy),
      @publication.captured_effect_dependency_body_json(source_free_policy),
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Policy(issue))
  }
  issue_client_serialization_plan_graph_with_policy(
    owner,
    task,
    step,
    policy,
    max_rows,
    max_bytes,
    max_preparation_work,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    include_results~,
  )
}

///|
/// Bind an acquired component to its checked complete Source policy closure.
/// Capture and physical completion remain mandatory at execution/Invocation;
/// a Plan does not manufacture observations or authorize provider I/O.
pub fn issue_prepared_client_acquired_serialization_plan_graph(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  max_rows : Int,
  max_bytes : Int,
  max_preparation_work : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientSerializationPlanGraph, ClientSerializationPlanGraphIssue] {
  issue_acquired_client_serialization_plan_graph(
    owner, task, step, max_rows, max_bytes, max_preparation_work, sequence_limits,
    max_wire_bytes, max_nodes, max_depth, true,
  )
}

///|
/// Retain the complete acquired policy closure for an intermediate Content
/// barrier. No public Result is invented; the enclosing consumer must supply
/// its real dependency and completion evidence under this original owner.
pub fn issue_prepared_client_acquired_serialization_plan_component(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  max_rows : Int,
  max_bytes : Int,
  max_preparation_work : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientSerializationPlanGraph, ClientSerializationPlanGraphIssue] {
  issue_acquired_client_serialization_plan_graph(
    owner, task, step, max_rows, max_bytes, max_preparation_work, sequence_limits,
    max_wire_bytes, max_nodes, max_depth, false,
  )
}

///|
fn issue_acquired_client_serialization_plan_graph(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  max_rows : Int,
  max_bytes : Int,
  max_preparation_work : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  include_results : Bool,
  effect_component? : Bool = false,
) -> Result[ClientSerializationPlanGraph, ClientSerializationPlanGraphIssue] {
  if max_rows < 0 ||
    max_bytes < 0 ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return Err(InvalidLimits)
  }
  if !client_serialization_single_capture_shape(owner, task) ||
    prepared_client_acquisition_count(owner) != 1 ||
    !client_serialization_source_inventory_supported(
      owner, task, step, max_preparation_work,
    ) ||
    (@strategy.graph_program_has_effects(owner.graph) && !effect_component) {
    return Err(UnsupportedGraph)
  }
  guard @strategy.graph_task_unit_index(owner.graph, task) is Some(unit) else {
    return Err(UnsupportedGraph)
  }
  let selected = @checked.prepare_serialization_output_source_policy(
    @strategy.graph_program(owner.graph),
    unit,
    step,
    max_preparation_work,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ) catch {
    @checked.BudgetExceeded =>
      return Err(PolicyClosure(@checked.BudgetExceeded))
    @checked.Encoding(_) => return Err(PolicyClosure(@checked.Encoding))
    issue => return Err(SourcePolicy(issue))
  }
  guard selected is Some(selected) else {
    return Err(PolicyClosure(@checked.MissingDependency))
  }
  let bodies = match
    checked_client_source_policy_bodies(
      @strategy.graph_program(owner.graph),
      selected,
      max_wire_bytes,
      max_nodes,
      max_depth,
      Int::min(max_nodes, 4096),
    ) {
    Ok(value) => value
    Err(issue) => return Err(PolicyClosure(issue))
  }
  guard !bodies.is_empty() && selected.cid == bodies[0].1 else {
    return Err(Policy(ClientCompiledRunIssue::InvalidResultPolicy))
  }
  let policy = match
    @publication.admit_catalog_effect_dependency_body(
      bodies[0].0,
      bodies[0].2,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(_) => return Err(Policy(ClientCompiledRunIssue::InvalidResultPolicy))
  }
  if @publication.captured_effect_dependency_body_cid(policy) != bodies[0].1 {
    return Err(Policy(ClientCompiledRunIssue::InvalidResultPolicy))
  }
  issue_client_serialization_plan_graph_with_policy(
    owner,
    task,
    step,
    policy,
    max_rows,
    max_bytes,
    max_preparation_work,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    include_results~,
  )
}

///|
/// A complete keyed selection is additional Source inventory, not permission
/// to discharge that Source with the Direct prefix's observation. Execution
/// must supply the original sealed lookup alongside the live Direct capture.
fn client_serialization_source_inventory_supported(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  max_work : Int,
) -> Bool {
  if client_single_direct_observation_covers_sources(owner) {
    return true
  }
  guard select_client_single_keyed_acquisition(owner) is Ok(Some(keyed)) else {
    return false
  }
  client_keyed_acquisition_reaches_serialization(
    owner, keyed, task, step, max_work~,
  )
}

///|
/// Read correspondence in the original checked graph. A split JOIN and its
/// downstream Serialize need not share a physical task ordinal. Follow their
/// actual single-input producer edges under the same nominal lowered owner;
/// equal coordinates, contracts or source bytes do not supply this relation.
/// This query issues no Source observation, permission, capacity or completion.
pub fn client_keyed_acquisition_reaches_serialization(
  prepared : PreparedClientProgram,
  keyed : ClientKeyedAcquisition,
  task : Int,
  step : Int,
  max_work? : Int = 1000000,
) -> Bool {
  let graph = prepared.graph
  guard max_work > 0 &&
    keyed.program is KeyedPure(original) &&
    physical_equal(original, prepared) &&
    client_keyed_acquisition_coordinates(keyed)
    is Some((stage, keyed_task, join)) &&
    join < step &&
    @strategy.graph_stage_operation_task(graph, stage, step) == Some(task) &&
    @strategy.graph_task_owner(graph, task) is Some(owner) &&
    physical_equal(owner, keyed.owner) &&
    client_keyed_direct_acquisition_coordinates(keyed) is Some(_) else {
    return false
  }
  let mut current = task
  let mut remaining = max_work
  while current != keyed_task {
    if current <= keyed_task || remaining <= 0 ||
      @strategy.graph_task_input_count(graph, current) != Some(1) {
      return false
    }
    let mut predecessor = None
    for index in 0..<@strategy.graph_data_count(graph) {
      if remaining <= 0 {
        return false
      }
      remaining -= 1
      guard @strategy.graph_data_at(graph, index) is Some(edge) else {
        return false
      }
      if @strategy.data_edge_consumer(edge) == current {
        let producer = @strategy.data_edge_producer(edge)
        guard predecessor is None &&
          @strategy.data_edge_input(edge) == 0 &&
          producer >= keyed_task && producer < current &&
          @strategy.graph_task_owner(graph, producer) is Some(parent) &&
          physical_equal(parent, keyed.owner) &&
          client_task_edge_input(graph, edge) is Some(_) else {
          return false
        }
        predecessor = Some(producer)
      }
    }
    guard predecessor is Some(producer) else { return false }
    current = producer
  }
  true
}

///|
/// The direct capture may be the Content task's same-pipeline prefix, or its
/// one exact checked Stage producer. Other inputs need their own inventory;
/// neither equal schema nor an authored Stage name proves this coverage.
fn client_serialization_single_capture_shape(
  owner : PreparedClientProgram,
  task : Int,
) -> Bool {
  let graph = owner.graph
  if @strategy.graph_task_count(graph) == 1 && task == 0 {
    return true
  }
  if @strategy.graph_task_selected_step(graph, task) is Some(step) {
    // Split tasks still belong to the same original acquired Stage. The
    // ordinary graph verifies every exact operation edge and retains each
    // predecessor; source inventory is checked separately above.
    guard @strategy.graph_captured_prefix(graph) == 1 &&
      @strategy.graph_task_unit_index(graph, task) == Some(1) &&
      @strategy.graph_task_input_count(graph, task) == Some(1) else {
      return false
    }
    let mut inputs = 0
    for index in 0..<@strategy.graph_data_count(graph) {
      guard @strategy.graph_data_at(graph, index) is Some(edge) else {
        return false
      }
      if @strategy.data_edge_consumer(edge) == task {
        guard @strategy.data_edge_producer(edge) >= 0 &&
          @strategy.data_edge_producer(edge) < task &&
          @strategy.data_edge_operation_input(edge) == Some((step, 0)) else {
          return false
        }
        inputs += 1
      }
    }
    return inputs == 1
  }
  guard @strategy.graph_task_count(graph) >= 2 &&
    task == 1 &&
    @strategy.graph_captured_prefix(graph) == 1 &&
    @strategy.graph_task_input_count(graph, task) == Some(1) else {
    return false
  }
  let mut inputs = 0
  for index in 0..<@strategy.graph_data_count(graph) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return false
    }
    if @strategy.data_edge_consumer(edge) == task {
      if @strategy.data_edge_producer(edge) != 0 ||
        @strategy.data_edge_operation_input(edge) is Some(_) {
        return false
      }
      inputs += 1
    }
  }
  inputs == 1
}

///|
fn issue_client_serialization_plan_graph_with_policy(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  policy : @publication.CapturedEffectDependencyBody,
  max_rows : Int,
  max_bytes : Int,
  max_preparation_work : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  include_results? : Bool = true,
) -> Result[ClientSerializationPlanGraph, ClientSerializationPlanGraphIssue] {
  let barrier = match
    prepare_client_serialization(
      owner,
      task,
      step,
      max_work=max_preparation_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let preparation = @lower.bound_preparation(
    @lower.serialization_owner(barrier),
  )
  guard @lower.preparation_output_target(preparation)
    is Some(@pipeline.Step(terminal)) &&
    terminal >= step &&
    (!include_results || terminal == step) &&
    step > 0 else {
    return Err(UnsupportedGraph)
  }
  let selected = @strategy.graph_task_selected_step(owner.graph, task) ==
    Some(step)
  let input = if selected &&
    @pipeline.serialization_sort(@lower.serialization_checked(barrier)) is None {
    None
  } else {
    Some(
      match
        issue_prepared_client_serialization_prefix_fragment(
          owner, task, step, max_preparation_work, sequence_limits, max_wire_bytes,
          max_nodes, max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Input(issue))
      },
    )
  }
  guard @lower.node_at(preparation, step) is Some(node) &&
    client_task_carrier_contract(
      @lower.node_output_carrier(node),
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(("relation", output_contract_cid)) else {
    return Err(UnsupportedGraph)
  }
  let input_contract_cid = match input {
    Some(input) => input.output_contract_cid
    None => {
      guard @lower.node_input_target(node, 0) is Some(target) &&
        @lower.preparation_carrier_at(preparation, target) is Some(carrier) &&
        client_task_carrier_contract(
          carrier, max_wire_bytes, max_nodes, max_depth,
        )
        is Some(("relation", cid)) else {
        return Err(UnsupportedGraph)
      }
      cid
    }
  }
  let (row_guard, byte_guard) = @lower.serialization_author_guards(barrier)
  let rows = match row_guard {
    Some(value) if value < max_rows.to_int64() => value.to_int()
    _ => max_rows
  }
  let bytes = match byte_guard {
    Some(value) if value < max_bytes.to_int64() => value.to_int()
    _ => max_bytes
  }
  let barrier_id = "task_" + task.to_string() + "_serialize_" + step.to_string()
  let output_port = @lower.node_id(node)
  let policy_cid = @publication.captured_effect_dependency_body_cid(policy)
  try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "barrier_id")
    @encode.string_value(writer, barrier_id)
    @encode.key(writer, "effective_output_data_policy_cid")
    @encode.string_value(writer, policy_cid)
    @encode.key(writer, "input_data_policy_cids")
    @encode.begin_array(writer)
    @encode.string_value(writer, policy_cid)
    @encode.end_array(writer)
    @encode.key(writer, "input_ref")
    @encode.string_value(writer, "input_0")
    @encode.key(writer, "output_ref")
    @encode.string_value(writer, output_port)
    @encode.key(writer, "serialization")
    @encode.begin_object(writer)
    @encode.key(writer, "bounds")
    @encode.begin_object(writer)
    @encode.key(writer, "max_bytes")
    @encode.number_value(writer, bytes.to_double())
    @encode.key(writer, "max_rows")
    @encode.number_value(writer, rows.to_double())
    @encode.end_object(writer)
    @publication.emit_content_serialization_options(
      @pipeline.serialization_profile(@lower.serialization_checked(barrier)),
      writer,
    )
    @encode.key(writer, "preserve_order")
    @encode.bool_value(writer, true)
    @encode.end_object(writer)
    @encode.key(writer, "serialization_contract_cid")
    @encode.string_value(
      writer,
      @environment.compiler_content_serialization_contract_cid(),
    )
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-content-barrier/0.1")
    @encode.end_object(writer)
    guard parse_plan_identity_value(
        @encode.finish(writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(body) else {
      return Err(Encoding)
    }
    let barrier_cid = @canonical.cid_value(
      body, max_wire_bytes, max_nodes, max_depth,
    )
    guard @canonical.object_with_string_field(body, "barrier_cid", barrier_cid)
      is Some(body) else {
      return Err(Encoding)
    }
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "barrier")
    @canonical.emit_value(body, writer)
    @encode.key(writer, "barrier_contract_cid")
    @encode.string_value(
      writer,
      @environment.compiler_content_barrier_contract_cid(),
    )
    @encode.key(writer, "input_contracts")
    @encode.begin_object(writer)
    @encode.key(writer, "input_0")
    @encode.string_value(writer, input_contract_cid)
    @encode.end_object(writer)
    @encode.key(writer, "input_refs")
    @encode.begin_array(writer)
    @encode.string_value(writer, "input_0")
    @encode.end_array(writer)
    @encode.key(writer, "kind")
    @encode.string_value(writer, "content_barrier")
    @encode.key(writer, "node_id")
    @encode.string_value(writer, barrier_id)
    @encode.key(writer, "output_contracts")
    @encode.begin_object(writer)
    @encode.key(writer, output_port)
    @encode.string_value(writer, output_contract_cid)
    @encode.end_object(writer)
    @encode.key(writer, "output_ref")
    @encode.string_value(writer, output_port)
    @encode.key(writer, "profile_id")
    @encode.string_value(writer, "actql-content/0.1")
    @encode.end_object(writer)
    let wire = @encode.finish(writer)
    guard parse_plan_identity_value(wire, max_wire_bytes, max_nodes, max_depth)
      is Some(content_node) else {
      return Err(Encoding)
    }
    let output : ClientTaskFragmentNode = {
      wire,
      node_id: barrier_id,
      output_port,
      logical_cid: barrier_cid,
      output_contract_cid,
      output_carrier: "relation",
    }
    let nodes = []
    let edges : Array[@canonical.CanonicalValue] = []
    if input is Some(input) {
      guard parse_plan_identity_value(
          input.wire,
          max_wire_bytes,
          max_nodes,
          max_depth,
        )
        is Some(input_node) else {
        return Err(Encoding)
      }
      nodes.push(input_node)
      let edge = "{\"carrier\":\"relation\",\"contract_cid\":\"" +
        input.output_contract_cid +
        "\",\"from\":{\"node_id\":\"" +
        input.node_id +
        "\",\"port\":\"" +
        input.output_port +
        "\"},\"to\":{\"node_id\":\"" +
        barrier_id +
        "\",\"port\":\"input_0\"}}"
      guard parse_plan_identity_value(
          edge, max_wire_bytes, max_nodes, max_depth,
        )
        is Some(edge) else {
        return Err(Encoding)
      }
      edges.push(edge)
    }
    nodes.push(content_node)
    let roots : Array[@canonical.CanonicalValue] = []
    let transformations : Array[ClientResultTransformation] = []
    for
      result in 0..<(if include_results {
        @strategy.graph_result_count(owner.graph)
      } else {
        0
      }) {
      guard @strategy.graph_result_task(owner.graph, result) == Some(task) else {
        return Err(UnsupportedGraph)
      }
      let parts = match
        issue_client_result_plan_parts(
          owner,
          result,
          barrier_id,
          output_port,
          output_contract_cid,
          max_wire_bytes,
          max_nodes,
          max_depth,
          serialization_output=Some(barrier),
        ) {
        Ok(value) => value
        Err(issue) => return Err(Root(issue))
      }
      if parts.transformation is Some((node, edge)) {
        nodes.push(node)
        edges.push(edge)
      }
      if parts.selection is Some(selection) {
        transformations.push(selection)
      }
      roots.push(parts.root)
    }
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "data_edges")
    client_plan_emit_array(writer, edges)
    @encode.key(writer, "nodes")
    client_plan_emit_array(writer, nodes)
    @encode.key(writer, "root_refs")
    client_plan_emit_array(writer, roots)
    @encode.end_object(writer)
    Ok({
      owner,
      task,
      step,
      barrier,
      input: input.unwrap_or(output),
      output,
      graph: { wire: @encode.finish(writer), transformations, },
      policy,
      max_rows: rows,
      max_bytes: bytes,
    })
  } catch {
    _ => Err(Encoding)
  }
}
