///|
/// Select the supported terminal acquisition from the actual checked graph.
/// Adapters must not rediscover a source ordinal by inspecting Program JSON.
pub fn prepared_client_terminal_infer_step(
  value : PreparedClientProgram,
) -> Int? {
  if prepared_client_acquired_infer_step(value) is Some(step) &&
    client_acquired_infer_prefix_owner(value, 0, step) is Some(owner) &&
    @lower.preparation_output_target(@lower.bound_preparation(owner)) ==
    Some(@pipeline.Step(step)) {
    return Some(step)
  }
  guard @strategy.graph_task_count(value.graph) == 1 &&
    @strategy.graph_task_target(value.graph, 0) is Some(@pipeline.Step(step)) &&
    client_infer_prefix_owner(value, 0, step) is Some(_) else {
    return None
  }
  Some(step)
}

///|
/// Select one acquisition in a checked task, retaining any following Compute
/// occurrences. Their provider and input admission remain separate checks.
pub fn prepared_client_infer_step(value : PreparedClientProgram) -> Int? {
  if prepared_client_acquired_infer_step(value) is Some(step) {
    return Some(step)
  }
  guard @strategy.graph_task_count(value.graph) == 1 &&
    @strategy.graph_task_target(value.graph, 0) is Some(@pipeline.Step(last)) &&
    @strategy.graph_task_owner(value.graph, 0) is Some(owner) else {
    return None
  }
  let mut selected = None
  for step in 0..<(last + 1) {
    guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) else {
      return None
    }
    if @lower.payload(node) is @lower.Infer(_) {
      if selected is Some(_) ||
        client_infer_prefix_owner(value, 0, step) is None {
        return None
      }
      selected = Some(step)
    }
  }
  selected
}

///|
/// Installation selects by the checked task identity, not Program JSON or
/// an adapter's source ordinal. This is metadata, never dispatch authority.
pub fn prepared_client_infer_model_task_cid(
  value : PreparedClientProgram,
  step : Int,
) -> String? {
  guard client_infer_metadata_owner(value, 0, step) is Some(owner) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) else {
    return None
  }
  Some(@environment.model_task_identity(@infer.model_task(infer)).2)
}

///|
/// Metadata selection recognizes both admitted input shapes. Execution,
/// identity and egress must still choose their own source-specific admission.
fn client_infer_metadata_owner(
  value : PreparedClientProgram,
  task : Int,
  step : Int,
) -> @lower.BoundPrepared? {
  match client_infer_prefix_owner(value, task, step) {
    Some(owner) => Some(owner)
    None => client_acquired_infer_prefix_owner(value, task, step)
  }
}

///|
/// Select the checked Relation owner consumed by the initial source-free
/// Infer path. Both compilation and execution use this exact selection;
/// equal source text, row values, or model identities cannot replace it.
/// Other task/input shapes need their own admitted acquisition connection.
pub fn client_infer_prefix_owner(
  value : PreparedClientProgram,
  task : Int,
  infer_step : Int,
) -> @lower.BoundPrepared? {
  client_infer_prefix_owner_for_input(value, task, infer_step, false)
}

///|
/// Select the same checked prefix only when its single external input is the
/// existing admitted Query acquisition. This is not the source-free scope:
/// callers still need captured input, source evidence and egress admission.
pub fn client_acquired_infer_prefix_owner(
  value : PreparedClientProgram,
  task : Int,
  infer_step : Int,
) -> @lower.BoundPrepared? {
  guard prepare_client_query_acquisition(value, task, 0) is Ok(_) else {
    return None
  }
  client_infer_prefix_owner_for_input(value, task, infer_step, true)
}

///|
pub fn prepared_client_acquired_infer_step(
  value : PreparedClientProgram,
) -> Int? {
  guard @strategy.graph_task_count(value.graph) == 1 &&
    @strategy.graph_task_owner(value.graph, 0) is Some(owner) &&
    @lower.preparation_output_target(@lower.bound_preparation(owner))
    is Some(@pipeline.Step(last)) else {
    return None
  }
  let mut selected = None
  for step in 0..<(last + 1) {
    guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) else {
      return None
    }
    if @lower.payload(node) is @lower.Infer(_) {
      if selected is Some(_) ||
        client_acquired_infer_prefix_owner(value, 0, step) is None {
        return None
      }
      selected = Some(step)
    }
  }
  selected
}

///|
fn client_infer_prefix_owner_for_input(
  value : PreparedClientProgram,
  task : Int,
  infer_step : Int,
  acquired : Bool,
) -> @lower.BoundPrepared? {
  guard task == 0 &&
    @strategy.graph_task_count(value.graph) == 1 &&
    @strategy.graph_task_selected_step(value.graph, task) is None &&
    @strategy.graph_task_prefix_end(value.graph, task) is None &&
    infer_step > 0 &&
    @strategy.graph_task_owner(value.graph, task) is Some(owner) &&
    @lower.preparation_input_count(@lower.bound_preparation(owner)) ==
    (if acquired { 1 } else { 0 }) &&
    @lower.node_at(@lower.bound_preparation(owner), infer_step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(_) &&
    @lower.node_input_target(node, 0) == Some(@pipeline.Step(infer_step - 1)) &&
    @lower.preparation_carrier_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(infer_step - 1),
    )
    is Some(input) &&
    @carrier.kind(input) == RelationKind else {
    return None
  }
  Some(owner)
}

///|
pub(all) enum ClientInferHostCapacityIssue {
  UnsupportedProgram
  Capacity(@environment.CapacityIssue)
  MissingItemCeiling
  MissingRequestCeiling
}

///|
pub(all) enum ClientInferItemLimitIssue {
  UnsupportedProgram
  Preparation(@checked.UnitBuildFailure)
}

///|
/// Prepare capacity evidence from the same checked Program as the Relation
/// prefix. This runs during compilation, not inside bounded execution start.
/// It does not replace the barrier's physical envelope or egress admission.
pub fn prepare_client_infer_item_limit(
  value : PreparedClientProgram,
  step : Int,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@checked.InferItemLimit, ClientInferItemLimitIssue] {
  if client_infer_metadata_owner(value, 0, step) is None {
    return Err(UnsupportedProgram)
  }
  Ok(
    @checked.prepare_infer_item_limit(
      @strategy.graph_program(value.graph),
      0,
      step,
      max_work,
      max_bytes,
      max_nodes,
      max_depth,
    ),
  ) catch {
    issue => Err(Preparation(issue))
  }
}

///|
/// Read the actual checked Host policy, never an adapter default. This is one
/// physical admission candidate, not the complete inference Plan envelope.
pub fn prepared_client_infer_host_item_ceiling(
  value : PreparedClientProgram,
  step : Int,
) -> Result[Int64, ClientInferHostCapacityIssue] {
  prepared_client_infer_host_ceiling(
    value,
    step,
    "max_infer_items",
    MissingItemCeiling,
  )
}

///|
/// Read the checked per-item request ceiling for bounded physical preflight.
pub fn prepared_client_infer_host_request_ceiling(
  value : PreparedClientProgram,
  step : Int,
) -> Result[Int64, ClientInferHostCapacityIssue] {
  prepared_client_infer_host_ceiling(
    value,
    step,
    "max_model_request_bytes_per_item",
    MissingRequestCeiling,
  )
}

///|
fn prepared_client_infer_host_ceiling(
  value : PreparedClientProgram,
  step : Int,
  field : String,
  missing : ClientInferHostCapacityIssue,
) -> Result[Int64, ClientInferHostCapacityIssue] {
  if client_infer_metadata_owner(value, 0, step) is None {
    return Err(UnsupportedProgram)
  }
  read_client_infer_host_ceiling(value, field, missing)
}

///|
fn read_client_infer_host_ceiling(
  value : PreparedClientProgram,
  field : String,
  missing : ClientInferHostCapacityIssue,
) -> Result[Int64, ClientInferHostCapacityIssue] {
  let capacity = match
    @environment.read_capacity(
      @checked.checked_environment(@strategy.graph_program(value.graph)),
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  guard @capacity_policy.ceiling(@environment.capacity_policy(capacity), field)
    is Some(ceiling) else {
    return Err(missing)
  }
  Ok(@capacity_policy.ceiling_value(ceiling))
}
