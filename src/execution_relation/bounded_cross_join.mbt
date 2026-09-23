///|
priv enum BoundedCrossJoinPhase {
  ResolveField
  ResolveSource
  BeginPair
  BuildCell
  CommitRow
  FinishOutput
  Terminal
}

///|
priv struct BoundedCrossJoinState {
  left : ProducerRead
  right : ProducerRead
  profile : @lower.PreparedCrossJoin
  output_schema : @schema.Schema
  output_ceiling : Int
  control : ControlBudget
  workspace : RowWorkspace
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut names : Array[String]
  mut columns : Array[(Bool, Int)]
  mut phase : BoundedCrossJoinPhase
  mut field : Int
  mut source_column : Int
  mut source_name : String
  mut output_name : String
  mut on_left : Bool
  mut left_row : Int
  mut right_row : Int
  mut column : Int
  mut emitted : Int
  mut checked_row : Array[@admitted.CheckedValue]
}

///|
pub(all) enum BoundedCrossJoinIssue {
  InvalidExecution
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedCrossJoinExecution {
  session : @bounded.Session[
    BoundedCrossJoinState,
    CompletedOutput,
    BoundedCrossJoinIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum BoundedCrossJoinPoll {
  BoundedCrossJoinContinue(progress~ : Int64, work~ : Int64)
  BoundedCrossJoinComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedCrossJoinFailed(
    BoundedCrossJoinIssue,
    progress~ : Int64,
    work~ : Int64
  )
  BoundedCrossJoinStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn bounded_cross_join_failure(
  issue : BoundedCrossJoinIssue,
  progress : Int,
  work : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedCrossJoinIssue] {
  @bounded.Failed(issue, progress, work)
}

///|
fn cleanup_bounded_cross_join_state(state : BoundedCrossJoinState) -> Bool {
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.names = []
  state.columns = []
  state.checked_row = []
  release_slots(state.workspace, state.workspace.live)
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
fn bounded_cross_join_step(
  state : BoundedCrossJoinState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedCrossJoinIssue] {
  let mut used = 0
  let mut progress = 0
  let left_count = producer_read_row_count(state.left)
  let right_count = producer_read_row_count(state.right)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !producer_read_available(state.left) ||
      !producer_read_available(state.right) {
      return bounded_cross_join_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      ResolveField => {
        if state.field == @lower.cross_join_field_count(state.profile) {
          state.phase = BeginPair
          continue
        }
        guard @lower.cross_join_field_at(state.profile, state.field)
          is Some(field) else {
          return bounded_cross_join_failure(InvalidExecution, progress, used)
        }
        let (on_left, source) = match field.input {
          @schema.Qualified(side, name) =>
            (side == @schema.Left, @schema.Unqualified(name))
          _ =>
            return bounded_cross_join_failure(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.output)
        if !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) {
          return bounded_cross_join_failure(Rows(RowLimit), progress, used)
        }
        state.output_name = name
        state.source_name = @schema.reference_name(source)
        state.on_left = on_left
        state.source_column = 0
        state.phase = ResolveSource
        used += 1
      }
      ResolveSource => {
        let schema = producer_read_schema(
          if state.on_left {
            state.left
          } else {
            state.right
          },
        )
        if state.source_column == @schema.field_count(schema) {
          return bounded_cross_join_failure(InvalidExecution, progress, used)
        }
        guard @schema.field_at(schema, state.source_column) is Some(candidate) else {
          return bounded_cross_join_failure(InvalidExecution, progress, used)
        }
        if !spend_control(state.control, 1) ||
          !spend_control_text(state.control, state.source_name) {
          return bounded_cross_join_failure(Rows(RowLimit), progress, used)
        }
        if @schema.reference_name(candidate.name) == state.source_name {
          if !reserve_slots(state.workspace, 3) {
            return bounded_cross_join_failure(Rows(RowLimit), progress, used)
          }
          state.names.push(state.output_name)
          state.columns.push((state.on_left, state.source_column))
          state.field += 1
          state.phase = ResolveField
        } else {
          state.source_column += 1
        }
        used += 1
      }
      BeginPair => {
        if state.left_row == left_count {
          state.phase = FinishOutput
          continue
        }
        if state.right_row == right_count {
          state.left_row += 1
          state.right_row = 0
          continue
        }
        if state.emitted >= state.output_ceiling ||
          !spend_control(state.control, 1) ||
          !reserve_slots(state.workspace, 2) {
          return bounded_cross_join_failure(Rows(RowLimit), progress, used)
        }
        state.checked_row = []
        state.column = 0
        state.phase = BuildCell
        used += 1
      }
      BuildCell => {
        if state.column == state.columns.length() {
          state.phase = CommitRow
          continue
        }
        let source = state.columns[state.column]
        guard producer_read_cell(
            if source.0 {
              state.left
            } else {
              state.right
            },
            if source.0 {
              state.left_row
            } else {
              state.right_row
            },
            source.1,
          )
          is Some(value) &&
          @schema.field_at(state.output_schema, state.column) is Some(field) else {
          return bounded_cross_join_failure(InvalidExecution, progress, used)
        }
        if !spend_control(state.control, 1) ||
          !reserve_slots(state.workspace, 1) {
          return bounded_cross_join_failure(Rows(RowLimit), progress, used)
        }
        guard checked_ordered_output_value(
            value,
            field.contract,
            state.admitted_limits,
          )
          is Some(checked) else {
          return bounded_cross_join_failure(InvalidExecution, progress, used)
        }
        state.checked_row.push(checked)
        state.column += 1
        used += 1
      }
      CommitRow => {
        guard state.output is Some(output) else {
          return bounded_cross_join_failure(InvalidExecution, progress, used)
        }
        match append_admitted_output(output, state.checked_row) {
          Err(issue) =>
            return bounded_cross_join_failure(
              Capture(issue),
              progress,
              used + 1,
            )
          Ok(_) => ()
        }
        release_slots(state.workspace, 2 + state.checked_row.length())
        state.checked_row = []
        state.right_row += 1
        state.emitted += 1
        state.phase = BeginPair
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return bounded_cross_join_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return bounded_cross_join_failure(
              Capture(issue),
              progress,
              used + 1,
            )
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) =>
            bounded_cross_join_failure(Completion(issue), progress, used)
        }
      }
      Terminal =>
        return bounded_cross_join_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
pub fn start_bounded_cross_join(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  left : ProducerRead,
  right : ProducerRead,
  max_rows : Int,
  values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedCrossJoinExecution, BoundedCrossJoinIssue] {
  if max_rows < 0 ||
    max_work < 0 ||
    max_frames < 0 ||
    max_entries < 0 ||
    max_name_bytes < 0 {
    return Err(InvalidExecution)
  }
  let owner = @lower.sequence_owner(generated.sequence)
  guard generated_sequence_step_index_at(generated, 0) is Some(step) &&
    generated_sequence_step_index_at(generated, 1) is None &&
    @lower.sequence_step(generated.sequence, step)
    is Some(@lower.CrossJoinStep(kernel)) &&
    producer_read_matches_operation_input(left, owner, step, 0) &&
    producer_read_matches_operation_input(right, owner, step, 1) &&
    producer_read_has_cell_access(left) &&
    producer_read_has_cell_access(right) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(output_schema) else {
    return Err(InvalidExecution)
  }
  let left_count = producer_read_row_count(left)
  let right_count = producer_read_row_count(right)
  if left_count > max_rows || right_count > max_rows {
    return Err(Rows(RowLimit))
  }
  let profile = @lower.cross_join_kernel_profile(kernel)
  if @lower.cross_join_requires_one_right(profile) && right_count != 1 {
    return Err(Rows(InvalidRows))
  }
  let mut ceiling = max_rows
  if @lower.cross_join_kernel_output_limit(kernel) is Some(limit) &&
    limit < ceiling.to_int64() {
    if limit < 0L {
      return Err(InvalidExecution)
    }
    ceiling = limit.to_int()
  }
  if generated_join_output_ceiling(generated, step) is Some(limit) &&
    limit < ceiling.to_int64() {
    if limit < 0L {
      return Err(InvalidExecution)
    }
    ceiling = limit.to_int()
  }
  if right_count != 0 && left_count > ceiling / right_count {
    return Err(Rows(RowLimit))
  }
  let width = @lower.cross_join_field_count(profile)
  if width > (max_entries - 2) / 3 ||
    width != @schema.field_count(output_schema) {
    return Err(Rows(RowLimit))
  }
  let workspace = row_workspace(max_entries)
  if !reserve_slots(workspace, 2) {
    return Err(Rows(RowLimit))
  }
  let output = match
    prepare_admitted_output(owner, @pipeline.Step(step), ceiling, values) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let rows : Ref[AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    prepare_trusted_output_port(
      generated_completion_preparation(generated),
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=[left, right],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedCrossJoinState = {
    left,
    right,
    profile,
    output_schema,
    output_ceiling: ceiling,
    control: { remaining: max_work, max_frames, },
    workspace,
    admitted_limits: {
      max_nodes: values.max_nodes,
      max_depth: values.max_depth,
      max_text_bytes: values.max_text_bytes,
    },
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    names: [],
    columns: [],
    phase: ResolveField,
    field: 0,
    source_column: 0,
    source_name: "",
    output_name: "",
    on_left: true,
    left_row: 0,
    right_row: 0,
    column: 0,
    emitted: 0,
    checked_row: [],
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_cross_join_step,
    cleanup_bounded_cross_join_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn advance_bounded_cross_join(
  value : BoundedCrossJoinExecution,
  quantum : Int,
) -> Result[BoundedCrossJoinPoll, BoundedCrossJoinIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedCrossJoinContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedCrossJoinComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedCrossJoinFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedCrossJoinStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_cross_join(
  value : BoundedCrossJoinExecution,
) -> Result[Bool, BoundedCrossJoinIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}
