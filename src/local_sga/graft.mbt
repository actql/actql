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
  StorageSource(@storage.Storage)
  ViewSource(@lifecycle.ProducerView)
}

///|
priv struct GraftState {
  sources : Array[GraftSource]
  mode : StructuralMode
  retain_shared_nodes : Bool
  retain_shared_edges : Bool
  mut output : @graph.OutputBuilder?
  node_fields : Int
  edge_fields : Int
  mut input_index : Int
  mut phase : GraftPhase
  mut record_index : Int
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
    Some(@lower.GraphStructuralStep(structural)) =>
      input_count == 2 &&
      (
        @lower.operation(node) == "SGA.graft" ||
        (
          @lower.operation(node) == "SGA.union_structural" &&
          @lower.graph_structural_has_only_exact_property_strategies(structural)
        ) ||
        (
          @lower.operation(node) == "SGA.diff_structural" &&
          @lower.graph_structural_has_only_exact_property_strategies(structural)
        )
      )
    Some(@lower.GraphUnionStep(union)) =>
      @lower.operation(node) == "SGA.union_structural" &&
      @lower.graph_union_input_count(union) == input_count &&
      @lower.graph_union_has_only_exact_property_strategies(union)
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
fn graft_source(state : GraftState) -> GraftSource? {
  state.sources.get(state.input_index)
}

///|
fn graft_inputs_available(state : GraftState) -> Bool {
  for source in state.sources {
    match source {
      StorageSource(source) =>
        match @storage.carrier(source) {
          @carrier.GraphValue(_) => ()
          _ => return false
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
fn advance_graft_source(state : GraftState) -> Unit {
  state.input_index += 1
  state.phase = CopyNodes
  state.record_index = 0
  if state.input_index >= state.sources.length() {
    state.phase = Finish
  }
}

///|
fn subtract_node_step(
  state : GraftState,
  left : @storage.Storage,
  right : @storage.Storage,
) -> Result[Unit, GraftIssue] {
  guard state.output is Some(output) else { return Err(GraftInputUnavailable) }
  if state.input_index == 0 {
    guard @storage.node_identity(left, state.record_index) is Some(identity) else {
      return Err(GraftInputUnavailable)
    }
    let shared = match @storage.node_index(right, identity) {
      Ok(value) => value is Some(_)
      Err(_) => return Err(GraftInputUnavailable)
    }
    if !shared || state.retain_shared_nodes {
      match
        copy_graph_node(left, output, state.node_fields, state.record_index) {
        Ok(_) => ()
        Err(Unavailable) => return Err(GraftInputUnavailable)
        Err(GraphCopyIssue::Output(issue)) => return Err(GraftOutput(issue))
      }
    }
    return Ok(())
  }
  if state.input_index != 1 || !state.retain_shared_nodes {
    return Ok(())
  }
  guard @storage.node_identity(right, state.record_index) is Some(identity) else {
    return Err(GraftInputUnavailable)
  }
  let shared = match @storage.node_index(left, identity) {
    Ok(value) => value is Some(_)
    Err(_) => return Err(GraftInputUnavailable)
  }
  if shared {
    match
      copy_graph_node(right, output, state.node_fields, state.record_index) {
      Ok(_) => ()
      Err(Unavailable) => return Err(GraftInputUnavailable)
      Err(GraphCopyIssue::Output(issue)) => return Err(GraftOutput(issue))
    }
  }
  Ok(())
}

///|
fn subtract_edge_step(
  state : GraftState,
  left : @storage.Storage,
  right : @storage.Storage,
) -> Result[Unit, GraftIssue] {
  guard state.output is Some(output) else { return Err(GraftInputUnavailable) }
  let source = if state.input_index == 0 { left } else { right }
  let other = if state.input_index == 0 { right } else { left }
  guard @storage.edge_endpoints(source, state.record_index)
    is Some((source_node, target_node)) &&
    @storage.node_identity(source, source_node) is Some(source_id) &&
    @storage.node_identity(source, target_node) is Some(target_id) &&
    @storage.edge_label(source, state.record_index) is Some(label) else {
    return Err(GraftInputUnavailable)
  }
  let shared = match @storage.edge_index(other, source_id, target_id, label) {
    Ok(value) => value is Some(_)
    Err(_) => return Err(GraftInputUnavailable)
  }
  if state.input_index == 1 && (!state.retain_shared_edges || !shared) {
    return Ok(())
  }
  let source_present = match @graph.contains_declared_node(output, source_id) {
    Ok(value) => value
    Err(issue) => return Err(GraftOutput(issue))
  }
  let target_present = match @graph.contains_declared_node(output, target_id) {
    Ok(value) => value
    Err(issue) => return Err(GraftOutput(issue))
  }
  let keep = if state.input_index == 0 {
    !shared || state.retain_shared_edges
  } else {
    shared
  }
  if keep && source_present && target_present {
    match
      copy_graph_edge(source, output, state.edge_fields, state.record_index) {
      Ok(_) => ()
      Err(Unavailable) => return Err(GraftInputUnavailable)
      Err(GraphCopyIssue::Output(issue)) => return Err(GraftOutput(issue))
    }
  }
  Ok(())
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
          StorageSource(value) => @storage.node_count(value)
          ViewSource(value) =>
            match @lifecycle.producer_view_node_count(value) {
              Some(count) => count
              None =>
                return @bounded.Failed(GraftInputUnavailable, progress, used)
            }
        }
        if state.record_index < count {
          if state.mode == Subtract {
            guard state.sources.length() == 2 &&
              state.sources[0] is StorageSource(left) &&
              state.sources[1] is StorageSource(right) else {
              return @bounded.Failed(InvalidGraftKernel, progress, used)
            }
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
          guard state.output is Some(output) else {
            return @bounded.Failed(InvalidGraftKernel, progress, used)
          }
          let copied = match source {
            StorageSource(source) =>
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
          StorageSource(value) => @storage.edge_count(value)
          ViewSource(value) =>
            match @lifecycle.producer_view_edge_count(value) {
              Some(count) => count
              None =>
                return @bounded.Failed(GraftInputUnavailable, progress, used)
            }
        }
        if state.record_index < count {
          if state.mode == Subtract {
            guard state.sources.length() == 2 &&
              state.sources[0] is StorageSource(left) &&
              state.sources[1] is StorageSource(right) else {
              return @bounded.Failed(InvalidGraftKernel, progress, used)
            }
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
          guard state.output is Some(output) else {
            return @bounded.Failed(InvalidGraftKernel, progress, used)
          }
          let copied = match source {
            StorageSource(source) =>
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
    sources.push(StorageSource(source))
  }
  guard sources[0] is StorageSource(first) &&
    @storage.carrier(first) is @carrier.GraphValue(contract) else {
    return Err(GraftInputUnavailable)
  }
  if mode == Subtract {
    if !retain_shared_nodes &&
      @carrier.field_count(@carrier.graph_node_properties(contract)) != 0 {
      return Err(InvalidGraftKernel)
    }
    if !retain_shared_edges &&
      @carrier.field_count(@carrier.graph_edge_properties(contract)) != 0 {
      return Err(InvalidGraftKernel)
    }
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
    retain_shared_nodes,
    retain_shared_edges,
    output: Some(output),
    node_fields: @carrier.field_count(@carrier.graph_node_properties(contract)),
    edge_fields: @carrier.field_count(@carrier.graph_edge_properties(contract)),
    input_index: 0,
    phase: CopyNodes,
    record_index: 0,
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
  guard structural_mode(sequence, step) is Some(mode) && mode == Add else {
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
    retain_shared_nodes: false,
    retain_shared_edges: false,
    output: Some(output),
    node_fields: @carrier.field_count(@carrier.graph_node_properties(contract)),
    edge_fields: @carrier.field_count(@carrier.graph_edge_properties(contract)),
    input_index: 0,
    phase: CopyNodes,
    record_index: 0,
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
