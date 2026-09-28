///|
priv enum Phase {
  StartRows
  Rows
  StartWatermark
  Watermark
  StartProjection
  Projection
  Terminal
}

///|
priv struct Execution {
  generated : @execution.GeneratedSequence
  sequence : @lower.PreparedSequence
  inputs : Array[@execution.ProducerRead]
  carrier_input : @lifecycle.ProducerView?
  relation_output : Bool
  row_step : Int
  event_step : Int
  projection_step : Int?
  control : @bounded.Control
  limits : @storage.Limits
  storage_bytes : Int64
  max_rows : Int
  max_value_bytes : Int
  mut phase : Phase
  mut rows : @bridge.RowsToEventsExecution?
  mut row_events : @records.Completed?
  mut watermark : @tea.WatermarkExecution?
  mut dedupe : @tea.DedupeExecution?
  mut window : @tea.EventWindowExecution?
  mut session : @tea.SessionExecution?
  mut watermarked : @records.Completed?
  mut projection : @bridge.EventsToRowsExecution?
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
  let count = @execution.generated_sequence_step_count(sequence)
  if count != 1 && count != 3 {
    return false
  }
  let index = Ref(0)
  let accepted = @execution.generated_sequence_all_steps(sequence, fn(step) {
    let current = index.val
    index.val += 1
    guard @execution.generated_sequence_step_index_at(sequence, current)
      is Some(actual) else {
      return false
    }
    guard @lower.node_at(@lower.bound_preparation(owner), actual) is Some(node) else {
      return false
    }
    match (current, step) {
      (0, @lower.EventStep(_)) =>
        @lower.operation(node) == "BRIDGE.rows.to_events" ||
        (
          count == 1 &&
          (
            @lower.operation(node) == "TEA.watermark.label" ||
            @lower.operation(node) == "TEA.dedupe" ||
            @lower.operation(node) == "TEA.window.session_assign"
          )
        )
      (0, @lower.CarrierProjectionStep(projection)) if count == 1 =>
        @lower.operation(node) == "BRIDGE.events.to_rows" &&
        @lower.carrier_projection_operation(projection) ==
        @carrier_projection.Events
      (1, @lower.EventStep(_)) =>
        @lower.operation(node) == "TEA.watermark.label" ||
        @lower.operation(node) == "TEA.dedupe" ||
        @lower.operation(node) == "TEA.window.session_assign"
      (1, @lower.WindowStep(window)) =>
        @lower.window_preserves_events(window) &&
        (
          @lower.operation(node) == "TEA.window.fixed_label" ||
          @lower.operation(node) == "TEA.window.sliding_assign"
        )
      (2, @lower.CarrierProjectionStep(projection)) =>
        @lower.operation(node) == "BRIDGE.events.to_rows" &&
        @lower.carrier_projection_operation(projection) ==
        @carrier_projection.Events
      _ => false
    }
  })
  accepted && index.val == count
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
          @bridge.start_rows_to_events(
            value.control,
            value.sequence,
            value.row_step,
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
        match @bridge.advance_rows_to_events(active, quantum) {
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
            if @execution.generated_sequence_step_count(value.generated) == 1 {
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
            value.row_events = Some(output)
            value.phase = StartWatermark
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
      StartWatermark => {
        let input = match value.row_events {
          Some(output) =>
            match
              @records.prepare_step_read(
                @execution.generated_sequence_owner(value.generated),
                value.event_step,
                0,
                output,
              ) {
              Ok(read) => Some(read)
              Err(_) => return fail_execution(value)
            }
          None => None
        }
        guard @lower.node_at(
            @lower.bound_preparation(
              @execution.generated_sequence_owner(value.generated),
            ),
            value.event_step,
          )
          is Some(node) else {
          return fail_execution(value)
        }
        match @lower.operation(node) {
          "TEA.watermark.label" =>
            match (input, value.carrier_input) {
              (Some(input), _) =>
                match
                  @tea.start_watermark(
                    value.control,
                    value.sequence,
                    value.event_step,
                    input,
                    value.limits,
                    value.storage_bytes,
                    fn() { true },
                  ) {
                  Ok(execution) => value.watermark = Some(execution)
                  Err(_) => return fail_execution(value)
                }
              (None, Some(view)) =>
                match
                  @tea.start_watermark_view(
                    value.control,
                    value.sequence,
                    value.event_step,
                    view,
                    value.limits,
                    value.storage_bytes,
                    fn() { true },
                  ) {
                  Ok(execution) => value.watermark = Some(execution)
                  Err(_) => return fail_execution(value)
                }
              _ => return fail_execution(value)
            }
          "TEA.dedupe" =>
            match (input, value.carrier_input) {
              (Some(read), _) =>
                match
                  @tea.start_dedupe(
                    value.control,
                    value.sequence,
                    value.event_step,
                    read,
                    value.limits,
                    value.storage_bytes,
                    fn() { true },
                  ) {
                  Ok(execution) => value.dedupe = Some(execution)
                  Err(_) => return fail_execution(value)
                }
              (None, Some(view)) =>
                match
                  @tea.start_dedupe_view(
                    value.control,
                    value.sequence,
                    value.event_step,
                    view,
                    value.limits,
                    value.storage_bytes,
                    fn() { true },
                  ) {
                  Ok(execution) => value.dedupe = Some(execution)
                  Err(_) => return fail_execution(value)
                }
              _ => return fail_execution(value)
            }
          "TEA.window.session_assign" => {
            let started = match (input, value.carrier_input) {
              (Some(input), _) =>
                @tea.start_session(
                  value.control,
                  value.sequence,
                  value.event_step,
                  input,
                  value.limits,
                  value.storage_bytes,
                  fn() { true },
                )
              (None, Some(input)) =>
                @tea.start_session_view(
                  value.control,
                  value.sequence,
                  value.event_step,
                  input,
                  value.limits,
                  value.storage_bytes,
                  fn() { true },
                )
              _ =>
                if value.relation_output && value.inputs.length() == 1 {
                  @tea.start_session_relation(
                    value.control,
                    value.sequence,
                    value.event_step,
                    value.inputs[0],
                    value.limits,
                    value.storage_bytes,
                    fn() { true },
                  )
                } else {
                  return fail_execution(value)
                }
            }
            match started {
              Ok(execution) => value.session = Some(execution)
              Err(_) => return fail_execution(value)
            }
          }
          "TEA.window.fixed_label" | "TEA.window.sliding_assign" =>
            match
              @tea.start_event_window(
                value.control,
                value.sequence,
                value.event_step,
                input.unwrap(),
                value.limits,
                value.storage_bytes,
                fn() { true },
              ) {
              Ok(execution) => value.window = Some(execution)
              Err(_) => return fail_execution(value)
            }
          _ => return fail_execution(value)
        }
        value.phase = Watermark
        reset_stage(value)
      }
      Watermark =>
        if value.watermark is Some(active) {
          match @tea.advance_watermark(active, quantum) {
            Err(_) => return fail_execution(value)
            Ok(@tea.Continue(progress~, work~)) => {
              guard continue_poll(value, progress, work) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
            Ok(@tea.Complete(output, progress~, work~)) => {
              guard delta(progress, value.stage_progress)
                is Some(progress_delta) &&
                delta(work, value.stage_work) is Some(work_delta) else {
                return fail_execution(value)
              }
              if value.projection_step is None {
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
              let poll = @local.managed_provider_continue(
                progress_delta, work_delta,
              )
              value.watermarked = Some(output)
              discard(value.row_events) |> ignore
              value.row_events = None
              value.phase = StartProjection
              if poll is @local.Continue(work=work_delta, ..) && work_delta > 0L {
                return Ok(poll)
              }
            }
            Ok(@tea.Failed(_, progress~, work~)) => {
              guard terminal_poll(value, progress, work, false) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
            Ok(@tea.Stopped(_, progress~, work~)) => {
              guard terminal_poll(value, progress, work, true) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
          }
        } else if value.dedupe is Some(active) {
          match @tea.advance_dedupe(active, quantum) {
            Err(_) => return fail_execution(value)
            Ok(@tea.DedupeContinue(progress~, work~)) => {
              guard continue_poll(value, progress, work) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
            Ok(@tea.DedupeComplete(output, progress~, work~)) => {
              guard delta(progress, value.stage_progress)
                is Some(progress_delta) &&
                delta(work, value.stage_work) is Some(work_delta) else {
                @records.discard_completed(output) |> ignore
                return fail_execution(value)
              }
              if value.projection_step is None {
                let material = match @records.completed_material(output) {
                  Ok(material) => material
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
              let poll = @local.managed_provider_continue(
                progress_delta, work_delta,
              )
              value.watermarked = Some(output)
              discard(value.row_events) |> ignore
              value.row_events = None
              value.phase = StartProjection
              if poll is @local.Continue(work=work_delta, ..) && work_delta > 0L {
                return Ok(poll)
              }
            }
            Ok(@tea.DedupeFailed(_, progress~, work~)) => {
              guard terminal_poll(value, progress, work, false) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
            Ok(@tea.DedupeStopped(_, progress~, work~)) => {
              guard terminal_poll(value, progress, work, true) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
          }
        } else if value.window is Some(active) {
          match @tea.advance_event_window(active, quantum) {
            Err(_) => return fail_execution(value)
            Ok(@tea.EventWindowContinue(progress~, work~)) => {
              guard continue_poll(value, progress, work) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
            Ok(@tea.EventWindowComplete(output, progress~, work~)) => {
              guard continue_poll(value, progress, work) is Some(poll) else {
                return fail_execution(value)
              }
              value.watermarked = Some(output)
              discard(value.row_events) |> ignore
              value.row_events = None
              value.phase = StartProjection
              if poll is @local.Continue(work=work_delta, ..) && work_delta > 0L {
                return Ok(poll)
              }
            }
            Ok(@tea.EventWindowFailed(_, progress~, work~)) => {
              guard terminal_poll(value, progress, work, false) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
            Ok(@tea.EventWindowStopped(_, progress~, work~)) => {
              guard terminal_poll(value, progress, work, true) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
          }
        } else if value.session is Some(active) {
          match @tea.advance_session(active, quantum) {
            Err(_) => return fail_execution(value)
            Ok(@tea.SessionContinue(progress~, work~)) => {
              guard continue_poll(value, progress, work) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
            Ok(@tea.SessionComplete(output, progress~, work~)) => {
              guard delta(progress, value.stage_progress)
                is Some(progress_delta) &&
                delta(work, value.stage_work) is Some(work_delta) else {
                return fail_execution(value)
              }
              if value.projection_step is None && value.relation_output {
                let started = match
                  @bridge.start_completed_relation_to_rows(
                    value.control,
                    @execution.generated_completion_preparation(value.generated),
                    value.sequence,
                    value.event_step,
                    output,
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
                    control_work_limit=Some(value.limits.max_work),
                  ) {
                  Ok(execution) => execution
                  Err(_) => {
                    @records.discard_completed(output) |> ignore
                    return fail_execution(value)
                  }
                }
                value.projection = Some(started)
                value.phase = Projection
                reset_stage(value)
                if work_delta > 0L {
                  return Ok(
                    @local.managed_provider_continue(progress_delta, work_delta),
                  )
                }
              } else if value.projection_step is None {
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
              let poll = @local.managed_provider_continue(
                progress_delta, work_delta,
              )
              value.watermarked = Some(output)
              discard(value.row_events) |> ignore
              value.row_events = None
              value.phase = StartProjection
              if work_delta > 0L {
                return Ok(poll)
              }
            }
            Ok(@tea.SessionFailed(_, progress~, work~)) => {
              guard terminal_poll(value, progress, work, false) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
            Ok(@tea.SessionStopped(_, progress~, work~)) => {
              guard terminal_poll(value, progress, work, true) is Some(poll) else {
                return fail_execution(value)
              }
              return Ok(poll)
            }
          }
        } else {
          return fail_execution(value)
        }
      StartProjection => {
        guard value.projection_step is Some(projection_step) else {
          return fail_execution(value)
        }
        let started = match value.carrier_input {
          Some(view) =>
            match
              @bridge.start_events_view_to_rows(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                projection_step,
                view,
                value.max_rows,
                {
                  max_nodes: value.limits.max_value_nodes,
                  max_text_bytes: value.max_value_bytes,
                  max_depth: value.limits.max_value_depth,
                  max_work: value.limits.max_work,
                },
                value.limits.max_workspace_slots,
                value.max_value_bytes,
                control_work_limit=Some(value.limits.max_work),
              ) {
              Ok(execution) => execution
              Err(_) => return fail_execution(value)
            }
          None => {
            guard value.watermarked is Some(output) else {
              return fail_execution(value)
            }
            let input = match
              @records.prepare_step_read(
                @execution.generated_sequence_owner(value.generated),
                projection_step,
                0,
                output,
              ) {
              Ok(read) => read
              Err(_) => return fail_execution(value)
            }
            match
              @bridge.start_events_to_rows(
                value.control,
                @execution.generated_completion_preparation(value.generated),
                value.sequence,
                projection_step,
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
                control_work_limit=Some(value.limits.max_work),
              ) {
              Ok(execution) => execution
              Err(_) => return fail_execution(value)
            }
          }
        }
        value.projection = Some(started)
        value.phase = Projection
        reset_stage(value)
      }
      Projection => {
        guard value.projection is Some(active) else {
          return fail_execution(value)
        }
        match @bridge.advance_events_to_rows(active, quantum) {
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
            discard(value.watermarked) |> ignore
            value.watermarked = None
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
    match @bridge.cleanup_rows_to_events(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.watermark is Some(active) {
    match @tea.cleanup_watermark(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.dedupe is Some(active) {
    match @tea.cleanup_dedupe(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.window is Some(active) {
    match @tea.cleanup_event_window(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.session is Some(active) {
    match @tea.cleanup_session(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  if value.projection is Some(active) {
    match @bridge.cleanup_events_to_rows(active) {
      Ok(_) => ()
      Err(_) => failed = true
    }
  }
  discard(value.row_events) |> ignore
  value.row_events = None
  discard(value.watermarked) |> ignore
  value.watermarked = None
  let rows_pending = match value.rows {
    Some(active) => @bridge.rows_to_events_cleanup_pending(active)
    None => false
  }
  let watermark_pending = match value.watermark {
    Some(active) => @tea.watermark_cleanup_pending(active)
    None => false
  }
  let dedupe_pending = match value.dedupe {
    Some(active) => @tea.dedupe_cleanup_pending(active)
    None => false
  }
  let window_pending = match value.window {
    Some(active) => @tea.event_window_cleanup_pending(active)
    None => false
  }
  let session_pending = match value.session {
    Some(active) => @tea.session_cleanup_pending(active)
    None => false
  }
  let projection_pending = match value.projection {
    Some(active) => @bridge.events_to_rows_cleanup_pending(active)
    None => false
  }
  if failed {
    return Err(issue())
  }
  if rows_pending ||
    watermark_pending ||
    dedupe_pending ||
    window_pending ||
    session_pending ||
    projection_pending {
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
    fn(sequence) {
      if accepts(sequence) {
        provider_capacity(capacity, storage_bytes)
      } else {
        None
      }
    },
    fn(sequence, inputs, max_rows, max_value_bytes, _execution) {
      if !accepts(sequence) || storage_bytes < 0L {
        return Err(@connector.InvalidLimits)
      }
      let owner = @execution.generated_sequence_owner(sequence)
      let step_count = @execution.generated_sequence_step_count(sequence)
      guard @execution.generated_sequence_step_index_at(sequence, 0)
        is Some(first_step) else {
        return Err(@connector.InvalidLimits)
      }
      let direct_session = step_count == 1 &&
        @lower.node_at(@lower.bound_preparation(owner), first_step)
        is Some(node) &&
        @lower.operation(node) == "TEA.window.session_assign"
      let direct_watermark = step_count == 1 &&
        @lower.node_at(@lower.bound_preparation(owner), first_step)
        is Some(node) &&
        @lower.operation(node) == "TEA.watermark.label"
      let direct_dedupe = step_count == 1 &&
        @lower.node_at(@lower.bound_preparation(owner), first_step)
        is Some(node) &&
        @lower.operation(node) == "TEA.dedupe"
      let direct_projection = step_count == 1 &&
        @lower.node_at(@lower.bound_preparation(owner), first_step)
        is Some(node) &&
        @lower.operation(node) == "BRIDGE.events.to_rows"
      let direct_rows = step_count == 1 &&
        @lower.node_at(@lower.bound_preparation(owner), first_step)
        is Some(node) &&
        @lower.operation(node) == "BRIDGE.rows.to_events"
      let direct_relation = direct_session &&
        @lower.node_at(@lower.bound_preparation(owner), first_step)
        is Some(node) &&
        @lower.node_input_target(node, 0) is Some(input_target) &&
        @lower.preparation_carrier_at(
          @lower.bound_preparation(owner),
          input_target,
        )
        is Some(input_carrier) &&
        @carrier.kind(input_carrier) == @carrier.RelationKind
      let relations : Array[@execution.ProducerRead] = []
      let mut carrier_input = None
      for input in inputs {
        match input {
          @local.RelationInput(value) => relations.push(value)
          @local.SuppliedRelationInput(_) =>
            return Err(@connector.Execution(@execution.InputSet))
          @local.CarrierInput(value) =>
            if carrier_input is Some(_) {
              return Err(@connector.InvalidLimits)
            } else {
              carrier_input = Some(value)
            }
        }
      }
      if direct_relation {
        if relations.length() != 1 || carrier_input is Some(_) {
          return Err(@connector.InvalidLimits)
        }
      } else if direct_session ||
        direct_watermark ||
        direct_dedupe ||
        direct_projection {
        if relations.length() != 0 || carrier_input is None {
          return Err(@connector.InvalidLimits)
        }
      } else if direct_rows {
        if relations.length() != 1 || carrier_input is Some(_) {
          return Err(@connector.InvalidLimits)
        }
      } else if relations.length() != inputs.length() ||
        carrier_input is Some(_) {
        return Err(@connector.InvalidLimits)
      }
      let state : Execution = {
        generated: sequence,
        sequence: @execution.generated_prepared_sequence(sequence),
        inputs: relations,
        carrier_input,
        relation_output: direct_relation,
        row_step: if direct_rows {
          first_step
        } else {
          0
        },
        event_step: if direct_session || direct_watermark || direct_dedupe {
          first_step
        } else {
          1
        },
        projection_step: if direct_projection {
          Some(first_step)
        } else if direct_session || direct_watermark || direct_dedupe {
          None
        } else if step_count == 3 {
          Some(2)
        } else {
          None
        },
        control: @bounded.control(),
        limits,
        storage_bytes,
        max_rows,
        max_value_bytes,
        phase: if direct_projection {
          StartProjection
        } else if direct_session || direct_watermark || direct_dedupe {
          StartWatermark
        } else {
          StartRows
        },
        rows: None,
        row_events: None,
        watermark: None,
        dedupe: None,
        window: None,
        session: None,
        watermarked: None,
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
