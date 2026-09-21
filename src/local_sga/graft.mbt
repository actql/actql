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
priv struct StructuralMergePlan {
  graph : @carrier.Graph
  nodes : Array[@graph_type.FieldStrategy?]
  edges : Array[@graph_type.FieldStrategy?]
}

///|
priv struct GraftState {
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
}

///|
struct GraftExecution {
  session : @bounded.Session[GraftState, @graph.Completed, GraftIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
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
fn checked_set_members(
  value : @value.CheckedValue,
  item : @contract.Contract,
  limits : @value.Limits,
) -> Result[Array[@value.CheckedValue], GraftIssue] {
  guard value.value is @value.Array(values) else {
    return Err(GraftPropertyValue)
  }
  let out = []
  for child in @value.elements(values) {
    match @value.recheck_runtime_value(child, item, limits) {
      Some(checked) => out.push(checked)
      None => return Err(GraftPropertyValue)
    }
  }
  Ok(out)
}

///|
fn set_member_map(
  values : Array[@value.CheckedValue],
  limits : @value.Limits,
) -> Result[Map[String, @value.CheckedValue], GraftIssue] {
  let out : Map[String, @value.CheckedValue] = Map([])
  for value in values {
    let key = match @value.complete_order_key(value, limits) {
      Ok(key) => key
      Err(_) => return Err(GraftPropertyValue)
    }
    if !out.contains(key) {
      out[key] = value
    }
  }
  Ok(out)
}

///|
fn merge_set_property(
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  strategy : @graph_type.FieldStrategy,
  contract : @contract.Contract,
  limits : @value.Limits,
  workspace_slots : Int,
) -> Result[@value.CheckedValue, GraftIssue] {
  guard contract.shape is @contract.Array(item, ..) else {
    return Err(GraftPropertyValue)
  }
  guard left.value is @value.Array(left_input) &&
    right.value is @value.Array(right_input) else {
    return Err(GraftPropertyValue)
  }
  let left_count = @value.element_count(left_input)
  let right_count = @value.element_count(right_input)
  if right_count > 2147483647 - left_count - 1 {
    return Err(GraftWorkspaceLimit)
  }
  let count = left_count + right_count
  if count > (2147483647 - 8) / 8 || count * 8 + 8 > workspace_slots {
    return Err(GraftWorkspaceLimit)
  }
  let left_values = match checked_set_members(left, item, limits) {
    Ok(values) => values
    Err(issue) => return Err(issue)
  }
  let right_values = match checked_set_members(right, item, limits) {
    Ok(values) => values
    Err(issue) => return Err(issue)
  }
  let left_set = match set_member_map(left_values, limits) {
    Ok(values) => values
    Err(issue) => return Err(issue)
  }
  let right_set = match set_member_map(right_values, limits) {
    Ok(values) => values
    Err(issue) => return Err(issue)
  }
  if strategy == @graph_type.SetUnion {
    for key, value in right_set {
      if !left_set.contains(key) {
        left_set[key] = value
      }
    }
  } else if strategy == @graph_type.SetDifference {
    for key, _ in right_set {
      left_set.remove(key)
    }
  } else {
    return Err(GraftPropertyValue)
  }
  let keys = left_set.keys().collect()
  keys.sort_by((left, right) => @canonical.compare_utf16(left, right))
  let values = keys.map(key => left_set[key].value)
  match
    @value.recheck_runtime_value(@value.array_value(values), contract, limits) {
    Some(checked) => Ok(checked)
    None => Err(GraftPropertyValue)
  }
}

///|
fn merge_property(
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  strategy : @graph_type.FieldStrategy?,
  contract : @contract.Contract,
  limits : @value.Limits,
  workspace_slots : Int,
) -> Result[@value.CheckedValue, GraftIssue] {
  match strategy {
    None | Some(@graph_type.ExactEqual) =>
      match complete_property_equal(left, right, limits) {
        Ok(true) => checked_property_for_contract(left, contract, limits)
        Ok(false) => Err(GraftPropertyConflict)
        Err(issue) => Err(issue)
      }
    Some(
      @graph_type.NumberSum
      | @graph_type.NumberMean
      | @graph_type.NumberMin
      | @graph_type.NumberMax
    ) =>
      merge_numeric_property(left, right, strategy.unwrap(), contract, limits)
    Some(@graph_type.SetUnion | @graph_type.SetDifference) =>
      merge_set_property(
        left,
        right,
        strategy.unwrap(),
        contract,
        limits,
        workspace_slots,
      )
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
  left : Array[@value.CheckedValue],
  right : Array[@value.CheckedValue],
  fields : @carrier.Knowledge,
  strategies : Array[@graph_type.FieldStrategy?],
  limits : @value.Limits,
  workspace_slots : Int,
) -> Result[Array[@value.CheckedValue], GraftIssue] {
  if left.length() != right.length() ||
    left.length() != @carrier.field_count(fields) ||
    strategies.length() != left.length() {
    return Err(GraftInputUnavailable)
  }
  let out = []
  for index in 0..<left.length() {
    guard @carrier.field_at(fields, index)
      is Some({ contract: Some(contract), .. }) else {
      return Err(InvalidGraftKernel)
    }
    match
      merge_property(
        left[index],
        right[index],
        strategies[index],
        contract,
        limits,
        workspace_slots,
      ) {
      Ok(checked) => out.push(checked)
      Err(issue) => return Err(issue)
    }
  }
  Ok(out)
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
      state.max_workspace_slots - @graph.output_workspace_slots(output)
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
) -> Result[Unit, GraftIssue] {
  guard state.output is Some(output) &&
    source_node_identity(source, state.record_index) is Some(identity) else {
    return Err(GraftInputUnavailable)
  }
  match prior_node_exists(state, state.input_index, identity) {
    Ok(true) => {
      let final_graph = state.plans[state.plans.length() - 1].graph
      guard node_properties_at(source, state.record_index, state.node_fields)
        is Some(actual) else {
        return Err(GraftInputUnavailable)
      }
      let properties = match
        rebind_properties(
          actual,
          @carrier.graph_node_properties(final_graph),
          state.value_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let checked_identity = match
        checked_property_for_contract(
          identity,
          @carrier.graph_identity(final_graph),
          state.value_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      return @graph.observe_node(output, checked_identity, properties).map_err(issue => {
        GraftOutput(issue)
      })
    }
    Ok(false) => ()
    Err(issue) => return Err(issue)
  }
  guard node_properties_at(source, state.record_index, state.node_fields)
    is Some(initial) else {
    return Err(GraftInputUnavailable)
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
      Err(issue) => return Err(issue)
    }
  }
  for input in (state.input_index + 1)..<state.sources.length() {
    guard state.sources.get(input) is Some(next) else {
      return Err(InvalidGraftKernel)
    }
    let plan = state.plans[input - 1]
    let fields = @carrier.graph_node_properties(plan.graph)
    let matching = match source_node_index(next, identity) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    properties = match matching {
      Some(index) => {
        guard node_properties_at(next, index, state.node_fields) is Some(right) else {
          return Err(GraftInputUnavailable)
        }
        match
          merge_properties(
            properties,
            right,
            fields,
            plan.nodes,
            state.value_limits,
            merge_workspace_slots(state),
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      }
      None =>
        match rebind_properties(properties, fields, state.value_limits) {
          Ok(value) => value
          Err(issue) => return Err(issue)
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
    Err(issue) => return Err(issue)
  }
  @graph.append_node(output, checked_identity, properties).map_err(issue => {
    GraftOutput(issue)
  })
}

///|
fn union_edge_step(
  state : GraftState,
  source : GraftSource,
) -> Result[Unit, GraftIssue] {
  guard state.output is Some(output) &&
    source_edge_identity(source, state.record_index)
    is Some((source_id, target_id, label)) else {
    return Err(GraftInputUnavailable)
  }
  match
    prior_edge_exists(state, state.input_index, source_id, target_id, label) {
    Ok(true) => {
      let final_graph = state.plans[state.plans.length() - 1].graph
      guard edge_properties_at(source, state.record_index, state.edge_fields)
        is Some(actual) else {
        return Err(GraftInputUnavailable)
      }
      let properties = match
        rebind_properties(
          actual,
          @carrier.graph_edge_properties(final_graph),
          state.value_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let identity_contract = @carrier.graph_identity(final_graph)
      let checked_source = match
        checked_property_for_contract(
          source_id,
          identity_contract,
          state.value_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let checked_target = match
        checked_property_for_contract(
          target_id,
          identity_contract,
          state.value_limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let checked_label = match
        (label, @carrier.graph_label_contract(final_graph)) {
        (None, None) => None
        (Some(value), Some(contract)) =>
          match
            checked_property_for_contract(value, contract, state.value_limits) {
            Ok(checked) => Some(checked)
            Err(issue) => return Err(issue)
          }
        _ => return Err(GraftPropertyValue)
      }
      return @graph.observe_edge(
        output, checked_source, checked_target, checked_label, properties,
      ).map_err(issue => GraftOutput(issue))
    }
    Ok(false) => ()
    Err(issue) => return Err(issue)
  }
  guard edge_properties_at(source, state.record_index, state.edge_fields)
    is Some(initial) else {
    return Err(GraftInputUnavailable)
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
      Err(issue) => return Err(issue)
    }
  }
  for input in (state.input_index + 1)..<state.sources.length() {
    guard state.sources.get(input) is Some(next) else {
      return Err(InvalidGraftKernel)
    }
    let plan = state.plans[input - 1]
    let fields = @carrier.graph_edge_properties(plan.graph)
    let matching = match source_edge_index(next, source_id, target_id, label) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    properties = match matching {
      Some(index) => {
        guard edge_properties_at(next, index, state.edge_fields) is Some(right) else {
          return Err(GraftInputUnavailable)
        }
        match
          merge_properties(
            properties,
            right,
            fields,
            plan.edges,
            state.value_limits,
            merge_workspace_slots(state),
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
      }
      None =>
        match rebind_properties(properties, fields, state.value_limits) {
          Ok(value) => value
          Err(issue) => return Err(issue)
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
    Err(issue) => return Err(issue)
  }
  let checked_target = match
    checked_property_for_contract(
      target_id,
      identity_contract,
      state.value_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let checked_label = match
    (label, @carrier.graph_label_contract(final_graph)) {
    (None, None) => None
    (Some(value), Some(contract)) =>
      match checked_property_for_contract(value, contract, state.value_limits) {
        Ok(checked) => Some(checked)
        Err(issue) => return Err(issue)
      }
    _ => return Err(GraftPropertyValue)
  }
  @graph.append_edge(
    output, checked_source, checked_target, checked_label, properties,
  ).map_err(issue => GraftOutput(issue))
}

///|
fn subtract_node_step(
  state : GraftState,
  left : GraftSource,
  right : GraftSource,
) -> Result[Unit, GraftIssue] {
  guard state.output is Some(output) else { return Err(GraftInputUnavailable) }
  if state.input_index != 0 {
    return Ok(())
  }
  guard state.plans.get(0) is Some(plan) &&
    source_node_identity(left, state.record_index) is Some(identity) &&
    node_properties_at(left, state.record_index, state.node_fields)
    is Some(left_values) else {
    return Err(GraftInputUnavailable)
  }
  let shared = match source_node_index(right, identity) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let fields = @carrier.graph_node_properties(plan.graph)
  let properties = match shared {
    None => rebind_properties(left_values, fields, state.value_limits)
    Some(index) => {
      guard node_properties_at(right, index, state.node_fields)
        is Some(right_values) else {
        return Err(GraftInputUnavailable)
      }
      let observed_left = match
        rebind_properties(left_values, fields, state.value_limits) {
        Ok(values) => values
        Err(issue) => return Err(issue)
      }
      let observed_right = match
        rebind_properties(right_values, fields, state.value_limits) {
        Ok(values) => values
        Err(issue) => return Err(issue)
      }
      let strategies = if state.retain_shared_nodes {
        plan.nodes
      } else {
        Array::make(state.node_fields, None)
      }
      match
        merge_properties(
          left_values,
          right_values,
          fields,
          strategies,
          state.value_limits,
          merge_workspace_slots(state),
        ) {
        Ok(_) if !state.retain_shared_nodes => {
          match @graph.observe_node(output, identity, observed_left) {
            Ok(_) => ()
            Err(issue) => return Err(GraftOutput(issue))
          }
          return @graph.observe_node(output, identity, observed_right).map_err(issue => {
            GraftOutput(issue)
          })
        }
        Ok(merged) =>
          match @graph.observe_node(output, identity, observed_right) {
            Ok(_) => Ok(merged)
            Err(issue) => Err(GraftOutput(issue))
          }
        Err(issue) => Err(issue)
      }
    }
  }
  guard properties is Ok(properties) else {
    return properties.map(_ => ()).map_err(issue => issue)
  }
  let checked_identity = match
    checked_property_for_contract(
      identity,
      @carrier.graph_identity(plan.graph),
      state.value_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @graph.append_node(output, checked_identity, properties).map_err(issue => {
    GraftOutput(issue)
  })
}

///|
fn subtract_edge_step(
  state : GraftState,
  left : GraftSource,
  right : GraftSource,
) -> Result[Unit, GraftIssue] {
  guard state.output is Some(output) else { return Err(GraftInputUnavailable) }
  if state.input_index != 0 {
    return Ok(())
  }
  guard state.plans.get(0) is Some(plan) &&
    source_edge_identity(left, state.record_index)
    is Some((source_id, target_id, label)) &&
    edge_properties_at(left, state.record_index, state.edge_fields)
    is Some(left_values) else {
    return Err(GraftInputUnavailable)
  }
  let shared = match source_edge_index(right, source_id, target_id, label) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let fields = @carrier.graph_edge_properties(plan.graph)
  let properties = match shared {
    None => rebind_properties(left_values, fields, state.value_limits)
    Some(index) => {
      guard edge_properties_at(right, index, state.edge_fields)
        is Some(right_values) else {
        return Err(GraftInputUnavailable)
      }
      let observed_left = match
        rebind_properties(left_values, fields, state.value_limits) {
        Ok(values) => values
        Err(issue) => return Err(issue)
      }
      let observed_right = match
        rebind_properties(right_values, fields, state.value_limits) {
        Ok(values) => values
        Err(issue) => return Err(issue)
      }
      let strategies = if state.retain_shared_edges {
        plan.edges
      } else {
        Array::make(state.edge_fields, None)
      }
      match
        merge_properties(
          left_values,
          right_values,
          fields,
          strategies,
          state.value_limits,
          merge_workspace_slots(state),
        ) {
        Ok(_) if !state.retain_shared_edges => {
          match
            @graph.observe_edge(
              output, source_id, target_id, label, observed_left,
            ) {
            Ok(_) => ()
            Err(issue) => return Err(GraftOutput(issue))
          }
          return @graph.observe_edge(
            output, source_id, target_id, label, observed_right,
          ).map_err(issue => GraftOutput(issue))
        }
        Ok(merged) =>
          match
            @graph.observe_edge(
              output, source_id, target_id, label, observed_right,
            ) {
            Ok(_) => Ok(merged)
            Err(issue) => Err(GraftOutput(issue))
          }
        Err(issue) => Err(issue)
      }
    }
  }
  guard properties is Ok(properties) else {
    return properties.map(_ => ()).map_err(issue => issue)
  }
  let source_present = match @graph.contains_declared_node(output, source_id) {
    Ok(value) => value
    Err(issue) => return Err(GraftOutput(issue))
  }
  let target_present = match @graph.contains_declared_node(output, target_id) {
    Ok(value) => value
    Err(issue) => return Err(GraftOutput(issue))
  }
  if !source_present || !target_present {
    return Ok(())
  }
  let identity_contract = @carrier.graph_identity(plan.graph)
  let checked_source = match
    checked_property_for_contract(
      source_id,
      identity_contract,
      state.value_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let checked_target = match
    checked_property_for_contract(
      target_id,
      identity_contract,
      state.value_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let checked_label = match (label, @carrier.graph_label_contract(plan.graph)) {
    (None, None) => None
    (Some(value), Some(contract)) =>
      match checked_property_for_contract(value, contract, state.value_limits) {
        Ok(checked) => Some(checked)
        Err(issue) => return Err(issue)
      }
    _ => return Err(GraftPropertyValue)
  }
  @graph.append_edge(
    output, checked_source, checked_target, checked_label, properties,
  ).map_err(issue => GraftOutput(issue))
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
              Ok(_) => {
                state.record_index += 1
                used += 1
                progress += 1
                continue
              }
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          }
          if state.merge_shared {
            match union_node_step(state, source) {
              Ok(_) => {
                state.record_index += 1
                used += 1
                progress += 1
                continue
              }
              Err(issue) => return @bounded.Failed(issue, progress, used)
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
              Ok(_) => {
                state.record_index += 1
                used += 1
                progress += 1
                continue
              }
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          }
          if state.merge_shared {
            match union_edge_step(state, source) {
              Ok(_) => {
                state.record_index += 1
                used += 1
                progress += 1
                continue
              }
              Err(issue) => return @bounded.Failed(issue, progress, used)
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
  if limits.max_value_nodes < 1 || limits.max_value_nodes > (2147483647 - 1) / 4 {
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
  }
  let (session, token) = @bounded.start(
    control, state, graft_step, cleanup_graft_state, @graph.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes * 4 + 1,
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
  if limits.max_value_nodes < 1 || limits.max_value_nodes > (2147483647 - 1) / 4 {
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
  }
  let (session, token) = @bounded.start(
    control, state, graft_step, cleanup_graft_state, @graph.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes * 4 + 1,
  })
}

///|
pub fn graft_max_noninterruptible_value_nodes(value : GraftExecution) -> Int {
  value.max_noninterruptible_value_nodes
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
