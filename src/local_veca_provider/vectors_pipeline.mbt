///|
priv enum Phase {
  StartBindingRows
  BindingRows
  StartRows
  Rows
  StartKernel
  Kernel
  CleanupKernel
  StartProjection
  Projection
  StartNearestBridge
  NearestBridge
  CleanupNearestBridge
  StartNearest
  Nearest
  StartRanking
  Ranking
  Terminal
}

///|
priv enum VectorExecution {
  Normalize(@veca.NormalizeExecution)
  Score(@veca.ScoreExecution)
  Pool(@veca.PoolExecution)
}

///|
priv struct Execution {
  generated : @execution.GeneratedSequence
  sequence : @lower.PreparedSequence
  inputs : Array[@local.ManagedProviderInput]
  relation_inputs : Array[@execution.ProducerRead]?
  carrier_input : @lifecycle.ProducerView?
  ranking_inputs : Array[@veca.RankingInput]?
  control : @bounded.Control
  limits : @storage.Limits
  storage_bytes : Int64
  max_rows : Int
  max_value_bytes : Int
  execution_limits : @execution.SequenceExecutionLimits
  projection_step : Int
  relation_pool : Bool
  mut phase : Phase
  mut binding_execution : @execution.BoundedBindingRowsExecution?
  mut rows : @bridge.RowsToVectorsExecution?
  mut kernel_step : Int
  mut kernel : VectorExecution?
  mut transformed : @records.Completed?
  mut pending_transformed : @records.Completed?
  mut projection_input : @records.ProducerRead?
  mut projection : @bridge.VectorsToRowsExecution?
  nearest_step : Int
  mut nearest_bridge_step : Int
  mut nearest_bridge : @bridge.RowsToVectorsExecution?
  mut nearest_bridge_output : @records.Completed?
  mut nearest_bridge_outputs : Array[@records.Completed]
  nearest_inputs : Array[@veca.NearestProducerInput?]
  mut nearest : @veca.NearestExecution?
  mut ranking : @veca.RankingExecution?
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
fn accepts_nearest_pipeline(
  sequence : @execution.GeneratedSequence,
  count : Int,
) -> Bool {
  if count < 2 || count > 3 {
    return false
  }
  let owner = @execution.generated_sequence_owner(sequence)
  let prepared = @execution.generated_prepared_sequence(sequence)
  guard @lower.sequence_step(prepared, count - 1) is Some(@lower.VectorStep(_)) &&
    @lower.node_at(@lower.bound_preparation(owner), count - 1) is Some(nearest) &&
    @lower.operation(nearest) == "VEC.knn_join" else {
    return false
  }
  for step in 0..<(count - 1) {
    guard @lower.sequence_step(prepared, step) is Some(@lower.VectorStep(_)) &&
      @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
      @lower.operation(node) == "BRIDGE.rows.to_vectors" &&
      @lower.node_input_target(node, 0) is Some(@pipeline.Input(_)) else {
      return false
    }
    let mut uses = 0
    for side in 0..<2 {
      if @lower.node_input_target(nearest, side) == Some(@pipeline.Step(step)) {
        uses += 1
      }
    }
    if uses != 1 {
      return false
    }
  }
  true
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
  if @execution.completion_preparation_selected_step(
      @execution.generated_completion_preparation(sequence),
    )
    is Some(selected) {
    guard @lower.node_at(@lower.bound_preparation(owner), selected)
      is Some(node) &&
      @lower.sequence_step(
        @execution.generated_prepared_sequence(sequence),
        selected,
      )
      is Some(step) else {
      return false
    }
    let direct_bridge = match step {
      @lower.VectorStep(_) => @lower.operation(node) == "BRIDGE.rows.to_vectors"
      @lower.CarrierProjectionStep(projection) =>
        @lower.operation(node) == "BRIDGE.vectors.to_rows" &&
        @lower.carrier_projection_operation(projection) ==
        @carrier_projection.Vectors
      _ => false
    }
    if direct_bridge {
      return true
    }
  }
  let count = @execution.generated_sequence_step_count(sequence)
  if count == 1 {
    guard @lower.sequence_step(
        @execution.generated_prepared_sequence(sequence),
        0,
      )
      is Some(step) &&
      @lower.node_at(@lower.bound_preparation(owner), 0) is Some(node) else {
      return false
    }
    if step is @lower.RowStep(kernel) {
      return @lower.kernel_has_veca_bindings(kernel)
    }
    guard step is @lower.VectorStep(_) else { return false }
    let operation = @lower.operation(node)
    return operation == "VEC.merge_rankings" || operation == "VEC.knn_join"
  }
  if count < 2 {
    return false
  }
  if accepts_nearest_pipeline(sequence, count) {
    return true
  }
  let index = Ref(0)
  let accepted = @execution.generated_sequence_all_steps(sequence, fn(step) {
    let current = index.val
    index.val += 1
    guard @lower.node_at(@lower.bound_preparation(owner), current) is Some(node) else {
      return false
    }
    match step {
      @lower.VectorStep(vector) if current == 0 =>
        @lower.operation(node) == "BRIDGE.rows.to_vectors" ||
        (
          count == 2 &&
          @lower.operation(node) == "VEC.pool" &&
          @lower.vector_pool_identity_count(vector).unwrap_or(0) > 0 &&
          @lower.vector_pool_member_vectors(vector) is Some(_)
        )
      @lower.VectorStep(_) if current < count - 1 => {
        let operation = @lower.operation(node)
        operation == "VEC.normalize_l2" ||
        operation == "VEC.score_sort" ||
        operation == "VEC.pool"
      }
      @lower.CarrierProjectionStep(projection) if current == count - 1 =>
        @lower.operation(node) == "BRIDGE.vectors.to_rows" &&
        @lower.carrier_projection_operation(projection) ==
        @carrier_projection.Vectors
      _ => false
    }
  })
  accepted && index.val == count
}

///|
fn provider_capacity(
  base : @execution.ExecutionCapacity,
  storage_bytes : Int64,
  intermediate_count : Int,
) -> @execution.ExecutionCapacity? {
  if storage_bytes < 0L || intermediate_count < 1 {
    return None
  }
  let count = intermediate_count.to_int64()
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
fn relation_inputs(
  inputs : Array[@local.ManagedProviderInput],
) -> Array[@execution.ProducerRead]? {
  let relations = []
  for input in inputs {
    match input {
      @local.RelationInput(read) => relations.push(read)
      @local.SuppliedRelationInput(_) | @local.CarrierInput(_) => return None
    }
  }
  Some(relations)
}

///|
fn ranking_inputs(
  inputs : Array[@local.ManagedProviderInput],
) -> Array[@veca.RankingInput]? {
  let relations = []
  for input in inputs {
    match input {
      @local.RelationInput(read) =>
        relations.push(@veca.ranking_producer_input(read))
      @local.SuppliedRelationInput(read) =>
        relations.push(@veca.ranking_supplied_input(read))
      @local.CarrierInput(_) => return None
    }
  }
  Some(relations)
}

///|
fn nearest_input(
  input : @local.ManagedProviderInput,
) -> @veca.NearestProducerInput? {
  match input {
    @local.RelationInput(read) => Some(@veca.nearest_relation_producer(read))
    @local.SuppliedRelationInput(_) => None
    @local.CarrierInput(view) => Some(@veca.nearest_carrier_producer(view))
  }
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
fn cleanup_kernel_execution(
  value : VectorExecution,
) -> Result[Bool, @connector.FixedComputeIssue] {
  match value {
    Normalize(execution) =>
      @veca.cleanup_normalize(execution).map_err(_ => issue())
    Score(execution) => @veca.cleanup_score(execution).map_err(_ => issue())
    Pool(execution) => @veca.cleanup_pool(execution).map_err(_ => issue())
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
      StartBindingRows => {
        guard value.relation_inputs is Some(inputs) && inputs.length() == 1 else {
          return fail_execution(value)
        }
        let started = match
          @execution.start_bounded_binding_rows(
            value.control,
            value.generated,
            inputs[0],
            value.max_rows,
            value.execution_limits.rows.output_values,
            value.execution_limits.max_work,
            value.execution_limits.max_frames,
            value.execution_limits.rows.operation_entries,
            value.max_value_bytes,
          ) {
          Ok(execution) => execution
          Err(_) => return fail_execution(value)
        }
        value.binding_execution = Some(started)
        value.phase = BindingRows
        reset_stage(value)
      }
      BindingRows => {
        guard value.binding_execution is Some(active) else {
          return fail_execution(value)
        }
        match @execution.advance_bounded_binding_rows(active, quantum) {
          Err(_) => return fail_execution(value)
          Ok(@execution.BoundedBindingRowsContinue(progress~, work~)) => {
            guard continue_poll(value, progress, work) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok(@execution.BoundedBindingRowsComplete(output, progress~, work~)) => {
            guard delta(progress, value.stage_progress) is Some(progress_delta) &&
              delta(work, value.stage_work) is Some(work_delta) else {
              return fail_execution(value)
            }
            value.terminal = true
            value.phase = Terminal
            return Ok(
              @local.managed_provider_complete(
                output, progress_delta, work_delta,
              ),
            )
          }
          Ok(@execution.BoundedBindingRowsFailed(_, progress~, work~)) => {
            guard terminal_poll(value, progress, work, false) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok(@execution.BoundedBindingRowsStopped(_, progress~, work~)) => {
            guard terminal_poll(value, progress, work, true) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
        }
      }
      StartRows => {
        guard value.relation_inputs is Some(inputs) && inputs.length() == 1 else {
          return fail_execution(value)
        }
        if value.relation_pool {
          let started = match
            @veca.start_relation_pool(
              value.control,
              value.sequence,
              0,
              inputs[0],
              value.limits,
              value.storage_bytes,
              fn() { true },
            ) {
            Ok(execution) => execution
            Err(_) => return fail_execution(value)
          }
          value.kernel = Some(Pool(started))
          value.phase = Kernel
          reset_stage(value)
          continue
        }
        let started = match
          @bridge.start_rows_to_vectors(
            value.control,
            value.sequence,
            0,
            inputs[0],
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
            guard delta(progress, value.stage_progress) is Some(progress_delta) &&
              delta(work, value.stage_work) is Some(work_delta) else {
              return fail_execution(value)
            }
            if @execution.completion_preparation_selected_step(
                @execution.generated_completion_preparation(value.generated),
              )
              is Some(_) {
              let material = match @records.completed_material(output) {
                Ok(value) => value
                Err(_) => {
                  @records.discard_completed(output) |> ignore
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
              @records.discard_completed(output) |> ignore
              return fail_execution(value)
            }
            value.transformed = Some(output)
            value.phase = if value.kernel_step == value.projection_step {
              StartProjection
            } else {
              StartKernel
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
        guard value.transformed is Some(output) else {
          return fail_execution(value)
        }
        if value.kernel_step == value.projection_step - 1 {
          guard @lower.node_at(
              @lower.bound_preparation(
                @execution.generated_sequence_owner(value.generated),
              ),
              value.projection_step,
            )
            is Some(projection) else {
            return fail_execution(value)
          }
          if @lower.node_input_target(projection, 0) ==
            Some(@pipeline.Step(value.kernel_step - 1)) {
            value.projection_input = match
              @records.prepare_step_read(
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
        let input = match
          @records.prepare_step_read(
            @execution.generated_sequence_owner(value.generated),
            value.kernel_step,
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
            value.kernel_step,
          )
          is Some(node) else {
          return fail_execution(value)
        }
        let started = if @lower.operation(node) == "VEC.normalize_l2" {
          match
            @veca.start_normalize(
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
        } else if @lower.operation(node) == "VEC.score_sort" {
          match
            @veca.start_score(
              value.control,
              value.sequence,
              value.kernel_step,
              input,
              value.limits,
              value.storage_bytes,
              fn() { true },
            ) {
            Ok(execution) => Score(execution)
            Err(_) => return fail_execution(value)
          }
        } else if @lower.operation(node) == "VEC.pool" {
          match
            @veca.start_pool(
              value.control,
              value.sequence,
              value.kernel_step,
              input,
              value.limits,
              value.storage_bytes,
              fn() { true },
            ) {
            Ok(execution) => Pool(execution)
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
          Pool(execution) =>
            match @veca.advance_pool(execution, quantum) {
              Ok(@veca.PoolContinue(progress~, work~)) =>
                Some((0, None, progress, work))
              Ok(@veca.PoolComplete(output, progress~, work~)) =>
                Some((1, Some(output), progress, work))
              Ok(@veca.PoolFailed(_, progress~, work~)) =>
                Some((2, None, progress, work))
              Ok(@veca.PoolStopped(_, progress~, work~)) =>
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
            value.pending_transformed = Some(completed)
            value.phase = CleanupKernel
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
      CleanupKernel => {
        guard value.kernel is Some(active) &&
          value.pending_transformed is Some(completed) else {
          return fail_execution(value)
        }
        match cleanup_kernel_execution(active) {
          Ok(true) => ()
          Ok(false) | Err(_) => return fail_execution(value)
        }
        value.kernel = None
        if value.projection_input is Some(_) {
          discard(Some(completed)) |> ignore
        } else {
          discard(value.transformed) |> ignore
          value.transformed = Some(completed)
        }
        value.pending_transformed = None
        value.kernel_step += 1
        if value.kernel_step < value.projection_step {
          value.phase = StartKernel
        } else {
          value.phase = StartProjection
        }
      }
      StartProjection => {
        let limits : @execution.ValueLimits = {
          max_nodes: value.limits.max_value_nodes,
          max_text_bytes: value.max_value_bytes,
          max_depth: value.limits.max_value_depth,
          max_work: value.limits.max_work,
        }
        let started_result = match value.carrier_input {
          Some(view) =>
            @bridge.start_vectors_view_to_rows(
              value.control,
              @execution.generated_completion_preparation(value.generated),
              value.sequence,
              value.projection_step,
              view,
              value.max_rows,
              limits,
              value.limits.max_workspace_slots,
              value.max_value_bytes,
            )
          None => {
            guard value.transformed is Some(output) &&
              value.relation_inputs is Some(inputs) else {
              return fail_execution(value)
            }
            let input = match value.projection_input {
              Some(read) => read
              None =>
                match
                  @records.prepare_step_read(
                    @execution.generated_sequence_owner(value.generated),
                    value.projection_step,
                    0,
                    output,
                  ) {
                  Ok(read) => read
                  Err(_) => return fail_execution(value)
                }
            }
            @bridge.start_vectors_to_rows(
              value.control,
              @execution.generated_completion_preparation(value.generated),
              value.sequence,
              value.projection_step,
              input,
              value.max_rows,
              limits,
              value.limits.max_workspace_slots,
              value.max_value_bytes,
              inputs,
            )
          }
        }
        let started = match started_result {
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
      StartNearestBridge => {
        guard value.relation_inputs is Some(inputs) &&
          value.nearest_bridge_step >= 0 &&
          value.nearest_bridge_step < value.nearest_step &&
          @lower.node_at(
            @lower.bound_preparation(
              @execution.generated_sequence_owner(value.generated),
            ),
            value.nearest_bridge_step,
          )
          is Some(node) &&
          @lower.node_input_target(node, 0) is Some(@pipeline.Input(input)) &&
          inputs.get(input) is Some(source) else {
          return fail_execution(value)
        }
        let started = match
          @bridge.start_rows_to_vectors(
            value.control,
            value.sequence,
            value.nearest_bridge_step,
            source,
            value.limits,
            value.storage_bytes,
            fn() { true },
          ) {
          Ok(execution) => execution
          Err(_) => return fail_execution(value)
        }
        value.nearest_bridge = Some(started)
        value.phase = NearestBridge
        reset_stage(value)
      }
      NearestBridge => {
        guard value.nearest_bridge is Some(active) else {
          return fail_execution(value)
        }
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
            value.nearest_bridge_output = Some(output)
            value.phase = CleanupNearestBridge
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
      CleanupNearestBridge => {
        guard value.nearest_bridge is Some(active) &&
          value.nearest_bridge_output is Some(output) else {
          return fail_execution(value)
        }
        match @bridge.cleanup_rows_to_vectors(active) {
          Ok(true) => ()
          Ok(false) | Err(_) => return fail_execution(value)
        }
        guard @lower.node_at(
            @lower.bound_preparation(
              @execution.generated_sequence_owner(value.generated),
            ),
            value.nearest_step,
          )
          is Some(nearest) else {
          return fail_execution(value)
        }
        let mut side = None
        for candidate in 0..<2 {
          if @lower.node_input_target(nearest, candidate) ==
            Some(@pipeline.Step(value.nearest_bridge_step)) {
            side = Some(candidate)
          }
        }
        guard side is Some(side) &&
          @records.prepare_step_read(
            @execution.generated_sequence_owner(value.generated),
            value.nearest_step,
            side,
            output,
          )
          is Ok(read) &&
          @veca.nearest_record_producer(read) is Some(nearest_input) else {
          return fail_execution(value)
        }
        value.nearest_inputs[side] = Some(nearest_input)
        value.nearest_bridge_outputs.push(output)
        value.nearest_bridge = None
        value.nearest_bridge_output = None
        value.nearest_bridge_step += 1
        value.phase = if value.nearest_bridge_step < value.nearest_step {
          StartNearestBridge
        } else {
          StartNearest
        }
      }
      StartNearest => {
        let prepared = @execution.generated_prepared_sequence(value.generated)
        guard @lower.sequence_step(prepared, value.nearest_step)
          is Some(@lower.VectorStep(_)) else {
          return fail_execution(value)
        }
        guard @lower.node_at(
            @lower.bound_preparation(
              @execution.generated_sequence_owner(value.generated),
            ),
            value.nearest_step,
          )
          is Some(nearest_node) else {
          return fail_execution(value)
        }
        for side in 0..<2 {
          if value.nearest_inputs[side] is None {
            guard @lower.node_input_target(nearest_node, side)
              is Some(@pipeline.Input(input_index)) &&
              value.inputs.get(input_index) is Some(input) &&
              nearest_input(input) is Some(prepared_input) else {
              return fail_execution(value)
            }
            value.nearest_inputs[side] = Some(prepared_input)
          }
        }
        guard value.nearest_inputs[0] is Some(left) &&
          value.nearest_inputs[1] is Some(right) else {
          return fail_execution(value)
        }
        let started_result = if value.nearest_step > 0 {
          match value.relation_inputs {
            Some(inputs) =>
              @veca.start_nearest_inputs_with_relations(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                value.nearest_step,
                left,
                right,
                value.max_rows,
                {
                  max_nodes: value.limits.max_value_nodes,
                  max_text_bytes: value.max_value_bytes,
                  max_depth: value.limits.max_value_depth,
                  max_work: value.limits.max_work,
                },
                value.limits.max_workspace_slots,
                value.limits.max_workspace_slots,
                value.max_value_bytes,
                inputs,
              )
            None => Err(@veca.InvalidNearestKernel)
          }
        } else {
          @veca.start_nearest_inputs(
            value.control,
            @execution.generated_completion_preparation(value.generated),
            value.sequence,
            value.nearest_step,
            left,
            right,
            value.max_rows,
            {
              max_nodes: value.limits.max_value_nodes,
              max_text_bytes: value.max_value_bytes,
              max_depth: value.limits.max_value_depth,
              max_work: value.limits.max_work,
            },
            value.limits.max_workspace_slots,
            value.limits.max_workspace_slots,
            value.max_value_bytes,
          )
        }
        let started = match started_result {
          Ok(execution) => execution
          Err(_) => return fail_execution(value)
        }
        value.nearest = Some(started)
        value.phase = Nearest
        reset_stage(value)
      }
      Nearest => {
        guard value.nearest is Some(active) else {
          return fail_execution(value)
        }
        match @veca.advance_nearest(active, quantum) {
          Err(_) => return fail_execution(value)
          Ok(@veca.NearestContinue(progress~, work~)) => {
            guard continue_poll(value, progress, work) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok(@veca.NearestComplete(output, progress~, work~)) => {
            guard delta(progress, value.stage_progress) is Some(progress_delta) &&
              delta(work, value.stage_work) is Some(work_delta) else {
              return fail_execution(value)
            }
            value.terminal = true
            value.phase = Terminal
            return Ok(
              @local.managed_provider_complete(
                output, progress_delta, work_delta,
              ),
            )
          }
          Ok(@veca.NearestFailed(_, progress~, work~)) => {
            guard terminal_poll(value, progress, work, false) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok(@veca.NearestStopped(_, progress~, work~)) => {
            guard terminal_poll(value, progress, work, true) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
        }
      }
      StartRanking => {
        guard value.ranking_inputs is Some(inputs) else {
          return fail_execution(value)
        }
        let started = match
          @veca.start_ranking_inputs(
            value.control,
            @execution.generated_completion_preparation(value.generated),
            value.sequence,
            0,
            inputs,
            value.max_rows,
            {
              max_nodes: value.limits.max_value_nodes,
              max_text_bytes: value.max_value_bytes,
              max_depth: value.limits.max_value_depth,
              max_work: value.limits.max_work,
            },
            value.limits.max_workspace_slots,
            value.limits.max_workspace_slots,
            value.max_value_bytes,
          ) {
          Ok(execution) => execution
          Err(_) => return fail_execution(value)
        }
        value.ranking = Some(started)
        value.phase = Ranking
        reset_stage(value)
      }
      Ranking => {
        guard value.ranking is Some(active) else {
          return fail_execution(value)
        }
        match @veca.advance_ranking(active, quantum) {
          Err(_) => return fail_execution(value)
          Ok(@veca.RankingContinue(progress~, work~)) => {
            guard continue_poll(value, progress, work) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok(@veca.RankingComplete(output, progress~, work~)) => {
            guard delta(progress, value.stage_progress) is Some(progress_delta) &&
              delta(work, value.stage_work) is Some(work_delta) else {
              return fail_execution(value)
            }
            value.terminal = true
            value.phase = Terminal
            return Ok(
              @local.managed_provider_complete(
                output, progress_delta, work_delta,
              ),
            )
          }
          Ok(@veca.RankingFailed(_, progress~, work~)) => {
            guard terminal_poll(value, progress, work, false) is Some(poll) else {
              return fail_execution(value)
            }
            return Ok(poll)
          }
          Ok(@veca.RankingStopped(_, progress~, work~)) => {
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
  if value.binding_execution is Some(active) {
    match @execution.cleanup_bounded_binding_rows(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.kernel is Some(active) {
    match cleanup_kernel_execution(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.projection is Some(active) {
    match @bridge.cleanup_vectors_to_rows(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.nearest_bridge is Some(active) {
    match @bridge.cleanup_rows_to_vectors(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.nearest is Some(active) {
    match @veca.cleanup_nearest(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.ranking is Some(active) {
    match @veca.cleanup_ranking(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  discard(value.transformed) |> ignore
  value.transformed = None
  discard(value.pending_transformed) |> ignore
  value.pending_transformed = None
  let rows_pending = match value.rows {
    Some(active) => @bridge.rows_to_vectors_cleanup_pending(active)
    None => false
  }
  let binding_pending = match value.binding_execution {
    Some(active) => @execution.bounded_binding_rows_cleanup_pending(active)
    None => false
  }
  let kernel_pending = match value.kernel {
    Some(Normalize(active)) => @veca.normalize_cleanup_pending(active)
    Some(Score(active)) => @veca.score_cleanup_pending(active)
    Some(Pool(active)) => @veca.pool_cleanup_pending(active)
    None => false
  }
  let projection_pending = match value.projection {
    Some(active) => @bridge.vectors_to_rows_cleanup_pending(active)
    None => false
  }
  let nearest_pending = match value.nearest {
    Some(active) => @veca.nearest_cleanup_pending(active)
    None => false
  }
  let nearest_bridge_pending = match value.nearest_bridge {
    Some(active) => @bridge.rows_to_vectors_cleanup_pending(active)
    None => false
  }
  let ranking_pending = match value.ranking {
    Some(active) => @veca.ranking_cleanup_pending(active)
    None => false
  }
  if failed {
    return Err(issue())
  }
  if binding_pending ||
    rows_pending ||
    kernel_pending ||
    projection_pending ||
    nearest_bridge_pending ||
    nearest_pending ||
    ranking_pending {
    return Ok(false)
  }
  for output in value.nearest_bridge_outputs {
    discard(Some(output)) |> ignore
  }
  value.nearest_bridge_outputs = []
  discard(value.nearest_bridge_output) |> ignore
  value.nearest_bridge_output = None
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
    fn(sequence) {
      if accepts(sequence) {
        let count = @execution.generated_sequence_step_count(sequence)
        if count == 1 {
          Some(capacity)
        } else {
          provider_capacity(capacity, storage_bytes, count - 1)
        }
      } else {
        None
      }
    },
    fn(sequence, inputs, max_rows, max_value_bytes, execution_limits) {
      if !accepts(sequence) || storage_bytes < 0L {
        return Err(@connector.InvalidLimits)
      }
      let selected_step = @execution.completion_preparation_selected_step(
        @execution.generated_completion_preparation(sequence),
      )
      let count = @execution.generated_sequence_step_count(sequence)
      guard @execution.generated_sequence_step_index_at(sequence, 0)
        is Some(first_step) else {
        return Err(@connector.InvalidLimits)
      }
      let selected = selected_step is Some(_)
      let first_operation = @lower.node_at(
        @lower.bound_preparation(@execution.generated_sequence_owner(sequence)),
        first_step,
      ).map(node => @lower.operation(node))
      let relation_pool = count == 2 && first_operation == Some("VEC.pool")
      let binding_rows = count == 1 &&
        !selected &&
        @lower.sequence_step(
          @execution.generated_prepared_sequence(sequence),
          0,
        )
        is Some(@lower.RowStep(_))
      let direct = count == 1
      let direct_operation = if direct {
        @lower.node_at(
          @lower.bound_preparation(
            @execution.generated_sequence_owner(sequence),
          ),
          first_step,
        ).map(node => @lower.operation(node))
      } else {
        None
      }
      let nearest_pipeline = accepts_nearest_pipeline(sequence, count)
      let relations = relation_inputs(inputs)
      let rankings = ranking_inputs(inputs)
      let direct_projection = direct_operation == Some("BRIDGE.vectors.to_rows")
      let carrier_input = match inputs {
        [@local.CarrierInput(view)] if direct_projection => Some(view)
        _ => None
      }
      if direct_projection && carrier_input is None {
        return Err(@connector.Execution(@execution.InputSet))
      }
      if direct_operation == Some("VEC.merge_rankings") && rankings is None {
        return Err(@connector.Execution(@execution.InputSet))
      }
      if direct_operation != Some("VEC.knn_join") &&
        !nearest_pipeline &&
        direct_operation != Some("VEC.merge_rankings") &&
        !direct_projection &&
        relations is None {
        return Err(@connector.Execution(@execution.InputSet))
      }
      let state : Execution = {
        generated: sequence,
        sequence: @execution.generated_prepared_sequence(sequence),
        inputs: inputs.copy(),
        relation_inputs: relations,
        carrier_input,
        ranking_inputs: rankings,
        control: @bounded.control(),
        limits,
        storage_bytes,
        max_rows,
        max_value_bytes,
        execution_limits,
        projection_step: if direct_projection {
          first_step
        } else {
          count - 1
        },
        relation_pool,
        phase: if direct_projection {
          StartProjection
        } else if binding_rows {
          StartBindingRows
        } else if direct_operation == Some("VEC.knn_join") {
          StartNearest
        } else if nearest_pipeline {
          StartNearestBridge
        } else if direct_operation == Some("VEC.merge_rankings") {
          StartRanking
        } else {
          StartRows
        },
        rows: None,
        binding_execution: None,
        kernel_step: if relation_pool {
          0
        } else {
          1
        },
        kernel: None,
        transformed: None,
        pending_transformed: None,
        projection_input: None,
        projection: None,
        nearest_step: if nearest_pipeline {
          count - 1
        } else {
          0
        },
        nearest_bridge_step: 0,
        nearest_bridge: None,
        nearest_bridge_output: None,
        nearest_bridge_outputs: [],
        nearest_inputs: Array::make(2, None),
        nearest: None,
        ranking: None,
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
