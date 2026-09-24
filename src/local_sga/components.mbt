///|
priv enum ComponentsPhase {
  InitializeNodes
  FinishOffsets
  ScanDegrees
  BuildOffsets
  InitializeEdges
  CopyCursors
  FillEdges
  StartFirstPass
  WalkFirstPass
  ResetVisited
  StartComponent
  WalkComponent
  CompareMinimum
  PrepareSort
  PrepareMerge
  Merge
  CompareMerge
  CopyPass
  SelectRow
  ReadField
  CommitRow
  Finish
}

///|
priv struct ComponentsState {
  input : @graph.ProducerRead
  source : @storage.Storage
  schema : @schema.Schema
  value_limits : @value.Limits
  strong : Bool
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : ComponentsPhase
  mut index : Int
  mut component_index : Int
  mut active_component : Int
  out_degree : Array[Int]
  in_degree : Array[Int]
  out_start : Array[Int]
  in_start : Array[Int]
  out_cursor : Array[Int]
  in_cursor : Array[Int]
  out_edges : Array[Int]
  in_edges : Array[Int]
  visited : Array[Bool]
  component : Array[Int]
  component_size : Array[Int]
  component_min : Array[Int]
  finish_order : Array[Int]
  stack_nodes : Array[Int]
  stack_positions : Array[Int]
  selected : Array[Int]
  scratch : Array[Int?]
  mut width : Int
  mut run_start : Int
  mut middle : Int
  mut run_end : Int
  mut left_index : Int
  mut right_index : Int
  mut merge_index : Int
  mut key_component : Int
  mut key_comparison : @value.BoundedKeyComparison?
  mut pending_node : Int
  mut pending_component : Int
  mut copy_index : Int
  mut candidate : Int
  mut column : Int
  mut values : Array[@value.CheckedValue]
  mut control_work_remaining : Int
}

///|
struct ComponentsExecution {
  session : @bounded.Session[
    ComponentsState,
    @execution.CompletedOutput,
    ComponentsIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum ComponentsPoll {
  ComponentsContinue(progress~ : Int64, work~ : Int64)
  ComponentsComplete(
    @execution.CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  ComponentsFailed(ComponentsIssue, progress~ : Int64, work~ : Int64)
  ComponentsStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum ComponentsIssue {
  InvalidComponentsKernel
  ComponentsInputUnavailable
  ComponentsOutputLimit
  ComponentsWorkspaceLimit
  ComponentsWorkLimit
  ComponentsKeyOrder(@value.KeyOrderIssue)
  ComponentsOutput(@execution.CaptureIssue)
  ComponentsCompletion(@execution.TrustedOutputIssue)
  ComponentsExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn checked_components_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn checked_components_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn components_workspace(nodes : Int, edges : Int, width : Int) -> Int? {
  guard checked_components_multiply(nodes, 15) is Some(node_slots) &&
    checked_components_multiply(edges, 2) is Some(edge_slots) &&
    checked_components_add(node_slots, edge_slots) is Some(graph_slots) &&
    checked_components_add(graph_slots, width) is Some(value_slots) &&
    checked_components_add(value_slots, 2) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn capped_components_run_end(start : Int, width : Int, count : Int) -> Int {
  if start > count - Int::min(width, count) {
    count
  } else {
    Int::min(start + width, count)
  }
}

///|
fn compare_component_nodes_step(
  state : ComponentsState,
  left : Int,
  right : Int,
) -> Result[Int?, ComponentsIssue] {
  guard state.component.get(left) is Some(left_component) &&
    state.component.get(right) is Some(right_component) &&
    state.component_min.get(left_component) is Some(left_min) &&
    state.component_min.get(right_component) is Some(right_min) &&
    @storage.node_identity(state.source, left_min) is Some(left_component_id) &&
    @storage.node_identity(state.source, right_min) is Some(right_component_id) else {
    return Err(ComponentsInputUnavailable)
  }
  let comparison = match state.key_comparison {
    Some(value) => value
    None => {
      let (a, b) = if state.key_component == 0 {
        (left_component_id, right_component_id)
      } else {
        guard @storage.node_identity(state.source, left) is Some(left_id) &&
          @storage.node_identity(state.source, right) is Some(right_id) else {
          return Err(ComponentsInputUnavailable)
        }
        (left_id, right_id)
      }
      let value = match @value.start_bounded_key_comparison(a, b) {
        Ok(value) => value
        Err(issue) => return Err(ComponentsKeyOrder(issue))
      }
      state.key_comparison = Some(value)
      value
    }
  }
  match @value.advance_bounded_key_comparison(comparison, 1) {
    Ok(@value.KeyComparisonContinue(_)) => Ok(None)
    Ok(@value.KeyComparisonComplete(order~, ..)) => {
      state.key_comparison = None
      if order == 0 && state.key_component == 0 {
        state.key_component = 1
        Ok(None)
      } else {
        state.key_component = 0
        Ok(Some(order))
      }
    }
    Err(issue) => {
      state.key_comparison = None
      state.key_component = 0
      Err(ComponentsKeyOrder(issue))
    }
  }
}

///|
fn prepare_components_merge(state : ComponentsState) -> Unit {
  state.middle = capped_components_run_end(
    state.run_start,
    state.width,
    state.selected.length(),
  )
  state.run_end = capped_components_run_end(
    state.middle,
    state.width,
    state.selected.length(),
  )
  state.left_index = state.run_start
  state.right_index = state.middle
  state.merge_index = state.run_start
  state.phase = Merge
}

///|
fn emit_components_merge(state : ComponentsState, take_left : Bool) -> Unit {
  let selected = if take_left {
    let value = state.selected[state.left_index]
    state.left_index += 1
    value
  } else {
    let value = state.selected[state.right_index]
    state.right_index += 1
    value
  }
  state.scratch[state.merge_index] = Some(selected)
  state.merge_index += 1
  if state.merge_index >= state.run_end {
    state.run_start = state.run_end
    state.phase = PrepareMerge
  } else {
    state.phase = Merge
  }
}

///|
fn merge_components(state : ComponentsState) -> Unit {
  if state.left_index >= state.middle {
    emit_components_merge(state, false)
  } else if state.right_index >= state.run_end {
    emit_components_merge(state, true)
  } else {
    state.phase = CompareMerge
  }
}

///|
fn finish_component_node(
  state : ComponentsState,
  node : Int,
  component : Int,
  new_minimum : Bool,
) -> Result[Unit, ComponentsIssue] {
  guard state.component.get(node) is Some(existing) && existing < 0 else {
    return Err(InvalidComponentsKernel)
  }
  state.component[node] = component
  state.component_size[component] += 1
  if new_minimum {
    state.component_min[component] = node
  }
  state.stack_nodes.push(node)
  state.stack_positions.push(0)
  Ok(())
}

///|
fn push_component_node_step(
  state : ComponentsState,
  node : Int,
  component : Int,
) -> Result[Unit, ComponentsIssue] {
  guard state.component.get(node) is Some(existing) &&
    existing < 0 &&
    state.component_min.get(component) is Some(minimum) else {
    return Err(InvalidComponentsKernel)
  }
  if minimum < 0 {
    match finish_component_node(state, node, component, true) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    state.phase = WalkComponent
    return Ok(())
  }
  guard @storage.node_identity(state.source, node) is Some(node_id) &&
    @storage.node_identity(state.source, minimum) is Some(minimum_id) else {
    return Err(ComponentsInputUnavailable)
  }
  let comparison = match
    @value.start_bounded_key_comparison(node_id, minimum_id) {
    Ok(value) => value
    Err(issue) => return Err(ComponentsKeyOrder(issue))
  }
  match @value.advance_bounded_key_comparison(comparison, 1) {
    Ok(@value.KeyComparisonComplete(order~, ..)) => {
      match finish_component_node(state, node, component, order < 0) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      state.phase = WalkComponent
    }
    Ok(@value.KeyComparisonContinue(_)) => {
      state.key_comparison = Some(comparison)
      state.pending_node = node
      state.pending_component = component
      state.phase = CompareMinimum
    }
    Err(issue) => return Err(ComponentsKeyOrder(issue))
  }
  Ok(())
}

///|
fn first_pass_neighbor(
  state : ComponentsState,
  node : Int,
  offset : Int,
) -> Int? {
  let start = state.out_start[node]
  let end = state.out_start[node + 1]
  if offset < end - start {
    state.out_edges.get(start + offset)
  } else {
    None
  }
}

///|
fn component_neighbor(
  state : ComponentsState,
  node : Int,
  offset : Int,
) -> Int? {
  let incoming_start = state.in_start[node]
  let incoming_end = state.in_start[node + 1]
  if state.strong {
    if offset < incoming_end - incoming_start {
      state.in_edges.get(incoming_start + offset)
    } else {
      None
    }
  } else {
    let outgoing_start = state.out_start[node]
    let outgoing_end = state.out_start[node + 1]
    let outgoing_count = outgoing_end - outgoing_start
    if offset < outgoing_count {
      state.out_edges.get(outgoing_start + offset)
    } else if offset - outgoing_count < incoming_end - incoming_start {
      state.in_edges.get(incoming_start + offset - outgoing_count)
    } else {
      None
    }
  }
}

///|
fn checked_component_value(
  state : ComponentsState,
  field : @schema.Field,
  node : Int,
) -> @value.CheckedValue? {
  guard state.component.get(node) is Some(component) &&
    state.component_min.get(component) is Some(minimum) &&
    state.component_size.get(component) is Some(size) else {
    return None
  }
  match field.name {
    @schema.Unqualified("node_id") =>
      @storage.node_identity(state.source, node).bind(value => {
        @value.recheck_runtime_value(
          value.value,
          field.contract,
          state.value_limits,
        )
      })
    @schema.Unqualified("component_id") =>
      @storage.node_identity(state.source, minimum).bind(value => {
        @value.recheck_runtime_value(
          value.value,
          field.contract,
          state.value_limits,
        )
      })
    @schema.Unqualified("component_size") =>
      @value.checked_number_value(size.to_double(), field.contract)
    _ => None
  }
}

///|
fn components_step(
  state : ComponentsState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, ComponentsIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@graph.producer_read_available(state.input) {
      return @bounded.Failed(ComponentsInputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(ComponentsWorkLimit, progress, used)
    }
    match state.phase {
      InitializeNodes =>
        if state.index < @storage.node_count(state.source) {
          state.out_degree.push(0)
          state.in_degree.push(0)
          state.out_start.push(0)
          state.in_start.push(0)
          state.out_cursor.push(0)
          state.in_cursor.push(0)
          state.visited.push(false)
          state.component.push(-1)
          state.component_size.push(0)
          state.component_min.push(-1)
          state.selected.push(state.index)
          state.scratch.push(None)
          state.index += 1
          used += 1
        } else {
          state.phase = FinishOffsets
        }
      FinishOffsets => {
        state.out_start.push(0)
        state.in_start.push(0)
        state.index = 0
        state.phase = ScanDegrees
        used += 1
      }
      ScanDegrees =>
        if state.index < @storage.edge_count(state.source) {
          guard @storage.edge_endpoints(state.source, state.index)
            is Some((source, target)) &&
            state.out_degree.get(source) is Some(outgoing) &&
            state.in_degree.get(target) is Some(incoming) else {
            return @bounded.Failed(ComponentsInputUnavailable, progress, used)
          }
          state.out_degree[source] = outgoing + 1
          state.in_degree[target] = incoming + 1
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = BuildOffsets
        }
      BuildOffsets =>
        if state.index < @storage.node_count(state.source) {
          state.out_start[state.index + 1] = state.out_start[state.index] +
            state.out_degree[state.index]
          state.in_start[state.index + 1] = state.in_start[state.index] +
            state.in_degree[state.index]
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = InitializeEdges
        }
      InitializeEdges =>
        if state.index < @storage.edge_count(state.source) {
          state.out_edges.push(-1)
          state.in_edges.push(-1)
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = CopyCursors
        }
      CopyCursors =>
        if state.index < @storage.node_count(state.source) {
          state.out_cursor[state.index] = state.out_start[state.index]
          state.in_cursor[state.index] = state.in_start[state.index]
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = FillEdges
        }
      FillEdges =>
        if state.index < @storage.edge_count(state.source) {
          guard @storage.edge_endpoints(state.source, state.index)
            is Some((source, target)) else {
            return @bounded.Failed(ComponentsInputUnavailable, progress, used)
          }
          let out = state.out_cursor[source]
          let incoming = state.in_cursor[target]
          state.out_edges[out] = target
          state.in_edges[incoming] = source
          state.out_cursor[source] = out + 1
          state.in_cursor[target] = incoming + 1
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = if state.strong {
            StartFirstPass
          } else {
            StartComponent
          }
        }
      StartFirstPass =>
        if !state.stack_nodes.is_empty() {
          state.phase = WalkFirstPass
        } else if state.index >= @storage.node_count(state.source) {
          state.index = 0
          state.phase = ResetVisited
        } else {
          let node = state.index
          state.index += 1
          used += 1
          if !state.visited[node] {
            state.visited[node] = true
            state.stack_nodes.push(node)
            state.stack_positions.push(0)
            state.phase = WalkFirstPass
          }
        }
      WalkFirstPass => {
        guard !state.stack_nodes.is_empty() && !state.stack_positions.is_empty() else {
          return @bounded.Failed(InvalidComponentsKernel, progress, used)
        }
        let top = state.stack_nodes.length() - 1
        let node = state.stack_nodes[top]
        let offset = state.stack_positions[top]
        match first_pass_neighbor(state, node, offset) {
          Some(neighbor) => {
            state.stack_positions[top] = offset + 1
            if !state.visited[neighbor] {
              state.visited[neighbor] = true
              state.stack_nodes.push(neighbor)
              state.stack_positions.push(0)
            }
          }
          None => {
            ignore(state.stack_nodes.pop())
            ignore(state.stack_positions.pop())
            state.finish_order.push(node)
            if state.stack_nodes.is_empty() {
              state.phase = StartFirstPass
            }
          }
        }
        used += 1
      }
      ResetVisited =>
        if state.index < state.visited.length() {
          state.visited[state.index] = false
          state.index += 1
          used += 1
        } else {
          state.index = if state.strong {
            state.finish_order.length() - 1
          } else {
            0
          }
          state.phase = StartComponent
        }
      StartComponent =>
        if !state.stack_nodes.is_empty() {
          state.phase = WalkComponent
        } else if state.strong && state.index < 0 {
          state.width = 1
          state.phase = PrepareSort
        } else if !state.strong &&
          state.index >= @storage.node_count(state.source) {
          state.width = 1
          state.phase = PrepareSort
        } else {
          let node = if state.strong {
            state.finish_order[state.index]
          } else {
            state.index
          }
          if state.strong {
            state.index -= 1
          } else {
            state.index += 1
          }
          used += 1
          if state.component[node] < 0 {
            let component = state.component_index
            state.component_index += 1
            state.active_component = component
            match push_component_node_step(state, node, component) {
              Err(issue) => return @bounded.Failed(issue, progress, used)
              Ok(_) => ()
            }
          }
        }
      WalkComponent => {
        guard !state.stack_nodes.is_empty() && !state.stack_positions.is_empty() else {
          return @bounded.Failed(InvalidComponentsKernel, progress, used)
        }
        let top = state.stack_nodes.length() - 1
        let node = state.stack_nodes[top]
        let offset = state.stack_positions[top]
        match component_neighbor(state, node, offset) {
          Some(neighbor) => {
            state.stack_positions[top] = offset + 1
            if state.component[neighbor] < 0 {
              match
                push_component_node_step(
                  state,
                  neighbor,
                  state.active_component,
                ) {
                Err(issue) => return @bounded.Failed(issue, progress, used)
                Ok(_) => ()
              }
            }
          }
          None => {
            ignore(state.stack_nodes.pop())
            ignore(state.stack_positions.pop())
            if state.stack_nodes.is_empty() {
              state.phase = StartComponent
            }
          }
        }
        used += 1
      }
      CompareMinimum => {
        used += 1
        guard state.key_comparison is Some(comparison) &&
          state.pending_node >= 0 &&
          state.pending_component >= 0 else {
          return @bounded.Failed(InvalidComponentsKernel, progress, used)
        }
        match @value.advance_bounded_key_comparison(comparison, 1) {
          Ok(@value.KeyComparisonContinue(_)) => ()
          Ok(@value.KeyComparisonComplete(order~, ..)) => {
            state.key_comparison = None
            match
              finish_component_node(
                state,
                state.pending_node,
                state.pending_component,
                order < 0,
              ) {
              Err(issue) => return @bounded.Failed(issue, progress, used)
              Ok(_) => ()
            }
            state.pending_node = -1
            state.pending_component = -1
            state.phase = WalkComponent
          }
          Err(issue) =>
            return @bounded.Failed(ComponentsKeyOrder(issue), progress, used)
        }
      }
      PrepareSort =>
        if state.width >= state.selected.length() {
          state.candidate = 0
          state.phase = SelectRow
        } else {
          state.run_start = 0
          state.phase = PrepareMerge
        }
      PrepareMerge =>
        if state.run_start >= state.selected.length() {
          state.copy_index = 0
          state.phase = CopyPass
        } else {
          prepare_components_merge(state)
        }
      Merge => {
        merge_components(state)
        used += 1
      }
      CompareMerge => {
        used += 1
        match
          compare_component_nodes_step(
            state,
            state.selected[state.left_index],
            state.selected[state.right_index],
          ) {
          Ok(Some(comparison)) => emit_components_merge(state, comparison <= 0)
          Ok(None) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyPass =>
        if state.copy_index < state.selected.length() {
          guard state.scratch[state.copy_index] is Some(node) else {
            return @bounded.Failed(InvalidComponentsKernel, progress, used)
          }
          state.selected[state.copy_index] = node
          state.scratch[state.copy_index] = None
          state.copy_index += 1
          used += 1
        } else {
          state.width = if state.width > state.selected.length() / 2 {
            state.selected.length()
          } else {
            state.width * 2
          }
          state.phase = PrepareSort
        }
      SelectRow =>
        if state.candidate >= state.selected.length() {
          state.phase = Finish
        } else {
          state.column = 0
          state.values = []
          state.phase = ReadField
        }
      ReadField =>
        if state.column < @schema.field_count(state.schema) {
          used += 1
          let node = state.selected[state.candidate]
          guard @schema.field_at(state.schema, state.column) is Some(field) &&
            checked_component_value(state, field, node) is Some(value) else {
            return @bounded.Failed(InvalidComponentsKernel, progress, used)
          }
          state.values.push(value)
          state.column += 1
        } else {
          state.phase = CommitRow
        }
      CommitRow => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidComponentsKernel, progress, used)
        }
        match @execution.append_admitted_output(output, state.values) {
          Ok(_) => {
            state.values = []
            state.candidate += 1
            state.phase = SelectRow
            progress += 1
          }
          Err(issue) =>
            return @bounded.Failed(ComponentsOutput(issue), progress, used)
        }
      }
      Finish => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidComponentsKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(ComponentsOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(ComponentsCompletion(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_components_state(state : ComponentsState) -> Bool {
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  state.out_degree.clear()
  state.in_degree.clear()
  state.out_start.clear()
  state.in_start.clear()
  state.out_cursor.clear()
  state.in_cursor.clear()
  state.out_edges.clear()
  state.in_edges.clear()
  state.visited.clear()
  state.component.clear()
  state.component_size.clear()
  state.component_min.clear()
  state.finish_order.clear()
  state.stack_nodes.clear()
  state.stack_positions.clear()
  state.selected.clear()
  state.scratch.clear()
  state.key_component = 0
  state.key_comparison = None
  state.pending_node = -1
  state.pending_component = -1
  state.values = []
  true
}

///|
pub fn start_components(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @graph.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[ComponentsExecution, ComponentsIssue] {
  let owner = @lower.sequence_owner(sequence)
  let control_work_limit = control_work_limit.unwrap_or(limits.max_work)
  if control_work_limit < 0 {
    return Err(ComponentsWorkLimit)
  }
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphBasicStep(prepared)) &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) &&
    @graph.producer_read_storage(input) is Some(source) else {
    return Err(InvalidComponentsKernel)
  }
  let kind = @lower.graph_basic_kind(prepared)
  guard kind == @lower.ComponentsWeakBasic ||
    kind == @lower.ComponentsStrongBasic else {
    return Err(InvalidComponentsKernel)
  }
  let nodes = @storage.node_count(source)
  let edges = @storage.edge_count(source)
  let schema = @lower.graph_basic_output_schema(prepared)
  let width = @schema.field_count(schema)
  guard max_rows >= 0 && nodes <= max_rows else {
    return Err(ComponentsOutputLimit)
  }
  if @lower.graph_basic_component_max_output_rows(prepared) is Some(authored) &&
    nodes.to_int64() > authored {
    return Err(ComponentsOutputLimit)
  }
  guard components_workspace(nodes, edges, width) is Some(workspace) &&
    workspace <= max_workspace_slots else {
    return Err(ComponentsWorkspaceLimit)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ComponentsOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    @execution.prepare_trusted_output_port(
      preparation,
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs~,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(ComponentsCompletion(issue))
    }
  }
  let state : ComponentsState = {
    input,
    source,
    schema,
    value_limits: {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_text_bytes,
    },
    strong: kind == @lower.ComponentsStrongBasic,
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    phase: InitializeNodes,
    index: 0,
    component_index: 0,
    active_component: -1,
    out_degree: [],
    in_degree: [],
    out_start: [],
    in_start: [],
    out_cursor: [],
    in_cursor: [],
    out_edges: [],
    in_edges: [],
    visited: [],
    component: [],
    component_size: [],
    component_min: [],
    finish_order: [],
    stack_nodes: [],
    stack_positions: [],
    selected: [],
    scratch: [],
    width: 1,
    run_start: 0,
    middle: 0,
    run_end: 0,
    left_index: 0,
    right_index: 0,
    merge_index: 0,
    key_component: 0,
    key_comparison: None,
    pending_node: -1,
    pending_component: -1,
    copy_index: 0,
    candidate: 0,
    column: 0,
    values: [],
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    components_step,
    cleanup_components_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({
    session,
    token: Some(token),
    accepted,
    max_noninterruptible_value_nodes: limits.max_nodes,
    max_noninterruptible_value_bytes: limits.max_text_bytes,
  })
}

///|
pub fn components_max_noninterruptible_value_nodes(
  value : ComponentsExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn components_max_noninterruptible_value_bytes(
  value : ComponentsExecution,
) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn advance_components(
  value : ComponentsExecution,
  quantum : Int,
) -> Result[ComponentsPoll, ComponentsIssue] {
  guard value.token is Some(token) else {
    return Err(ComponentsExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(ComponentsExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(ComponentsContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(ComponentsComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(ComponentsFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(ComponentsStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn components_cleanup_pending(value : ComponentsExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_components(
  value : ComponentsExecution,
) -> Result[Bool, ComponentsIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    ComponentsExecutionIssue(issue)
  })
}
