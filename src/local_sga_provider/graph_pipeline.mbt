///|
priv enum Phase {
  StartConstruction
  Construction
  StartProjection
  Projection
  Terminal
}

///|
priv struct Execution {
  generated : @execution.GeneratedSequence
  sequence : @lower.PreparedSequence
  inputs : Array[@execution.ProducerRead]
  control : @bounded.Control
  limits : @storage.Limits
  storage_bytes : Int64
  max_rows : Int
  max_value_bytes : Int
  mut phase : Phase
  mut construction : @bridge.RowsToGraphExecution?
  mut graph : @graph.Completed?
  mut projection : @bridge.GraphRowsExecution?
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
  let index = Ref(0)
  let accepted = @execution.generated_sequence_all_steps(sequence, fn(step) {
    let current = index.val
    index.val += 1
    guard @lower.node_at(@lower.bound_preparation(owner), current) is Some(node) else {
      return false
    }
    match (current, step) {
      (0, @lower.GraphConstructionStep(_)) =>
        @lower.operation(node) == "BRIDGE.rows.to_graph"
      (1, @lower.CarrierProjectionStep(projection)) =>
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
      _ => false
    }
  })
  accepted && index.val == 2
}

///|
fn provider_capacity(
  base : @execution.ExecutionCapacity,
  storage_bytes : Int64,
) -> @execution.ExecutionCapacity? {
  if storage_bytes < 0L || storage_bytes > 4611686018427387903L {
    return None
  }
  let extra = storage_bytes * 2L
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
fn input_at(value : Execution, edge : Int) -> @execution.ProducerRead? {
  let owner = @execution.generated_sequence_owner(value.generated)
  for input in value.inputs {
    if @execution.producer_read_matches_operation_input(input, owner, 0, edge) {
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
        guard input_at(value, 0) is Some(nodes) &&
          input_at(value, 1) is Some(edges) else {
          return fail_execution(value)
        }
        let started = match
          @bridge.start_rows_to_graph(
            value.control,
            value.sequence,
            0,
            [nodes, edges],
            value.limits,
            value.storage_bytes,
            value.limits.max_workspace_slots,
            fn() { true },
          ) {
          Ok(execution) => execution
          Err(_) => return fail_execution(value)
        }
        value.construction = Some(started)
        value.phase = Construction
        reset_stage(value)
      }
      Construction => {
        guard value.construction is Some(active) else {
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
        guard value.graph is Some(output) else { return fail_execution(value) }
        let input = match
          @graph.prepare_step_read(
            @execution.generated_sequence_owner(value.generated),
            1,
            0,
            output,
          ) {
          Ok(read) => read
          Err(_) => return fail_execution(value)
        }
        let started = match
          @bridge.start_graph_to_rows(
            value.control,
            @execution.generated_completion_preparation(value.generated),
            value.sequence,
            1,
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
          Ok(execution) => execution
          Err(_) => return fail_execution(value)
        }
        value.projection = Some(started)
        value.phase = Projection
        reset_stage(value)
      }
      Projection => {
        guard value.projection is Some(active) else {
          return fail_execution(value)
        }
        match @bridge.advance_graph_to_rows(active, quantum) {
          Err(_) => return fail_execution(value)
          Ok(@bridge.Continue(progress~, work~)) => {
            guard continue_poll(value, progress, work) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok(@bridge.Complete(output, progress~, work~)) => {
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
  if value.construction is Some(active) {
    match @bridge.cleanup_rows_to_graph(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.projection is Some(active) {
    match @bridge.cleanup_graph_to_rows(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  discard(value.graph) |> ignore
  value.graph = None
  let construction_pending = match value.construction {
    Some(active) => @bridge.rows_to_graph_cleanup_pending(active)
    None => false
  }
  let projection_pending = match value.projection {
    Some(active) => @bridge.graph_to_rows_cleanup_pending(active)
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
) -> @local.ManagedProvider {
  @local.managed_provider(
    accepts,
    sequence => {
      if accepts(sequence) {
        provider_capacity(capacity, storage_bytes)
      } else {
        None
      }
    },
    fn(sequence, inputs, max_rows, max_value_bytes) {
      if !accepts(sequence) || storage_bytes < 0L {
        return Err(@connector.InvalidLimits)
      }
      let state : Execution = {
        generated: sequence,
        sequence: @execution.generated_prepared_sequence(sequence),
        inputs: inputs.copy(),
        control: @bounded.control(),
        limits,
        storage_bytes,
        max_rows,
        max_value_bytes,
        phase: StartConstruction,
        construction: None,
        graph: None,
        projection: None,
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
