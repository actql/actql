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
  // Keep the issuer's immutable component parts for the same Request compiler.
  // They are not reconstructed from saved wire or a copied Graph holder.
  priv original_graph : ClientTaskPlanGraph
  priv direct_occurrences : ClientDirectAcquisitionOccurrences?
  priv graph_nodes : Array[@canonical.CanonicalValue]
  priv graph_edges : Array[@canonical.CanonicalValue]
  priv graph_roots : Array[@canonical.CanonicalValue]
  priv graph_wire_bytes : Int
  priv graph_wire_nodes : Int
  priv graph_wire_depth : Int
}

///|
// The same immutable original read used by the Model component. This is DATA
// for compiler construction, not current authority or physical backing. The
// constructor caller retains the complete component before using these parts.
fn client_serialization_graph_original_parts(
  value : ClientSerializationPlanGraph,
  owner : PreparedClientProgram,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> (
  Array[@canonical.CanonicalValue],
  Array[@canonical.CanonicalValue],
  Array[@canonical.CanonicalValue],
)? {
  if !physical_equal(value.owner, owner) ||
    !physical_equal(value.graph, value.original_graph) ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 ||
    value.graph_wire_bytes > max_wire_bytes ||
    value.graph_wire_nodes > max_nodes ||
    value.graph_wire_depth > max_depth {
    return None
  }
  Some((value.graph_nodes, value.graph_edges, value.graph_roots))
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
/// Borrow the ordinary Direct inventory proved by this exact component. No
/// capture, read grant or completion is issued by this accessor.
pub fn client_serialization_plan_direct_occurrences(
  component : ClientSerializationPlanGraph,
  prepared : PreparedClientProgram,
) -> ClientDirectAcquisitionOccurrences? {
  guard physical_equal(component.owner, prepared) &&
    physical_equal(component.graph, component.original_graph) else {
    return None
  }
  component.direct_occurrences
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
    (include_results && @strategy.graph_program_has_effects(owner.graph)) {
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
    owner,
    task,
    step,
    max_rows,
    max_bytes,
    max_preparation_work,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    false,
    effect_component=@strategy.graph_program_has_effects(owner.graph),
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
  let single = prepared_client_acquisition_count(owner) == 1 &&
    client_serialization_single_capture_shape(
      owner,
      task,
      max_work=max_preparation_work,
    ) &&
    client_serialization_source_inventory_supported(
      owner, task, step, max_preparation_work,
    )
  let effects = @strategy.graph_program_has_effects(owner.graph)
  if @strategy.graph_source_free_inputs_complete(owner.graph) ||
    (effects && (!effect_component || !single)) {
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
    @checked.Encoding(issue) =>
      return Err(PolicyClosure(@checked.Encoding(issue)))
    issue => return Err(SourcePolicy(issue))
  }
  guard selected is Some(selected) else {
    return Err(PolicyClosure(@checked.MissingDependency))
  }
  let direct_occurrences = if effects {
    None
  } else {
    client_serialization_direct_source_coverage(
      owner, task, unit, selected, max_preparation_work,
    )
  }
  if !single && direct_occurrences is None {
    return Err(UnsupportedGraph)
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
    direct_occurrences~,
  )
}

///|
/// The checked policy walks the actual Serialize input through producer
/// occurrences. Require every original Direct input on the same checked
/// Stage, not merely a matching Source CID or count. Multiple Whole inputs
/// may share one physical Compute task. For independent earlier Stages,
/// require each exact checked Result port and physical edge; runtime still
/// needs those producer completions, not the underlying Source rows.
fn client_serialization_direct_source_coverage(
  owner : PreparedClientProgram,
  task : Int,
  unit : Int,
  policy : @checked.PublicationSourcePolicy,
  max_work : Int,
) -> ClientDirectAcquisitionOccurrences? {
  let checks = @checked.source_execution_count(
    @strategy.graph_program(owner.graph),
  )
  let count = @checked.publication_policy_source_count(policy)
  guard count > 0 &&
    max_work > 0 &&
    checks <= max_work &&
    count <= (max_work - checks) / 3 &&
    @checked.publication_policy_model_step_count(policy) == 0 &&
    @checked.publication_policy_generator_count(policy) == 0 &&
    @checked.publication_policy_local_check_count(policy) == 0 &&
    client_direct_observations_cover_sources(owner, count) else {
    return None
  }
  // Split the bounded structural selection from the Whole route check.
  let remaining = max_work - checks - 3 * count
  let selector_work = remaining / 2
  let mut route_work = remaining - selector_work
  guard select_client_direct_acquisition_occurrences(owner, selector_work)
    is Ok(occurrences) &&
    client_direct_acquisition_occurrence_count(occurrences) == count else {
    return None
  }
  let inputs : Map[(Int, Int), @checked.SourceExecution] = Map([])
  let mut source_policy_unknown = false
  for index in 0..<count {
    guard @checked.publication_policy_source_at(policy, index) is Some(check) &&
      @checked.source_execution_kind(check) is @checked.CarrierResponse else {
      return None
    }
    let subject = @checked.source_execution_subject(check)
    guard subject.request is @acquisition.Direct(_, _) &&
      subject.direct_policy is Some(direct_policy) &&
      !inputs.contains((subject.stage, subject.input)) else {
      return None
    }
    inputs.set((subject.stage, subject.input), check)
    source_policy_unknown = source_policy_unknown ||
      direct_policy.unknown_provenance
  }
  // An exact Direct read may permanently have unclassified request values.
  // Preserve its original unknown policy and CID; capture coverage does not
  // furnish a classification, declassification, or an egress grant.
  guard !policy.unknown_provenance || source_policy_unknown else { return None }
  let mut same_stage = 0
  for index in 0..<count {
    guard client_direct_acquisition_occurrence_at(occurrences, index)
      is Some((stage, input, _)) &&
      inputs.get((stage, input)) is Some(original) &&
      physical_equal(original, occurrences.checks[index]) else {
      return None
    }
    let subject = @checked.source_execution_subject(original)
    guard @context.program_identity_stage_requests(subject.owner, stage)
      is Some(requests) &&
      @acquisition.select_source_acquisition_route(requests, input, route_work)
      is Ok(@acquisition.WholeInputRoute(acquisition)) else {
      return None
    }
    route_work -= @acquisition.source_acquisition_work(acquisition)
    if stage == unit {
      same_stage += 1
    }
  }
  if same_stage == count {
    guard @checked.publication_policy_import_count(policy) == 0 else {
      return None
    }
  } else if same_stage != 0 ||
    !client_serialization_direct_source_imports(
      owner, task, policy, occurrences, route_work,
    ) {
    return None
  }
  Some(occurrences)
}

///|
/// The existing bounded Direct-prefix graph may feed one Content computation
/// through one or two independently checked Stage Result ports.
fn client_serialization_direct_source_imports(
  owner : PreparedClientProgram,
  task : Int,
  policy : @checked.PublicationSourcePolicy,
  occurrences : ClientDirectAcquisitionOccurrences,
  max_work : Int,
) -> Bool {
  let graph = owner.graph
  let count = client_direct_acquisition_occurrence_count(occurrences)
  let edges = @strategy.graph_data_count(graph)
  guard count > 0 &&
    count <= 2 &&
    task == count &&
    @strategy.graph_captured_prefix(graph) == count &&
    @strategy.graph_task_input_count(graph, task) == Some(count) &&
    @checked.publication_policy_import_count(policy) == count &&
    count <= max_work &&
    edges <= (max_work - count) / (1 + count) else {
    return false
  }
  let used = Array::make(count, false)
  for index in 0..<edges {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return false
    }
    if @strategy.data_edge_consumer(edge) != task {
      continue
    }
    let input = @strategy.data_edge_input(edge)
    let producer = @strategy.data_edge_producer(edge)
    guard input >= 0 &&
      input < count &&
      producer >= 0 &&
      producer < count &&
      !used[producer] &&
      @strategy.data_edge_operation_input(edge) is None &&
      client_task_edge_input(graph, edge) is Some(_) &&
      client_direct_acquisition_occurrence_at(occurrences, producer)
      is Some((stage, _, original_task)) &&
      producer == original_task else {
      return false
    }
    let mut has_exact_import = false
    for import_index in 0..<count {
      let imported = @checked.publication_policy_import_at(policy, import_index).unwrap()
      if imported.input != input {
        continue
      }
      let resolution = @context.publication_row_limit_result(
        @checked.publication_selection(imported.publication),
      )
      let target = @results.target(@results.port_result(resolution.port))
      guard !has_exact_import &&
        resolution.stage == stage &&
        @strategy.data_edge_target(edge) == target &&
        @strategy.graph_task_unit_index(graph, producer) == Some(stage) &&
        client_task_output_target(graph, producer) == Some(target) &&
        @checked.publication_source_policy(imported.publication) is Some(parent) &&
        @checked.publication_policy_source_count(parent) == 1 &&
        @checked.publication_policy_model_step_count(parent) == 0 &&
        @checked.publication_policy_generator_count(parent) == 0 &&
        @checked.publication_policy_local_check_count(parent) == 0 &&
        @checked.publication_policy_source_at(parent, 0) is Some(source) &&
        physical_equal(source, occurrences.checks[producer]) else {
        return false
      }
      has_exact_import = true
    }
    if !has_exact_import {
      return false
    }
    used[producer] = true
  }
  used.iter().all(present => present)
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
    owner,
    keyed,
    task,
    step,
    max_work~,
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
  client_serialization_original_task_path(
    graph,
    keyed_task,
    task,
    max_work,
    Some(keyed.owner),
  )
}

///|
/// The checked edge ports prove ancestry, including across a real Stage input.
/// A keyed suffix additionally retains one exact nominal lowered owner. The
/// decreasing task order and shared work cursor bound the scan without a new
/// worklist, copied graph or caller-supplied ancestry assertion.
fn client_serialization_original_task_path(
  graph : @strategy.CheckedDAG,
  producer : Int,
  consumer : Int,
  max_work : Int,
  original_owner : @lower.BoundPrepared?,
) -> Bool {
  if producer < 0 ||
    consumer < producer ||
    consumer >= @strategy.graph_task_count(graph) ||
    max_work <= 0 {
    return false
  }
  let mut current = consumer
  let mut remaining = max_work
  while current != producer {
    if current <= producer ||
      remaining <= 0 ||
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
        let parent = @strategy.data_edge_producer(edge)
        guard predecessor is None &&
          @strategy.data_edge_input(edge) == 0 &&
          parent >= producer &&
          parent < current &&
          client_task_edge_input(graph, edge) is Some(_) else {
          return false
        }
        if original_owner is Some(original) {
          guard @strategy.graph_task_owner(graph, current) is Some(child) &&
            physical_equal(child, original) &&
            @strategy.graph_task_owner(graph, parent) is Some(owner) &&
            physical_equal(owner, original) else {
            return false
          }
        }
        predecessor = Some(parent)
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
  max_work? : Int = 1000000,
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
      @strategy.graph_task_input_count(graph, task) == Some(1) else {
      return false
    }
    return match select_client_single_keyed_acquisition(owner) {
      Ok(Some(keyed)) =>
        client_keyed_acquisition_reaches_serialization(
          owner,
          keyed,
          task,
          step,
          max_work~,
        )
      Ok(None) =>
        client_serialization_original_task_path(graph, 0, task, max_work, None)
      Err(_) => false
    }
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
  direct_occurrences? : ClientDirectAcquisitionOccurrences? = None,
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
    emit_client_serialization_barrier_body(
      writer,
      barrier,
      barrier_id,
      output_port,
      policy_cid,
      rows,
      bytes,
      None,
      (cid : String, out) => @encode.string_value(out, cid),
    )
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
    emit_client_serialization_node_body(
      writer,
      body,
      @canonical.emit_value,
      barrier_id,
      output_port,
      input_contract_cid,
      output_contract_cid,
      (cid, out) => @encode.string_value(out, cid),
    )
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
    let result_plans : Array[ClientResultPlanIdentity] = []
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
      result_plans.push(parts.plan)
    }
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "data_edges")
    client_plan_emit_array(writer, edges, @canonical.emit_value)
    @encode.key(writer, "nodes")
    client_plan_emit_array(writer, nodes, @canonical.emit_value)
    @encode.key(writer, "root_refs")
    client_plan_emit_array(writer, roots, @canonical.emit_value)
    @encode.end_object(writer)
    let (wire, graph_wire_bytes, graph_wire_nodes, graph_wire_depth) = @encode.finish_text_usage(
      writer,
    )
    let original_graph : ClientTaskPlanGraph = {
      wire,
      transformations,
      result_plans,
      standard_progress_keys: None,
    }
    Ok({
      owner,
      task,
      step,
      barrier,
      input: input.unwrap_or(output),
      output,
      graph: original_graph,
      policy,
      max_rows: rows,
      max_bytes: bytes,
      original_graph,
      direct_occurrences,
      graph_nodes: nodes,
      graph_edges: edges,
      graph_roots: roots,
      graph_wire_bytes,
      graph_wire_nodes,
      graph_wire_depth,
    })
  } catch {
    _ => Err(Encoding)
  }
}

///|
// Shared original Content emitters. Measurement substitutes only future CID
// encoded extents; real issuers retain all original policy/hash/port checks.
fn[C] emit_client_serialization_barrier_body(
  writer : @encode.Writer,
  barrier : @lower.PreparedSerialization,
  barrier_id : String,
  output_port : String,
  policy_cid : C,
  rows : Int,
  bytes : Int,
  cid : C?,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  if cid is Some(cid) {
    @encode.key(writer, "barrier_cid")
    emit_cid(cid, writer)
  }
  @encode.key(writer, "barrier_id")
  @encode.string_value(writer, barrier_id)
  @encode.key(writer, "effective_output_data_policy_cid")
  emit_cid(policy_cid, writer)
  @encode.key(writer, "input_data_policy_cids")
  @encode.begin_array(writer)
  emit_cid(policy_cid, writer)
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
}

///|
fn[B, C] emit_client_serialization_node_body(
  writer : @encode.Writer,
  body : B,
  emit_body : (B, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  barrier_id : String,
  output_port : String,
  input_contract_cid : C,
  output_contract_cid : C,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "barrier")
  emit_body(body, writer)
  @encode.key(writer, "barrier_contract_cid")
  @encode.string_value(
    writer,
    @environment.compiler_content_barrier_contract_cid(),
  )
  @encode.key(writer, "input_contracts")
  @encode.begin_object(writer)
  @encode.key(writer, "input_0")
  emit_cid(input_contract_cid, writer)
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
  emit_cid(output_contract_cid, writer)
  @encode.end_object(writer)
  @encode.key(writer, "output_ref")
  @encode.string_value(writer, output_port)
  @encode.key(writer, "profile_id")
  @encode.string_value(writer, "actql-content/0.1")
  @encode.end_object(writer)
}
