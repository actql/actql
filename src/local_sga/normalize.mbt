///|
/// A normalization copy reads the admitted typed key, not the presentation
/// identity. Each definition, key component and property is a cancellable step.
priv enum NormalizePhase {
  MeasureNodes
  MeasureEdges
  PrepareOutput
  BeginNode
  NodeKey
  NodeProperty
  CommitNode
  BeginEdge
  EdgeKey
  EdgeSourceKey
  EdgeTargetKey
  EdgeProperty
  CommitEdge
  Finish
} derive(Eq)

///|
priv struct NormalizeState {
  source : GraphReadSource
  profile : @carrier.PropertyGraphDefinition
  owner : @lower.BoundPrepared
  step : Int
  limits : @storage.Limits
  storage_bytes : Int64
  available : () -> Bool
  node_count : Int
  edge_count : Int
  mut output : @graph.OutputBuilder?
  mut phase : NormalizePhase
  mut definition : Int
  mut width : Int
  mut index : Int
  mut column : Int
  mut node_definition : Int
  mut edge_definition : Int
  mut source_node : Int
  mut target_node : Int
  mut keys : Array[@value.CheckedValue]
  mut source_keys : Array[@value.CheckedValue]
  mut target_keys : Array[@value.CheckedValue]
  mut properties : Array[@value.CheckedValue]
}

///|
struct NormalizeExecution {
  session : @bounded.Session[NormalizeState, @graph.Completed, NormalizeIssue]
  mut token : @bounded.Token?
}

///|
pub enum NormalizePoll {
  NormalizeContinue(progress~ : Int64, work~ : Int64)
  NormalizeComplete(@graph.Completed, progress~ : Int64, work~ : Int64)
  NormalizeFailed(NormalizeIssue, progress~ : Int64, work~ : Int64)
  NormalizeStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum NormalizeIssue {
  InvalidNormalizeKernel
  NormalizeInputUnavailable
  NormalizeWorkspaceLimit
  NormalizeOutput(@graph.Issue)
  NormalizeExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn normalize_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn normalize_width(values : Array[Int]) -> Int? {
  let mut total = 0
  for value in values {
    guard normalize_add(total, value) is Some(next) else { return None }
    total = next
  }
  Some(total)
}

///|
fn normalize_step(
  state : NormalizeState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, NormalizeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !graph_read_available(state.source) {
      return @bounded.Failed(NormalizeInputUnavailable, progress, used)
    }
    match state.phase {
      MeasureNodes => {
        used += 1
        if state.definition == @carrier.property_graph_node_count(state.profile) {
          state.definition = 0
          state.phase = MeasureEdges
        } else {
          guard @carrier.property_graph_node_at(state.profile, state.definition)
            is Some(definition) &&
            normalize_width([
              @carrier.property_definition_key_count(definition),
              @carrier.field_count(
                @carrier.property_definition_properties(definition),
              ),
            ])
            is Some(width) else {
            return @bounded.Failed(NormalizeWorkspaceLimit, progress, used)
          }
          state.width = Int::max(state.width, width)
          state.definition += 1
        }
      }
      MeasureEdges => {
        used += 1
        if state.definition == @carrier.property_graph_edge_count(state.profile) {
          state.phase = PrepareOutput
        } else {
          guard @carrier.property_graph_edge_at(state.profile, state.definition)
            is Some(edge) else {
            return @bounded.Failed(InvalidNormalizeKernel, progress, used)
          }
          let (source_name, target_name) = @carrier.property_edge_endpoints(
            edge,
          )
          guard @carrier.property_graph_node_named(state.profile, source_name)
            is Some(source) &&
            @carrier.property_graph_node_named(state.profile, target_name)
            is Some(target) &&
            normalize_width([
              @carrier.property_definition_key_count(
                @carrier.property_edge_element(edge),
              ),
              @carrier.property_definition_key_count(source),
              @carrier.property_definition_key_count(target),
              @carrier.field_count(
                @carrier.property_definition_properties(
                  @carrier.property_edge_element(edge),
                ),
              ),
            ])
            is Some(width) else {
            return @bounded.Failed(NormalizeWorkspaceLimit, progress, used)
          }
          state.width = Int::max(state.width, width)
          state.definition += 1
        }
      }
      PrepareOutput => {
        used += 1
        // Four array headers remain live while the row buffer is populated.
        guard normalize_add(state.width, 4) is Some(scratch) &&
          scratch <= state.limits.max_workspace_slots else {
          return @bounded.Failed(NormalizeWorkspaceLimit, progress, used)
        }
        let limits = {
          ..state.limits,
          max_workspace_slots: state.limits.max_workspace_slots - scratch,
        }
        match
          @graph.prepare_output(
            state.owner,
            @pipeline.Step(state.step),
            @storage.DeclaredNodes,
            limits,
            state.storage_bytes,
            state.available,
          ) {
          Ok(output) => state.output = Some(output)
          Err(issue) =>
            return @bounded.Failed(NormalizeOutput(issue), progress, used)
        }
        state.phase = BeginNode
      }
      BeginNode => {
        used += 1
        if state.index == state.node_count {
          state.index = 0
          state.phase = BeginEdge
        } else {
          guard graph_read_node_definition(state.source, state.index)
            is Some(definition) &&
            @carrier.property_graph_node_at(state.profile, definition)
            is Some(_) else {
            return @bounded.Failed(NormalizeInputUnavailable, progress, used)
          }
          state.node_definition = definition
          state.column = 0
          state.keys = []
          state.properties = []
          state.phase = NodeKey
        }
      }
      NodeKey => {
        used += 1
        let definition = @carrier.property_graph_node_at(
          state.profile,
          state.node_definition,
        ).unwrap()
        if state.column == @carrier.property_definition_key_count(definition) {
          state.column = 0
          state.phase = NodeProperty
        } else {
          guard graph_read_node_key_component(
              state.source,
              state.index,
              state.column,
            )
            is Some(key) else {
            return @bounded.Failed(NormalizeInputUnavailable, progress, used)
          }
          state.keys.push(key)
          state.column += 1
        }
      }
      NodeProperty => {
        used += 1
        let definition = @carrier.property_graph_node_at(
          state.profile,
          state.node_definition,
        ).unwrap()
        let count = @carrier.field_count(
          @carrier.property_definition_properties(definition),
        )
        if state.column == count {
          state.phase = CommitNode
        } else {
          guard graph_read_node_property(
              state.source,
              state.index,
              state.column,
            )
            is Some(property) else {
            return @bounded.Failed(NormalizeInputUnavailable, progress, used)
          }
          state.properties.push(property)
          state.column += 1
        }
      }
      CommitNode => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidNormalizeKernel, progress, used)
        }
        match
          @graph.append_property_node(
            output,
            state.node_definition,
            state.keys,
            state.properties,
          ) {
          Ok(_) => ()
          Err(issue) =>
            return @bounded.Failed(NormalizeOutput(issue), progress, used)
        }
        state.keys = []
        state.properties = []
        state.index += 1
        progress += 1
        state.phase = BeginNode
      }
      BeginEdge => {
        used += 1
        if state.index == state.edge_count {
          state.phase = Finish
        } else {
          guard graph_read_edge_definition(state.source, state.index)
            is Some(definition) &&
            @carrier.property_graph_edge_at(state.profile, definition)
            is Some(_) &&
            graph_read_edge_endpoints(state.source, state.index)
            is Some((source, target)) else {
            return @bounded.Failed(NormalizeInputUnavailable, progress, used)
          }
          state.edge_definition = definition
          state.source_node = source
          state.target_node = target
          state.column = 0
          state.keys = []
          state.source_keys = []
          state.target_keys = []
          state.properties = []
          state.phase = EdgeKey
        }
      }
      EdgeKey => {
        used += 1
        let edge = @carrier.property_graph_edge_at(
          state.profile,
          state.edge_definition,
        ).unwrap()
        if state.column ==
          @carrier.property_definition_key_count(
            @carrier.property_edge_element(edge),
          ) {
          state.column = 0
          state.phase = EdgeSourceKey
        } else {
          guard graph_read_edge_key_component(
              state.source,
              state.index,
              state.column,
            )
            is Some(key) else {
            return @bounded.Failed(NormalizeInputUnavailable, progress, used)
          }
          state.keys.push(key)
          state.column += 1
        }
      }
      EdgeSourceKey | EdgeTargetKey => {
        used += 1
        let node = if state.phase == EdgeSourceKey {
          state.source_node
        } else {
          state.target_node
        }
        guard graph_read_node_definition(state.source, node) is Some(index) &&
          @carrier.property_graph_node_at(state.profile, index)
          is Some(definition) else {
          return @bounded.Failed(NormalizeInputUnavailable, progress, used)
        }
        if state.column == @carrier.property_definition_key_count(definition) {
          state.column = 0
          state.phase = if state.phase == EdgeSourceKey {
            EdgeTargetKey
          } else {
            EdgeProperty
          }
        } else {
          guard graph_read_node_key_component(state.source, node, state.column)
            is Some(key) else {
            return @bounded.Failed(NormalizeInputUnavailable, progress, used)
          }
          if state.phase == EdgeSourceKey {
            state.source_keys.push(key)
          } else {
            state.target_keys.push(key)
          }
          state.column += 1
        }
      }
      EdgeProperty => {
        used += 1
        let edge = @carrier.property_graph_edge_at(
          state.profile,
          state.edge_definition,
        ).unwrap()
        let count = @carrier.field_count(
          @carrier.property_definition_properties(
            @carrier.property_edge_element(edge),
          ),
        )
        if state.column == count {
          state.phase = CommitEdge
        } else {
          guard graph_read_edge_property(
              state.source,
              state.index,
              state.column,
            )
            is Some(property) else {
            return @bounded.Failed(NormalizeInputUnavailable, progress, used)
          }
          state.properties.push(property)
          state.column += 1
        }
      }
      CommitEdge => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidNormalizeKernel, progress, used)
        }
        match
          @graph.append_property_edge(
            output,
            state.edge_definition,
            state.keys,
            state.source_keys,
            state.target_keys,
            state.properties,
          ) {
          Ok(_) => ()
          Err(issue) =>
            return @bounded.Failed(NormalizeOutput(issue), progress, used)
        }
        state.keys = []
        state.source_keys = []
        state.target_keys = []
        state.properties = []
        state.index += 1
        progress += 1
        state.phase = BeginEdge
      }
      Finish => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidNormalizeKernel, progress, used)
        }
        state.output = None
        return match @graph.finish_output(output) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) => @bounded.Failed(NormalizeOutput(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_normalize_state(state : NormalizeState) -> Bool {
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  state.keys = []
  state.source_keys = []
  state.target_keys = []
  state.properties = []
  true
}

///|
pub fn start_normalize_view(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[NormalizeExecution, NormalizeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphNormalizeStep(_)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "SGA.normalize" &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) &&
    @lifecycle.producer_view_property_graph_definition(input) is Ok(profile) &&
    @lifecycle.producer_view_node_count(input) is Some(nodes) &&
    @lifecycle.producer_view_edge_count(input) is Some(edges) else {
    return Err(InvalidNormalizeKernel)
  }
  let state : NormalizeState = {
    source: Viewed(input),
    profile,
    owner,
    step,
    limits,
    storage_bytes,
    available,
    node_count: nodes,
    edge_count: edges,
    output: None,
    phase: MeasureNodes,
    definition: 0,
    width: 0,
    index: 0,
    column: 0,
    node_definition: 0,
    edge_definition: 0,
    source_node: 0,
    target_node: 0,
    keys: [],
    source_keys: [],
    target_keys: [],
    properties: [],
  }
  let (session, token) = @bounded.start(
    control, state, normalize_step, cleanup_normalize_state, @graph.discard_completed,
  )
  Ok({ session, token: Some(token), })
}

///|
pub fn advance_normalize(
  value : NormalizeExecution,
  quantum : Int,
) -> Result[NormalizePoll, NormalizeIssue] {
  guard value.token is Some(token) else {
    return Err(NormalizeExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(NormalizeExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(NormalizeContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(NormalizeComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(NormalizeFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(NormalizeStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn normalize_cleanup_pending(value : NormalizeExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_normalize(
  value : NormalizeExecution,
) -> Result[Bool, NormalizeIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    NormalizeExecutionIssue(issue)
  })
}
