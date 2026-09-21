///|
priv enum GraftPhase {
  CopyNodes
  CopyEdges
  Finish
}

///|
priv enum StructuralMode {
  Add
  Subtract
} derive(Eq)

///|
priv enum GraftSource {
  StorageSource(@graph.ProducerRead, @storage.Storage)
  ViewSource(@lifecycle.ProducerView)
}

///|
priv enum MergeValue[T] {
  MergeReady(T)
  MergePending
  MergeStopped(@bounded.StopReason)
  MergeFailed(GraftIssue)
}

///|
fn[T] merge_result(value : Result[T, GraftIssue]) -> MergeValue[T] {
  match value {
    Ok(value) => MergeReady(value)
    Err(issue) => MergeFailed(issue)
  }
}

///|
priv struct StructuralMergePlan {
  graph : @carrier.Graph
  nodes : Array[@graph_type.FieldStrategy?]
  edges : Array[@graph_type.FieldStrategy?]
}

///|
priv struct GraftState {
  set_control : @bounded.Control
  sources : Array[GraftSource]
  mode : StructuralMode
  merge_shared : Bool
  retain_shared_nodes : Bool
  retain_shared_edges : Bool
  plans : Array[StructuralMergePlan]
  value_limits : @value.Limits
  mut output : @graph.OutputBuilder?
  node_fields : Int
  edge_fields : Int
  mut input_index : Int
  mut phase : GraftPhase
  mut record_index : Int
  max_workspace_slots : Int
  mut set_execution : @value_set.Execution?
  mut set_token : Int
  mut set_cached_slots : Int
  set_results : Map[Int, @value.CheckedValue]
}

///|
struct GraftExecution {
  session : @bounded.Session[GraftState, @graph.Completed, GraftIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum GraftPoll {
  GraftContinue(progress~ : Int64, work~ : Int64)
  GraftComplete(@graph.Completed, progress~ : Int64, work~ : Int64)
  GraftFailed(GraftIssue, progress~ : Int64, work~ : Int64)
  GraftStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum GraftIssue {
  InvalidGraftKernel
  InvalidGraftLimits
  GraftInputUnavailable
  GraftPropertyConflict
  GraftPropertyValue
  GraftWorkspaceLimit
  GraftValue(@value.CompleteEqualityIssue)
  GraftSet(@value_set.Issue)
  GraftOutput(@graph.Issue)
  GraftExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn valid_graft_step(
  sequence : @lower.PreparedSequence,
  step : Int,
  input_count : Int,
) -> Bool {
  guard input_count >= 2 &&
    @lower.node_at(
      @lower.bound_preparation(@lower.sequence_owner(sequence)),
      step,
    )
    is Some(node) else {
    return false
  }
  match @lower.sequence_step(sequence, step) {
    Some(@lower.GraphStructuralStep(_)) =>
      input_count == 2 &&
      (
        @lower.operation(node) == "SGA.graft" ||
        @lower.operation(node) == "SGA.union_structural" ||
        @lower.operation(node) == "SGA.diff_structural"
      )
    Some(@lower.GraphUnionStep(union)) =>
      @lower.operation(node) == "SGA.union_structural" &&
      @lower.graph_union_input_count(union) == input_count
    _ => false
  }
}

///|
fn structural_mode(
  sequence : @lower.PreparedSequence,
  step : Int,
) -> StructuralMode? {
  guard @lower.node_at(
      @lower.bound_preparation(@lower.sequence_owner(sequence)),
      step,
    )
    is Some(node) else {
    return None
  }
  if @lower.operation(node) == "SGA.diff_structural" {
    Some(Subtract)
  } else {
    Some(Add)
  }
}

///|
fn structural_merges_shared(
  sequence : @lower.PreparedSequence,
  step : Int,
) -> Bool {
  match
    @lower.node_at(
      @lower.bound_preparation(@lower.sequence_owner(sequence)),
      step,
    ) {
    Some(node) => @lower.operation(node) != "SGA.graft"
    None => false
  }
}

///|
fn executable_merge_plans(plans : Array[StructuralMergePlan]) -> Bool {
  ignore(plans)
  true
}

///|
fn checked_noninterruptible_add(current : Int, count : Int, unit : Int) -> Int? {
  if current < 0 ||
    count < 0 ||
    unit < 0 ||
    (count > 0 && unit > (2147483647 - current) / count) {
    None
  } else {
    Some(current + count * unit)
  }
}

///|
fn graft_noninterruptible_value_nodes(
  plans : Array[StructuralMergePlan],
  limits : @storage.Limits,
) -> Int? {
  if limits.max_value_nodes < 1 || limits.max_value_nodes > (2147483647 - 8) / 8 {
    return None
  }
  let ordinary = limits.max_value_nodes * 4 + 1
  let set = limits.max_value_nodes * 8 + 8
  let mut node_bound = 0
  let mut edge_bound = 0
  for plan in plans {
    for strategy in plan.nodes {
      let unit = match strategy {
        Some(@graph_type.SetUnion | @graph_type.SetDifference) => set
        _ => ordinary
      }
      guard checked_noninterruptible_add(node_bound, 1, unit) is Some(next) else {
        return None
      }
      node_bound = next
    }
    for strategy in plan.edges {
      let unit = match strategy {
        Some(@graph_type.SetUnion | @graph_type.SetDifference) => set
        _ => ordinary
      }
      guard checked_noninterruptible_add(edge_bound, 1, unit) is Some(next) else {
        return None
      }
      edge_bound = next
    }
  }
  Some(Int::max(ordinary, Int::max(node_bound, edge_bound)))
}

///|
fn graft_noninterruptible_value_bytes(
  plans : Array[StructuralMergePlan],
  limits : @storage.Limits,
) -> Int? {
  guard limits.max_value_bytes >= 0 &&
    limits.max_value_bytes <= 2147483647 / 6 &&
    limits.max_value_nodes >= 0 &&
    limits.max_value_nodes <= (2147483647 - 128) / 96 else {
    return None
  }
  let text = limits.max_value_bytes * 6
  let structure = limits.max_value_nodes * 96 + 128
  if structure > 2147483647 - text {
    return None
  }
  let unit = text + structure
  let mut node_bound = 0
  let mut edge_bound = 0
  for plan in plans {
    guard checked_noninterruptible_add(node_bound, plan.nodes.length(), unit)
      is Some(next_nodes) &&
      checked_noninterruptible_add(edge_bound, plan.edges.length(), unit)
      is Some(next_edges) else {
      return None
    }
    node_bound = next_nodes
    edge_bound = next_edges
  }
  Some(Int::max(unit, Int::max(node_bound, edge_bound)))
}

///|
fn graft_source(state : GraftState) -> GraftSource? {
  state.sources.get(state.input_index)
}

///|
fn graft_inputs_available(state : GraftState) -> Bool {
  for source in state.sources {
    match source {
      StorageSource(read, source) =>
        if !@graph.producer_read_available(read) {
          return false
        } else {
          match @storage.carrier(source) {
            @carrier.GraphValue(_) => ()
            _ => return false
          }
        }
      ViewSource(source) =>
        if @lifecycle.producer_view_node_count(source) is None {
          return false
        }
    }
  }
  true
}

///|
fn strategy_field_index(fields : @carrier.Knowledge, name : String) -> Int? {
  for index in 0..<@carrier.field_count(fields) {
    guard @carrier.field_at(fields, index) is Some(field) else { return None }
    if @schema.reference_name(field.name) == name {
      return Some(index)
    }
  }
  None
}

///|
fn structural_strategy_fields(
  structural : @lower.PreparedGraphStructural,
  side : @schema.Side,
  graph : @carrier.Graph,
) -> Array[@graph_type.FieldStrategy?]? {
  let fields = if side == @schema.Left {
    @carrier.graph_node_properties(graph)
  } else {
    @carrier.graph_edge_properties(graph)
  }
  let strategies = Array::make(@carrier.field_count(fields), None)
  for index in 0..<@lower.graph_structural_strategy_count(structural, side) {
    guard @lower.graph_structural_strategy_name(structural, side, index)
      is Some(name) &&
      @lower.graph_structural_strategy_kind(structural, side, index)
      is Some(kind) &&
      strategy_field_index(fields, name) is Some(field) else {
      return None
    }
    strategies[field] = Some(kind)
  }
  Some(strategies)
}

///|
fn union_strategy_fields(
  union : @lower.PreparedGraphUnion,
  fold : Int,
  side : @schema.Side,
  graph : @carrier.Graph,
) -> Array[@graph_type.FieldStrategy?]? {
  let fields = if side == @schema.Left {
    @carrier.graph_node_properties(graph)
  } else {
    @carrier.graph_edge_properties(graph)
  }
  let strategies = Array::make(@carrier.field_count(fields), None)
  guard @lower.graph_union_fold_strategy_count(union, fold, side) is Some(count) else {
    return None
  }
  for index in 0..<count {
    guard @lower.graph_union_fold_strategy_name(union, fold, side, index)
      is Some(name) &&
      @lower.graph_union_fold_strategy_kind(union, fold, side, index)
      is Some(kind) &&
      strategy_field_index(fields, name) is Some(field) else {
      return None
    }
    strategies[field] = Some(kind)
  }
  Some(strategies)
}

///|
fn structural_merge_plans(
  sequence : @lower.PreparedSequence,
  step : Int,
) -> Array[StructuralMergePlan]? {
  match @lower.sequence_step(sequence, step) {
    Some(@lower.GraphStructuralStep(structural)) => {
      guard @lower.graph_structural_output(structural)
        is @carrier.GraphValue(graph) &&
        structural_strategy_fields(structural, @schema.Left, graph)
        is Some(nodes) &&
        structural_strategy_fields(structural, @schema.Right, graph)
        is Some(edges) else {
        return None
      }
      Some([{ graph, nodes, edges, }])
    }
    Some(@lower.GraphUnionStep(union)) => {
      let plans = []
      for fold in 0..<(@lower.graph_union_input_count(union) - 1) {
        guard @lower.graph_union_fold_output(union, fold)
          is Some(@carrier.GraphValue(graph)) &&
          union_strategy_fields(union, fold, @schema.Left, graph) is Some(nodes) &&
          union_strategy_fields(union, fold, @schema.Right, graph)
          is Some(edges) else {
          return None
        }
        plans.push({ graph, nodes, edges, })
      }
      Some(plans)
    }
    _ => Some([])
  }
}

///|
fn complete_property_equal(
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  limits : @value.Limits,
) -> Result[Bool, GraftIssue] {
  let equality = match @value.start_complete_equality(left, right, limits) {
    Ok(value) => value
    Err(issue) => return Err(GraftValue(issue))
  }
  let quantum = limits.max_nodes * 4 + 1
  while true {
    match @value.advance_complete_equality(equality, quantum) {
      @value.EqualityContinue(_) => ()
      @value.EqualityComplete(equal~, ..) => return Ok(equal)
      @value.EqualityFailed(issue, ..) => return Err(GraftValue(issue))
    }
  }
  Err(GraftPropertyValue)
}

///|
fn checked_property_for_contract(
  value : @value.CheckedValue,
  contract : @contract.Contract,
  limits : @value.Limits,
) -> Result[@value.CheckedValue, GraftIssue] {
  match @value.recheck_runtime_value(value.value, contract, limits) {
    Some(checked) => Ok(checked)
    None => Err(GraftPropertyValue)
  }
}

///|
fn merge_numeric_property(
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  strategy : @graph_type.FieldStrategy,
  contract : @contract.Contract,
  limits : @value.Limits,
) -> Result[@value.CheckedValue, GraftIssue] {
  guard left.value is @value.Number(a) && right.value is @value.Number(b) else {
    return Err(GraftPropertyValue)
  }
  let merged = match strategy {
    @graph_type.NumberSum => a + b
    @graph_type.NumberMean => (a + b) / 2.0
    @graph_type.NumberMin => Double::min(a, b)
    @graph_type.NumberMax => Double::max(a, b)
    _ => return Err(GraftPropertyValue)
  }
  guard @value.number_value(merged) is Some(value) else {
    return Err(GraftPropertyValue)
  }
  match @value.recheck_runtime_value(value, contract, limits) {
    Some(checked) => Ok(checked)
    None => Err(GraftPropertyValue)
  }
}

///|
fn merge_set_property(
  state : GraftState,
  token : Int,
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  strategy : @graph_type.FieldStrategy,
  contract : @contract.Contract,
) -> MergeValue[@value.CheckedValue] {
  if state.set_results.get(token) is Some(value) {
    return MergeReady(value)
  }
  if state.set_execution is None {
    let operation = if strategy == @graph_type.SetUnion {
      @value_set.Union
    } else if strategy == @graph_type.SetDifference {
      @value_set.Difference
    } else {
      return MergeFailed(GraftPropertyValue)
    }
    state.set_execution = match
      @value_set.start(
        state.set_control,
        operation,
        left,
        right,
        contract,
        state.value_limits,
        merge_workspace_slots(state),
      ) {
      Ok(execution) => Some(execution)
      Err(@value_set.WorkspaceLimit) => return MergeFailed(GraftWorkspaceLimit)
      Err(@value_set.InvalidSet) => return MergeFailed(GraftPropertyValue)
      Err(issue) => return MergeFailed(GraftSet(issue))
    }
    state.set_token = token
  }
  guard state.set_token == token && state.set_execution is Some(execution) else {
    return MergeFailed(InvalidGraftKernel)
  }
  match @value_set.advance(execution, 1) {
    Err(issue) => MergeFailed(GraftSet(issue))
    Ok(@value_set.Continue(_)) => MergePending
    Ok(@value_set.Complete(value, ..)) => {
      let slots = @value_set.workspace_slots(execution)
      if !@value_set.cleanup(execution).unwrap_or(false) {
        return MergeFailed(InvalidGraftKernel)
      }
      state.set_execution = None
      if slots > state.max_workspace_slots - state.set_cached_slots {
        return MergeFailed(GraftWorkspaceLimit)
      }
      state.set_cached_slots += slots
      state.set_results[token] = value
      MergePending
    }
    Ok(@value_set.Failed(issue, ..)) => {
      @value_set.cleanup(execution) |> ignore
      state.set_execution = None
      MergeFailed(GraftSet(issue))
    }
    Ok(@value_set.Stopped(reason, ..)) => {
      @value_set.cleanup(execution) |> ignore
      state.set_execution = None
      MergeStopped(reason)
    }
  }
}

///|
fn finish_merge_record(state : GraftState) -> Bool {
  if state.set_execution is Some(_) {
    return false
  }
  state.set_results.clear()
  state.set_token = -1
  state.set_cached_slots = 0
  true
}

///|
fn merge_property(
  state : GraftState,
  token : Int,
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  strategy : @graph_type.FieldStrategy?,
  contract : @contract.Contract,
  limits : @value.Limits,
) -> MergeValue[@value.CheckedValue] {
  match strategy {
    None | Some(@graph_type.ExactEqual) =>
      match complete_property_equal(left, right, limits) {
        Ok(true) =>
          match checked_property_for_contract(left, contract, limits) {
            Ok(value) => MergeReady(value)
            Err(issue) => MergeFailed(issue)
          }
        Ok(false) => MergeFailed(GraftPropertyConflict)
        Err(issue) => MergeFailed(issue)
      }
    Some(
      @graph_type.NumberSum
      | @graph_type.NumberMean
      | @graph_type.NumberMin
      | @graph_type.NumberMax
    ) =>
      match
        merge_numeric_property(left, right, strategy.unwrap(), contract, limits) {
        Ok(value) => MergeReady(value)
        Err(issue) => MergeFailed(issue)
      }
    Some(@graph_type.SetUnion | @graph_type.SetDifference) =>
      merge_set_property(state, token, left, right, strategy.unwrap(), contract)
  }
}

///|
fn rebind_properties(
  values : Array[@value.CheckedValue],
  fields : @carrier.Knowledge,
  limits : @value.Limits,
) -> Result[Array[@value.CheckedValue], GraftIssue] {
  if values.length() != @carrier.field_count(fields) {
    return Err(GraftInputUnavailable)
  }
  let out = []
  for index, value in values {
    guard @carrier.field_at(fields, index)
      is Some({ contract: Some(contract), .. }) else {
      return Err(InvalidGraftKernel)
    }
    match checked_property_for_contract(value, contract, limits) {
      Ok(checked) => out.push(checked)
      Err(issue) => return Err(issue)
    }
  }
  Ok(out)
}

///|
fn merge_properties(
  state : GraftState,
  tokens : Ref[Int],
  left : Array[@value.CheckedValue],
  right : Array[@value.CheckedValue],
  fields : @carrier.Knowledge,
  strategies : Array[@graph_type.FieldStrategy?],
  limits : @value.Limits,
) -> MergeValue[Array[@value.CheckedValue]] {
  if left.length() != right.length() ||
    left.length() != @carrier.field_count(fields) ||
    strategies.length() != left.length() {
    return MergeFailed(GraftInputUnavailable)
  }
  let out = []
  for index in 0..<left.length() {
    guard @carrier.field_at(fields, index)
      is Some({ contract: Some(contract), .. }) else {
      return MergeFailed(InvalidGraftKernel)
    }
    let token = tokens.val
    if token == 2147483647 {
      return MergeFailed(InvalidGraftLimits)
    }
    tokens.val += 1
    match
      merge_property(
        state,
        token,
        left[index],
        right[index],
        strategies[index],
        contract,
        limits,
      ) {
      MergeReady(checked) => out.push(checked)
      MergePending => return MergePending
      MergeStopped(reason) => return MergeStopped(reason)
      MergeFailed(issue) => return MergeFailed(issue)
    }
  }
  MergeReady(out)
}

///|
fn advance_graft_source(state : GraftState) -> Unit {
  state.input_index += 1
  state.phase = CopyNodes
  state.record_index = 0
  if state.input_index >= state.sources.length() {
    state.phase = Finish
  }
}

///|
fn merge_workspace_slots(state : GraftState) -> Int {
  match state.output {
    Some(output) =>
      state.max_workspace_slots -
      @graph.output_workspace_slots(output) -
      state.set_cached_slots
    None => 0
  }
}

///|
fn node_properties_at(
  source : GraftSource,
  index : Int,
  count : Int,
) -> Array[@value.CheckedValue]? {
  let values = []
  for field in 0..<count {
    let value = match source {
      StorageSource(_, source) => @storage.node_property(source, index, field)
      ViewSource(source) =>
        match @lifecycle.producer_view_node_property(source, index, field) {
          Ok(value) => Some(value)
          Err(_) => None
        }
    }
    guard value is Some(value) else { return None }
    values.push(value)
  }
  Some(values)
}

///|
fn edge_properties_at(
  source : GraftSource,
  index : Int,
  count : Int,
) -> Array[@value.CheckedValue]? {
  let values = []
  for field in 0..<count {
    let value = match source {
      StorageSource(_, source) => @storage.edge_property(source, index, field)
      ViewSource(source) =>
        match @lifecycle.producer_view_edge_property(source, index, field) {
          Ok(value) => Some(value)
          Err(_) => None
        }
    }
    guard value is Some(value) else { return None }
    values.push(value)
  }
  Some(values)
}

///|
fn source_node_identity(
  source : GraftSource,
  index : Int,
) -> @value.CheckedValue? {
  match source {
    StorageSource(_, source) => @storage.node_identity(source, index)
    ViewSource(source) =>
      match @lifecycle.producer_view_node_identity(source, index) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn source_node_index(
  source : GraftSource,
  identity : @value.CheckedValue,
) -> Result[Int?, GraftIssue] {
  match source {
    StorageSource(_, source) =>
      @storage.node_index(source, identity).map_err(_ => GraftInputUnavailable)
    ViewSource(source) =>
      @lifecycle.producer_view_node_index(source, identity).map_err(_ => {
        GraftInputUnavailable
      })
  }
}

///|
fn source_edge_identity(
  source : GraftSource,
  index : Int,
) -> (@value.CheckedValue, @value.CheckedValue, @value.CheckedValue?)? {
  let endpoints = match source {
    StorageSource(_, source) => @storage.edge_endpoints(source, index)
    ViewSource(source) =>
      match @lifecycle.producer_view_edge_endpoints(source, index) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
  guard endpoints is Some((source_node, target_node)) &&
    source_node_identity(source, source_node) is Some(source_id) &&
    source_node_identity(source, target_node) is Some(target_id) else {
    return None
  }
  let label = match source {
    StorageSource(_, source) => @storage.edge_label(source, index)
    ViewSource(source) =>
      match @lifecycle.producer_view_edge_label(source, index) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
  guard label is Some(label) else { return None }
  Some((source_id, target_id, label))
}

///|
fn source_edge_index(
  source : GraftSource,
  source_id : @value.CheckedValue,
  target_id : @value.CheckedValue,
  label : @value.CheckedValue?,
) -> Result[Int?, GraftIssue] {
  match source {
    StorageSource(_, source) =>
      @storage.edge_index(source, source_id, target_id, label).map_err(_ => {
        GraftInputUnavailable
      })
    ViewSource(source) =>
      @lifecycle.producer_view_edge_index(source, source_id, target_id, label).map_err(_ => {
          GraftInputUnavailable
        },
      )
  }
}

///|
fn prior_node_exists(
  state : GraftState,
  before : Int,
  identity : @value.CheckedValue,
) -> Result[Bool, GraftIssue] {
  for index in 0..<before {
    guard state.sources.get(index) is Some(source) else {
      return Err(InvalidGraftKernel)
    }
    match source_node_index(source, identity) {
      Ok(Some(_)) => return Ok(true)
      Ok(None) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok(false)
}

///|
fn prior_edge_exists(
  state : GraftState,
  before : Int,
  source_id : @value.CheckedValue,
  target_id : @value.CheckedValue,
  label : @value.CheckedValue?,
) -> Result[Bool, GraftIssue] {
  for index in 0..<before {
    guard state.sources.get(index) is Some(source) else {
      return Err(InvalidGraftKernel)
    }
    match source_edge_index(source, source_id, target_id, label) {
      Ok(Some(_)) => return Ok(true)
      Ok(None) => ()
      Err(issue) => return Err(issue)
    }
  }
  Ok(false)
}

///|
fn union_node_step(
  state : GraftState,
  source : GraftSource,
) -> MergeValue[Unit] {
  let tokens = Ref(0)
  guard state.output is Some(output) &&
    source_node_identity(source, state.record_index) is Some(identity) else {
    return MergeFailed(GraftInputUnavailable)
  }
  match prior_node_exists(state, state.input_index, identity) {
    Ok(true) => {
      let final_graph = state.plans[state.plans.length() - 1].graph
      guard node_properties_at(source, state.record_index, state.node_fields)
        is Some(actual) else {
        return MergeFailed(GraftInputUnavailable)
      }
      let properties = match
        rebind_properties(
          actual,
          @carrier.graph_node_properties(final_graph),
          state.value_limits,
        ) {
        Ok(value) => value
        Err(issue) => return MergeFailed(issue)
      }
      let checked_identity = match
        checked_property_for_contract(
          identity,
          @carrier.graph_identity(final_graph),
          state.value_limits,
        ) {
        Ok(value) => value
        Err(issue) => return MergeFailed(issue)
      }
      return merge_result(
        @graph.observe_node(output, checked_identity, properties).map_err(issue => {
          GraftOutput(issue)
        }),
      )
    }
    Ok(false) => ()
    Err(issue) => return MergeFailed(issue)
  }
  guard node_properties_at(source, state.record_index, state.node_fields)
    is Some(initial) else {
    return MergeFailed(GraftInputUnavailable)
  }
  let mut properties = initial
  if state.input_index > 0 {
    let prior = state.plans[state.input_index - 1]
    properties = match
      rebind_properties(
        properties,
        @carrier.graph_node_properties(prior.graph),
        state.value_limits,
      ) {
      Ok(value) => value
      Err(issue) => return MergeFailed(issue)
    }
  }
  for input in (state.input_index + 1)..<state.sources.length() {
    guard state.sources.get(input) is Some(next) else {
      return MergeFailed(InvalidGraftKernel)
    }
    let plan = state.plans[input - 1]
    let fields = @carrier.graph_node_properties(plan.graph)
    let matching = match source_node_index(next, identity) {
      Ok(value) => value
      Err(issue) => return MergeFailed(issue)
    }
    properties = match matching {
      Some(index) => {
        guard node_properties_at(next, index, state.node_fields) is Some(right) else {
          return MergeFailed(GraftInputUnavailable)
        }
        match
          merge_properties(
            state,
            tokens,
            properties,
            right,
            fields,
            plan.nodes,
            state.value_limits,
          ) {
          MergeReady(value) => value
          MergePending => return MergePending
          MergeStopped(reason) => return MergeStopped(reason)
          MergeFailed(issue) => return MergeFailed(issue)
        }
      }
      None =>
        match rebind_properties(properties, fields, state.value_limits) {
          Ok(value) => value
          Err(issue) => return MergeFailed(issue)
        }
    }
  }
  let final_graph = state.plans[state.plans.length() - 1].graph
  let checked_identity = match
    checked_property_for_contract(
      identity,
      @carrier.graph_identity(final_graph),
      state.value_limits,
    ) {
    Ok(value) => value
    Err(issue) => return MergeFailed(issue)
  }
  merge_result(
    @graph.append_node(output, checked_identity, properties).map_err(issue => {
      GraftOutput(issue)
    }),
  )
}

///|
fn union_edge_step(
  state : GraftState,
  source : GraftSource,
) -> MergeValue[Unit] {
  let tokens = Ref(0)
  guard state.output is Some(output) &&
    source_edge_identity(source, state.record_index)
    is Some((source_id, target_id, label)) else {
    return MergeFailed(GraftInputUnavailable)
  }
  match
    prior_edge_exists(state, state.input_index, source_id, target_id, label) {
    Ok(true) => {
      let final_graph = state.plans[state.plans.length() - 1].graph
      guard edge_properties_at(source, state.record_index, state.edge_fields)
        is Some(actual) else {
        return MergeFailed(GraftInputUnavailable)
      }
      let properties = match
        rebind_properties(
          actual,
          @carrier.graph_edge_properties(final_graph),
          state.value_limits,
        ) {
        Ok(value) => value
        Err(issue) => return MergeFailed(issue)
      }
      let identity_contract = @carrier.graph_identity(final_graph)
      let checked_source = match
        checked_property_for_contract(
          source_id,
          identity_contract,
          state.value_limits,
        ) {
        Ok(value) => value
        Err(issue) => return MergeFailed(issue)
      }
      let checked_target = match
        checked_property_for_contract(
          target_id,
          identity_contract,
          state.value_limits,
        ) {
        Ok(value) => value
        Err(issue) => return MergeFailed(issue)
      }
      let checked_label = match
        (label, @carrier.graph_label_contract(final_graph)) {
        (None, None) => None
        (Some(value), Some(contract)) =>
          match
            checked_property_for_contract(value, contract, state.value_limits) {
            Ok(checked) => Some(checked)
            Err(issue) => return MergeFailed(issue)
          }
        _ => return MergeFailed(GraftPropertyValue)
      }
      return merge_result(
        @graph.observe_edge(
          output, checked_source, checked_target, checked_label, properties,
        ).map_err(issue => GraftOutput(issue)),
      )
    }
    Ok(false) => ()
    Err(issue) => return MergeFailed(issue)
  }
  guard edge_properties_at(source, state.record_index, state.edge_fields)
    is Some(initial) else {
    return MergeFailed(GraftInputUnavailable)
  }
  let mut properties = initial
  if state.input_index > 0 {
    let prior = state.plans[state.input_index - 1]
    properties = match
      rebind_properties(
        properties,
        @carrier.graph_edge_properties(prior.graph),
        state.value_limits,
      ) {
      Ok(value) => value
      Err(issue) => return MergeFailed(issue)
    }
  }
  for input in (state.input_index + 1)..<state.sources.length() {
    guard state.sources.get(input) is Some(next) else {
      return MergeFailed(InvalidGraftKernel)
    }
    let plan = state.plans[input - 1]
    let fields = @carrier.graph_edge_properties(plan.graph)
    let matching = match source_edge_index(next, source_id, target_id, label) {
      Ok(value) => value
      Err(issue) => return MergeFailed(issue)
    }
    properties = match matching {
      Some(index) => {
        guard edge_properties_at(next, index, state.edge_fields) is Some(right) else {
          return MergeFailed(GraftInputUnavailable)
        }
        match
          merge_properties(
            state,
            tokens,
            properties,
            right,
            fields,
            plan.edges,
            state.value_limits,
          ) {
          MergeReady(value) => value
          MergePending => return MergePending
          MergeStopped(reason) => return MergeStopped(reason)
          MergeFailed(issue) => return MergeFailed(issue)
        }
      }
      None =>
        match rebind_properties(properties, fields, state.value_limits) {
          Ok(value) => value
          Err(issue) => return MergeFailed(issue)
        }
    }
  }
  let final_graph = state.plans[state.plans.length() - 1].graph
  let identity_contract = @carrier.graph_identity(final_graph)
  let checked_source = match
    checked_property_for_contract(
      source_id,
      identity_contract,
      state.value_limits,
    ) {
    Ok(value) => value
    Err(issue) => return MergeFailed(issue)
  }
  let checked_target = match
    checked_property_for_contract(
      target_id,
      identity_contract,
      state.value_limits,
    ) {
    Ok(value) => value
    Err(issue) => return MergeFailed(issue)
  }
  let checked_label = match
    (label, @carrier.graph_label_contract(final_graph)) {
    (None, None) => None
    (Some(value), Some(contract)) =>
      match checked_property_for_contract(value, contract, state.value_limits) {
        Ok(checked) => Some(checked)
        Err(issue) => return MergeFailed(issue)
      }
    _ => return MergeFailed(GraftPropertyValue)
  }
  merge_result(
    @graph.append_edge(
      output, checked_source, checked_target, checked_label, properties,
    ).map_err(issue => GraftOutput(issue)),
  )
}

///|
fn subtract_node_step(
  state : GraftState,
  left : GraftSource,
  right : GraftSource,
) -> MergeValue[Unit] {
  let tokens = Ref(0)
  guard state.output is Some(output) else {
    return MergeFailed(GraftInputUnavailable)
  }
  if state.input_index != 0 {
    return MergeReady(())
  }
  guard state.plans.get(0) is Some(plan) &&
    source_node_identity(left, state.record_index) is Some(identity) &&
    node_properties_at(left, state.record_index, state.node_fields)
    is Some(left_values) else {
    return MergeFailed(GraftInputUnavailable)
  }
  let shared = match source_node_index(right, identity) {
    Ok(value) => value
    Err(issue) => return MergeFailed(issue)
  }
  let fields = @carrier.graph_node_properties(plan.graph)
  let properties = match shared {
    None =>
      merge_result(rebind_properties(left_values, fields, state.value_limits))
    Some(index) => {
      guard node_properties_at(right, index, state.node_fields)
        is Some(right_values) else {
        return MergeFailed(GraftInputUnavailable)
      }
      let observed_left = match
        rebind_properties(left_values, fields, state.value_limits) {
        Ok(values) => values
        Err(issue) => return MergeFailed(issue)
      }
      let observed_right = match
        rebind_properties(right_values, fields, state.value_limits) {
        Ok(values) => values
        Err(issue) => return MergeFailed(issue)
      }
      let strategies = if state.retain_shared_nodes {
        plan.nodes
      } else {
        Array::make(state.node_fields, None)
      }
      match
        merge_properties(
          state,
          tokens,
          left_values,
          right_values,
          fields,
          strategies,
          state.value_limits,
        ) {
        MergeReady(_) if !state.retain_shared_nodes => {
          match @graph.observe_node(output, identity, observed_left) {
            Ok(_) => ()
            Err(issue) => return MergeFailed(GraftOutput(issue))
          }
          return merge_result(
            @graph.observe_node(output, identity, observed_right).map_err(issue => {
              GraftOutput(issue)
            }),
          )
        }
        MergeReady(merged) =>
          match @graph.observe_node(output, identity, observed_right) {
            Ok(_) => MergeReady(merged)
            Err(issue) => MergeFailed(GraftOutput(issue))
          }
        MergePending => MergePending
        MergeStopped(reason) => MergeStopped(reason)
        MergeFailed(issue) => MergeFailed(issue)
      }
    }
  }
  let properties = match properties {
    MergeReady(properties) => properties
    MergePending => return MergePending
    MergeStopped(reason) => return MergeStopped(reason)
    MergeFailed(issue) => return MergeFailed(issue)
  }
  let checked_identity = match
    checked_property_for_contract(
      identity,
      @carrier.graph_identity(plan.graph),
      state.value_limits,
    ) {
    Ok(value) => value
    Err(issue) => return MergeFailed(issue)
  }
  merge_result(
    @graph.append_node(output, checked_identity, properties).map_err(issue => {
      GraftOutput(issue)
    }),
  )
}

///|
fn subtract_edge_step(
  state : GraftState,
  left : GraftSource,
  right : GraftSource,
) -> MergeValue[Unit] {
  let tokens = Ref(0)
  guard state.output is Some(output) else {
    return MergeFailed(GraftInputUnavailable)
  }
  if state.input_index != 0 {
    return MergeReady(())
  }
  guard state.plans.get(0) is Some(plan) &&
    source_edge_identity(left, state.record_index)
    is Some((source_id, target_id, label)) &&
    edge_properties_at(left, state.record_index, state.edge_fields)
    is Some(left_values) else {
    return MergeFailed(GraftInputUnavailable)
  }
  let shared = match source_edge_index(right, source_id, target_id, label) {
    Ok(value) => value
    Err(issue) => return MergeFailed(issue)
  }
  let fields = @carrier.graph_edge_properties(plan.graph)
  let properties = match shared {
    None =>
      merge_result(rebind_properties(left_values, fields, state.value_limits))
    Some(index) => {
      guard edge_properties_at(right, index, state.edge_fields)
        is Some(right_values) else {
        return MergeFailed(GraftInputUnavailable)
      }
      let observed_left = match
        rebind_properties(left_values, fields, state.value_limits) {
        Ok(values) => values
        Err(issue) => return MergeFailed(issue)
      }
      let observed_right = match
        rebind_properties(right_values, fields, state.value_limits) {
        Ok(values) => values
        Err(issue) => return MergeFailed(issue)
      }
      let strategies = if state.retain_shared_edges {
        plan.edges
      } else {
        Array::make(state.edge_fields, None)
      }
      match
        merge_properties(
          state,
          tokens,
          left_values,
          right_values,
          fields,
          strategies,
          state.value_limits,
        ) {
        MergeReady(_) if !state.retain_shared_edges => {
          match
            @graph.observe_edge(
              output, source_id, target_id, label, observed_left,
            ) {
            Ok(_) => ()
            Err(issue) => return MergeFailed(GraftOutput(issue))
          }
          return merge_result(
            @graph.observe_edge(
              output, source_id, target_id, label, observed_right,
            ).map_err(issue => GraftOutput(issue)),
          )
        }
        MergeReady(merged) =>
          match
            @graph.observe_edge(
              output, source_id, target_id, label, observed_right,
            ) {
            Ok(_) => MergeReady(merged)
            Err(issue) => MergeFailed(GraftOutput(issue))
          }
        MergePending => MergePending
        MergeStopped(reason) => MergeStopped(reason)
        MergeFailed(issue) => MergeFailed(issue)
      }
    }
  }
  let properties = match properties {
    MergeReady(properties) => properties
    MergePending => return MergePending
    MergeStopped(reason) => return MergeStopped(reason)
    MergeFailed(issue) => return MergeFailed(issue)
  }
  let source_present = match @graph.contains_declared_node(output, source_id) {
    Ok(value) => value
    Err(issue) => return MergeFailed(GraftOutput(issue))
  }
  let target_present = match @graph.contains_declared_node(output, target_id) {
    Ok(value) => value
    Err(issue) => return MergeFailed(GraftOutput(issue))
  }
  if !source_present || !target_present {
    return MergeReady(())
  }
  let identity_contract = @carrier.graph_identity(plan.graph)
  let checked_source = match
    checked_property_for_contract(
      source_id,
      identity_contract,
      state.value_limits,
    ) {
    Ok(value) => value
    Err(issue) => return MergeFailed(issue)
  }
  let checked_target = match
    checked_property_for_contract(
      target_id,
      identity_contract,
      state.value_limits,
    ) {
    Ok(value) => value
    Err(issue) => return MergeFailed(issue)
  }
  let checked_label = match (label, @carrier.graph_label_contract(plan.graph)) {
    (None, None) => None
    (Some(value), Some(contract)) =>
      match checked_property_for_contract(value, contract, state.value_limits) {
        Ok(checked) => Some(checked)
        Err(issue) => return MergeFailed(issue)
      }
    _ => return MergeFailed(GraftPropertyValue)
  }
  merge_result(
    @graph.append_edge(
      output, checked_source, checked_target, checked_label, properties,
    ).map_err(issue => GraftOutput(issue)),
  )
}

///|
fn graft_step(
  state : GraftState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, GraftIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !graft_inputs_available(state) {
      return @bounded.Failed(GraftInputUnavailable, progress, used)
    }
    match state.phase {
      CopyNodes => {
        guard graft_source(state) is Some(source) else {
          return @bounded.Failed(InvalidGraftKernel, progress, used)
        }
        let count = match source {
          StorageSource(_, value) => @storage.node_count(value)
          ViewSource(value) =>
            match @lifecycle.producer_view_node_count(value) {
              Some(count) => count
              None =>
                return @bounded.Failed(GraftInputUnavailable, progress, used)
            }
        }
        if state.record_index < count {
          if state.mode == Subtract {
            guard state.sources.length() == 2 else {
              return @bounded.Failed(InvalidGraftKernel, progress, used)
            }
            let left = state.sources[0]
            let right = state.sources[1]
            match subtract_node_step(state, left, right) {
              MergeReady(_) => {
                if !finish_merge_record(state) {
                  return @bounded.Failed(InvalidGraftKernel, progress, used)
                }
                state.record_index += 1
                used += 1
                progress += 1
                continue
              }
              MergePending => return @bounded.Continue(progress + 1, used + 1)
              MergeStopped(reason) =>
                return @bounded.Stopped(reason, progress, used)
              MergeFailed(issue) =>
                return @bounded.Failed(issue, progress, used)
            }
          }
          if state.merge_shared {
            match union_node_step(state, source) {
              MergeReady(_) => {
                if !finish_merge_record(state) {
                  return @bounded.Failed(InvalidGraftKernel, progress, used)
                }
                state.record_index += 1
                used += 1
                progress += 1
                continue
              }
              MergePending => return @bounded.Continue(progress + 1, used + 1)
              MergeStopped(reason) =>
                return @bounded.Stopped(reason, progress, used)
              MergeFailed(issue) =>
                return @bounded.Failed(issue, progress, used)
            }
          }
          guard state.output is Some(output) else {
            return @bounded.Failed(InvalidGraftKernel, progress, used)
          }
          let copied = match source {
            StorageSource(_, source) =>
              copy_graph_node(
                source,
                output,
                state.node_fields,
                state.record_index,
              )
            ViewSource(source) =>
              copy_graph_view_node(
                source,
                output,
                state.node_fields,
                state.record_index,
              )
          }
          match copied {
            Ok(_) => {
              state.record_index += 1
              used += 1
              progress += 1
            }
            Err(Unavailable) =>
              return @bounded.Failed(GraftInputUnavailable, progress, used)
            Err(GraphCopyIssue::Output(issue)) =>
              return @bounded.Failed(GraftOutput(issue), progress, used)
          }
        } else {
          state.phase = CopyEdges
          state.record_index = 0
        }
      }
      CopyEdges => {
        guard graft_source(state) is Some(source) else {
          return @bounded.Failed(InvalidGraftKernel, progress, used)
        }
        let count = match source {
          StorageSource(_, value) => @storage.edge_count(value)
          ViewSource(value) =>
            match @lifecycle.producer_view_edge_count(value) {
              Some(count) => count
              None =>
                return @bounded.Failed(GraftInputUnavailable, progress, used)
            }
        }
        if state.record_index < count {
          if state.mode == Subtract {
            guard state.sources.length() == 2 else {
              return @bounded.Failed(InvalidGraftKernel, progress, used)
            }
            let left = state.sources[0]
            let right = state.sources[1]
            match subtract_edge_step(state, left, right) {
              MergeReady(_) => {
                if !finish_merge_record(state) {
                  return @bounded.Failed(InvalidGraftKernel, progress, used)
                }
                state.record_index += 1
                used += 1
                progress += 1
                continue
              }
              MergePending => return @bounded.Continue(progress + 1, used + 1)
              MergeStopped(reason) =>
                return @bounded.Stopped(reason, progress, used)
              MergeFailed(issue) =>
                return @bounded.Failed(issue, progress, used)
            }
          }
          if state.merge_shared {
            match union_edge_step(state, source) {
              MergeReady(_) => {
                if !finish_merge_record(state) {
                  return @bounded.Failed(InvalidGraftKernel, progress, used)
                }
                state.record_index += 1
                used += 1
                progress += 1
                continue
              }
              MergePending => return @bounded.Continue(progress + 1, used + 1)
              MergeStopped(reason) =>
                return @bounded.Stopped(reason, progress, used)
              MergeFailed(issue) =>
                return @bounded.Failed(issue, progress, used)
            }
          }
          guard state.output is Some(output) else {
            return @bounded.Failed(InvalidGraftKernel, progress, used)
          }
          let copied = match source {
            StorageSource(_, source) =>
              copy_graph_edge(
                source,
                output,
                state.edge_fields,
                state.record_index,
              )
            ViewSource(source) =>
              copy_graph_view_edge(
                source,
                output,
                state.edge_fields,
                state.record_index,
              )
          }
          match copied {
            Ok(_) => {
              state.record_index += 1
              used += 1
              progress += 1
            }
            Err(Unavailable) =>
              return @bounded.Failed(GraftInputUnavailable, progress, used)
            Err(GraphCopyIssue::Output(issue)) =>
              return @bounded.Failed(GraftOutput(issue), progress, used)
          }
        } else if state.mode == Subtract {
          if state.input_index == 0 &&
            (state.retain_shared_nodes || state.retain_shared_edges) {
            advance_graft_source(state)
          } else {
            state.phase = Finish
          }
        } else {
          advance_graft_source(state)
        }
      }
      Finish => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraftKernel, progress, used)
        }
        state.output = None
        return match @graph.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(GraftOutput(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_graft_state(state : GraftState) -> Bool {
  if state.set_execution is Some(execution) {
    @bounded.request_cancel(state.set_control) |> ignore
    match @value_set.advance(execution, 1) {
      Ok(@value_set.Stopped(_)) => ()
      _ => return false
    }
    match @value_set.cleanup(execution) {
      Ok(_) => state.set_execution = None
      Err(_) => return false
    }
  }
  state.set_results.clear()
  state.set_cached_slots = 0
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  true
}

///|
pub fn start_graft(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@graph.ProducerRead],
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[GraftExecution, GraftIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard valid_graft_step(sequence, step, inputs.length()) else {
    return Err(InvalidGraftKernel)
  }
  guard structural_mode(sequence, step) is Some(mode) else {
    return Err(InvalidGraftKernel)
  }
  guard structural_merge_plans(sequence, step) is Some(plans) &&
    executable_merge_plans(plans) else {
    return Err(InvalidGraftKernel)
  }
  let (retain_shared_nodes, retain_shared_edges) = match
    @lower.sequence_step(sequence, step) {
    Some(@lower.GraphStructuralStep(structural)) if mode == Subtract =>
      (
        @lower.graph_structural_has_node_property_strategies(structural),
        @lower.graph_structural_has_edge_property_strategies(structural),
      )
    _ => (false, false)
  }
  let sources = []
  for index, input in inputs {
    guard @graph.producer_read_matches_operation_input(
        input, owner, step, index,
      ) &&
      @graph.producer_read_storage(input) is Some(source) else {
      return Err(GraftInputUnavailable)
    }
    sources.push(StorageSource(input, source))
  }
  guard sources[0] is StorageSource(_, first) &&
    @storage.carrier(first) is @carrier.GraphValue(contract) else {
    return Err(GraftInputUnavailable)
  }
  guard graft_noninterruptible_value_nodes(plans, limits)
    is Some(max_noninterruptible_value_nodes) else {
    return Err(InvalidGraftLimits)
  }
  guard graft_noninterruptible_value_bytes(plans, limits)
    is Some(max_noninterruptible_value_bytes) else {
    return Err(InvalidGraftLimits)
  }
  let output = match
    @graph.prepare_output(
      owner,
      @pipeline.Step(step),
      @storage.DeclaredNodes,
      limits,
      storage_bytes,
      available,
    ) {
    Ok(value) => value
    Err(issue) => return Err(GraftOutput(issue))
  }
  let state : GraftState = {
    set_control: @bounded.control(),
    sources,
    mode,
    merge_shared: structural_merges_shared(sequence, step),
    retain_shared_nodes,
    retain_shared_edges,
    plans,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    output: Some(output),
    node_fields: @carrier.field_count(@carrier.graph_node_properties(contract)),
    edge_fields: @carrier.field_count(@carrier.graph_edge_properties(contract)),
    input_index: 0,
    phase: CopyNodes,
    record_index: 0,
    max_workspace_slots: limits.max_workspace_slots,
    set_execution: None,
    set_token: -1,
    set_cached_slots: 0,
    set_results: Map([]),
  }
  let (session, token) = @bounded.start(
    control, state, graft_step, cleanup_graft_state, @graph.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes,
    max_noninterruptible_value_bytes,
  })
}

///|
pub fn start_graft_views(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@lifecycle.ProducerView],
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[GraftExecution, GraftIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard valid_graft_step(sequence, step, inputs.length()) else {
    return Err(InvalidGraftKernel)
  }
  guard structural_mode(sequence, step) is Some(mode) else {
    return Err(InvalidGraftKernel)
  }
  guard structural_merge_plans(sequence, step) is Some(plans) &&
    executable_merge_plans(plans) else {
    return Err(InvalidGraftKernel)
  }
  let sources = []
  for index, input in inputs {
    let reference = @lifecycle.producer_view_read_reference(input)
    if @lifecycle.producer_view_kind(input) != @carrier.GraphKind ||
      !@lifecycle.producer_read_reference_matches_operation_input(
        reference, owner, step, index,
      ) {
      return Err(GraftInputUnavailable)
    }
    sources.push(ViewSource(input))
  }
  guard @lower.preparation_carrier_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(@carrier.GraphValue(contract)) else {
    return Err(InvalidGraftKernel)
  }
  let (retain_shared_nodes, retain_shared_edges) = match
    @lower.sequence_step(sequence, step) {
    Some(@lower.GraphStructuralStep(structural)) if mode == Subtract =>
      (
        @lower.graph_structural_has_node_property_strategies(structural),
        @lower.graph_structural_has_edge_property_strategies(structural),
      )
    _ => (false, false)
  }
  guard graft_noninterruptible_value_nodes(plans, limits)
    is Some(max_noninterruptible_value_nodes) else {
    return Err(InvalidGraftLimits)
  }
  guard graft_noninterruptible_value_bytes(plans, limits)
    is Some(max_noninterruptible_value_bytes) else {
    return Err(InvalidGraftLimits)
  }
  let output = match
    @graph.prepare_output(
      owner,
      @pipeline.Step(step),
      @storage.DeclaredNodes,
      limits,
      storage_bytes,
      available,
    ) {
    Ok(value) => value
    Err(issue) => return Err(GraftOutput(issue))
  }
  let state : GraftState = {
    set_control: @bounded.control(),
    sources,
    mode,
    merge_shared: structural_merges_shared(sequence, step),
    retain_shared_nodes,
    retain_shared_edges,
    plans,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    output: Some(output),
    node_fields: @carrier.field_count(@carrier.graph_node_properties(contract)),
    edge_fields: @carrier.field_count(@carrier.graph_edge_properties(contract)),
    input_index: 0,
    phase: CopyNodes,
    record_index: 0,
    max_workspace_slots: limits.max_workspace_slots,
    set_execution: None,
    set_token: -1,
    set_cached_slots: 0,
    set_results: Map([]),
  }
  let (session, token) = @bounded.start(
    control, state, graft_step, cleanup_graft_state, @graph.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes,
    max_noninterruptible_value_bytes,
  })
}

///|
pub fn graft_max_noninterruptible_value_nodes(value : GraftExecution) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn graft_max_noninterruptible_value_bytes(value : GraftExecution) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn advance_graft(
  value : GraftExecution,
  quantum : Int,
) -> Result[GraftPoll, GraftIssue] {
  guard value.token is Some(token) else {
    return Err(GraftExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(GraftExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(GraftContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(GraftComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(GraftFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(GraftStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn graft_stopped(value : GraftExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn graft_cleanup_pending(value : GraftExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_graft(value : GraftExecution) -> Result[Bool, GraftIssue] {
  @bounded.cleanup(value.session).map_err(issue => GraftExecutionIssue(issue))
}
