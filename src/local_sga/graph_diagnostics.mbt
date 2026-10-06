///|
priv enum GraphBoundsPhase {
  InitializeNodes
  ScanEdges
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
priv struct GraphBoundsState {
  source : GraphReadSource
  node_count : Int
  edge_count : Int
  schema : @schema.Schema
  value_limits : @value.Limits
  operation : @lower.GraphDiagnosticKind
  node_limit : Int64?
  edge_limit : Int64?
  degree_limit : Int64?
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : GraphBoundsPhase
  mut source_index : Int
  mut degrees : Array[Int64]
  mut selected : Array[Int]
  mut scratch : Array[Int?]
  mut width : Int
  mut run_start : Int
  mut middle : Int
  mut run_end : Int
  mut left_index : Int
  mut right_index : Int
  mut merge_index : Int
  mut key_comparison : @value.BoundedKeyComparison?
  mut key_name_position : Int
  mut key_name_done : Bool
  mut key_component : Int
  mut copy_index : Int
  mut candidate : Int
  mut kind : String
  mut actual : Int64
  mut maximum : Int64
  mut node : Int?
  mut column : Int
  mut values : Array[@value.CheckedValue]
  mut control_work_remaining : Int
}

///|
struct GraphBoundsExecution {
  session : @bounded.Session[
    GraphBoundsState,
    @execution.CompletedOutput,
    GraphBoundsIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
struct GraphDegreeExecution {
  inner : GraphBoundsExecution
}

///|
pub enum GraphBoundsPoll {
  GraphBoundsContinue(progress~ : Int64, work~ : Int64)
  GraphBoundsComplete(
    @execution.CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  GraphBoundsFailed(GraphBoundsIssue, progress~ : Int64, work~ : Int64)
  GraphBoundsStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub enum GraphDegreePoll {
  GraphDegreeContinue(progress~ : Int64, work~ : Int64)
  GraphDegreeComplete(
    @execution.CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  GraphDegreeFailed(GraphBoundsIssue, progress~ : Int64, work~ : Int64)
  GraphDegreeStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum GraphBoundsIssue {
  InvalidGraphBoundsKernel
  GraphBoundsInputUnavailable
  GraphBoundsWorkspaceLimit
  GraphBoundsWorkLimit
  GraphBoundsKeyOrder(@value.KeyOrderIssue)
  GraphBoundsOutput(@execution.CaptureIssue)
  GraphBoundsCompletion(@execution.TrustedOutputIssue)
  GraphBoundsExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn checked_graph_bounds_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn checked_graph_bounds_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn graph_bounds_workspace(nodes : Int, width : Int) -> Int? {
  guard checked_graph_bounds_multiply(nodes, 3) is Some(node_slots) &&
    checked_graph_bounds_add(node_slots, width) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn capped_graph_bounds_run_end(start : Int, width : Int, count : Int) -> Int {
  if start > count - Int::min(width, count) {
    count
  } else {
    Int::min(start + width, count)
  }
}

///|
fn compare_bound_nodes_step(
  state : GraphBoundsState,
  left : Int,
  right : Int,
) -> Result[Int?, GraphBoundsIssue] {
  guard graph_read_property_definition(state.source) is Some(profile) &&
    graph_read_node_definition(state.source, left) is Some(left_definition) &&
    graph_read_node_definition(state.source, right) is Some(right_definition) &&
    @carrier.graph_node_at(profile, left_definition) is Some(left_node) &&
    @carrier.graph_node_at(profile, right_definition) is Some(right_node) else {
    return Err(GraphBoundsInputUnavailable)
  }
  if !state.key_name_done {
    let (order, next) = graph_identity_compare_unit(
      @carrier.graph_element_definition_name(left_node),
      @carrier.graph_element_definition_name(right_node),
      state.key_name_position,
    )
    state.key_name_position = next
    match order {
      Some(value) if value != 0 => {
        reset_graph_bounds_comparison(state)
        return Ok(Some(value))
      }
      Some(_) => state.key_name_done = true
      None => return Ok(None)
    }
  }
  let components = @carrier.graph_element_definition_key_count(left_node)
  guard components == @carrier.graph_element_definition_key_count(right_node) else {
    return Err(GraphBoundsInputUnavailable)
  }
  if state.key_component >= components {
    reset_graph_bounds_comparison(state)
    return Ok(Some(0))
  }
  let active = match state.key_comparison {
    Some(value) => value
    None => {
      guard graph_read_node_key_component(
          state.source,
          left,
          state.key_component,
        )
        is Some(left_value) &&
        graph_read_node_key_component(state.source, right, state.key_component)
        is Some(right_value) else {
        return Err(GraphBoundsInputUnavailable)
      }
      let value = match
        @value.start_bounded_key_comparison(left_value, right_value) {
        Ok(value) => value
        Err(issue) => return Err(GraphBoundsKeyOrder(issue))
      }
      state.key_comparison = Some(value)
      value
    }
  }
  match @value.advance_bounded_key_comparison(active, 1) {
    Ok(@value.KeyComparisonContinue(_)) => Ok(None)
    Ok(@value.KeyComparisonComplete(order~, ..)) => {
      state.key_comparison = None
      if order != 0 {
        reset_graph_bounds_comparison(state)
        Ok(Some(order))
      } else {
        state.key_component += 1
        if state.key_component >= components {
          reset_graph_bounds_comparison(state)
          Ok(Some(0))
        } else {
          Ok(None)
        }
      }
    }
    Err(issue) => {
      reset_graph_bounds_comparison(state)
      Err(GraphBoundsKeyOrder(issue))
    }
  }
}

///|
fn reset_graph_bounds_comparison(state : GraphBoundsState) -> Unit {
  state.key_comparison = None
  state.key_name_position = 0
  state.key_name_done = false
  state.key_component = 0
}

///|
fn prepare_graph_bounds_merge(state : GraphBoundsState) -> Unit {
  state.middle = capped_graph_bounds_run_end(
    state.run_start,
    state.width,
    state.selected.length(),
  )
  state.run_end = capped_graph_bounds_run_end(
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
fn emit_graph_bounds_merge(state : GraphBoundsState, take_left : Bool) -> Unit {
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
fn merge_graph_bounds(state : GraphBoundsState) -> Unit {
  if state.left_index >= state.middle {
    emit_graph_bounds_merge(state, false)
  } else if state.right_index >= state.run_end {
    emit_graph_bounds_merge(state, true)
  } else {
    state.phase = CompareMerge
  }
}

///|
fn checked_graph_bounds_value(
  state : GraphBoundsState,
  field : @schema.Field,
) -> @value.CheckedValue? {
  match field.name {
    @schema.Unqualified("degree") =>
      @value.checked_number_value(state.actual.to_double(), field.contract)
    @schema.Unqualified("actual") =>
      @value.checked_number_value(state.actual.to_double(), field.contract)
    @schema.Unqualified("kind") =>
      @value.checked_text_value(state.kind, field.contract)
    @schema.Unqualified("max") =>
      @value.checked_number_value(state.maximum.to_double(), field.contract)
    @schema.Unqualified("node_id") =>
      match state.node {
        Some(node) =>
          graph_read_node_identity(state.source, node).bind(value => {
            @value.recheck_runtime_value(
              value.value,
              field.contract,
              state.value_limits,
            )
          })
        None => @value.checked_null_value(field.contract)
      }
    @schema.Unqualified("node") =>
      match state.node {
        Some(node) =>
          graph_read_node_identity(state.source, node).bind(value => {
            @value.recheck_runtime_value(
              value.value,
              field.contract,
              state.value_limits,
            )
          })
        None => None
      }
    _ => None
  }
}

///|
fn select_graph_bounds_row(state : GraphBoundsState) -> Bool {
  let candidate = state.candidate
  state.candidate += 1
  if state.operation != @lower.BoundsDiagnostic {
    let node = state.selected[candidate]
    state.actual = state.degrees[node]
    state.node = Some(node)
    return true
  } else if candidate == 0 {
    if state.node_limit is Some(maximum) &&
      state.node_count.to_int64() > maximum {
      state.kind = "nodes"
      state.actual = state.node_count.to_int64()
      state.maximum = maximum
      state.node = None
      return true
    }
  } else if candidate == 1 {
    if state.edge_limit is Some(maximum) &&
      state.edge_count.to_int64() > maximum {
      state.kind = "edges"
      state.actual = state.edge_count.to_int64()
      state.maximum = maximum
      state.node = None
      return true
    }
  } else if state.degree_limit is Some(maximum) {
    let node = state.selected[candidate - 2]
    let actual = state.degrees[node]
    if actual > maximum {
      state.kind = "degree"
      state.actual = actual
      state.maximum = maximum
      state.node = Some(node)
      return true
    }
  }
  false
}

///|
fn graph_bounds_candidate_count(state : GraphBoundsState) -> Int {
  if state.operation == @lower.BoundsDiagnostic {
    state.selected.length() + 2
  } else {
    state.selected.length()
  }
}

///|
fn charge_graph_bounds_work(state : GraphBoundsState) -> Bool {
  match state.output {
    Some(output) => @execution.admitted_output_charge_control_work(output, 1)
    None => false
  }
}

///|
fn graph_bounds_step(
  state : GraphBoundsState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, GraphBoundsIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !graph_read_available(state.source) {
      return @bounded.Failed(GraphBoundsInputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(GraphBoundsWorkLimit, progress, used)
    }
    match state.phase {
      InitializeNodes =>
        if state.source_index < state.node_count {
          if !charge_graph_bounds_work(state) {
            return @bounded.Failed(GraphBoundsWorkLimit, progress, used)
          }
          state.degrees.push(0L)
          state.selected.push(state.source_index)
          state.scratch.push(None)
          state.source_index += 1
          used += 1
        } else {
          state.source_index = 0
          state.phase = ScanEdges
        }
      ScanEdges =>
        if state.source_index < state.edge_count {
          if !charge_graph_bounds_work(state) {
            return @bounded.Failed(GraphBoundsWorkLimit, progress, used)
          }
          guard graph_read_edge_endpoints(state.source, state.source_index)
            is Some((source, target)) &&
            state.degrees.get(source) is Some(source_degree) &&
            state.degrees.get(target) is Some(target_degree) else {
            return @bounded.Failed(GraphBoundsInputUnavailable, progress, used)
          }
          match state.operation {
            @lower.IncomingDegreeDiagnostic =>
              state.degrees[target] = target_degree + 1L
            @lower.OutgoingDegreeDiagnostic =>
              state.degrees[source] = source_degree + 1L
            _ =>
              if source == target {
                state.degrees[source] = source_degree + 2L
              } else {
                state.degrees[source] = source_degree + 1L
                state.degrees[target] = target_degree + 1L
              }
          }
          state.source_index += 1
          used += 1
        } else {
          state.width = 1
          state.phase = PrepareSort
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
          prepare_graph_bounds_merge(state)
        }
      Merge => {
        if !charge_graph_bounds_work(state) {
          return @bounded.Failed(GraphBoundsWorkLimit, progress, used)
        }
        merge_graph_bounds(state)
        used += 1
      }
      CompareMerge => {
        if !charge_graph_bounds_work(state) {
          return @bounded.Failed(GraphBoundsWorkLimit, progress, used)
        }
        used += 1
        match
          compare_bound_nodes_step(
            state,
            state.selected[state.left_index],
            state.selected[state.right_index],
          ) {
          Ok(Some(comparison)) =>
            emit_graph_bounds_merge(state, comparison <= 0)
          Ok(None) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyPass =>
        if state.copy_index < state.selected.length() {
          if !charge_graph_bounds_work(state) {
            return @bounded.Failed(GraphBoundsWorkLimit, progress, used)
          }
          guard state.scratch[state.copy_index] is Some(node) else {
            return @bounded.Failed(InvalidGraphBoundsKernel, progress, used)
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
        if state.candidate >= graph_bounds_candidate_count(state) {
          state.phase = Finish
        } else {
          if !charge_graph_bounds_work(state) {
            return @bounded.Failed(GraphBoundsWorkLimit, progress, used)
          }
          used += 1
          if select_graph_bounds_row(state) {
            state.column = 0
            state.values = []
            state.phase = ReadField
          }
        }
      ReadField =>
        if state.column < @schema.field_count(state.schema) {
          if !charge_graph_bounds_work(state) {
            return @bounded.Failed(GraphBoundsWorkLimit, progress, used)
          }
          used += 1
          guard @schema.field_at(state.schema, state.column) is Some(field) &&
            checked_graph_bounds_value(state, field) is Some(value) else {
            return @bounded.Failed(InvalidGraphBoundsKernel, progress, used)
          }
          state.values.push(value)
          state.column += 1
        } else {
          state.phase = CommitRow
        }
      CommitRow => {
        if !charge_graph_bounds_work(state) {
          return @bounded.Failed(GraphBoundsWorkLimit, progress, used)
        }
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphBoundsKernel, progress, used)
        }
        match @execution.append_admitted_output(output, state.values) {
          Ok(_) => {
            state.values = []
            state.phase = SelectRow
            progress += 1
          }
          Err(issue) =>
            return @bounded.Failed(GraphBoundsOutput(issue), progress, used)
        }
      }
      Finish => {
        if !charge_graph_bounds_work(state) {
          return @bounded.Failed(GraphBoundsWorkLimit, progress, used)
        }
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphBoundsKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(GraphBoundsOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(GraphBoundsCompletion(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_graph_bounds_state(state : GraphBoundsState) -> Bool {
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  state.degrees = []
  state.selected = []
  state.scratch = []
  state.key_comparison = None
  state.key_name_position = 0
  state.key_name_done = false
  state.key_component = 0
  state.values = []
  true
}

///|
pub fn start_graph_bounds(
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
) -> Result[GraphBoundsExecution, GraphBoundsIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphDiagnosticStep(prepared)) &&
    @lower.graph_diagnostic_kind(prepared) == @lower.BoundsDiagnostic &&
    @lower.graph_diagnostic_bounds(prepared)
    is Some((node_limit, edge_limit, degree_limit)) &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) &&
    @graph.producer_read_storage(input) is Some(_) else {
    return Err(InvalidGraphBoundsKernel)
  }
  start_graph_diagnostic(
    control,
    preparation,
    owner,
    step,
    @lower.BoundsDiagnostic,
    @lower.graph_diagnostic_output_schema(prepared),
    node_limit,
    edge_limit,
    degree_limit,
    Stored(input),
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
    control_work_limit.unwrap_or(limits.max_work),
  )
}

///|
/// Run the same bounded diagnostic over an exact managed Graph generation.
pub fn start_graph_bounds_view(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[GraphBoundsExecution, GraphBoundsIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphDiagnosticStep(prepared)) &&
    @lower.graph_diagnostic_kind(prepared) == @lower.BoundsDiagnostic &&
    @lower.graph_diagnostic_bounds(prepared)
    is Some((node_limit, edge_limit, degree_limit)) &&
    @lifecycle.producer_view_kind(input) == @carrier.GraphKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) else {
    return Err(InvalidGraphBoundsKernel)
  }
  start_graph_diagnostic(
    control,
    preparation,
    owner,
    step,
    @lower.BoundsDiagnostic,
    @lower.graph_diagnostic_output_schema(prepared),
    node_limit,
    edge_limit,
    degree_limit,
    Viewed(input),
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
    control_work_limit.unwrap_or(limits.max_work),
  )
}

///|
pub fn start_graph_degree(
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
) -> Result[GraphDegreeExecution, GraphBoundsIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphDiagnosticStep(prepared)) else {
    return Err(InvalidGraphBoundsKernel)
  }
  let kind = @lower.graph_diagnostic_kind(prepared)
  guard (
      kind == @lower.IncomingDegreeDiagnostic ||
      kind == @lower.OutgoingDegreeDiagnostic ||
      kind == @lower.TotalDegreeDiagnostic
    ) &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) &&
    @graph.producer_read_storage(input) is Some(_) else {
    return Err(InvalidGraphBoundsKernel)
  }
  start_graph_diagnostic(
    control,
    preparation,
    owner,
    step,
    kind,
    @lower.graph_diagnostic_output_schema(prepared),
    None,
    None,
    None,
    Stored(input),
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
    control_work_limit.unwrap_or(limits.max_work),
  ).map(inner => { inner, })
}

///|
/// Run the same bounded degree kernel over an exact managed Graph generation.
pub fn start_graph_degree_view(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[GraphDegreeExecution, GraphBoundsIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphDiagnosticStep(prepared)) &&
    @lifecycle.producer_view_kind(input) == @carrier.GraphKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) else {
    return Err(InvalidGraphBoundsKernel)
  }
  let kind = @lower.graph_diagnostic_kind(prepared)
  guard kind == @lower.IncomingDegreeDiagnostic ||
    kind == @lower.OutgoingDegreeDiagnostic ||
    kind == @lower.TotalDegreeDiagnostic else {
    return Err(InvalidGraphBoundsKernel)
  }
  start_graph_diagnostic(
    control,
    preparation,
    owner,
    step,
    kind,
    @lower.graph_diagnostic_output_schema(prepared),
    None,
    None,
    None,
    Viewed(input),
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
    control_work_limit.unwrap_or(limits.max_work),
  ).map(inner => { inner, })
}

///|
fn start_graph_diagnostic(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  owner : @lower.BoundPrepared,
  step : Int,
  operation : @lower.GraphDiagnosticKind,
  schema : @schema.Schema,
  node_limit : Int64?,
  edge_limit : Int64?,
  degree_limit : Int64?,
  source : GraphReadSource,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit : Int,
) -> Result[GraphBoundsExecution, GraphBoundsIssue] {
  guard graph_read_node_count(source) is Some(nodes) &&
    graph_read_edge_count(source) is Some(edges) else {
    return Err(GraphBoundsInputUnavailable)
  }
  let width = @schema.field_count(schema)
  guard graph_bounds_workspace(nodes, width) is Some(workspace) else {
    return Err(GraphBoundsWorkspaceLimit)
  }
  guard max_rows >= 0 && workspace <= max_workspace_slots else {
    return Err(GraphBoundsWorkspaceLimit)
  }
  if control_work_limit < 0 {
    return Err(GraphBoundsWorkLimit)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(GraphBoundsOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port_result = match source {
    Accumulated(_) => return Err(InvalidGraphBoundsKernel)
    Stored(read) if @lifecycle.producer_read_reference_matches_input(
        @graph.producer_read_carrier_reference(read),
        owner,
        0,
      ) => {
      let retained_inputs = [
        @execution.trusted_output_carrier_input(
          @graph.producer_read_carrier_reference(read),
        ),
      ]
      for input in inputs {
        retained_inputs.push(@execution.trusted_output_relation_input(input))
      }
      @execution.prepare_trusted_output_port_with_inputs(
        preparation,
        @pipeline.Step(step),
        max_entries,
        max_name_bytes,
        fn(_) { if live.val { rows.val } else { None } },
        inputs=retained_inputs,
      )
    }
    Stored(_) =>
      @execution.prepare_trusted_output_port(
        preparation,
        @pipeline.Step(step),
        max_entries,
        max_name_bytes,
        fn(_) { if live.val { rows.val } else { None } },
        inputs~,
      )
    Viewed(view) => {
      guard inputs.is_empty() else {
        @execution.cancel_admitted_output(output) |> ignore
        return Err(InvalidGraphBoundsKernel)
      }
      @execution.prepare_trusted_output_port_with_inputs(
        preparation,
        @pipeline.Step(step),
        max_entries,
        max_name_bytes,
        fn(_) { if live.val { rows.val } else { None } },
        inputs=[
          @execution.trusted_output_carrier_input(
            @lifecycle.producer_view_read_reference(view),
          ),
        ],
      )
    }
  }
  let port = match port_result {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(GraphBoundsCompletion(issue))
    }
  }
  let state : GraphBoundsState = {
    source,
    node_count: nodes,
    edge_count: edges,
    schema,
    value_limits: {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_text_bytes,
    },
    operation,
    node_limit,
    edge_limit,
    degree_limit,
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    phase: InitializeNodes,
    source_index: 0,
    degrees: [],
    selected: [],
    scratch: [],
    width: 1,
    run_start: 0,
    middle: 0,
    run_end: 0,
    left_index: 0,
    right_index: 0,
    merge_index: 0,
    key_comparison: None,
    key_name_position: 0,
    key_name_done: false,
    key_component: 0,
    copy_index: 0,
    candidate: 0,
    kind: "",
    actual: 0L,
    maximum: 0L,
    node: None,
    column: 0,
    values: [],
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    graph_bounds_step,
    cleanup_graph_bounds_state,
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
pub fn graph_bounds_max_noninterruptible_value_nodes(
  value : GraphBoundsExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn graph_degree_max_noninterruptible_value_nodes(
  value : GraphDegreeExecution,
) -> Int {
  graph_bounds_max_noninterruptible_value_nodes(value.inner)
}

///|
pub fn graph_bounds_max_noninterruptible_value_bytes(
  value : GraphBoundsExecution,
) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn graph_degree_max_noninterruptible_value_bytes(
  value : GraphDegreeExecution,
) -> Int {
  graph_bounds_max_noninterruptible_value_bytes(value.inner)
}

///|
pub fn advance_graph_bounds(
  value : GraphBoundsExecution,
  quantum : Int,
) -> Result[GraphBoundsPoll, GraphBoundsIssue] {
  guard value.token is Some(token) else {
    return Err(GraphBoundsExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(GraphBoundsExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(GraphBoundsContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(GraphBoundsComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(GraphBoundsFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(GraphBoundsStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn advance_graph_degree(
  value : GraphDegreeExecution,
  quantum : Int,
) -> Result[GraphDegreePoll, GraphBoundsIssue] {
  advance_graph_bounds(value.inner, quantum).map(poll => {
    match poll {
      GraphBoundsContinue(progress~, work~) =>
        GraphDegreeContinue(progress~, work~)
      GraphBoundsComplete(output, progress~, work~) =>
        GraphDegreeComplete(output, progress~, work~)
      GraphBoundsFailed(issue, progress~, work~) =>
        GraphDegreeFailed(issue, progress~, work~)
      GraphBoundsStopped(reason, progress~, work~) =>
        GraphDegreeStopped(reason, progress~, work~)
    }
  })
}

///|
pub fn graph_bounds_cleanup_pending(value : GraphBoundsExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn graph_degree_cleanup_pending(value : GraphDegreeExecution) -> Bool {
  graph_bounds_cleanup_pending(value.inner)
}

///|
pub fn cleanup_graph_bounds(
  value : GraphBoundsExecution,
) -> Result[Bool, GraphBoundsIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    GraphBoundsExecutionIssue(issue)
  })
}

///|
pub fn cleanup_graph_degree(
  value : GraphDegreeExecution,
) -> Result[Bool, GraphBoundsIssue] {
  cleanup_graph_bounds(value.inner)
}
