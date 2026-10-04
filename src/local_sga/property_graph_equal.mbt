///|
priv enum PropertyEqualityPhase {
  CompareCounts
  FindNode
  CompareNodeKey
  CompareNodeProperty
  FindEdge
  CompareEdgeKey
  CompareEdgeSource
  CompareEdgeTarget
  CompareEdgeProperty
  EmitResult
  FinishResult
} derive(Eq)

///|
priv struct PropertyEqualityState {
  left : GraphReadSource
  right : GraphReadSource
  left_nodes : Int
  right_nodes : Int
  left_edges : Int
  right_edges : Int
  schema : @schema.Schema
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : PropertyEqualityPhase
  mut equal : Bool
  mut record : Int
  mut candidate : Int
  mut matched : Int
  mut position : Int
  mut property : Int
  mut comparison : @value.CompleteEquality?
  mut work_remaining : Int
  value_nodes : Int
  value_depth : Int
  value_text_bytes : Int
}

///|
struct PropertyEqualityExecution {
  session : @bounded.Session[
    PropertyEqualityState,
    @execution.CompletedOutput,
    PropertyEqualityIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub(all) enum PropertyEqualityIssue {
  InvalidPropertyEqualityKernel
  PropertyEqualityInputUnavailable
  PropertyEqualityWorkspaceLimit
  PropertyEqualityWorkLimit
  PropertyEqualityValue(@value.CompleteEqualityIssue)
  PropertyEqualityOutput(@execution.CaptureIssue)
  PropertyEqualityCompletion(@execution.TrustedOutputIssue)
  PropertyEqualityExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
pub enum PropertyEqualityPoll {
  PropertyEqualityContinue(progress~ : Int64, work~ : Int64)
  PropertyEqualityComplete(
    @execution.CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  PropertyEqualityFailed(
    PropertyEqualityIssue,
    progress~ : Int64,
    work~ : Int64
  )
  PropertyEqualityStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn property_equality_count(
  source : GraphReadSource,
  record : Int,
  edge : Bool,
) -> Int? {
  guard graph_read_property_definition(source) is Some(graph) else {
    return None
  }
  let definition = if edge {
    graph_read_edge_definition(source, record).bind(index => {
      @carrier.property_graph_edge_at(graph, index).map(
        @carrier.property_edge_element,
      )
    })
  } else {
    graph_read_node_definition(source, record).bind(index => {
      @carrier.property_graph_node_at(graph, index)
    })
  }
  definition.map(value => {
    @carrier.field_count(@carrier.property_definition_properties(value))
  })
}

///|
fn property_equality_field(
  source : GraphReadSource,
  record : Int,
  property : Int,
  edge : Bool,
) -> @value.CheckedValue? {
  if edge {
    graph_read_edge_property(source, record, property)
  } else {
    graph_read_node_property(source, record, property)
  }
}

///|
fn property_equality_endpoint_key(
  source : GraphReadSource,
  edge : Int,
  target : Bool,
) -> String? {
  graph_read_edge_endpoints(source, edge).bind(pair => {
    let (from, to) = pair
    graph_read_node_identity_order_key(source, if target { to } else { from })
  })
}

///|
fn property_equality_keys(state : PropertyEqualityState) -> (String, String)? {
  let edge = match state.phase {
    CompareEdgeKey | CompareEdgeSource | CompareEdgeTarget => true
    _ => false
  }
  if state.phase == CompareEdgeSource || state.phase == CompareEdgeTarget {
    let target = state.phase == CompareEdgeTarget
    guard property_equality_endpoint_key(state.left, state.record, target)
      is Some(left) &&
      property_equality_endpoint_key(state.right, state.candidate, target)
      is Some(right) else {
      return None
    }
    return Some((left, right))
  }
  let left = if edge {
    graph_read_edge_identity_order_key(state.left, state.record)
  } else {
    graph_read_node_identity_order_key(state.left, state.record)
  }
  let right = if edge {
    graph_read_edge_identity_order_key(state.right, state.candidate)
  } else {
    graph_read_node_identity_order_key(state.right, state.candidate)
  }
  match (left, right) {
    (Some(left), Some(right)) => Some((left, right))
    _ => None
  }
}

///|
fn property_equality_step(
  state : PropertyEqualityState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, PropertyEqualityIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !graph_read_available(state.left) || !graph_read_available(state.right) {
      return @bounded.Failed(PropertyEqualityInputUnavailable, progress, used)
    }
    if used >= state.work_remaining {
      return @bounded.Failed(PropertyEqualityWorkLimit, progress, used)
    }
    guard state.output is Some(output) &&
      @execution.admitted_output_charge_control_work(output, 1) else {
      return @bounded.Failed(PropertyEqualityWorkLimit, progress, used)
    }
    used += 1
    match state.phase {
      CompareCounts =>
        if state.left_nodes != state.right_nodes ||
          state.left_edges != state.right_edges {
          state.equal = false
          state.phase = EmitResult
        } else {
          state.phase = FindNode
        }
      FindNode =>
        if state.record >= state.left_nodes {
          state.record = 0
          state.candidate = 0
          state.phase = FindEdge
        } else if state.candidate >= state.right_nodes {
          state.equal = false
          state.phase = EmitResult
        } else {
          state.position = 0
          state.phase = CompareNodeKey
        }
      CompareNodeKey | CompareEdgeKey | CompareEdgeSource | CompareEdgeTarget => {
        guard property_equality_keys(state) is Some((left, right)) else {
          return @bounded.Failed(
            PropertyEqualityInputUnavailable,
            progress,
            used,
          )
        }
        let (order, next) = graph_identity_compare_unit(
          left,
          right,
          state.position,
        )
        state.position = next
        match order {
          None => ()
          Some(value) if value != 0 =>
            if state.phase == CompareNodeKey || state.phase == CompareEdgeKey {
              state.candidate += 1
              state.phase = if state.phase == CompareNodeKey {
                FindNode
              } else {
                FindEdge
              }
            } else {
              state.equal = false
              state.phase = EmitResult
            }
          Some(_) => {
            state.position = 0
            match state.phase {
              CompareNodeKey => {
                state.matched = state.candidate
                state.property = 0
                state.phase = CompareNodeProperty
              }
              CompareEdgeKey => state.phase = CompareEdgeSource
              CompareEdgeSource => state.phase = CompareEdgeTarget
              CompareEdgeTarget => {
                state.matched = state.candidate
                state.property = 0
                state.phase = CompareEdgeProperty
              }
              _ =>
                return @bounded.Failed(
                  InvalidPropertyEqualityKernel,
                  progress,
                  used,
                )
            }
          }
        }
      }
      CompareNodeProperty | CompareEdgeProperty => {
        let edge = state.phase == CompareEdgeProperty
        guard property_equality_count(state.left, state.record, edge)
          is Some(count) &&
          property_equality_count(state.right, state.matched, edge)
          is Some(other_count) else {
          return @bounded.Failed(
            PropertyEqualityInputUnavailable,
            progress,
            used,
          )
        }
        if count != other_count {
          state.equal = false
          state.phase = EmitResult
        } else if state.property >= count {
          state.record += 1
          state.candidate = 0
          state.phase = if edge { FindEdge } else { FindNode }
        } else if state.comparison is None {
          guard property_equality_field(
              state.left,
              state.record,
              state.property,
              edge,
            )
            is Some(left) &&
            property_equality_field(
              state.right,
              state.matched,
              state.property,
              edge,
            )
            is Some(right) else {
            return @bounded.Failed(
              PropertyEqualityInputUnavailable,
              progress,
              used,
            )
          }
          let limits : @value.Limits = {
            max_nodes: state.value_nodes,
            max_depth: state.value_depth,
            max_text_bytes: state.value_text_bytes,
          }
          match @value.start_complete_equality(left, right, limits) {
            Ok(comparison) => state.comparison = Some(comparison)
            Err(issue) =>
              return @bounded.Failed(
                PropertyEqualityValue(issue),
                progress,
                used,
              )
          }
        } else {
          guard state.comparison is Some(comparison) else {
            return @bounded.Failed(
              InvalidPropertyEqualityKernel,
              progress,
              used,
            )
          }
          match @value.advance_complete_equality(comparison, 1) {
            @value.EqualityContinue(_) => ()
            @value.EqualityComplete(equal~, ..) => {
              state.comparison = None
              if equal {
                state.property += 1
              } else {
                state.equal = false
                state.phase = EmitResult
              }
            }
            @value.EqualityFailed(issue, ..) =>
              return @bounded.Failed(
                PropertyEqualityValue(issue),
                progress,
                used,
              )
          }
        }
      }
      FindEdge =>
        if state.record >= state.left_edges {
          state.phase = EmitResult
        } else if state.candidate >= state.right_edges {
          state.equal = false
          state.phase = EmitResult
        } else {
          state.position = 0
          state.phase = CompareEdgeKey
        }
      EmitResult => {
        guard @schema.field_count(state.schema) == 1 &&
          @schema.field_at(state.schema, 0) is Some(field) &&
          field.name == @schema.Unqualified("equal") &&
          @value.checked_boolean_value(state.equal, field.contract)
          is Some(result) else {
          return @bounded.Failed(InvalidPropertyEqualityKernel, progress, used)
        }
        match @execution.append_admitted_output(output, [result]) {
          Ok(_) => {
            state.phase = FinishResult
            progress += 1
          }
          Err(issue) =>
            return @bounded.Failed(
              PropertyEqualityOutput(issue),
              progress,
              used,
            )
        }
      }
      FinishResult => {
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(rows) => rows
          Err(issue) =>
            return @bounded.Failed(
              PropertyEqualityOutput(issue),
              progress,
              used,
            )
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(PropertyEqualityCompletion(issue), progress, used)
        }
      }
    }
  }
  state.work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_property_equality_state(state : PropertyEqualityState) -> Bool {
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  state.comparison = None
  true
}

///|
pub fn start_property_equality_views(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  left : @lifecycle.ProducerView,
  right : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  control_work_limit : Int,
) -> Result[PropertyEqualityExecution, PropertyEqualityIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphEqualityStep(checked)) &&
    @lifecycle.producer_view_kind(left) == @carrier.GraphKind &&
    @lifecycle.producer_view_kind(right) == @carrier.GraphKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(left),
      owner,
      step,
      0,
    ) &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(right),
      owner,
      step,
      1,
    ) else {
    return Err(InvalidPropertyEqualityKernel)
  }
  let first = Viewed(left)
  let second = Viewed(right)
  guard graph_read_available(first) &&
    graph_read_available(second) &&
    graph_read_node_count(first) is Some(left_nodes) &&
    graph_read_node_count(second) is Some(right_nodes) &&
    graph_read_edge_count(first) is Some(left_edges) &&
    graph_read_edge_count(second) is Some(right_edges) &&
    graph_read_property_definition(first) is Some(first_definition) &&
    graph_read_property_definition(second) is Some(second_definition) &&
    @graph_type.property_equality_input(
      @lower.graph_equality_checked(checked),
      right=false,
    )
    is @carrier.GraphValue(checked_left) &&
    @graph_type.property_equality_input(
      @lower.graph_equality_checked(checked),
      right=true,
    )
    is @carrier.GraphValue(checked_right) &&
    @carrier.property_graph_domain(first_definition) ==
    @carrier.property_graph_domain(
      @carrier.graph_property_definition(checked_left),
    ) &&
    @carrier.property_graph_domain(second_definition) ==
    @carrier.property_graph_domain(
      @carrier.graph_property_definition(checked_right),
    ) else {
    return Err(PropertyEqualityInputUnavailable)
  }
  // Matching is a bounded scan of the retained identity indexes. No complete
  // key or record is copied at start; a live comparison holds one cursor.
  if max_workspace_slots < 1 || max_rows < 1 {
    return Err(PropertyEqualityWorkspaceLimit)
  }
  if control_work_limit < 0 {
    return Err(PropertyEqualityWorkLimit)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(output) => output
    Err(issue) => return Err(PropertyEqualityOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    @execution.prepare_trusted_output_port_with_inputs(
      preparation,
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=[
        @execution.trusted_output_carrier_input(
          @lifecycle.producer_view_read_reference(left),
        ),
        @execution.trusted_output_carrier_input(
          @lifecycle.producer_view_read_reference(right),
        ),
      ],
    ) {
    Ok(port) => port
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(PropertyEqualityCompletion(issue))
    }
  }
  let state : PropertyEqualityState = {
    left: first,
    right: second,
    left_nodes,
    right_nodes,
    left_edges,
    right_edges,
    schema: @lower.graph_equality_output_schema(checked),
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    phase: CompareCounts,
    equal: true,
    record: 0,
    candidate: 0,
    matched: 0,
    position: 0,
    property: 0,
    comparison: None,
    work_remaining: control_work_limit,
    value_nodes: limits.max_nodes,
    value_depth: limits.max_depth,
    value_text_bytes: limits.max_text_bytes,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    property_equality_step,
    cleanup_property_equality_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn advance_property_equality(
  value : PropertyEqualityExecution,
  quantum : Int,
) -> Result[PropertyEqualityPoll, PropertyEqualityIssue] {
  guard value.token is Some(token) else {
    return Err(PropertyEqualityExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(PropertyEqualityExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(PropertyEqualityContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(PropertyEqualityComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(PropertyEqualityFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(PropertyEqualityStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn property_equality_cleanup_pending(
  value : PropertyEqualityExecution,
) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_property_equality(
  value : PropertyEqualityExecution,
) -> Result[Bool, PropertyEqualityIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    PropertyEqualityExecutionIssue(issue)
  })
}
