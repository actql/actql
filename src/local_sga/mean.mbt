///|
priv enum MeanPhase {
  AddTotalWeight
  CollectNodes
  SortNodes
  CopyNodes
  BeginNodeSupport
  AddNodeSupport
  BeginNodeProperties
  AddNodeProperty
  FinishNodeProperty
  EmitNode
  CollectEdges
  SortEdges
  CopyEdges
  BeginEdgeSupport
  AddEdgeSupport
  BeginEdgeProperties
  AddEdgeProperty
  FinishEdgeProperty
  EmitEdge
  FinishMean
}

///|
priv struct MeanEdge {
  source : @value.CheckedValue
  target : @value.CheckedValue
  label : @value.CheckedValue?
}

///|
priv struct MeanState {
  prepared : @lower.PreparedGraphMean
  graph : @carrier.Graph
  inputs : Array[@lifecycle.ProducerView]
  weights : Array[Double]
  total : @exact.WeightSum
  exact_bits : Int
  value_limits : @value.Limits
  max_workspace_slots : Int
  mut workspace_slots : Int
  mut output : @graph.OutputBuilder?
  node_keys : Map[String, Bool]
  nodes : Array[@value.CheckedValue]
  node_sort_buffer : Array[@value.CheckedValue]
  retained_nodes : Map[String, Bool]
  edge_keys : Map[String, Bool]
  edges : Array[MeanEdge]
  edge_sort_buffer : Array[MeanEdge]
  mut support : @exact.WeightSum?
  properties : Array[@value.CheckedValue]
  mut property : Int
  mut exact_key : String?
  mut exact_value : @value.CheckedValue?
  mut mean : @exact.Mean?
  mut phase : MeanPhase
  mut input : Int
  mut record : Int
  mut candidate : Int
  mut retain_candidate : Bool
  mut sample : Int
  mut sort_width : Int
  mut sort_left : Int
  mut sort_middle : Int
  mut sort_right : Int
  mut sort_left_at : Int
  mut sort_right_at : Int
  mut sort_copy_at : Int
}

///|
struct MeanExecution {
  session : @bounded.Session[MeanState, @graph.Completed, MeanIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum MeanPoll {
  MeanContinue(progress~ : Int64, work~ : Int64)
  MeanComplete(@graph.Completed, progress~ : Int64, work~ : Int64)
  MeanFailed(MeanIssue, progress~ : Int64, work~ : Int64)
  MeanStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum MeanIssue {
  InvalidMeanKernel
  InvalidMeanLimits
  MeanInputUnavailable
  MeanPropertyConflict
  MeanPropertyValue
  MeanWorkspaceLimit
  MeanValue(@value.CompleteOrderIssue)
  MeanKey(@value.KeyOrderIssue)
  MeanNumeric(@exact.Issue)
  MeanOutput(@graph.Issue)
  MeanExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn mean_value_key(
  state : MeanState,
  value : @value.CheckedValue,
) -> Result[String, MeanIssue] {
  @value.complete_order_key(value, state.value_limits).map_err(issue => {
    MeanValue(issue)
  })
}

///|
fn mean_edge_key(
  state : MeanState,
  edge : MeanEdge,
) -> Result[String, MeanIssue] {
  let source = match mean_value_key(state, edge.source) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let target = match mean_value_key(state, edge.target) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let label = match edge.label {
    Some(value) =>
      match mean_value_key(state, value) {
        Ok(value) => "1" + value.length().to_string() + ":" + value
        Err(issue) => return Err(issue)
      }
    None => "0"
  }
  Ok(
    source.length().to_string() +
    ":" +
    source +
    target.length().to_string() +
    ":" +
    target +
    label,
  )
}

///|
fn reserve_mean_slots(state : MeanState, slots : Int) -> Bool {
  if slots < 0 || slots > state.max_workspace_slots - state.workspace_slots {
    false
  } else {
    state.workspace_slots += slots
    true
  }
}

///|
fn release_mean_slots(state : MeanState, slots : Int) -> Unit {
  state.workspace_slots -= slots
}

///|
fn begin_mean_sort(state : MeanState, count : Int) -> Bool {
  if count > 1 && !reserve_mean_slots(state, count) {
    false
  } else {
    state.sort_width = 1
    state.sort_left = 0
    state.sort_middle = -1
    state.sort_right = 0
    state.sort_left_at = 0
    state.sort_right_at = 0
    state.sort_copy_at = 0
    true
  }
}

///|
fn begin_mean_merge(state : MeanState, count : Int) -> Unit {
  let left = state.sort_left
  let middle = left + Int::min(state.sort_width, count - left)
  let right = middle + Int::min(state.sort_width, count - middle)
  state.sort_middle = middle
  state.sort_right = right
  state.sort_left_at = left
  state.sort_right_at = middle
}

///|
fn finish_mean_sort_pass(state : MeanState, count : Int) -> Unit {
  state.sort_width = if state.sort_width > count / 2 {
    count
  } else {
    state.sort_width * 2
  }
  state.sort_left = 0
  state.sort_middle = -1
  state.sort_copy_at = 0
}

///|
fn collect_mean_node(state : MeanState) -> Result[Unit, MeanIssue] {
  let view = state.inputs[state.input]
  let identity = match
    @lifecycle.producer_view_node_identity(view, state.record) {
    Ok(value) => value
    Err(_) => return Err(MeanInputUnavailable)
  }
  let key = match mean_value_key(state, identity) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !state.node_keys.contains(key) {
    if !reserve_mean_slots(state, 3) {
      return Err(MeanWorkspaceLimit)
    }
    state.node_keys[key] = true
    state.nodes.push(identity)
  }
  Ok(())
}

///|
fn edge_at(
  view : @lifecycle.ProducerView,
  index : Int,
) -> Result[MeanEdge, MeanIssue] {
  let (source_at, target_at) = match
    @lifecycle.producer_view_edge_endpoints(view, index) {
    Ok(value) => value
    Err(_) => return Err(MeanInputUnavailable)
  }
  let source = match @lifecycle.producer_view_node_identity(view, source_at) {
    Ok(value) => value
    Err(_) => return Err(MeanInputUnavailable)
  }
  let target = match @lifecycle.producer_view_node_identity(view, target_at) {
    Ok(value) => value
    Err(_) => return Err(MeanInputUnavailable)
  }
  let label = match @lifecycle.producer_view_edge_label(view, index) {
    Ok(value) => value
    Err(_) => return Err(MeanInputUnavailable)
  }
  Ok({ source, target, label, })
}

///|
fn collect_mean_edge(state : MeanState) -> Result[Unit, MeanIssue] {
  let edge = match edge_at(state.inputs[state.input], state.record) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let key = match mean_edge_key(state, edge) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !state.edge_keys.contains(key) {
    if !reserve_mean_slots(state, 5) {
      return Err(MeanWorkspaceLimit)
    }
    state.edge_keys[key] = true
    state.edges.push(edge)
  }
  Ok(())
}

///|
fn compare_mean_nodes(
  left : @value.CheckedValue,
  right : @value.CheckedValue,
) -> Result[Int, MeanIssue] {
  @value.compare_key_values(left, right).map_err(issue => MeanKey(issue))
}

///|
fn compare_mean_labels(
  left : @value.CheckedValue?,
  right : @value.CheckedValue?,
) -> Result[Int, MeanIssue] {
  match (left, right) {
    (None, None) => Ok(0)
    (None, Some(_)) => Ok(-1)
    (Some(_), None) => Ok(1)
    (Some(left), Some(right)) => compare_mean_nodes(left, right)
  }
}

///|
fn compare_mean_edges(
  left : MeanEdge,
  right : MeanEdge,
) -> Result[Int, MeanIssue] {
  let source = match compare_mean_nodes(left.source, right.source) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if source != 0 {
    return Ok(source)
  }
  let target = match compare_mean_nodes(left.target, right.target) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if target != 0 {
    return Ok(target)
  }
  compare_mean_labels(left.label, right.label)
}

///|
fn begin_mean_support(state : MeanState) -> Result[Unit, MeanIssue] {
  match @exact.prepare_weight_sum(state.exact_bits) {
    Ok(value) => {
      state.support = Some(value)
      state.sample = 0
      Ok(())
    }
    Err(issue) => Err(MeanNumeric(issue))
  }
}

///|
fn add_node_support(state : MeanState) -> Result[Unit, MeanIssue] {
  guard state.support is Some(support) else { return Err(InvalidMeanKernel) }
  let identity = state.nodes[state.candidate]
  match
    @lifecycle.producer_view_node_index(state.inputs[state.sample], identity) {
    Ok(Some(_)) =>
      @exact.add_weight(support, state.weights[state.sample]).map_err(issue => {
        MeanNumeric(issue)
      })
    Ok(None) => Ok(())
    Err(_) => Err(MeanInputUnavailable)
  }
}

///|
fn add_edge_support(state : MeanState) -> Result[Unit, MeanIssue] {
  guard state.support is Some(support) else { return Err(InvalidMeanKernel) }
  let edge = state.edges[state.candidate]
  match
    @lifecycle.producer_view_edge_index(
      state.inputs[state.sample],
      edge.source,
      edge.target,
      edge.label,
    ) {
    Ok(Some(_)) =>
      @exact.add_weight(support, state.weights[state.sample]).map_err(issue => {
        MeanNumeric(issue)
      })
    Ok(None) => Ok(())
    Err(_) => Err(MeanInputUnavailable)
  }
}

///|
fn finish_mean_support(
  state : MeanState,
  entity : @graph_type.EntityKind,
) -> Result[Bool, MeanIssue] {
  guard state.support is Some(support) else { return Err(InvalidMeanKernel) }
  let retained = @exact.accumulated_support_at_least(
    support,
    state.total,
    @lower.graph_mean_support(state.prepared, entity),
  ).map_err(issue => MeanNumeric(issue))
  @exact.cancel_weight_sum(support) |> ignore
  state.support = None
  retained
}

///|
fn mean_property_contract(
  state : MeanState,
  entity : @graph_type.EntityKind,
  index : Int,
) -> @contract.Contract? {
  let fields = match entity {
    @graph_type.Nodes => @carrier.graph_node_properties(state.graph)
    @graph_type.Edges => @carrier.graph_edge_properties(state.graph)
  }
  @carrier.field_at(fields, index).bind(field => field.contract)
}

///|
fn begin_mean_property(
  state : MeanState,
  entity : @graph_type.EntityKind,
) -> Result[Unit, MeanIssue] {
  guard @lower.graph_mean_property_strategy(
      state.prepared,
      entity,
      state.property,
    )
    is Some(strategy) else {
    return Err(InvalidMeanKernel)
  }
  state.sample = 0
  state.exact_key = None
  state.exact_value = None
  state.mean = None
  match strategy {
    @graph_type.EqualValues => Ok(())
    @graph_type.WeightedMean(_, _) =>
      match @exact.prepare_weighted_mean(state.exact_bits) {
        Ok(value) => {
          state.mean = Some(value)
          Ok(())
        }
        Err(issue) => Err(MeanNumeric(issue))
      }
  }
}

///|
fn add_exact_mean_value(
  state : MeanState,
  value : @value.CheckedValue,
) -> Result[Unit, MeanIssue] {
  let key = match mean_value_key(state, value) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match state.exact_key {
    None => {
      state.exact_key = Some(key)
      state.exact_value = Some(value)
      Ok(())
    }
    Some(expected) =>
      if expected == key {
        Ok(())
      } else {
        Err(MeanPropertyConflict)
      }
  }
}

///|
fn add_numeric_mean_value(
  state : MeanState,
  value : Double,
) -> Result[Unit, MeanIssue] {
  guard state.mean is Some(mean) else { return Err(InvalidMeanKernel) }
  @exact.add_weighted_value(mean, value, state.weights[state.sample]).map_err(issue => {
    MeanNumeric(issue)
  })
}

///|
fn add_mean_property_value(
  state : MeanState,
  entity : @graph_type.EntityKind,
  record : Int?,
) -> Result[Unit, MeanIssue] {
  guard @lower.graph_mean_property_strategy(
      state.prepared,
      entity,
      state.property,
    )
    is Some(strategy) else {
    return Err(InvalidMeanKernel)
  }
  let weight = state.weights[state.sample]
  if weight == 0.0 {
    return Ok(())
  }
  match strategy {
    @graph_type.EqualValues =>
      match record {
        None => Ok(())
        Some(record) => {
          let value = match entity {
            @graph_type.Nodes =>
              @lifecycle.producer_view_node_property(
                state.inputs[state.sample],
                record,
                state.property,
              )
            @graph_type.Edges =>
              @lifecycle.producer_view_edge_property(
                state.inputs[state.sample],
                record,
                state.property,
              )
          }
          match value {
            Ok(value) => add_exact_mean_value(state, value)
            Err(_) => Err(MeanInputUnavailable)
          }
        }
      }
    @graph_type.WeightedMean(missing, nulls) =>
      match record {
        None =>
          match missing {
            @graph_type.ExcludeMissing => Ok(())
            @graph_type.ZeroMissing => add_numeric_mean_value(state, 0.0)
          }
        Some(record) => {
          let value = match entity {
            @graph_type.Nodes =>
              @lifecycle.producer_view_node_property(
                state.inputs[state.sample],
                record,
                state.property,
              )
            @graph_type.Edges =>
              @lifecycle.producer_view_edge_property(
                state.inputs[state.sample],
                record,
                state.property,
              )
          }
          guard value is Ok(value) else { return Err(MeanInputUnavailable) }
          match value.value {
            @value.Number(number) => add_numeric_mean_value(state, number)
            @value.Null =>
              match nulls {
                @graph_type.ExcludeNull => Ok(())
                @graph_type.ZeroNull => add_numeric_mean_value(state, 0.0)
                @graph_type.FailNull => Err(MeanPropertyValue)
              }
            _ => Err(MeanPropertyValue)
          }
        }
      }
  }
}

///|
fn add_node_property(state : MeanState) -> Result[Unit, MeanIssue] {
  let identity = state.nodes[state.candidate]
  let record = match
    @lifecycle.producer_view_node_index(state.inputs[state.sample], identity) {
    Ok(value) => value
    Err(_) => return Err(MeanInputUnavailable)
  }
  add_mean_property_value(state, @graph_type.Nodes, record)
}

///|
fn add_edge_property(state : MeanState) -> Result[Unit, MeanIssue] {
  let edge = state.edges[state.candidate]
  let record = match
    @lifecycle.producer_view_edge_index(
      state.inputs[state.sample],
      edge.source,
      edge.target,
      edge.label,
    ) {
    Ok(value) => value
    Err(_) => return Err(MeanInputUnavailable)
  }
  add_mean_property_value(state, @graph_type.Edges, record)
}

///|
fn finish_mean_property(
  state : MeanState,
  entity : @graph_type.EntityKind,
) -> Result[Unit, MeanIssue] {
  guard @lower.graph_mean_property_strategy(
      state.prepared,
      entity,
      state.property,
    )
    is Some(strategy) &&
    mean_property_contract(state, entity, state.property) is Some(contract) else {
    return Err(InvalidMeanKernel)
  }
  let value = match strategy {
    @graph_type.EqualValues =>
      match state.exact_value {
        Some(value) =>
          match
            @value.recheck_runtime_value(
              value.value,
              contract,
              state.value_limits,
            ) {
            Some(value) => value
            None => return Err(MeanPropertyValue)
          }
        None => return Err(MeanPropertyConflict)
      }
    @graph_type.WeightedMean(_, _) => {
      guard state.mean is Some(mean) else { return Err(InvalidMeanKernel) }
      state.mean = None
      match @exact.finish_weighted_mean(mean) {
        Ok(number) => {
          guard @value.number_value(number) is Some(number_value) &&
            @value.recheck_runtime_value(
              number_value,
              contract,
              state.value_limits,
            )
            is Some(value) else {
            return Err(MeanPropertyValue)
          }
          value
        }
        Err(@exact.ZeroDenominator) =>
          match @value.checked_null_value(contract) {
            Some(value) => value
            None => return Err(MeanPropertyValue)
          }
        Err(issue) => return Err(MeanNumeric(issue))
      }
    }
  }
  state.properties.push(value)
  Ok(())
}

///|
fn mean_inputs_available(state : MeanState) -> Bool {
  for input in state.inputs {
    if @lifecycle.producer_view_node_count(input) is None ||
      @lifecycle.producer_view_edge_count(input) is None {
      return false
    }
  }
  true
}

///|
fn advance_mean_state(
  state : MeanState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, MeanIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !mean_inputs_available(state) {
      return @bounded.Failed(MeanInputUnavailable, progress, used)
    }
    match state.phase {
      AddTotalWeight =>
        if state.sample < state.weights.length() {
          match @exact.add_weight(state.total, state.weights[state.sample]) {
            Ok(_) => {
              state.sample += 1
              used += 1
              progress += 1
            }
            Err(issue) =>
              return @bounded.Failed(MeanNumeric(issue), progress, used)
          }
        } else {
          state.phase = CollectNodes
          state.input = 0
          state.record = 0
        }
      CollectNodes =>
        if state.input < state.inputs.length() {
          let count = @lifecycle.producer_view_node_count(
            state.inputs[state.input],
          ).unwrap()
          if state.record < count {
            match collect_mean_node(state) {
              Ok(_) => {
                state.record += 1
                used += 1
                progress += 1
              }
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          } else {
            state.input += 1
            state.record = 0
          }
        } else {
          if !begin_mean_sort(state, state.nodes.length()) {
            return @bounded.Failed(MeanWorkspaceLimit, progress, used)
          }
          state.phase = SortNodes
        }
      SortNodes =>
        if state.sort_width >= state.nodes.length() {
          if state.nodes.length() > 1 {
            release_mean_slots(state, state.nodes.length())
          }
          state.node_sort_buffer.clear()
          state.phase = BeginNodeSupport
          state.candidate = 0
        } else if state.sort_left >= state.nodes.length() {
          state.phase = CopyNodes
          state.sort_copy_at = 0
        } else {
          if state.sort_middle < 0 {
            begin_mean_merge(state, state.nodes.length())
          }
          if state.sort_left_at < state.sort_middle &&
            state.sort_right_at < state.sort_right {
            match
              compare_mean_nodes(
                state.nodes[state.sort_left_at],
                state.nodes[state.sort_right_at],
              ) {
              Ok(order) => {
                if order <= 0 {
                  state.node_sort_buffer.push(state.nodes[state.sort_left_at])
                  state.sort_left_at += 1
                } else {
                  state.node_sort_buffer.push(state.nodes[state.sort_right_at])
                  state.sort_right_at += 1
                }
                used += 1
                progress += 1
              }
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          } else if state.sort_left_at < state.sort_middle {
            state.node_sort_buffer.push(state.nodes[state.sort_left_at])
            state.sort_left_at += 1
            used += 1
            progress += 1
          } else if state.sort_right_at < state.sort_right {
            state.node_sort_buffer.push(state.nodes[state.sort_right_at])
            state.sort_right_at += 1
            used += 1
            progress += 1
          } else {
            state.sort_left = state.sort_right
            state.sort_middle = -1
          }
        }
      CopyNodes =>
        if state.sort_copy_at < state.nodes.length() {
          state.nodes[state.sort_copy_at] = state.node_sort_buffer[state.sort_copy_at]
          state.sort_copy_at += 1
          used += 1
          progress += 1
        } else {
          state.node_sort_buffer.clear()
          finish_mean_sort_pass(state, state.nodes.length())
          state.phase = SortNodes
        }
      BeginNodeSupport =>
        if state.candidate < state.nodes.length() {
          match begin_mean_support(state) {
            Ok(_) => state.phase = AddNodeSupport
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = CollectEdges
          state.input = 0
          state.record = 0
        }
      AddNodeSupport =>
        if state.sample < state.inputs.length() {
          match add_node_support(state) {
            Ok(_) => {
              state.sample += 1
              used += 1
              progress += 1
            }
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          let retained = match finish_mean_support(state, @graph_type.Nodes) {
            Ok(value) => value
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
          if retained {
            state.retain_candidate = true
            state.property = 0
            state.properties.clear()
            state.phase = BeginNodeProperties
          } else {
            state.candidate += 1
            state.phase = BeginNodeSupport
          }
        }
      BeginNodeProperties =>
        if state.property <
          @lower.graph_mean_property_count(state.prepared, @graph_type.Nodes) {
          match begin_mean_property(state, @graph_type.Nodes) {
            Ok(_) => state.phase = AddNodeProperty
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = EmitNode
        }
      AddNodeProperty =>
        if state.sample < state.inputs.length() {
          match add_node_property(state) {
            Ok(_) => {
              state.sample += 1
              used += 1
              progress += 1
            }
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = FinishNodeProperty
        }
      FinishNodeProperty =>
        match finish_mean_property(state, @graph_type.Nodes) {
          Ok(_) => {
            state.property += 1
            state.phase = BeginNodeProperties
            used += 1
            progress += 1
          }
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      EmitNode => {
        if !state.retain_candidate {
          return @bounded.Failed(InvalidMeanKernel, progress, used)
        }
        let identity = state.nodes[state.candidate]
        let key = match mean_value_key(state, identity) {
          Ok(value) => value
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidMeanKernel, progress, used)
        }
        match @graph.append_node(output, identity, state.properties) {
          Ok(_) => state.retained_nodes[key] = true
          Err(issue) =>
            return @bounded.Failed(MeanOutput(issue), progress, used)
        }
        state.retain_candidate = false
        state.properties.clear()
        state.candidate += 1
        state.phase = BeginNodeSupport
        used += 1
        progress += 1
      }
      CollectEdges =>
        if state.input < state.inputs.length() {
          let count = @lifecycle.producer_view_edge_count(
            state.inputs[state.input],
          ).unwrap()
          if state.record < count {
            match collect_mean_edge(state) {
              Ok(_) => {
                state.record += 1
                used += 1
                progress += 1
              }
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          } else {
            state.input += 1
            state.record = 0
          }
        } else {
          if !begin_mean_sort(state, state.edges.length()) {
            return @bounded.Failed(MeanWorkspaceLimit, progress, used)
          }
          state.phase = SortEdges
        }
      SortEdges =>
        if state.sort_width >= state.edges.length() {
          if state.edges.length() > 1 {
            release_mean_slots(state, state.edges.length())
          }
          state.edge_sort_buffer.clear()
          state.phase = BeginEdgeSupport
          state.candidate = 0
        } else if state.sort_left >= state.edges.length() {
          state.phase = CopyEdges
          state.sort_copy_at = 0
        } else {
          if state.sort_middle < 0 {
            begin_mean_merge(state, state.edges.length())
          }
          if state.sort_left_at < state.sort_middle &&
            state.sort_right_at < state.sort_right {
            match
              compare_mean_edges(
                state.edges[state.sort_left_at],
                state.edges[state.sort_right_at],
              ) {
              Ok(order) => {
                if order <= 0 {
                  state.edge_sort_buffer.push(state.edges[state.sort_left_at])
                  state.sort_left_at += 1
                } else {
                  state.edge_sort_buffer.push(state.edges[state.sort_right_at])
                  state.sort_right_at += 1
                }
                used += 1
                progress += 1
              }
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          } else if state.sort_left_at < state.sort_middle {
            state.edge_sort_buffer.push(state.edges[state.sort_left_at])
            state.sort_left_at += 1
            used += 1
            progress += 1
          } else if state.sort_right_at < state.sort_right {
            state.edge_sort_buffer.push(state.edges[state.sort_right_at])
            state.sort_right_at += 1
            used += 1
            progress += 1
          } else {
            state.sort_left = state.sort_right
            state.sort_middle = -1
          }
        }
      CopyEdges =>
        if state.sort_copy_at < state.edges.length() {
          state.edges[state.sort_copy_at] = state.edge_sort_buffer[state.sort_copy_at]
          state.sort_copy_at += 1
          used += 1
          progress += 1
        } else {
          state.edge_sort_buffer.clear()
          finish_mean_sort_pass(state, state.edges.length())
          state.phase = SortEdges
        }
      BeginEdgeSupport =>
        if state.candidate < state.edges.length() {
          match begin_mean_support(state) {
            Ok(_) => state.phase = AddEdgeSupport
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = FinishMean
        }
      AddEdgeSupport =>
        if state.sample < state.inputs.length() {
          match add_edge_support(state) {
            Ok(_) => {
              state.sample += 1
              used += 1
              progress += 1
            }
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          let retained = match finish_mean_support(state, @graph_type.Edges) {
            Ok(value) => value
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
          if retained {
            let edge = state.edges[state.candidate]
            let source_key = match mean_value_key(state, edge.source) {
              Ok(value) => value
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
            let target_key = match mean_value_key(state, edge.target) {
              Ok(value) => value
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
            if state.retained_nodes.contains(source_key) &&
              state.retained_nodes.contains(target_key) {
              state.retain_candidate = true
              state.property = 0
              state.properties.clear()
              state.phase = BeginEdgeProperties
            } else {
              state.candidate += 1
              state.phase = BeginEdgeSupport
            }
          } else {
            state.candidate += 1
            state.phase = BeginEdgeSupport
          }
        }
      BeginEdgeProperties =>
        if state.property <
          @lower.graph_mean_property_count(state.prepared, @graph_type.Edges) {
          match begin_mean_property(state, @graph_type.Edges) {
            Ok(_) => state.phase = AddEdgeProperty
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = EmitEdge
        }
      AddEdgeProperty =>
        if state.sample < state.inputs.length() {
          match add_edge_property(state) {
            Ok(_) => {
              state.sample += 1
              used += 1
              progress += 1
            }
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = FinishEdgeProperty
        }
      FinishEdgeProperty =>
        match finish_mean_property(state, @graph_type.Edges) {
          Ok(_) => {
            state.property += 1
            state.phase = BeginEdgeProperties
            used += 1
            progress += 1
          }
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      EmitEdge => {
        if !state.retain_candidate {
          return @bounded.Failed(InvalidMeanKernel, progress, used)
        }
        let edge = state.edges[state.candidate]
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidMeanKernel, progress, used)
        }
        match
          @graph.append_edge(
            output,
            edge.source,
            edge.target,
            edge.label,
            state.properties,
          ) {
          Ok(_) => ()
          Err(issue) =>
            return @bounded.Failed(MeanOutput(issue), progress, used)
        }
        state.retain_candidate = false
        state.properties.clear()
        state.candidate += 1
        state.phase = BeginEdgeSupport
        used += 1
        progress += 1
      }
      FinishMean => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidMeanKernel, progress, used)
        }
        state.output = None
        @exact.cancel_weight_sum(state.total) |> ignore
        return match @graph.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(MeanOutput(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_mean_state(state : MeanState) -> Bool {
  if state.support is Some(support) {
    @exact.cancel_weight_sum(support) |> ignore
    state.support = None
  }
  if state.mean is Some(mean) {
    @exact.cancel_weighted_mean(mean) |> ignore
    state.mean = None
  }
  @exact.cancel_weight_sum(state.total) |> ignore
  state.node_keys.clear()
  state.nodes.clear()
  state.node_sort_buffer.clear()
  state.retained_nodes.clear()
  state.edge_keys.clear()
  state.edges.clear()
  state.edge_sort_buffer.clear()
  state.properties.clear()
  state.workspace_slots = 0
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  true
}

///|
pub fn start_mean_views(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@lifecycle.ProducerView],
  limits : @storage.Limits,
  storage_bytes : Int64,
  exact_bits : Int,
  available : () -> Bool,
) -> Result[MeanExecution, MeanIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphMeanStep(prepared)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "SGA.mean_structural" &&
    @lower.graph_mean_input_count(prepared) == inputs.length() &&
    inputs.length() > 0 else {
    return Err(InvalidMeanKernel)
  }
  if exact_bits < 1 ||
    limits.max_workspace_slots < 0 ||
    limits.max_value_nodes < 0 ||
    limits.max_value_nodes > (2147483647 - 1) / 2 ||
    limits.max_value_bytes < 0 ||
    limits.max_value_bytes > (2147483647 - 32) / 2 {
    return Err(InvalidMeanLimits)
  }
  for index, input in inputs {
    if @lifecycle.producer_view_kind(input) != @carrier.GraphKind ||
      !@lifecycle.producer_read_reference_matches_operation_input(
        @lifecycle.producer_view_read_reference(input),
        owner,
        step,
        index,
      ) ||
      @lifecycle.producer_view_node_count(input) is None ||
      @lifecycle.producer_view_edge_count(input) is None {
      return Err(MeanInputUnavailable)
    }
  }
  guard @lower.preparation_carrier_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(@carrier.GraphValue(graph)) else {
    return Err(InvalidMeanKernel)
  }
  let property_slots = Int::max(
    @lower.graph_mean_property_count(prepared, @graph_type.Nodes),
    @lower.graph_mean_property_count(prepared, @graph_type.Edges),
  )
  if inputs.length() > limits.max_workspace_slots ||
    property_slots > limits.max_workspace_slots - inputs.length() {
    return Err(MeanWorkspaceLimit)
  }
  let initial_workspace_slots = inputs.length() + property_slots
  let weights = []
  for index in 0..<inputs.length() {
    guard @lower.graph_mean_weight(prepared, index) is Some(weight) else {
      return Err(InvalidMeanKernel)
    }
    weights.push(weight)
  }
  let total = match @exact.prepare_weight_sum(exact_bits) {
    Ok(value) => value
    Err(issue) => return Err(MeanNumeric(issue))
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
    Err(issue) => {
      @exact.cancel_weight_sum(total) |> ignore
      return Err(MeanOutput(issue))
    }
  }
  let state : MeanState = {
    prepared,
    graph,
    inputs,
    weights,
    total,
    exact_bits,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    max_workspace_slots: limits.max_workspace_slots,
    workspace_slots: initial_workspace_slots,
    output: Some(output),
    node_keys: Map([]),
    nodes: [],
    node_sort_buffer: [],
    retained_nodes: Map([]),
    edge_keys: Map([]),
    edges: [],
    edge_sort_buffer: [],
    support: None,
    properties: [],
    property: 0,
    exact_key: None,
    exact_value: None,
    mean: None,
    phase: AddTotalWeight,
    input: 0,
    record: 0,
    candidate: 0,
    retain_candidate: false,
    sample: 0,
    sort_width: 0,
    sort_left: 0,
    sort_middle: -1,
    sort_right: 0,
    sort_left_at: 0,
    sort_right_at: 0,
    sort_copy_at: 0,
  }
  let (session, token) = @bounded.start(
    control, state, advance_mean_state, cleanup_mean_state, @graph.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes * 2 + 1,
    max_noninterruptible_value_bytes: limits.max_value_bytes * 2 + 32,
  })
}

///|
pub fn mean_max_noninterruptible_value_nodes(value : MeanExecution) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn mean_max_noninterruptible_value_bytes(value : MeanExecution) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn advance_mean(
  value : MeanExecution,
  quantum : Int,
) -> Result[MeanPoll, MeanIssue] {
  guard value.token is Some(token) else {
    return Err(MeanExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(MeanExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(MeanContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(MeanComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(MeanFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(MeanStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn mean_stopped(value : MeanExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn mean_cleanup_pending(value : MeanExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_mean(value : MeanExecution) -> Result[Bool, MeanIssue] {
  @bounded.cleanup(value.session).map_err(issue => MeanExecutionIssue(issue))
}
