///|
priv enum Phase {
  StartRows
  Rows
  StartKernel
  Kernel
  StartProjection
  Projection
  Terminal
}

///|
priv enum VectorExecution {
  Normalize(@veca.NormalizeExecution)
  Score(@veca.ScoreExecution)
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
  mut rows : @bridge.RowsToVectorsExecution?
  mut row_vectors : @records.Completed?
  mut kernel : VectorExecution?
  mut transformed : @records.Completed?
  mut projection : @bridge.VectorsToRowsExecution?
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
      (0, @lower.VectorStep(_)) =>
        @lower.operation(node) == "BRIDGE.rows.to_vectors"
      (1, @lower.VectorStep(_)) => {
        let operation = @lower.operation(node)
        operation == "VEC.normalize_l2" || operation == "VEC.score_sort"
      }
      (2, @lower.CarrierProjectionStep(projection)) =>
        @lower.operation(node) == "BRIDGE.vectors.to_rows" &&
        @lower.carrier_projection_operation(projection) ==
        @carrier_projection.Vectors
      _ => false
    }
  })
  accepted && index.val == 3
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
fn discard(value : @records.Completed?) -> Bool {
  match value {
    Some(output) => @records.discard_completed(output)
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
      StartRows => {
        guard value.inputs.length() == 1 else { return fail_execution(value) }
        let started = match
          @bridge.start_rows_to_vectors(
            value.control,
            value.sequence,
            0,
            value.inputs[0],
            value.limits,
            value.storage_bytes,
            fn() { true },
          ) {
          Ok(execution) => execution
          Err(_) => return fail_execution(value)
        }
        value.rows = Some(started)
        value.phase = Rows
        reset_stage(value)
      }
      Rows => {
        guard value.rows is Some(active) else { return fail_execution(value) }
        match @bridge.advance_rows_to_vectors(active, quantum) {
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
            value.row_vectors = Some(output)
            value.phase = StartKernel
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
        guard value.row_vectors is Some(output) else {
          return fail_execution(value)
        }
        let input = match
          @records.prepare_step_read(
            @execution.generated_sequence_owner(value.generated),
            1,
            0,
            output,
          ) {
          Ok(read) => read
          Err(_) => return fail_execution(value)
        }
        guard @lower.node_at(
            @lower.bound_preparation(
              @execution.generated_sequence_owner(value.generated),
            ),
            1,
          )
          is Some(node) else {
          return fail_execution(value)
        }
        let started = if @lower.operation(node) == "VEC.normalize_l2" {
          match
            @veca.start_normalize(
              value.control,
              value.sequence,
              1,
              input,
              value.limits,
              value.storage_bytes,
              fn() { true },
            ) {
            Ok(execution) => Normalize(execution)
            Err(_) => return fail_execution(value)
          }
        } else if @lower.operation(node) == "VEC.score_sort" {
          match
            @veca.start_score(
              value.control,
              value.sequence,
              1,
              input,
              value.limits,
              value.storage_bytes,
              fn() { true },
            ) {
            Ok(execution) => Score(execution)
            Err(_) => return fail_execution(value)
          }
        } else {
          return fail_execution(value)
        }
        value.kernel = Some(started)
        value.phase = Kernel
        reset_stage(value)
      }
      Kernel => {
        guard value.kernel is Some(active) else { return fail_execution(value) }
        let poll = match active {
          Normalize(execution) =>
            match @veca.advance_normalize(execution, quantum) {
              Ok(@veca.Continue(progress~, work~)) =>
                Some((0, None, progress, work))
              Ok(@veca.Complete(output, progress~, work~)) =>
                Some((1, Some(output), progress, work))
              Ok(@veca.Failed(_, progress~, work~)) =>
                Some((2, None, progress, work))
              Ok(@veca.Stopped(_, progress~, work~)) =>
                Some((3, None, progress, work))
              Err(_) => None
            }
          Score(execution) =>
            match @veca.advance_score(execution, quantum) {
              Ok(@veca.ScoreContinue(progress~, work~)) =>
                Some((0, None, progress, work))
              Ok(@veca.ScoreComplete(output, progress~, work~)) =>
                Some((1, Some(output), progress, work))
              Ok(@veca.ScoreFailed(_, progress~, work~)) =>
                Some((2, None, progress, work))
              Ok(@veca.ScoreStopped(_, progress~, work~)) =>
                Some((3, None, progress, work))
              Err(_) => None
            }
        }
        guard poll is Some((kind, output, progress, work)) else {
          return fail_execution(value)
        }
        match kind {
          0 => {
            guard continue_poll(value, progress, work) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          1 => {
            guard continue_poll(value, progress, work) is Some(poll) else {
              return fail_execution(value)
            }
            guard output is Some(completed) else {
              return fail_execution(value)
            }
            value.transformed = Some(completed)
            discard(value.row_vectors) |> ignore
            value.row_vectors = None
            value.phase = StartProjection
            if poll is @local.Continue(work=work_delta, ..) && work_delta > 0L {
              return Ok(poll)
            }
          }
          2 => {
            guard terminal_poll(value, progress, work, false) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          3 => {
            guard terminal_poll(value, progress, work, true) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          _ => return fail_execution(value)
        }
      }
      StartProjection => {
        guard value.transformed is Some(output) else {
          return fail_execution(value)
        }
        let input = match
          @records.prepare_step_read(
            @execution.generated_sequence_owner(value.generated),
            2,
            0,
            output,
          ) {
          Ok(read) => read
          Err(_) => return fail_execution(value)
        }
        let started = match
          @bridge.start_vectors_to_rows(
            value.control,
            @execution.generated_completion_preparation(value.generated),
            value.sequence,
            2,
            input,
            value.max_rows,
            {
              max_nodes: value.limits.max_value_nodes,
              max_text_bytes: value.max_value_bytes,
              max_depth: value.limits.max_value_depth,
              max_work: value.limits.max_work,
            },
            value.limits.max_workspace_slots,
            value.max_value_bytes,
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
        match @bridge.advance_vectors_to_rows(active, quantum) {
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
            discard(value.transformed) |> ignore
            value.transformed = None
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
  if value.rows is Some(active) {
    match @bridge.cleanup_rows_to_vectors(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.kernel is Some(active) {
    match active {
      Normalize(execution) =>
        match @veca.cleanup_normalize(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
      Score(execution) =>
        match @veca.cleanup_score(execution) {
          Ok(_) => ()
          Err(_) => failed = true
        }
    }
  }
  if value.projection is Some(active) {
    match @bridge.cleanup_vectors_to_rows(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  discard(value.row_vectors) |> ignore
  value.row_vectors = None
  discard(value.transformed) |> ignore
  value.transformed = None
  let rows_pending = match value.rows {
    Some(active) => @bridge.rows_to_vectors_cleanup_pending(active)
    None => false
  }
  let kernel_pending = match value.kernel {
    Some(Normalize(active)) => @veca.normalize_cleanup_pending(active)
    Some(Score(active)) => @veca.score_cleanup_pending(active)
    None => false
  }
  let projection_pending = match value.projection {
    Some(active) => @bridge.vectors_to_rows_cleanup_pending(active)
    None => false
  }
  if failed {
    return Err(issue())
  }
  if rows_pending || kernel_pending || projection_pending {
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
    fn(sequence) {
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
        phase: StartRows,
        rows: None,
        row_vectors: None,
        kernel: None,
        transformed: None,
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
