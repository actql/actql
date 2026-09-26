///|
priv enum BoundedJoinPhase {
  ChargeInput
  ResolveKey
  ResolveKeySource
  ResolveField
  ResolveSource
  BeginPair
  BuildCell
  ChargeCell
  CommitRow
  FinishOutput
  Terminal
}

///|
priv struct BoundedJoinState {
  left : BoundedBindingInput
  right : BoundedBindingInput
  profile : @lower.PreparedInnerJoin
  output_schema : @schema.Schema
  output_ceiling : Int
  control : ControlBudget
  workspace : RowWorkspace
  input_scan : BoundedBinaryInputScan
  pairs : BoundedJoinPairs
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut names : Array[String]
  mut columns : Array[(Bool, Int)]
  mut phase : BoundedJoinPhase
  mut field : Int
  mut source_column : Int
  mut source_name : String
  mut output_name : String
  mut on_left : Bool
  mut column : Int
  mut emitted : Int
  mut checked_row : Array[@admitted.Value]
  mut pair : JoinPair?
  mut pending : @admitted.Value?
  mut measure : SteppedValueMeasure?
  mut key_left_column : Int
}

///|
pub(all) enum BoundedJoinIssue {
  InvalidExecution
  InputLimit
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedJoinExecution {
  session : @bounded.Session[
    BoundedJoinState,
    CompletedOutput,
    BoundedJoinIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  state : BoundedJoinState
}

///|
fn bounded_join_state(value : BoundedJoinExecution) -> BoundedJoinState {
  value.state
}

///|
pub enum BoundedJoinPoll {
  BoundedJoinContinue(progress~ : Int64, work~ : Int64)
  BoundedJoinComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedJoinFailed(BoundedJoinIssue, progress~ : Int64, work~ : Int64)
  BoundedJoinStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn bounded_join_failure(
  issue : BoundedJoinIssue,
  progress : Int,
  work : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedJoinIssue] {
  @bounded.Failed(issue, progress, work)
}

///|
fn cleanup_bounded_join_state(state : BoundedJoinState) -> Bool {
  cleanup_binary_input_scan(state.input_scan)
  cleanup_bounded_join_pairs(state.pairs)
  if state.measure is Some(cursor) {
    clear_stepped_measure(cursor)
    state.measure = None
  }
  state.pending = None
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
fn bounded_join_step(
  state : BoundedJoinState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedJoinIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !bounded_binding_input_available(state.left) ||
      !bounded_binding_input_available(state.right) {
      return bounded_join_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      ChargeInput => {
        match advance_binary_input_scan(state.input_scan) {
          Ok(true) => state.phase = ResolveKey
          Ok(false) => ()
          Err(ValueLimit) =>
            return bounded_join_failure(InputLimit, progress, used + 1)
          Err(ControlLimit) =>
            return bounded_join_failure(Rows(RowLimit), progress, used + 1)
          Err(WorkspaceLimit) =>
            return bounded_join_failure(Rows(RowLimit), progress, used + 1)
          Err(InputUnavailable) =>
            return bounded_join_failure(InvalidExecution, progress, used + 1)
        }
        used += 1
      }
      ResolveKey => {
        if state.field == @lower.inner_join_key_count(state.profile) {
          state.field = 0
          state.phase = ResolveField
          continue
        }
        guard @lower.inner_join_key_at(state.profile, state.field)
          is Some((left, _)) else {
          return bounded_join_failure(InvalidExecution, progress, used)
        }
        state.source_name = @schema.reference_name(left)
        state.source_column = 0
        state.on_left = true
        state.phase = ResolveKeySource
        used += 1
      }
      ResolveKeySource => {
        let schema = bounded_binding_input_schema(
          if state.on_left {
            state.left
          } else {
            state.right
          },
        )
        guard @schema.field_at(schema, state.source_column) is Some(field) else {
          return bounded_join_failure(InvalidExecution, progress, used)
        }
        if !spend_control(state.control, 1) ||
          !spend_control_text(state.control, state.source_name) {
          return bounded_join_failure(Rows(RowLimit), progress, used)
        }
        if @schema.reference_name(field.name) != state.source_name {
          state.source_column += 1
        } else if state.on_left {
          state.key_left_column = state.source_column
          let (_, right) = @lower.inner_join_key_at(state.profile, state.field).unwrap()
          state.source_name = @schema.reference_name(right)
          state.source_column = 0
          state.on_left = false
        } else {
          if !reserve_slots(state.workspace, 3) {
            return bounded_join_failure(Rows(RowLimit), progress, used)
          }
          state.pairs.keys.push((state.key_left_column, state.source_column))
          state.pairs.orders.push({
            column: state.field,
            descending: false,
            nulls_first: true,
          })
          state.field += 1
          state.phase = ResolveKey
        }
        used += 1
      }
      ResolveField => {
        if state.field == @lower.inner_join_field_count(state.profile) {
          state.phase = BeginPair
          continue
        }
        guard @lower.inner_join_field_at(state.profile, state.field)
          is Some(field) else {
          return bounded_join_failure(InvalidExecution, progress, used)
        }
        let (on_left, source) = match field.input {
          @schema.Qualified(side, name) =>
            (side == @schema.Left, @schema.Unqualified(name))
          _ => return bounded_join_failure(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.output)
        if !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) {
          return bounded_join_failure(Rows(RowLimit), progress, used)
        }
        state.output_name = name
        state.source_name = @schema.reference_name(source)
        state.on_left = on_left
        state.source_column = 0
        state.phase = ResolveSource
        used += 1
      }
      ResolveSource => {
        let schema = bounded_binding_input_schema(
          if state.on_left {
            state.left
          } else {
            state.right
          },
        )
        if state.source_column == @schema.field_count(schema) {
          return bounded_join_failure(InvalidExecution, progress, used)
        }
        guard @schema.field_at(schema, state.source_column) is Some(candidate) else {
          return bounded_join_failure(InvalidExecution, progress, used)
        }
        if !spend_control(state.control, 1) ||
          !spend_control_text(state.control, state.source_name) {
          return bounded_join_failure(Rows(RowLimit), progress, used)
        }
        if @schema.reference_name(candidate.name) == state.source_name {
          if !reserve_slots(state.workspace, 3) {
            return bounded_join_failure(Rows(RowLimit), progress, used)
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
        match advance_bounded_join_pairs(state.pairs) {
          Err(issue) =>
            return bounded_join_failure(Rows(issue), progress, used + 1)
          Ok(JoinPairContinue) => ()
          Ok(JoinPairsComplete) => state.phase = FinishOutput
          Ok(JoinPairReady(pair)) => {
            guard state.output is Some(output) else {
              return bounded_join_failure(InvalidExecution, progress, used)
            }
            if state.emitted >= state.output_ceiling ||
              !output.buffer.open ||
              output.buffer.reading ||
              !reserve_slots(state.workspace, 2) {
              return bounded_join_failure(Rows(RowLimit), progress, used + 1)
            }
            if !charge_node(output.buffer.budget, 1) {
              return bounded_join_failure(
                Capture(CaptureLimit),
                progress,
                used + 1,
              )
            }
            state.pair = Some(pair)
            state.checked_row = []
            state.column = 0
            state.phase = BuildCell
          }
        }
        used += 1
      }
      BuildCell => {
        if state.column == state.columns.length() {
          state.phase = CommitRow
          continue
        }
        let source = state.columns[state.column]
        guard state.pair is Some(pair) &&
          @schema.field_at(state.output_schema, state.column) is Some(field) else {
          return bounded_join_failure(InvalidExecution, progress, used)
        }
        let input = if source.0 { state.left } else { state.right }
        let row = if source.0 { pair.left } else { pair.right }
        if !spend_control(state.control, 1) ||
          !reserve_slots(state.workspace, 1) {
          return bounded_join_failure(Rows(RowLimit), progress, used)
        }
        let admitted = match row {
          None => {
            if !field.contract.nullable {
              return bounded_join_failure(InvalidExecution, progress, used)
            }
            @admitted.null_value()
          }
          Some(row) =>
            match bounded_binding_input_admitted_cell(input, row, source.1) {
              // The exact checked join projection preserves the source domain,
              // with only a nullable lift for an outer side.
              Some(value) => value
              None => {
                guard bounded_binding_input_cell(input, row, source.1)
                  is Some(value) &&
                  checked_ordered_output_value(
                    value,
                    field.contract,
                    state.admitted_limits,
                  )
                  is Some(checked) else {
                  return bounded_join_failure(InvalidExecution, progress, used)
                }
                checked.value
              }
            }
        }
        guard start_stepped_measure_result(Captured(admitted), state.workspace)
          is Some(cursor) else {
          return bounded_join_failure(Rows(RowLimit), progress, used)
        }
        state.measure = Some(cursor)
        // Field names contribute text/work, not an additional value node.
        if !push_stepped_measure(
            cursor,
            SteppedTextNext(state.names[state.column], 0),
          ) {
          return bounded_join_failure(Rows(RowLimit), progress, used)
        }
        state.pending = Some(admitted)
        state.phase = ChargeCell
        used += 1
      }
      ChargeCell => {
        guard state.output is Some(output) && state.measure is Some(cursor) else {
          return bounded_join_failure(InvalidExecution, progress, used)
        }
        if !spend_control(state.control, 1) {
          return bounded_join_failure(Rows(RowLimit), progress, used + 1)
        }
        match advance_stepped_measure_result(cursor, output.buffer.budget) {
          SteppedMeasureContinue => ()
          SteppedMeasureLimit =>
            return bounded_join_failure(
              Capture(CaptureLimit),
              progress,
              used + 1,
            )
          SteppedMeasureWorkspaceLimit =>
            return bounded_join_failure(Rows(RowLimit), progress, used + 1)
          SteppedMeasureComplete => {
            clear_stepped_measure(cursor)
            state.measure = None
            state.checked_row.push(state.pending.unwrap())
            state.pending = None
            state.column += 1
            state.phase = BuildCell
          }
        }
        used += 1
      }
      CommitRow => {
        guard state.output is Some(output) else {
          return bounded_join_failure(InvalidExecution, progress, used)
        }
        if !output.buffer.open || output.buffer.reading {
          return bounded_join_failure(InvalidExecution, progress, used)
        }
        output.buffer.rows.push(state.checked_row)
        release_slots(state.workspace, 2 + state.checked_row.length())
        state.checked_row = []
        state.pair = None
        state.emitted += 1
        state.phase = BeginPair
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return bounded_join_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return bounded_join_failure(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => bounded_join_failure(Completion(issue), progress, used)
        }
      }
      Terminal => return bounded_join_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
pub fn start_bounded_join(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  left : TrustedOutputInput,
  right : TrustedOutputInput,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedJoinExecution, BoundedJoinIssue] {
  if max_rows < 0 ||
    max_work < 0 ||
    max_frames < 0 ||
    max_entries < 0 ||
    max_name_bytes < 0 {
    return Err(InvalidExecution)
  }
  let left = match left.value {
    RelationInput(read) => CompletedBindingInput(read)
    SuppliedRelationInput(read) => SuppliedBindingInput(read)
    CarrierInput(_) => return Err(InvalidExecution)
  }
  let right = match right.value {
    RelationInput(read) => CompletedBindingInput(read)
    SuppliedRelationInput(read) => SuppliedBindingInput(read)
    CarrierInput(_) => return Err(InvalidExecution)
  }
  let owner = @lower.sequence_owner(generated.sequence)
  guard generated_sequence_step_index_at(generated, 0) is Some(step) &&
    generated_sequence_step_index_at(generated, 1) is None &&
    @lower.sequence_step(generated.sequence, step)
    is Some(@lower.JoinStep(kernel)) &&
    bounded_binding_input_matches(left, owner, step) &&
    bounded_binding_input_matches(right, owner, step, port=1) &&
    bounded_binding_input_available(left) &&
    bounded_binding_input_available(right) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(output_schema) else {
    return Err(InvalidExecution)
  }
  let left_count = bounded_binding_input_row_count(left)
  let right_count = bounded_binding_input_row_count(right)
  if left_count > max_rows || right_count > max_rows {
    return Err(Rows(RowLimit))
  }
  let profile = @lower.join_kernel_profile(kernel)
  let mut ceiling = max_rows
  if @lower.join_kernel_output_limit(kernel) is Some(limit) &&
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
  let width = @lower.inner_join_field_count(profile)
  if width > (max_entries - 2) / 3 ||
    width != @schema.field_count(output_schema) {
    return Err(Rows(RowLimit))
  }
  let workspace = row_workspace(max_entries)
  if !reserve_slots(workspace, 2) {
    return Err(Rows(RowLimit))
  }
  let control : ControlBudget = { remaining: max_work, max_frames, }
  let pairs : BoundedJoinPairs = {
    left,
    right,
    profile,
    control,
    workspace,
    engine,
    keys: [],
    orders: [],
    comparison: {
      left: 0,
      right: 0,
      terms: 0,
      term: 0,
      phase: -1,
      offset: 0,
      charge: { offset: 0, next: 0, remaining: 0, },
    },
    phase: ValidateSide,
    on_left: true,
    row: 0,
    key: 0,
    row_null: false,
    left_nulls: [],
    right_nulls: [],
    right_matches: [],
    sorter: None,
    index: [],
    position: 0,
    representative: None,
    duplicate: None,
    left_row: 0,
    low: 0,
    high: 0,
    matched: false,
  }
  guard binary_binding_input_scan(left, right, input_values, control, workspace)
    is Some(input_scan) else {
    return Err(InvalidExecution)
  }
  let budget = match value_budget(output_values) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  // A join without an authored projection has a checked scoped schema.
  // Keep that exact private layout for its qualified consumer; it is not
  // an externally supplied object and must not pass the object-only importer.
  let output : AdmittedOutput = {
    owner,
    target: @pipeline.Step(step),
    buffer: {
      schema: output_schema,
      max_rows: ceiling,
      budget,
      rows: [],
      open: true,
      reading: false,
    },
  }
  let rows : Ref[AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    prepare_trusted_output_port_with_inputs(
      generated_completion_preparation(generated),
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=[
        bounded_binding_trusted_input(left),
        bounded_binding_trusted_input(right),
      ],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedJoinState = {
    left,
    right,
    profile,
    output_schema,
    output_ceiling: ceiling,
    control,
    workspace,
    input_scan,
    pairs,
    admitted_limits: {
      max_nodes: output_values.max_nodes,
      max_depth: output_values.max_depth,
      max_text_bytes: output_values.max_text_bytes,
    },
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    names: [],
    columns: [],
    phase: ChargeInput,
    field: 0,
    source_column: 0,
    source_name: "",
    output_name: "",
    on_left: true,
    column: 0,
    emitted: 0,
    checked_row: [],
    pair: None,
    pending: None,
    measure: None,
    key_left_column: 0,
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_join_step,
    cleanup_bounded_join_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, state, })
}

///|
pub fn advance_bounded_join(
  value : BoundedJoinExecution,
  quantum : Int,
) -> Result[BoundedJoinPoll, BoundedJoinIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedJoinContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedJoinComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedJoinFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedJoinStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_join(
  value : BoundedJoinExecution,
) -> Result[Bool, BoundedJoinIssue] {
  let changed = match @bounded.cleanup(value.session) {
    Ok(changed) => changed
    Err(issue) => return Err(Execution(issue))
  }
  let state = bounded_join_state(value)
  if !@bounded.cleanup_pending(value.session) &&
    (state.input_scan.frames.length() != 0 || state.workspace.live != 0) {
    return Err(InvalidExecution)
  }
  Ok(changed)
}
