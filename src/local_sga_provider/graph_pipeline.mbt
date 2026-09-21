///|
priv enum Phase {
  StartConstruction
  Construction
  StartKernel
  Kernel
  CleanupKernel
  StartProjection
  Projection
  Terminal
}

///|
priv enum GraphExecution {
  Normalize(@sga.NormalizeExecution)
  Graft(@sga.GraftExecution)
}

///|
priv enum RelationExecution {
  ProjectionExecution(@bridge.GraphRowsExecution)
  MatchNodesExecution(@sga.MatchNodesExecution)
  MatchEdgesExecution(@sga.MatchEdgesExecution)
  GraphBoundsExecution(@sga.GraphBoundsExecution)
  GraphDegreeExecution(@sga.GraphDegreeExecution)
  ComponentsExecution(@sga.ComponentsExecution)
  ReachExecution(@sga.ReachExecution)
  TraverseExecution(@sga.TraverseExecution)
  GraphsEqualExecution(@sga.GraphsEqualExecution)
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
  max_rows : Int
  max_value_bytes : Int
  projection_step : Int
  construction_steps : Int
  mut kernel_step : Int
  mut phase : Phase
  constructions : Array[@bridge.RowsToGraphExecution]
  graphs : Array[@graph.Completed]
  mut graph : @graph.Completed?
  mut kernel : GraphExecution?
  mut pending_graph : @graph.Completed?
  mut projection_input : @graph.ProducerRead?
  mut relation : RelationExecution?
  mut stage_progress : Int64
  mut stage_work : Int64
  mut terminal : Bool
  mut reclaimed : Bool
}

///|
fn issue() -> @connector.FixedComputeIssue {
  @connector.Execution(@execution.InputSet)
}

///|
fn accepts_traverse(value : @lower.PreparedGraphTraverse) -> Bool {
  !@lower.graph_traverse_patterned(value) &&
  !@lower.graph_traverse_emits_paths(value) &&
  @lower.graph_traverse_bounds(value) is Some((minimum, maximum)) &&
  minimum <= 2147483647L &&
  maximum <= 2147483647L &&
  @lower.graph_traverse_start_id_count(value) == 1 &&
  @lower.graph_traverse_start_id_at(value, 0) is Some(_) &&
  @lower.graph_traverse_start_predicate(value) is None &&
  @lower.graph_traverse_start_relation_field(value) is None &&
  @lower.graph_traverse_hop_count(value) == 1 &&
  @lower.graph_traverse_hop_direction(value, 0) is Some(_) &&
  @lower.graph_traverse_hop_type_count(value, 0) is None &&
  @lower.graph_traverse_hop_edge_predicate(value, 0) is None &&
  @lower.graph_traverse_hop_node_predicate(value, 0) is None
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
  let count = @lower.sequence_count(
    @execution.generated_prepared_sequence(sequence),
  )
  if count < 1 || count > 4 {
    return false
  }
  let direct_graft = match
    @lower.sequence_step(@execution.generated_prepared_sequence(sequence), 0) {
    Some(@lower.GraphStructuralStep(_)) => true
    _ => false
  }
  let index = Ref(0)
  let accepted = @execution.generated_sequence_all_steps(sequence, fn(step) {
    let current = index.val
    index.val += 1
    guard @lower.node_at(@lower.bound_preparation(owner), current) is Some(node) else {
      return false
    }
    match (current, step) {
      (0, @lower.GraphConstructionStep(_)) if count == 1 =>
        @lower.operation(node) == "BRIDGE.rows.to_graph"
      (current, @lower.GraphConstructionStep(_)) if !direct_graft &&
        current < count - 1 => @lower.operation(node) == "BRIDGE.rows.to_graph"
      (0, @lower.GraphStructuralStep(_)) if direct_graft =>
        @lower.operation(node) == "SGA.graft"
      (current, @lower.GraphBasicStep(basic)) if current < count - 1 =>
        @lower.operation(node) == "SGA.normalize" &&
        @lower.graph_basic_kind(basic) == @lower.NormalizeBasic
      (current, @lower.GraphStructuralStep(_)) if current < count - 1 =>
        @lower.operation(node) == "SGA.graft"
      (current, @lower.CarrierProjectionStep(projection)) if current ==
        count - 1 =>
        (
          @lower.operation(node) == "BRIDGE.graph.to_node_rows" &&
          @lower.carrier_projection_operation(projection) ==
          @projection.NodeRows
        ) ||
        (
          @lower.operation(node) == "BRIDGE.graph.to_edge_rows" &&
          @lower.carrier_projection_operation(projection) ==
          @projection.EdgeRows
        )
      (current, @lower.GraphMatchStep(matched)) if current == count - 1 =>
        if @lower.graph_match_nodes(matched) {
          @lower.operation(node) == "SGA.match_nodes"
        } else {
          @lower.operation(node) == "SGA.match_edges"
        }
      (current, @lower.GraphReachStep(_)) if current == count - 1 =>
        @lower.operation(node) == "SGA.reachable"
      (current, @lower.GraphTraverseStep(traverse)) if current == count - 1 =>
        @lower.operation(node) == "SGA.traverse" && accepts_traverse(traverse)
      (current, @lower.GraphBasicStep(basic)) if current == count - 1 =>
        (
          @lower.operation(node) == "SGA.bounds_check" &&
          @lower.graph_basic_kind(basic) == @lower.BoundsBasic
        ) ||
        (
          @lower.operation(node) == "SGA.degree_metrics" &&
          (
            @lower.graph_basic_kind(basic) == @lower.DegreeIncomingBasic ||
            @lower.graph_basic_kind(basic) == @lower.DegreeOutgoingBasic ||
            @lower.graph_basic_kind(basic) == @lower.DegreeBothBasic
          )
        ) ||
        (
          @lower.operation(node) == "SGA.components" &&
          (
            @lower.graph_basic_kind(basic) == @lower.ComponentsWeakBasic ||
            @lower.graph_basic_kind(basic) == @lower.ComponentsStrongBasic
          )
        )
      (current, @lower.GraphRelationStep(relation)) if current == count - 1 =>
        @lower.operation(node) == "SGA.equal" &&
        @lower.graph_relation_kind(relation) == @lower.GraphsEqualRelation &&
        @lower.graph_relation_input_step(relation, 0) is Some(left) &&
        @lower.graph_relation_input_step(relation, 1) is Some(right) &&
        left >= 0 &&
        left < current &&
        right >= 0 &&
        right < current &&
        @lower.sequence_step(
          @execution.generated_prepared_sequence(sequence),
          left,
        )
        is Some(@lower.GraphConstructionStep(_)) &&
        @lower.sequence_step(
          @execution.generated_prepared_sequence(sequence),
          right,
        )
        is Some(@lower.GraphConstructionStep(_))
      _ => false
    }
  })
  accepted && index.val == count
}

///|
fn provider_capacity(
  base : @execution.ExecutionCapacity,
  storage_bytes : Int64,
  generation_count : Int,
) -> @execution.ExecutionCapacity? {
  if storage_bytes < 0L || generation_count < 2 {
    return None
  }
  let count = generation_count.to_int64()
  if storage_bytes != 0L && count > 9223372036854775807L / storage_bytes {
    return None
  }
  let extra = storage_bytes * count
  let execution = @execution.execution_capacity_execution_bytes(base)
  if execution > 9223372036854775807L - extra {
    return None
  }
  @execution.execution_capacity(
    @execution.execution_capacity_retained_bytes(base),
    execution + extra,
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
        let step = value.graphs.length()
        if step >= value.construction_steps {
          return fail_execution(value)
        }
        guard @lower.sequence_step(value.sequence, step)
          is Some(@lower.GraphConstructionStep(graph)) &&
          input_at(value, step, 0) is Some(first) else {
          return fail_execution(value)
        }
        let inputs = if @lower.graph_construction_derives_nodes(graph) {
          [first]
        } else {
          guard input_at(value, step, 1) is Some(second) else {
            return fail_execution(value)
          }
          [first, second]
        }
        let started = match
          @bridge.start_rows_to_graph(
            value.control,
            value.sequence,
            step,
            inputs,
            value.limits,
            value.storage_bytes,
            value.limits.max_workspace_slots,
            fn() { true },
          ) {
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
            if value.construction_steps == 1 &&
              @lower.sequence_count(value.sequence) == 1 {
              guard delta(progress, value.stage_progress)
                is Some(progress_delta) &&
                delta(work, value.stage_work) is Some(work_delta) else {
                @graph.discard_completed(output) |> ignore
                return fail_execution(value)
              }
              let material = match @graph.completed_material(output) {
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
            value.graphs.push(output)
            value.phase = if value.graphs.length() < value.construction_steps {
              StartConstruction
            } else if value.projection_step > value.construction_steps {
              if value.construction_steps == 1 {
                value.graph = Some(output)
                value.graphs.clear()
              }
              StartKernel
            } else {
              value.graph = Some(output)
              StartProjection
            }
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
      StartKernel => {
        if value.kernel_step == value.projection_step - 1 &&
          value.graph is Some(output) {
          value.projection_input = match
            @graph.prepare_step_read(
              @execution.generated_sequence_owner(value.generated),
              value.projection_step,
              0,
              output,
            ) {
            Ok(read) => Some(read)
            Err(_) => None
          }
        }
        let started = match
          @lower.sequence_step(value.sequence, value.kernel_step) {
          Some(@lower.GraphStructuralStep(_)) if value.kernel_step == 0 =>
            match
              @sga.start_graft_views(
                value.control,
                value.sequence,
                value.kernel_step,
                value.carrier_inputs,
                value.limits,
                value.storage_bytes,
                fn() { true },
              ) {
              Ok(execution) => Graft(execution)
              Err(_) => return fail_execution(value)
            }
          Some(@lower.GraphStructuralStep(_)) => {
            let reads = []
            for index, output in value.graphs {
              match
                @graph.prepare_step_read(
                  @execution.generated_sequence_owner(value.generated),
                  value.kernel_step,
                  index,
                  output,
                ) {
                Ok(read) => reads.push(read)
                Err(_) => return fail_execution(value)
              }
            }
            match
              @sga.start_graft(
                value.control,
                value.sequence,
                value.kernel_step,
                reads,
                value.limits,
                value.storage_bytes,
                fn() { true },
              ) {
              Ok(execution) => Graft(execution)
              Err(_) => return fail_execution(value)
            }
          }
          Some(@lower.GraphBasicStep(basic)) if @lower.graph_basic_kind(basic) ==
            @lower.NormalizeBasic => {
            guard value.graph is Some(output) else {
              return fail_execution(value)
            }
            let input = match
              @graph.prepare_step_read(
                @execution.generated_sequence_owner(value.generated),
                value.kernel_step,
                0,
                output,
              ) {
              Ok(read) => read
              Err(_) => return fail_execution(value)
            }
            match
              @sga.start_normalize(
                value.control,
                value.sequence,
                value.kernel_step,
                input,
                value.limits,
                value.storage_bytes,
                fn() { true },
              ) {
              Ok(execution) => Normalize(execution)
              Err(_) => return fail_execution(value)
            }
          }
          _ => return fail_execution(value)
        }
        value.kernel = Some(started)
        value.phase = Kernel
        reset_stage(value)
      }
      Kernel => {
        guard value.kernel is Some(active) else { return fail_execution(value) }
        let advanced = match active {
          Normalize(execution) =>
            match @sga.advance_normalize(execution, quantum) {
              Ok(@sga.Continue(progress~, work~)) =>
                Ok((0, None, progress, work))
              Ok(@sga.Complete(output, progress~, work~)) =>
                Ok((1, Some(output), progress, work))
              Ok(@sga.Failed(_, progress~, work~)) =>
                Ok((2, None, progress, work))
              Ok(@sga.Stopped(_, progress~, work~)) =>
                Ok((3, None, progress, work))
              Err(_) => Err(())
            }
          Graft(execution) =>
            match @sga.advance_graft(execution, quantum) {
              Ok(@sga.GraftContinue(progress~, work~)) =>
                Ok((0, None, progress, work))
              Ok(@sga.GraftComplete(output, progress~, work~)) =>
                Ok((1, Some(output), progress, work))
              Ok(@sga.GraftFailed(_, progress~, work~)) =>
                Ok((2, None, progress, work))
              Ok(@sga.GraftStopped(_, progress~, work~)) =>
                Ok((3, None, progress, work))
              Err(_) => Err(())
            }
        }
        match advanced {
          Err(_) => return fail_execution(value)
          Ok((0, _, progress, work)) => {
            guard continue_poll(value, progress, work) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok((1, Some(output), progress, work)) => {
            guard continue_poll(value, progress, work) is Some(poll) else {
              return fail_execution(value)
            }
            value.pending_graph = Some(output)
            value.phase = CleanupKernel
            if poll is @local.Continue(work=work_delta, ..) && work_delta > 0L {
              return Ok(poll)
            }
          }
          Ok((2, _, progress, work)) => {
            guard terminal_poll(value, progress, work, false) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok((3, _, progress, work)) => {
            guard terminal_poll(value, progress, work, true) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          _ => return fail_execution(value)
        }
      }
      CleanupKernel => {
        guard value.kernel is Some(active) &&
          value.pending_graph is Some(completed) else {
          return fail_execution(value)
        }
        let cleaned = match active {
          Normalize(execution) =>
            match @sga.cleanup_normalize(execution) {
              Ok(true) => 1
              Ok(false) => 0
              Err(_) => -1
            }
          Graft(execution) =>
            match @sga.cleanup_graft(execution) {
              Ok(true) => 1
              Ok(false) => 0
              Err(_) => -1
            }
        }
        match cleaned {
          1 => ()
          _ => return fail_execution(value)
        }
        value.kernel = None
        if active is Graft(_) && !value.graphs.is_empty() {
          for source in value.graphs {
            discard(Some(source)) |> ignore
          }
          value.graphs.clear()
          value.graph = Some(completed)
        } else if value.projection_input is Some(_) {
          discard(Some(completed)) |> ignore
        } else {
          discard(value.graph) |> ignore
          value.graph = Some(completed)
        }
        value.pending_graph = None
        value.kernel_step += 1
        value.phase = if value.kernel_step < value.projection_step {
          StartKernel
        } else {
          StartProjection
        }
      }
      StartProjection => {
        let relation_step = match
          @lower.sequence_step(value.sequence, value.projection_step) {
          Some(@lower.GraphRelationStep(_)) => true
          _ => false
        }
        let direct_view = if value.graph is None &&
          value.carrier_inputs.length() == 1 {
          Some(value.carrier_inputs[0])
        } else {
          None
        }
        let input = if relation_step || direct_view is Some(_) {
          None
        } else {
          guard value.graph is Some(output) else {
            return fail_execution(value)
          }
          match value.projection_input {
            Some(read) => Some(read)
            None =>
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
        }
        let started = match
          @lower.sequence_step(value.sequence, value.projection_step) {
          Some(@lower.CarrierProjectionStep(_)) => {
            let started = if direct_view is Some(view) {
              @bridge.start_graph_view_to_rows(
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
              )
            } else if value.carrier_inputs.is_empty() {
              guard input is Some(input) else { return fail_execution(value) }
              @bridge.start_graph_to_rows(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                value.projection_step,
                input,
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
              )
            } else {
              guard input is Some(input) else { return fail_execution(value) }
              @bridge.start_graph_to_rows_from_carrier_inputs(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                value.projection_step,
                input,
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
              )
            }
            match started {
              Ok(execution) => ProjectionExecution(execution)
              Err(_) => return fail_execution(value)
            }
          }
          Some(@lower.GraphMatchStep(matched)) => {
            guard input is Some(input) else { return fail_execution(value) }
            if @lower.graph_match_nodes(matched) {
              match
                @sga.start_match_nodes(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  input,
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
                ) {
                Ok(execution) => MatchNodesExecution(execution)
                Err(_) => return fail_execution(value)
              }
            } else {
              match
                @sga.start_match_edges(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  input,
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
                ) {
                Ok(execution) => MatchEdgesExecution(execution)
                Err(_) => return fail_execution(value)
              }
            }
          }
          Some(@lower.GraphBasicStep(basic)) => {
            guard input is Some(input) else { return fail_execution(value) }
            if @lower.graph_basic_kind(basic) == @lower.BoundsBasic {
              match
                @sga.start_graph_bounds(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  input,
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
                ) {
                Ok(execution) => GraphBoundsExecution(execution)
                Err(_) => return fail_execution(value)
              }
            } else if @lower.graph_basic_kind(basic) ==
              @lower.DegreeIncomingBasic ||
              @lower.graph_basic_kind(basic) == @lower.DegreeOutgoingBasic ||
              @lower.graph_basic_kind(basic) == @lower.DegreeBothBasic {
              match
                @sga.start_graph_degree(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  input,
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
                ) {
                Ok(execution) => GraphDegreeExecution(execution)
                Err(_) => return fail_execution(value)
              }
            } else if @lower.graph_basic_kind(basic) ==
              @lower.ComponentsWeakBasic ||
              @lower.graph_basic_kind(basic) == @lower.ComponentsStrongBasic {
              match
                @sga.start_components(
                  value.control,
                  @execution.generated_completion_preparation(value.generated),
                  value.sequence,
                  value.projection_step,
                  input,
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
                ) {
                Ok(execution) => ComponentsExecution(execution)
                Err(_) => return fail_execution(value)
              }
            } else {
              return fail_execution(value)
            }
          }
          Some(@lower.GraphReachStep(_)) => {
            guard input is Some(input) else { return fail_execution(value) }
            match
              @sga.start_reach(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                value.projection_step,
                input,
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
              ) {
              Ok(execution) => ReachExecution(execution)
              Err(_) => return fail_execution(value)
            }
          }
          Some(@lower.GraphTraverseStep(_)) => {
            guard input is Some(input) else { return fail_execution(value) }
            match
              @sga.start_traverse(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                value.projection_step,
                input,
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
              ) {
              Ok(execution) => TraverseExecution(execution)
              Err(_) => return fail_execution(value)
            }
          }
          Some(@lower.GraphRelationStep(relation)) => {
            guard @lower.graph_relation_kind(relation) ==
              @lower.GraphsEqualRelation &&
              @lower.graph_relation_input_step(relation, 0) is Some(left) &&
              @lower.graph_relation_input_step(relation, 1) is Some(right) &&
              value.graphs.get(left) is Some(left_graph) &&
              value.graphs.get(right) is Some(right_graph) else {
              return fail_execution(value)
            }
            let reads : Array[@graph.ProducerRead] = []
            for index, output in [left_graph, right_graph] {
              match
                @graph.prepare_step_read(
                  @execution.generated_sequence_owner(value.generated),
                  value.projection_step,
                  index,
                  output,
                ) {
                Ok(read) => reads.push(read)
                Err(_) => return fail_execution(value)
              }
            }
            match
              @sga.start_graphs_equal(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                value.projection_step,
                reads[0],
                reads[1],
                value.max_rows,
                {
                  max_nodes: value.limits.max_value_nodes,
                  max_text_bytes: value.max_value_bytes,
                  max_depth: value.limits.max_value_depth,
                  max_work: value.limits.max_work,
                },
                value.limits.max_value_bytes,
                value.limits.max_value_bytes,
                value.inputs,
              ) {
              Ok(execution) => GraphsEqualExecution(execution)
              Err(_) => return fail_execution(value)
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
          ProjectionExecution(execution) =>
            match @bridge.advance_graph_to_rows(execution, quantum) {
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
          ReachExecution(execution) =>
            match @sga.advance_reach(execution, quantum) {
              Ok(@sga.ReachContinue(progress~, work~)) =>
                Ok(RelationContinue(progress, work))
              Ok(@sga.ReachComplete(output, progress~, work~)) =>
                Ok(RelationComplete(output, progress, work))
              Ok(@sga.ReachFailed(_, progress~, work~)) =>
                Ok(RelationFailed(progress, work))
              Ok(@sga.ReachStopped(_, progress~, work~)) =>
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
          GraphsEqualExecution(execution) =>
            match @sga.advance_graphs_equal(execution, quantum) {
              Ok(@sga.GraphsEqualContinue(progress~, work~)) =>
                Ok(RelationContinue(progress, work))
              Ok(@sga.GraphsEqualComplete(output, progress~, work~)) =>
                Ok(RelationComplete(output, progress, work))
              Ok(@sga.GraphsEqualFailed(_, progress~, work~)) =>
                Ok(RelationFailed(progress, work))
              Ok(@sga.GraphsEqualStopped(_, progress~, work~)) =>
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
            for graph in value.graphs {
              discard(Some(graph)) |> ignore
            }
            value.graphs.clear()
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
      ProjectionExecution(execution) =>
        match @bridge.cleanup_graph_to_rows(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
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
      ReachExecution(execution) =>
        match @sga.cleanup_reach(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
      TraverseExecution(execution) =>
        match @sga.cleanup_traverse(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
      GraphsEqualExecution(execution) =>
        match @sga.cleanup_graphs_equal(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
    }
  }
  if value.kernel is Some(active) {
    match active {
      Normalize(execution) =>
        match @sga.cleanup_normalize(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
      Graft(execution) =>
        match @sga.cleanup_graft(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
    }
  }
  discard(value.graph) |> ignore
  value.graph = None
  for graph in value.graphs {
    discard(Some(graph)) |> ignore
  }
  value.graphs.clear()
  discard(value.pending_graph) |> ignore
  value.pending_graph = None
  let mut construction_pending = false
  for active in value.constructions {
    if @bridge.rows_to_graph_cleanup_pending(active) {
      construction_pending = true
    }
  }
  let projection_pending = match value.relation {
    Some(ProjectionExecution(active)) =>
      @bridge.graph_to_rows_cleanup_pending(active)
    Some(MatchNodesExecution(active)) =>
      @sga.match_nodes_cleanup_pending(active)
    Some(MatchEdgesExecution(active)) =>
      @sga.match_edges_cleanup_pending(active)
    Some(GraphBoundsExecution(active)) =>
      @sga.graph_bounds_cleanup_pending(active)
    Some(GraphDegreeExecution(active)) =>
      @sga.graph_degree_cleanup_pending(active)
    Some(ComponentsExecution(active)) => @sga.components_cleanup_pending(active)
    Some(ReachExecution(active)) => @sga.reach_cleanup_pending(active)
    Some(TraverseExecution(active)) => @sga.traverse_cleanup_pending(active)
    Some(GraphsEqualExecution(active)) =>
      @sga.graphs_equal_cleanup_pending(active)
    None => false
  }
  let kernel_pending = match value.kernel {
    Some(Normalize(active)) => @sga.normalize_cleanup_pending(active)
    Some(Graft(active)) => @sga.graft_cleanup_pending(active)
    None => false
  }
  if failed {
    return Err(issue())
  }
  if construction_pending || kernel_pending || projection_pending {
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
) -> @local.ManagedProvider {
  @local.managed_provider_with_inputs(
    accepts,
    sequence => {
      if accepts(sequence) {
        provider_capacity(
          capacity,
          storage_bytes,
          @lower.sequence_count(
            @execution.generated_prepared_sequence(sequence),
          ),
        )
      } else {
        None
      }
    },
    fn(sequence, inputs, max_rows, max_value_bytes) {
      if !accepts(sequence) || storage_bytes < 0L {
        return Err(@connector.InvalidLimits)
      }
      let relations = []
      let carriers = []
      for input in inputs {
        match input {
          @local.RelationInput(value) => relations.push(value)
          @local.CarrierInput(value) => carriers.push(value)
        }
      }
      let direct_graft = match
        @lower.sequence_step(
          @execution.generated_prepared_sequence(sequence),
          0,
        ) {
        Some(@lower.GraphStructuralStep(_)) => true
        _ => false
      }
      let direct_projection = match
        @lower.sequence_step(
          @execution.generated_prepared_sequence(sequence),
          0,
        ) {
        Some(@lower.CarrierProjectionStep(_)) => true
        _ => false
      }
      if (direct_graft && (relations.length() != 0 || carriers.length() != 2)) ||
        (
          direct_projection &&
          (relations.length() != 0 || carriers.length() != 1)
        ) ||
        (!direct_graft && !direct_projection && carriers.length() != 0) {
        return Err(@connector.Execution(@execution.InputSet))
      }
      let construction_steps = if direct_graft {
        0
      } else {
        let mut count = 0
        while true {
          match
            @lower.sequence_step(
              @execution.generated_prepared_sequence(sequence),
              count,
            ) {
            Some(@lower.GraphConstructionStep(_)) => count += 1
            _ => break
          }
        }
        count
      }
      let state : Execution = {
        generated: sequence,
        sequence: @execution.generated_prepared_sequence(sequence),
        inputs: relations,
        carrier_inputs: carriers,
        control: @bounded.control(),
        limits,
        storage_bytes,
        max_rows,
        max_value_bytes,
        projection_step: @lower.sequence_count(
          @execution.generated_prepared_sequence(sequence),
        ) -
        1,
        construction_steps,
        kernel_step: construction_steps,
        phase: if direct_graft {
          StartKernel
        } else if direct_projection {
          StartProjection
        } else {
          StartConstruction
        },
        constructions: [],
        graphs: [],
        graph: None,
        kernel: None,
        pending_graph: None,
        projection_input: None,
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
