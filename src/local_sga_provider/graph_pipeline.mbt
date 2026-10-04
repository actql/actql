///|
priv enum Phase {
  StartConstruction
  Construction
  StartProjection
  Projection
  Terminal
}

///|
priv enum RelationExecution {
  MatchNodesExecution(@sga.MatchNodesExecution)
  MatchEdgesExecution(@sga.MatchEdgesExecution)
  TraverseExecution(@sga.TraverseExecution)
  GraphRowsExecution(@bridge.EventsToRowsExecution)
  GraphBoundsExecution(@sga.GraphBoundsExecution)
  GraphDegreeExecution(@sga.GraphDegreeExecution)
  ComponentsExecution(@sga.ComponentsExecution)
}

///|
priv enum RelationPoll {
  RelationContinue(Int64, Int64)
  RelationComplete(@execution.CompletedOutput, Int64, Int64)
  RelationFailed(Int64, Int64)
  RelationStopped(Int64, Int64)
}

///|
priv struct Execution {
  generated : @execution.GeneratedSequence
  sequence : @lower.PreparedSequence
  inputs : Array[@execution.ProducerRead]
  carrier_inputs : Array[@lifecycle.ProducerView]
  control : @bounded.Control
  limits : @storage.Limits
  storage_bytes : Int64
  snapshot_policy : SnapshotPolicy?
  max_rows : Int
  max_value_bytes : Int
  selected_step : Int?
  projection_step : Int
  construction_steps : Int
  mut phase : Phase
  constructions : Array[@bridge.RowsToGraphExecution]
  mut graph : @graph.Completed?
  mut relation : RelationExecution?
  mut stage_progress : Int64
  mut stage_work : Int64
  mut terminal : Bool
  mut reclaimed : Bool
}

///|
/// Installed serialization/read bounds and advertised private workspace.
/// They are not supplied by a Program or a persisted header and do not claim
/// a machine-independent heap-size theorem for the Graph implementation.
pub(all) struct SnapshotPolicy {
  serialization : @snapshot.Limits
  read : @decode.Limits
  maximum_bytes : Int
  maximum_frame_bytes : Int
  workspace_bytes : Int64
}

///|
fn valid_snapshot_policy(value : SnapshotPolicy) -> Bool {
  value.maximum_bytes > 0 &&
  value.maximum_frame_bytes > 0 &&
  value.maximum_frame_bytes <= value.maximum_bytes &&
  value.maximum_frame_bytes <= 16777216 &&
  value.workspace_bytes >= value.maximum_bytes.to_int64() * 4L &&
  value.serialization.max_workspace_slots >= 0 &&
  value.serialization.max_identity_bytes >= 0 &&
  value.serialization.max_identity_nodes >= 0 &&
  value.serialization.max_identity_depth >= 0 &&
  value.serialization.value_limits.max_nodes >= 0 &&
  value.serialization.value_limits.max_depth >= 0 &&
  value.serialization.value_limits.max_text_bytes >= 0 &&
  value.read.max_nodes > 0 &&
  value.read.max_depth > 0 &&
  value.read.max_string_bytes >= 0 &&
  value.read.max_total_string_bytes >= 0
}

///|
fn constructor_material(sequence : @execution.GeneratedSequence) -> Bool {
  let selected = @execution.completion_preparation_selected_step(
    @execution.generated_completion_preparation(sequence),
  )
  if selected is None && @execution.generated_sequence_step_count(sequence) != 1 {
    return false
  }
  @lower.sequence_step(
    @execution.generated_prepared_sequence(sequence),
    selected.unwrap_or(0),
  )
  is Some(@lower.PropertyGraphConstructionStep(_))
}

///|
fn issue() -> @connector.FixedComputeIssue {
  @connector.Execution(@execution.InputSet)
}

///|
fn accepts_traverse(value : @lower.PreparedGraphTraverse) -> Bool {
  let hop_count = @lower.graph_traverse_hop_count(value)
  let bounds = if @lower.graph_traverse_patterned(value) {
    Some((hop_count.to_int64(), hop_count.to_int64()))
  } else {
    @lower.graph_traverse_bounds(value)
  }
  bounds is Some((minimum, maximum)) &&
  minimum <= 2147483647L &&
  maximum <= 2147483647L &&
  (
    @lower.graph_traverse_start_id_count(value) > 0 ||
    @lower.graph_traverse_start_relation_field(value) is Some(_)
  ) &&
  hop_count > 0 &&
  ({
    let mut valid = true
    for hop in 0..<hop_count {
      if @lower.graph_traverse_hop_direction(value, hop) is None {
        valid = false
      }
    }
    valid
  })
}

///|
fn fail_execution(
  value : Execution,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  value.terminal = true
  value.phase = Terminal
  Ok(@local.managed_provider_failed(issue(), 0L, 0L))
}

///|
fn accepts(sequence : @execution.GeneratedSequence) -> Bool {
  let owner = @execution.generated_sequence_owner(sequence)
  let prepared = @lower.bound_preparation(owner)
  let selected = @execution.completion_preparation_selected_step(
    @execution.generated_completion_preparation(sequence),
  )
  let accepts_step = fn(index, operation) {
    guard @lower.node_at(prepared, index) is Some(node) else { return false }
    // The prepared owner's typed ports, not wire spelling or a legacy module
    // claim, select the one current Graph representation.
    let current_graph = fn(carrier) {
      match carrier {
        @carrier.GraphValue(_) => true
        _ => false
      }
    }
    match operation {
      @lower.PropertyGraphConstructionStep(_) =>
        @lower.operation(node) == "BRIDGE.rows.to_property_graph" &&
        current_graph(@lower.node_output_carrier(node))
      @lower.GraphMatchStep(matched) => {
        guard @lower.node_input_target(node, 0) is Some(input) &&
          @lower.preparation_carrier_at(prepared, input) is Some(carrier) else {
          return false
        }
        current_graph(carrier) &&
        @lower.operation(node) ==
        (if @lower.graph_match_nodes(matched) {
          "SGA.match_nodes"
        } else {
          "SGA.match_edges"
        })
      }
      @lower.GraphTraverseStep(traverse) => {
        guard @lower.node_input_target(node, 0) is Some(input) &&
          @lower.preparation_carrier_at(prepared, input) is Some(carrier) else {
          return false
        }
        current_graph(carrier) &&
        @lower.operation(node) == "SGA.traverse" &&
        accepts_traverse(traverse)
      }
      @lower.CarrierProjectionStep(_) =>
        (
          @lower.operation(node) == "BRIDGE.graph.to_node_rows" ||
          @lower.operation(node) == "BRIDGE.graph.to_edge_rows"
        ) &&
        @lower.node_input_target(node, 0)
        .bind(target => @lower.preparation_carrier_at(prepared, target))
        .map(current_graph)
        .unwrap_or(false)
      @lower.GraphDiagnosticStep(diagnostic) => {
        guard @lower.node_input_target(node, 0) is Some(input) &&
          @lower.preparation_carrier_at(prepared, input) is Some(carrier) else {
          return false
        }
        current_graph(carrier) &&
        @lower.operation(node) ==
        (match @lower.graph_diagnostic_kind(diagnostic) {
          @lower.BoundsDiagnostic => "SGA.bounds_check"
          @lower.IncomingDegreeDiagnostic
          | @lower.OutgoingDegreeDiagnostic
          | @lower.TotalDegreeDiagnostic => "SGA.degree_metrics"
          @lower.WeakComponentsDiagnostic | @lower.StrongComponentsDiagnostic =>
            "SGA.components"
        })
      }
      // No tuple Graph constructor/projection or legacy SGA execution fallback.
      // Other new-profile operations remain explicit unsupported selections.
      _ => false
    }
  }
  if selected is Some(step) {
    return match
      @lower.sequence_step(
        @execution.generated_prepared_sequence(sequence),
        step,
      ) {
      Some(operation) => accepts_step(step, operation)
      None => false
    }
  }
  let count = @execution.generated_sequence_step_count(sequence)
  if count < 1 || count > 2 {
    return false
  }
  let index = Ref(0)
  let accepted = @execution.generated_sequence_all_steps(sequence, fn(step) {
    let current = index.val
    index.val += 1
    accepts_step(current, step)
  })
  if !accepted || index.val != count {
    return false
  }
  if count == 2 {
    // Multi-operation execution owns one constructor and one consumer. Longer
    // Programs use the existing selected-step task composition instead.
    match
      @lower.sequence_step(@execution.generated_prepared_sequence(sequence), 0) {
      Some(@lower.PropertyGraphConstructionStep(_)) => ()
      _ => return false
    }
    match
      @lower.sequence_step(@execution.generated_prepared_sequence(sequence), 1) {
      Some(@lower.GraphMatchStep(_))
      | Some(@lower.GraphTraverseStep(_))
      | Some(@lower.GraphDiagnosticStep(_)) => ()
      _ => return false
    }
  }
  true
}

///|
fn provider_capacity(
  base : @execution.ExecutionCapacity,
  storage_bytes : Int64,
  generation_count : Int,
  private_scratch_bytes : Int64,
) -> @execution.ExecutionCapacity? {
  if storage_bytes < 0L || private_scratch_bytes < 0L || generation_count < 1 {
    return None
  }
  let count = generation_count.to_int64()
  if storage_bytes != 0L && count > 9223372036854775807L / storage_bytes {
    return None
  }
  let extra = storage_bytes * count
  let execution = @execution.execution_capacity_execution_bytes(base)
  if execution > 9223372036854775807L - extra ||
    private_scratch_bytes > 9223372036854775807L - execution - extra {
    return None
  }
  @execution.execution_capacity(
    @execution.execution_capacity_retained_bytes(base),
    execution + extra + private_scratch_bytes,
  )
}

///|
fn input_at(
  value : Execution,
  step : Int,
  edge : Int,
) -> @execution.ProducerRead? {
  let owner = @execution.generated_sequence_owner(value.generated)
  for input in value.inputs {
    if @execution.producer_read_matches_operation_input(
        input, owner, step, edge,
      ) {
      return Some(input)
    }
  }
  None
}

///|
fn delta(current : Int64, prior : Int64) -> Int64? {
  if current < prior {
    None
  } else {
    Some(current - prior)
  }
}

///|
fn reset_stage(value : Execution) -> Unit {
  value.stage_progress = 0L
  value.stage_work = 0L
}

///|
fn continue_poll(
  value : Execution,
  progress : Int64,
  work : Int64,
) -> @local.ManagedProviderPoll? {
  guard delta(progress, value.stage_progress) is Some(progress_delta) &&
    delta(work, value.stage_work) is Some(work_delta) else {
    return None
  }
  value.stage_progress = progress
  value.stage_work = work
  Some(@local.managed_provider_continue(progress_delta, work_delta))
}

///|
fn terminal_poll(
  value : Execution,
  progress : Int64,
  work : Int64,
  stopped : Bool,
) -> @local.ManagedProviderPoll? {
  guard delta(progress, value.stage_progress) is Some(progress_delta) &&
    delta(work, value.stage_work) is Some(work_delta) else {
    return None
  }
  value.terminal = true
  value.phase = Terminal
  if stopped {
    Some(@local.managed_provider_stopped_poll(progress_delta, work_delta))
  } else {
    Some(@local.managed_provider_failed(issue(), progress_delta, work_delta))
  }
}

///|
fn discard(value : @graph.Completed?) -> Bool {
  match value {
    Some(output) => @graph.discard_completed(output)
    None => false
  }
}

///|
fn advance_execution(
  value : Execution,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  if quantum <= 0 || value.terminal {
    return Err(@connector.InvalidLimits)
  }
  while true {
    match value.phase {
      StartConstruction => {
        let step = value.selected_step.unwrap_or(0)
        if value.selected_step is None && step >= value.construction_steps {
          return fail_execution(value)
        }
        // The keyed contract uses the existing bounded construction session;
        // completion and cleanup stay with the same provider and lifecycle.
        let started = match @lower.sequence_step(value.sequence, step) {
          Some(@lower.PropertyGraphConstructionStep(graph)) => {
            let count = @lower.property_graph_construction_node_count(graph) +
              @lower.property_graph_construction_edge_count(graph)
            let inputs = []
            for edge in 0..<count {
              guard input_at(value, step, edge) is Some(input) else {
                return fail_execution(value)
              }
              inputs.push(input)
            }
            @bridge.start_rows_to_property_graph(
              value.control,
              value.sequence,
              step,
              inputs,
              value.limits,
              value.storage_bytes,
              value.limits.max_workspace_slots,
              fn() { true },
              control_work_limit=Some(value.limits.max_work),
            )
          }
          _ => return fail_execution(value)
        }
        let started = match started {
          Ok(execution) => execution
          Err(_) => return fail_execution(value)
        }
        value.constructions.push(started)
        value.phase = Construction
        reset_stage(value)
      }
      Construction => {
        guard value.constructions.last() is Some(active) else {
          return fail_execution(value)
        }
        match @bridge.advance_rows_to_graph(active, quantum) {
          Err(_) => return fail_execution(value)
          Ok(@bridge.Continue(progress~, work~)) => {
            guard continue_poll(value, progress, work) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok(@bridge.Complete(output, progress~, work~)) => {
            if constructor_material(value.generated) {
              guard delta(progress, value.stage_progress)
                is Some(progress_delta) &&
                delta(work, value.stage_work) is Some(work_delta) else {
                @graph.discard_completed(output) |> ignore
                return fail_execution(value)
              }
              let prepared_material = match value.snapshot_policy {
                None => @graph.completed_material(output).map_err(_ => issue())
                Some(policy) =>
                  @bridge.completed_property_snapshot_material(
                    value.control,
                    @execution.generated_sequence_owner(value.generated),
                    @pipeline.Step(value.selected_step.unwrap_or(0)),
                    output,
                    value.limits,
                    policy.serialization,
                    policy.read,
                    policy.maximum_bytes,
                    policy.maximum_frame_bytes,
                    policy.workspace_bytes,
                    // Restored output belongs to its own completion owner.
                    // Releasing this provider's scratch must not revoke that
                    // generation. The snapshot port checks source availability
                    // and the restored lifecycle still enforces reclamation.
                    () => true,
                  ).map_err(_ => issue())
              }
              let material = match prepared_material {
                Ok(value) => value
                Err(_) => {
                  @graph.discard_completed(output) |> ignore
                  return fail_execution(value)
                }
              }
              value.terminal = true
              value.phase = Terminal
              return Ok(
                @local.managed_provider_carrier_complete(
                  material, progress_delta, work_delta,
                ),
              )
            }
            guard continue_poll(value, progress, work) is Some(poll) else {
              return fail_execution(value)
            }
            value.graph = Some(output)
            value.phase = StartProjection
            if poll is @local.Continue(work=work_delta, ..) && work_delta > 0L {
              return Ok(poll)
            }
          }
          Ok(@bridge.Failed(_, progress~, work~)) => {
            guard terminal_poll(value, progress, work, false) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok(@bridge.Stopped(_, progress~, work~)) => {
            guard terminal_poll(value, progress, work, true) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
        }
      }
      StartProjection => {
        let direct_view = if value.graph is None &&
          value.carrier_inputs.length() == 1 {
          Some(value.carrier_inputs[0])
        } else {
          None
        }
        let input = if direct_view is Some(_) {
          None
        } else {
          guard value.graph is Some(output) else {
            return fail_execution(value)
          }
          match
            @graph.prepare_step_read(
              @execution.generated_sequence_owner(value.generated),
              value.projection_step,
              0,
              output,
            ) {
            Ok(read) => Some(read)
            Err(_) => return fail_execution(value)
          }
        }
        let started = match
          @lower.sequence_step(value.sequence, value.projection_step) {
          Some(@lower.GraphMatchStep(matched)) =>
            if @lower.graph_match_nodes(matched) {
              let started = if direct_view is Some(view) {
                @sga.start_match_nodes_view(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  view,
                  value.max_rows,
                  {
                    max_nodes: value.limits.max_value_nodes,
                    max_text_bytes: value.max_value_bytes,
                    max_depth: value.limits.max_value_depth,
                    max_work: value.limits.max_work,
                  },
                  value.limits.max_workspace_slots,
                  value.limits.max_value_bytes,
                  value.limits.max_value_bytes,
                  value.inputs,
                  control_work_limit=Some(value.limits.max_work),
                )
              } else {
                guard input is Some(read) else { return fail_execution(value) }
                @sga.start_match_nodes(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  read,
                  value.max_rows,
                  {
                    max_nodes: value.limits.max_value_nodes,
                    max_text_bytes: value.max_value_bytes,
                    max_depth: value.limits.max_value_depth,
                    max_work: value.limits.max_work,
                  },
                  value.limits.max_workspace_slots,
                  value.limits.max_value_bytes,
                  value.limits.max_value_bytes,
                  value.inputs,
                  control_work_limit=Some(value.limits.max_work),
                )
              }
              match started {
                Ok(execution) => MatchNodesExecution(execution)
                Err(_) => return fail_execution(value)
              }
            } else {
              let started = if direct_view is Some(view) {
                @sga.start_match_edges_view(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  view,
                  value.max_rows,
                  {
                    max_nodes: value.limits.max_value_nodes,
                    max_text_bytes: value.max_value_bytes,
                    max_depth: value.limits.max_value_depth,
                    max_work: value.limits.max_work,
                  },
                  value.limits.max_workspace_slots,
                  value.limits.max_value_bytes,
                  value.limits.max_value_bytes,
                  value.inputs,
                  control_work_limit=Some(value.limits.max_work),
                )
              } else {
                guard input is Some(read) else { return fail_execution(value) }
                @sga.start_match_edges(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  read,
                  value.max_rows,
                  {
                    max_nodes: value.limits.max_value_nodes,
                    max_text_bytes: value.max_value_bytes,
                    max_depth: value.limits.max_value_depth,
                    max_work: value.limits.max_work,
                  },
                  value.limits.max_workspace_slots,
                  value.limits.max_value_bytes,
                  value.limits.max_value_bytes,
                  value.inputs,
                  control_work_limit=Some(value.limits.max_work),
                )
              }
              match started {
                Ok(execution) => MatchEdgesExecution(execution)
                Err(_) => return fail_execution(value)
              }
            }
          Some(@lower.GraphTraverseStep(_)) => {
            // The checked search envelope is independent of output cardinality.
            // Public dispatch always binds it from the captured limit owner.
            let (paths, rows) = @execution.generated_traversal_ceilings(
              value.generated,
              value.projection_step,
            ).unwrap_or(
              (
                value.limits.max_workspace_slots.to_int64(),
                value.max_rows.to_int64(),
              ),
            )
            let max_paths = if paths < 2147483647L {
              paths.to_int()
            } else {
              2147483647
            }
            let max_rows = if rows < value.max_rows.to_int64() {
              rows.to_int()
            } else {
              value.max_rows
            }
            let started = if direct_view is Some(view) {
              @sga.start_traverse_view(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                value.projection_step,
                view,
                max_rows,
                {
                  max_nodes: value.limits.max_value_nodes,
                  max_text_bytes: value.max_value_bytes,
                  max_depth: value.limits.max_value_depth,
                  max_work: value.limits.max_work,
                },
                value.limits.max_workspace_slots,
                value.limits.max_value_bytes,
                value.limits.max_value_bytes,
                value.inputs,
                max_paths~,
              )
            } else {
              guard input is Some(input) else { return fail_execution(value) }
              @sga.start_traverse(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                value.projection_step,
                input,
                max_rows,
                {
                  max_nodes: value.limits.max_value_nodes,
                  max_text_bytes: value.max_value_bytes,
                  max_depth: value.limits.max_value_depth,
                  max_work: value.limits.max_work,
                },
                value.limits.max_workspace_slots,
                value.limits.max_value_bytes,
                value.limits.max_value_bytes,
                value.inputs,
                max_paths~,
              )
            }
            match started {
              Ok(execution) => TraverseExecution(execution)
              Err(_) => return fail_execution(value)
            }
          }
          Some(@lower.CarrierProjectionStep(_)) => {
            let limits : @execution.ValueLimits = {
              max_nodes: value.limits.max_value_nodes,
              max_text_bytes: value.max_value_bytes,
              max_depth: value.limits.max_value_depth,
              max_work: value.limits.max_work,
            }
            let started = if direct_view is Some(view) {
              @bridge.start_graph_view_to_rows(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                value.projection_step,
                view,
                value.max_rows,
                limits,
                value.limits.max_workspace_slots,
                value.limits.max_value_bytes,
                control_work_limit=Some(value.limits.max_work),
              )
            } else {
              guard input is Some(read) else { return fail_execution(value) }
              @bridge.start_graph_to_rows(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                value.projection_step,
                read,
                value.max_rows,
                limits,
                value.limits.max_workspace_slots,
                value.limits.max_value_bytes,
                value.inputs,
                control_work_limit=Some(value.limits.max_work),
              )
            }
            match started {
              Ok(execution) => GraphRowsExecution(execution)
              Err(_) => return fail_execution(value)
            }
          }
          Some(@lower.GraphDiagnosticStep(diagnostic)) => {
            let limits : @execution.ValueLimits = {
              max_nodes: value.limits.max_value_nodes,
              max_text_bytes: value.max_value_bytes,
              max_depth: value.limits.max_value_depth,
              max_work: value.limits.max_work,
            }
            if @lower.graph_diagnostic_kind(diagnostic) ==
              @lower.BoundsDiagnostic {
              let started = if direct_view is Some(view) {
                @sga.start_graph_bounds_view(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  view,
                  value.max_rows,
                  limits,
                  value.limits.max_workspace_slots,
                  value.limits.max_value_bytes,
                  value.limits.max_value_bytes,
                  value.inputs,
                  control_work_limit=Some(value.limits.max_work),
                )
              } else {
                guard input is Some(read) else { return fail_execution(value) }
                @sga.start_graph_bounds(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  read,
                  value.max_rows,
                  limits,
                  value.limits.max_workspace_slots,
                  value.limits.max_value_bytes,
                  value.limits.max_value_bytes,
                  value.inputs,
                  control_work_limit=Some(value.limits.max_work),
                )
              }
              match started {
                Ok(execution) => GraphBoundsExecution(execution)
                Err(_) => return fail_execution(value)
              }
            } else if @lower.graph_diagnostic_kind(diagnostic) ==
              @lower.WeakComponentsDiagnostic ||
              @lower.graph_diagnostic_kind(diagnostic) ==
              @lower.StrongComponentsDiagnostic {
              let started = if direct_view is Some(view) {
                @sga.start_components_view(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  view,
                  value.max_rows,
                  limits,
                  value.limits.max_workspace_slots,
                  value.limits.max_value_bytes,
                  value.limits.max_value_bytes,
                  value.inputs,
                  control_work_limit=Some(value.limits.max_work),
                )
              } else {
                guard input is Some(read) else { return fail_execution(value) }
                @sga.start_components(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  read,
                  value.max_rows,
                  limits,
                  value.limits.max_workspace_slots,
                  value.limits.max_value_bytes,
                  value.limits.max_value_bytes,
                  value.inputs,
                  control_work_limit=Some(value.limits.max_work),
                )
              }
              match started {
                Ok(execution) => ComponentsExecution(execution)
                Err(_) => return fail_execution(value)
              }
            } else {
              let started = if direct_view is Some(view) {
                @sga.start_graph_degree_view(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  view,
                  value.max_rows,
                  limits,
                  value.limits.max_workspace_slots,
                  value.limits.max_value_bytes,
                  value.limits.max_value_bytes,
                  value.inputs,
                  control_work_limit=Some(value.limits.max_work),
                )
              } else {
                guard input is Some(read) else { return fail_execution(value) }
                @sga.start_graph_degree(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  read,
                  value.max_rows,
                  limits,
                  value.limits.max_workspace_slots,
                  value.limits.max_value_bytes,
                  value.limits.max_value_bytes,
                  value.inputs,
                  control_work_limit=Some(value.limits.max_work),
                )
              }
              match started {
                Ok(execution) => GraphDegreeExecution(execution)
                Err(_) => return fail_execution(value)
              }
            }
          }
          _ => return fail_execution(value)
        }
        value.relation = Some(started)
        value.phase = Projection
        reset_stage(value)
      }
      Projection => {
        guard value.relation is Some(active) else {
          return fail_execution(value)
        }
        let poll = match active {
          MatchNodesExecution(execution) =>
            match @sga.advance_match_nodes(execution, quantum) {
              Ok(@sga.MatchNodesContinue(progress~, work~)) =>
                Ok(RelationContinue(progress, work))
              Ok(@sga.MatchNodesComplete(output, progress~, work~)) =>
                Ok(RelationComplete(output, progress, work))
              Ok(@sga.MatchNodesFailed(_, progress~, work~)) =>
                Ok(RelationFailed(progress, work))
              Ok(@sga.MatchNodesStopped(_, progress~, work~)) =>
                Ok(RelationStopped(progress, work))
              Err(_) => Err(issue())
            }
          MatchEdgesExecution(execution) =>
            match @sga.advance_match_edges(execution, quantum) {
              Ok(@sga.MatchEdgesContinue(progress~, work~)) =>
                Ok(RelationContinue(progress, work))
              Ok(@sga.MatchEdgesComplete(output, progress~, work~)) =>
                Ok(RelationComplete(output, progress, work))
              Ok(@sga.MatchEdgesFailed(_, progress~, work~)) =>
                Ok(RelationFailed(progress, work))
              Ok(@sga.MatchEdgesStopped(_, progress~, work~)) =>
                Ok(RelationStopped(progress, work))
              Err(_) => Err(issue())
            }
          TraverseExecution(execution) =>
            match @sga.advance_traverse(execution, quantum) {
              Ok(@sga.TraverseContinue(progress~, work~)) =>
                Ok(RelationContinue(progress, work))
              Ok(@sga.TraverseComplete(output, progress~, work~)) =>
                Ok(RelationComplete(output, progress, work))
              Ok(@sga.TraverseFailed(_, progress~, work~)) =>
                Ok(RelationFailed(progress, work))
              Ok(@sga.TraverseStopped(_, progress~, work~)) =>
                Ok(RelationStopped(progress, work))
              Err(_) => Err(issue())
            }
          GraphRowsExecution(execution) =>
            match @bridge.advance_events_to_rows(execution, quantum) {
              Ok(@bridge.Continue(progress~, work~)) =>
                Ok(RelationContinue(progress, work))
              Ok(@bridge.Complete(output, progress~, work~)) =>
                Ok(RelationComplete(output, progress, work))
              Ok(@bridge.Failed(_, progress~, work~)) =>
                Ok(RelationFailed(progress, work))
              Ok(@bridge.Stopped(_, progress~, work~)) =>
                Ok(RelationStopped(progress, work))
              Err(_) => Err(issue())
            }
          GraphBoundsExecution(execution) =>
            match @sga.advance_graph_bounds(execution, quantum) {
              Ok(@sga.GraphBoundsContinue(progress~, work~)) =>
                Ok(RelationContinue(progress, work))
              Ok(@sga.GraphBoundsComplete(output, progress~, work~)) =>
                Ok(RelationComplete(output, progress, work))
              Ok(@sga.GraphBoundsFailed(_, progress~, work~)) =>
                Ok(RelationFailed(progress, work))
              Ok(@sga.GraphBoundsStopped(_, progress~, work~)) =>
                Ok(RelationStopped(progress, work))
              Err(_) => Err(issue())
            }
          GraphDegreeExecution(execution) =>
            match @sga.advance_graph_degree(execution, quantum) {
              Ok(@sga.GraphDegreeContinue(progress~, work~)) =>
                Ok(RelationContinue(progress, work))
              Ok(@sga.GraphDegreeComplete(output, progress~, work~)) =>
                Ok(RelationComplete(output, progress, work))
              Ok(@sga.GraphDegreeFailed(_, progress~, work~)) =>
                Ok(RelationFailed(progress, work))
              Ok(@sga.GraphDegreeStopped(_, progress~, work~)) =>
                Ok(RelationStopped(progress, work))
              Err(_) => Err(issue())
            }
          ComponentsExecution(execution) =>
            match @sga.advance_components(execution, quantum) {
              Ok(@sga.ComponentsContinue(progress~, work~)) =>
                Ok(RelationContinue(progress, work))
              Ok(@sga.ComponentsComplete(output, progress~, work~)) =>
                Ok(RelationComplete(output, progress, work))
              Ok(@sga.ComponentsFailed(_, progress~, work~)) =>
                Ok(RelationFailed(progress, work))
              Ok(@sga.ComponentsStopped(_, progress~, work~)) =>
                Ok(RelationStopped(progress, work))
              Err(_) => Err(issue())
            }
        }
        match poll {
          Err(_) => return fail_execution(value)
          Ok(RelationContinue(progress, work)) => {
            guard continue_poll(value, progress, work) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok(RelationComplete(output, progress, work)) => {
            guard delta(progress, value.stage_progress) is Some(progress_delta) &&
              delta(work, value.stage_work) is Some(work_delta) else {
              return fail_execution(value)
            }
            discard(value.graph) |> ignore
            value.graph = None
            value.terminal = true
            value.phase = Terminal
            return Ok(
              @local.managed_provider_complete(
                output, progress_delta, work_delta,
              ),
            )
          }
          Ok(RelationFailed(progress, work)) => {
            guard terminal_poll(value, progress, work, false) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok(RelationStopped(progress, work)) => {
            guard terminal_poll(value, progress, work, true) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
        }
      }
      Terminal => return Err(@connector.InvalidLimits)
    }
  }
  Err(issue())
}

///|
fn cleanup_execution(
  value : Execution,
) -> Result[Bool, @connector.FixedComputeIssue] {
  if !value.terminal {
    return Ok(false)
  }
  if value.reclaimed {
    return Ok(true)
  }
  let mut failed = false
  for active in value.constructions {
    match @bridge.cleanup_rows_to_graph(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.relation is Some(active) {
    match active {
      MatchNodesExecution(execution) =>
        match @sga.cleanup_match_nodes(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
      MatchEdgesExecution(execution) =>
        match @sga.cleanup_match_edges(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
      TraverseExecution(execution) =>
        match @sga.cleanup_traverse(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
      GraphRowsExecution(execution) =>
        match @bridge.cleanup_events_to_rows(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
      GraphBoundsExecution(execution) =>
        match @sga.cleanup_graph_bounds(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
      GraphDegreeExecution(execution) =>
        match @sga.cleanup_graph_degree(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
      ComponentsExecution(execution) =>
        match @sga.cleanup_components(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
    }
  }
  discard(value.graph) |> ignore
  value.graph = None
  let mut construction_pending = false
  for active in value.constructions {
    if @bridge.rows_to_graph_cleanup_pending(active) {
      construction_pending = true
    }
  }
  let projection_pending = match value.relation {
    Some(MatchNodesExecution(active)) =>
      @sga.match_nodes_cleanup_pending(active)
    Some(MatchEdgesExecution(active)) =>
      @sga.match_edges_cleanup_pending(active)
    Some(TraverseExecution(active)) => @sga.traverse_cleanup_pending(active)
    Some(GraphRowsExecution(active)) =>
      @bridge.events_to_rows_cleanup_pending(active)
    Some(GraphBoundsExecution(active)) =>
      @sga.graph_bounds_cleanup_pending(active)
    Some(GraphDegreeExecution(active)) =>
      @sga.graph_degree_cleanup_pending(active)
    Some(ComponentsExecution(active)) => @sga.components_cleanup_pending(active)
    None => false
  }
  if failed {
    return Err(issue())
  }
  if construction_pending || projection_pending {
    return Ok(false)
  }
  value.reclaimed = true
  Ok(true)
}

///|
pub fn provider(
  limits : @storage.Limits,
  storage_bytes : Int64,
  capacity : @execution.ExecutionCapacity,
  snapshot_policy? : SnapshotPolicy? = None,
) -> @local.ManagedProvider {
  @local.managed_provider_with_inputs(
    accepts,
    sequence => {
      if accepts(sequence) &&
        (
          snapshot_policy is None ||
          (snapshot_policy is Some(policy) && valid_snapshot_policy(policy))
        ) {
        provider_capacity(
          capacity,
          storage_bytes,
          @lower.sequence_count(
            @execution.generated_prepared_sequence(sequence),
          ),
          if constructor_material(sequence) {
            snapshot_policy.map(policy => policy.workspace_bytes).unwrap_or(0L)
          } else {
            0L
          },
        )
      } else {
        None
      }
    },
    fn(sequence, inputs, max_rows, max_value_bytes, _execution) {
      if !accepts(sequence) ||
        storage_bytes < 0L ||
        (snapshot_policy is Some(policy) && !valid_snapshot_policy(policy)) {
        return Err(@connector.InvalidLimits)
      }
      let relations = []
      let carriers = []
      let selected_step = @execution.completion_preparation_selected_step(
        @execution.generated_completion_preparation(sequence),
      )
      for input in inputs {
        match input {
          @local.RelationInput(value) => relations.push(value)
          @local.SuppliedRelationInput(_) =>
            return Err(@connector.Execution(@execution.InputSet))
          @local.CarrierInput(value) => carriers.push(value)
        }
      }
      let direct_traverse = match
        @lower.sequence_step(
          @execution.generated_prepared_sequence(sequence),
          selected_step.unwrap_or(0),
        ) {
        Some(@lower.GraphTraverseStep(_)) => selected_step is Some(_)
        _ => false
      }
      let direct_traverse_relation_count = match
        @lower.sequence_step(
          @execution.generated_prepared_sequence(sequence),
          selected_step.unwrap_or(0),
        ) {
        Some(@lower.GraphTraverseStep(traverse)) =>
          if @lower.graph_traverse_start_relation_field(traverse) is Some(_) {
            1
          } else {
            0
          }
        _ => 1
      }
      let direct_match = match
        @lower.sequence_step(
          @execution.generated_prepared_sequence(sequence),
          selected_step.unwrap_or(0),
        ) {
        Some(@lower.GraphMatchStep(_)) => selected_step is Some(_)
        Some(@lower.CarrierProjectionStep(_)) => selected_step is Some(_)
        _ => false
      }
      let direct_diagnostic = match
        @lower.sequence_step(
          @execution.generated_prepared_sequence(sequence),
          selected_step.unwrap_or(0),
        ) {
        Some(@lower.GraphDiagnosticStep(_)) => selected_step is Some(_)
        _ => false
      }
      let property_inputs = match
        @lower.sequence_step(
          @execution.generated_prepared_sequence(sequence),
          selected_step.unwrap_or(0),
        ) {
        Some(@lower.PropertyGraphConstructionStep(graph)) =>
          Some(
            @lower.property_graph_construction_node_count(graph) +
            @lower.property_graph_construction_edge_count(graph),
          )
        _ => None
      }
      if property_inputs is Some(count) {
        // A selected task has one read per checked operation occurrence. A
        // fused prefix instead has one read per pipeline input, which can be
        // reused by several definitions. Construction still checks every
        // occurrence through input_at; no producer identity is inferred.
        let expected = if selected_step is Some(_) {
          count
        } else {
          @lower.preparation_input_count(
            @lower.bound_preparation(
              @execution.generated_sequence_owner(sequence),
            ),
          )
        }
        if relations.length() != expected || !carriers.is_empty() {
          return Err(@connector.Execution(@execution.InputSet))
        }
      } else if direct_match || direct_traverse || direct_diagnostic {
        if carriers.length() != 1 ||
          relations.length() !=
          (if direct_traverse { direct_traverse_relation_count } else { 0 }) {
          return Err(@connector.Execution(@execution.InputSet))
        }
      } else if !carriers.is_empty() {
        return Err(@connector.Execution(@execution.InputSet))
      }
      let construction_steps = if property_inputs is Some(_) { 1 } else { 0 }
      let state : Execution = {
        generated: sequence,
        sequence: @execution.generated_prepared_sequence(sequence),
        inputs: relations,
        carrier_inputs: carriers,
        control: @bounded.control(),
        limits,
        storage_bytes,
        snapshot_policy: if constructor_material(sequence) {
          snapshot_policy
        } else {
          None
        },
        max_rows,
        max_value_bytes,
        selected_step,
        projection_step: selected_step.unwrap_or(
          @execution.generated_sequence_step_count(sequence) - 1,
        ),
        construction_steps,
        phase: if construction_steps == 1 {
          StartConstruction
        } else {
          StartProjection
        },
        constructions: [],
        graph: None,
        relation: None,
        stage_progress: 0L,
        stage_work: 0L,
        terminal: false,
        reclaimed: false,
      }
      Ok(
        @local.managed_provider_execution(
          quantum => advance_execution(state, quantum),
          fn() { @bounded.request_cancel(state.control) },
          fn() { state.terminal },
          fn() { cleanup_execution(state) },
        ),
      )
    },
  )
}
