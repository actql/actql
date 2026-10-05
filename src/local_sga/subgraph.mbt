///|
priv enum SubgraphPhase {
  ProfileNodes
  ProfileEdges
  PrepareOutput
  InitializeSelection
  ResolveSelection
  BeginNode
  ReadNodeKeys
  ReadNodeProperties
  CommitNode
  BeginEdge
  PrepareEdgePredicate
  EvaluateEdgePredicate
  ReadEdgeKeys
  ReadSourceKeys
  ReadTargetKeys
  ReadEdgeProperties
  CommitEdge
  FinishSubgraph
}

///|
priv struct SubgraphState {
  source : GraphReadSource
  selector_input : @execution.ProducerRead?
  graph : @carrier.Graph
  profile : @carrier.PropertyGraphDefinition
  prepared : @lower.PreparedGraphSubgraph
  owner : @lower.BoundPrepared
  step : Int
  limits : @storage.Limits
  storage_bytes : Int64
  available : () -> Bool
  node_count : Int
  edge_count : Int
  mut output : @graph.OutputBuilder?
  mut phase : SubgraphPhase
  selected : Array[Bool]
  mut definition : Int
  mut widest_node_key : Int
  mut widest_record : Int
  mut node : Int
  mut edge : Int
  mut selector_row : Int
  selector_column : Int
  mut column : Int
  mut source_node : Int
  mut target_node : Int
  mut keys : Array[@value.CheckedValue]
  mut source_keys : Array[@value.CheckedValue]
  mut target_keys : Array[@value.CheckedValue]
  mut properties : Array[@value.CheckedValue]
  edge_predicate : @lower.Expression?
  edge_literal : Bool?
  predicate_fields : Int
  mut predicate_field : Int
  predicate_input : Map[String, @execution.Value]
  mut predicate_execution : @execution.PredicateExpressionExecution?
  mut predicate_work_remaining : Int
  mut predicate_workspace : Int
  value_limits : @value.Limits
  mut control_work_remaining : Int
}

///|
struct SubgraphExecution {
  session : @bounded.Session[SubgraphState, @graph.Completed, SubgraphIssue]
  mut token : @bounded.Token?
}

///|
pub enum SubgraphPoll {
  SubgraphContinue(progress~ : Int64, work~ : Int64)
  SubgraphComplete(@graph.Completed, progress~ : Int64, work~ : Int64)
  SubgraphFailed(SubgraphIssue, progress~ : Int64, work~ : Int64)
  SubgraphStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum SubgraphIssue {
  InvalidSubgraphKernel
  InvalidSubgraphLimits
  SubgraphInputUnavailable
  MissingSubgraphNodeIdentity(Int)
  SubgraphWorkspaceLimit
  SubgraphWorkLimit
  SubgraphIdentity
  SubgraphPredicate(@execution.EvalIssueKind)
  SubgraphOutput(@graph.Issue)
  SubgraphExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn subgraph_node_definition(
  state : SubgraphState,
) -> @carrier.PropertyNodeDefinition? {
  graph_read_node_definition(state.source, state.node).bind(index => {
    @carrier.property_graph_node_at(state.profile, index)
  })
}

///|
fn subgraph_edge_definition(
  state : SubgraphState,
) -> @carrier.PropertyEdgeDefinition? {
  graph_read_edge_definition(state.source, state.edge).bind(index => {
    @carrier.property_graph_edge_at(state.profile, index)
  })
}

///|
fn subgraph_predicate_field(
  state : SubgraphState,
) -> (String, @execution.Value)? {
  let fields = @lower.graph_subgraph_edge_fields(state.prepared)
  guard @carrier.field_at(fields, state.predicate_field) is Some(field) &&
    field.contract is Some(contract) &&
    graph_read_edge_definition(state.source, state.edge) is Some(definition) &&
    @lower.graph_subgraph_edge_property_position(
      state.prepared,
      definition,
      state.predicate_field,
    )
    is Some(position) &&
    position >= 0 &&
    graph_read_edge_property(state.source, state.edge, position)
    is Some(checked) &&
    @value.recheck_runtime_value(checked.value, contract, state.value_limits)
    is Some(value) else {
    return None
  }
  Some((@schema.reference_name(field.name), @execution.capture(value.value)))
}

///|
fn subgraph_step(
  state : SubgraphState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, SubgraphIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !graph_read_available(state.source) ||
      (
        state.selector_input is Some(selector) &&
        !@execution.producer_read_available(selector)
      ) {
      return @bounded.Failed(SubgraphInputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(SubgraphWorkLimit, progress, used)
    }
    match state.phase {
      ProfileNodes => {
        used += 1
        if state.definition < @carrier.property_graph_node_count(state.profile) {
          guard @carrier.property_graph_node_at(state.profile, state.definition)
            is Some(definition) else {
            return @bounded.Failed(InvalidSubgraphKernel, progress, used)
          }
          let keys = @carrier.property_definition_key_count(definition)
          let properties = @carrier.field_count(
            @carrier.property_definition_properties(definition),
          )
          if properties > state.limits.max_workspace_slots ||
            keys > state.limits.max_workspace_slots - properties {
            return @bounded.Failed(SubgraphWorkspaceLimit, progress, used)
          }
          state.widest_node_key = Int::max(state.widest_node_key, keys)
          state.widest_record = Int::max(state.widest_record, keys + properties)
          state.definition += 1
        } else {
          state.definition = 0
          state.phase = ProfileEdges
        }
      }
      ProfileEdges => {
        used += 1
        if state.definition < @carrier.property_graph_edge_count(state.profile) {
          guard @carrier.property_graph_edge_at(state.profile, state.definition)
            is Some(edge) else {
            return @bounded.Failed(InvalidSubgraphKernel, progress, used)
          }
          let definition = @carrier.property_edge_element(edge)
          let keys = @carrier.property_definition_key_count(definition)
          let properties = @carrier.field_count(
            @carrier.property_definition_properties(definition),
          )
          if state.widest_node_key > state.limits.max_workspace_slots / 2 {
            return @bounded.Failed(SubgraphWorkspaceLimit, progress, used)
          }
          let endpoints = state.widest_node_key * 2
          if keys > state.limits.max_workspace_slots - endpoints ||
            properties > state.limits.max_workspace_slots - endpoints - keys {
            return @bounded.Failed(SubgraphWorkspaceLimit, progress, used)
          }
          state.widest_record = Int::max(
            state.widest_record,
            endpoints + keys + properties,
          )
          state.definition += 1
        } else {
          state.phase = PrepareOutput
        }
      }
      PrepareOutput => {
        used += 1
        if state.predicate_fields > state.limits.max_workspace_slots - 16 ||
          state.widest_record >
          state.limits.max_workspace_slots - state.predicate_fields - 16 {
          return @bounded.Failed(SubgraphWorkspaceLimit, progress, used)
        }
        let scratch = state.widest_record + state.predicate_fields + 16
        if state.node_count > state.limits.max_workspace_slots - scratch {
          return @bounded.Failed(SubgraphWorkspaceLimit, progress, used)
        }
        let output_limits = {
          ..state.limits,
          max_workspace_slots: state.limits.max_workspace_slots -
          state.node_count -
          scratch,
        }
        state.predicate_workspace = output_limits.max_workspace_slots
        state.output = match
          @graph.prepare_output(
            state.owner,
            @pipeline.Step(state.step),
            @storage.DeclaredNodes,
            output_limits,
            state.storage_bytes,
            state.available,
          ) {
          Ok(output) => Some(output)
          Err(issue) =>
            return @bounded.Failed(SubgraphOutput(issue), progress, used)
        }
        state.phase = InitializeSelection
      }
      InitializeSelection => {
        used += 1
        if state.selected.length() < state.node_count {
          state.selected.push(false)
        } else {
          state.phase = ResolveSelection
        }
      }
      ResolveSelection => {
        let count = match state.selector_input {
          Some(input) => @execution.producer_read_row_count(input)
          None =>
            @lower.graph_subgraph_literal_id_count(state.prepared).unwrap_or(0)
        }
        used += 1
        if state.selector_row < count {
          let selected = match state.selector_input {
            Some(input) =>
              @execution.producer_read_checked_cell(
                input,
                state.selector_row,
                state.selector_column,
                state.value_limits,
              )
            None =>
              @lower.graph_subgraph_literal_id_at(
                state.prepared,
                state.selector_row,
              )
          }
          guard selected is Some(checked) &&
            @value.recheck_runtime_value(
              checked.value,
              @carrier.graph_identity(state.graph),
              state.value_limits,
            )
            is Some(identity) else {
            return @bounded.Failed(SubgraphIdentity, progress, used)
          }
          match graph_read_node_index(state.source, identity) {
            Err(_) =>
              return @bounded.Failed(SubgraphInputUnavailable, progress, used)
            Ok(None) =>
              return @bounded.Failed(
                MissingSubgraphNodeIdentity(state.selector_row),
                progress,
                used,
              )
            Ok(Some(node)) => state.selected[node] = true
          }
          state.selector_row += 1
        } else {
          state.phase = BeginNode
        }
      }
      BeginNode => {
        used += 1
        if state.node < state.node_count {
          if state.selected[state.node] {
            state.column = 0
            state.phase = ReadNodeKeys
          } else {
            state.node += 1
          }
        } else {
          state.phase = BeginEdge
        }
      }
      ReadNodeKeys | ReadNodeProperties => {
        guard subgraph_node_definition(state) is Some(definition) else {
          return @bounded.Failed(SubgraphInputUnavailable, progress, used)
        }
        let count = if state.phase is ReadNodeKeys {
          @carrier.property_definition_key_count(definition)
        } else {
          @carrier.field_count(
            @carrier.property_definition_properties(definition),
          )
        }
        if state.column < count {
          used += 1
          let value = if state.phase is ReadNodeKeys {
            graph_read_node_key_component(
              state.source,
              state.node,
              state.column,
            )
          } else {
            graph_read_node_property(state.source, state.node, state.column)
          }
          guard value is Some(value) else {
            return @bounded.Failed(SubgraphInputUnavailable, progress, used)
          }
          if state.phase is ReadNodeKeys {
            state.keys.push(value)
          } else {
            state.properties.push(value)
          }
          state.column += 1
        } else {
          state.column = 0
          state.phase = if state.phase is ReadNodeKeys {
            ReadNodeProperties
          } else {
            CommitNode
          }
        }
      }
      CommitNode => {
        used += 1
        guard state.output is Some(output) &&
          graph_read_node_definition(state.source, state.node)
          is Some(definition) else {
          return @bounded.Failed(SubgraphInputUnavailable, progress, used)
        }
        match
          @graph.append_property_node(
            output,
            definition,
            state.keys,
            state.properties,
          ) {
          Ok(_) => ()
          Err(issue) =>
            return @bounded.Failed(SubgraphOutput(issue), progress, used)
        }
        state.keys = []
        state.properties = []
        state.node += 1
        state.phase = BeginNode
        progress += 1
      }
      BeginEdge => {
        used += 1
        if state.edge < state.edge_count {
          guard graph_read_edge_endpoints(state.source, state.edge)
            is Some((source, target)) &&
            state.selected.get(source) is Some(left) &&
            state.selected.get(target) is Some(right) else {
            return @bounded.Failed(SubgraphInputUnavailable, progress, used)
          }
          if left && right {
            state.source_node = source
            state.target_node = target
            match state.edge_literal {
              Some(true) => {
                state.column = 0
                state.phase = ReadEdgeKeys
              }
              Some(false) => state.edge += 1
              None => {
                state.predicate_field = 0
                state.predicate_input.clear()
                state.phase = PrepareEdgePredicate
              }
            }
          } else {
            state.edge += 1
          }
        } else {
          state.phase = FinishSubgraph
        }
      }
      PrepareEdgePredicate =>
        if state.predicate_field < state.predicate_fields {
          used += 1
          guard subgraph_predicate_field(state) is Some((name, value)) else {
            return @bounded.Failed(SubgraphInputUnavailable, progress, used)
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard state.edge_predicate is Some(predicate) &&
            state.output is Some(output) else {
            return @bounded.Failed(InvalidSubgraphKernel, progress, used)
          }
          state.predicate_execution = match
            @execution.start_predicate_expression(
              predicate,
              state.predicate_input,
              state.predicate_work_remaining,
              state.value_limits.max_nodes,
              state.predicate_workspace - @graph.output_workspace_slots(output),
            ) {
            Ok(execution) => Some(execution)
            Err(issue) =>
              return @bounded.Failed(
                SubgraphPredicate(issue.kind),
                progress,
                used,
              )
          }
          state.phase = EvaluateEdgePredicate
        }
      EvaluateEdgePredicate => {
        used += 1
        guard state.predicate_execution is Some(execution) else {
          return @bounded.Failed(InvalidSubgraphKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(
              SubgraphPredicate(issue.kind),
              progress,
              used,
            )
          }
          Ok(@execution.PredicateExpressionContinue) => ()
          Ok(@execution.PredicateExpressionComplete(selected)) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            state.predicate_input.clear()
            if selected {
              state.column = 0
              state.phase = ReadEdgeKeys
            } else {
              state.edge += 1
              state.phase = BeginEdge
            }
          }
        }
      }
      ReadEdgeKeys | ReadSourceKeys | ReadTargetKeys | ReadEdgeProperties => {
        guard subgraph_edge_definition(state) is Some(edge) &&
          graph_read_node_definition(state.source, state.source_node)
          is Some(source_definition) &&
          graph_read_node_definition(state.source, state.target_node)
          is Some(target_definition) &&
          @carrier.property_graph_node_at(state.profile, source_definition)
          is Some(source_node) &&
          @carrier.property_graph_node_at(state.profile, target_definition)
          is Some(target_node) else {
          return @bounded.Failed(SubgraphInputUnavailable, progress, used)
        }
        let count = match state.phase {
          ReadEdgeKeys =>
            @carrier.property_definition_key_count(
              @carrier.property_edge_element(edge),
            )
          ReadSourceKeys => @carrier.property_definition_key_count(source_node)
          ReadTargetKeys => @carrier.property_definition_key_count(target_node)
          _ =>
            @carrier.field_count(
              @carrier.property_definition_properties(
                @carrier.property_edge_element(edge),
              ),
            )
        }
        if state.column < count {
          used += 1
          let value = match state.phase {
            ReadEdgeKeys =>
              graph_read_edge_key_component(
                state.source,
                state.edge,
                state.column,
              )
            ReadSourceKeys =>
              graph_read_node_key_component(
                state.source,
                state.source_node,
                state.column,
              )
            ReadTargetKeys =>
              graph_read_node_key_component(
                state.source,
                state.target_node,
                state.column,
              )
            _ =>
              graph_read_edge_property(state.source, state.edge, state.column)
          }
          guard value is Some(value) else {
            return @bounded.Failed(SubgraphInputUnavailable, progress, used)
          }
          match state.phase {
            ReadEdgeKeys => state.keys.push(value)
            ReadSourceKeys => state.source_keys.push(value)
            ReadTargetKeys => state.target_keys.push(value)
            _ => state.properties.push(value)
          }
          state.column += 1
        } else {
          state.column = 0
          state.phase = match state.phase {
            ReadEdgeKeys => ReadSourceKeys
            ReadSourceKeys => ReadTargetKeys
            ReadTargetKeys => ReadEdgeProperties
            _ => CommitEdge
          }
        }
      }
      CommitEdge => {
        used += 1
        guard state.output is Some(output) &&
          graph_read_edge_definition(state.source, state.edge)
          is Some(definition) else {
          return @bounded.Failed(SubgraphInputUnavailable, progress, used)
        }
        match
          @graph.append_property_edge(
            output,
            definition,
            state.keys,
            state.source_keys,
            state.target_keys,
            state.properties,
          ) {
          Ok(_) => ()
          Err(issue) =>
            return @bounded.Failed(SubgraphOutput(issue), progress, used)
        }
        state.keys = []
        state.source_keys = []
        state.target_keys = []
        state.properties = []
        state.edge += 1
        state.phase = BeginEdge
        progress += 1
      }
      FinishSubgraph => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidSubgraphKernel, progress, used)
        }
        state.output = None
        return match @graph.finish_output(output) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) => @bounded.Failed(SubgraphOutput(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_subgraph_state(state : SubgraphState) -> Bool {
  if state.predicate_execution is Some(execution) {
    @execution.cancel_predicate_expression(execution) |> ignore
    state.predicate_execution = None
  }
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  state.selected.clear()
  state.keys = []
  state.source_keys = []
  state.target_keys = []
  state.properties = []
  state.predicate_input.clear()
  true
}

///|
fn start_subgraph_core(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  source : GraphReadSource,
  selector_input : @execution.ProducerRead?,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[SubgraphExecution, SubgraphIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphSubgraphStep(prepared)) &&
    (
      @lower.graph_subgraph_literal_id_count(prepared) is Some(_) ||
      @lower.graph_subgraph_relation_selector_field(prepared) is Some(_)
    ) &&
    (
      @lower.graph_subgraph_literal_edge_predicate(prepared) is Some(_) ||
      @lower.graph_subgraph_edge_predicate(prepared) is Some(_)
    ) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.node_input_target(node, 0).bind(target => {
      @lower.preparation_carrier_at(@lower.bound_preparation(owner), target)
    })
    is Some(@carrier.GraphValue(graph)) else {
    return Err(InvalidSubgraphKernel)
  }
  let selector_column = match
    (@lower.graph_subgraph_relation_selector_field(prepared), selector_input) {
    (Some(field), Some(input)) => {
      if !@execution.producer_read_matches_operation_input(
          input, owner, step, 1,
        ) {
        return Err(InvalidSubgraphKernel)
      }
      let schema = @execution.producer_read_schema(input)
      let mut found = None
      for column in 0..<@schema.field_count(schema) {
        if @schema.field_at(schema, column).map(value => value.name) ==
          Some(field) {
          found = Some(column)
        }
      }
      match found {
        Some(column) => column
        None => return Err(InvalidSubgraphKernel)
      }
    }
    (None, None) => -1
    _ => return Err(InvalidSubgraphKernel)
  }
  guard graph_read_node_count(source) is Some(node_count) &&
    graph_read_edge_count(source) is Some(edge_count) else {
    return Err(SubgraphInputUnavailable)
  }
  let control_work_limit = control_work_limit.unwrap_or(limits.max_work)
  if control_work_limit < 1 ||
    limits.max_workspace_slots < 16 ||
    node_count > limits.max_workspace_slots - 16 {
    return Err(InvalidSubgraphLimits)
  }
  let edge_literal = @lower.graph_subgraph_literal_edge_predicate(prepared)
  let edge_predicate = if edge_literal is Some(_) {
    None
  } else {
    @lower.graph_subgraph_edge_predicate(prepared)
  }
  let predicate_fields = if edge_predicate is Some(_) {
    @carrier.field_count(@lower.graph_subgraph_edge_fields(prepared))
  } else {
    0
  }
  let state : SubgraphState = {
    source,
    selector_input,
    graph,
    profile: @carrier.graph_property_definition(graph),
    prepared,
    owner,
    step,
    limits,
    storage_bytes,
    available,
    node_count,
    edge_count,
    output: None,
    phase: ProfileNodes,
    selected: [],
    definition: 0,
    widest_node_key: 0,
    widest_record: 0,
    node: 0,
    edge: 0,
    selector_row: 0,
    selector_column,
    column: 0,
    source_node: 0,
    target_node: 0,
    keys: [],
    source_keys: [],
    target_keys: [],
    properties: [],
    edge_predicate,
    edge_literal,
    predicate_fields,
    predicate_field: 0,
    predicate_input: Map([]),
    predicate_execution: None,
    predicate_work_remaining: limits.max_work,
    predicate_workspace: 0,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control, state, subgraph_step, cleanup_subgraph_state, @graph.discard_completed,
  )
  Ok({ session, token: Some(token), })
}

///|
pub fn start_subgraph(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @graph.ProducerRead,
  selector_input : @execution.ProducerRead?,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[SubgraphExecution, SubgraphIssue] {
  guard @graph.producer_read_matches_operation_input(
      input,
      @lower.sequence_owner(sequence),
      step,
      0,
    ) &&
    @graph.producer_read_storage(input) is Some(storage) &&
    @storage.carrier(storage) is @carrier.GraphValue(_) else {
    return Err(InvalidSubgraphKernel)
  }
  start_subgraph_core(
    control,
    sequence,
    step,
    Stored(input),
    selector_input,
    limits,
    storage_bytes,
    available,
    control_work_limit~,
  )
}

///|
pub fn start_subgraph_view(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  selector_input : @execution.ProducerRead?,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[SubgraphExecution, SubgraphIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lifecycle.producer_view_kind(input) == @carrier.GraphKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) else {
    return Err(InvalidSubgraphKernel)
  }
  start_subgraph_core(
    control,
    sequence,
    step,
    Viewed(input),
    selector_input,
    limits,
    storage_bytes,
    available,
    control_work_limit~,
  )
}

///|
pub fn advance_subgraph(
  value : SubgraphExecution,
  quantum : Int,
) -> Result[SubgraphPoll, SubgraphIssue] {
  guard value.token is Some(token) else {
    return Err(SubgraphExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(SubgraphExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(SubgraphContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(SubgraphComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(SubgraphFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(SubgraphStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn subgraph_cleanup_pending(value : SubgraphExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_subgraph(
  value : SubgraphExecution,
) -> Result[Bool, SubgraphIssue] {
  @bounded.cleanup(value.session).map_err(issue => SubgraphExecutionIssue(issue))
}
