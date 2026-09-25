///|
priv enum BoundedGlobalCountInput {
  CompletedGlobalCountInput(ProducerRead)
  SuppliedGlobalCountInput(SuppliedRelationRead)
}

///|
fn global_count_input_available(input : BoundedGlobalCountInput) -> Bool {
  match input {
    CompletedGlobalCountInput(read) =>
      producer_read_available(read) && producer_read_has_cell_access(read)
    SuppliedGlobalCountInput(read) => supplied_relation_read_available(read)
  }
}

///|
fn global_count_input_matches(
  input : BoundedGlobalCountInput,
  owner : @lower.BoundPrepared,
  step : Int,
) -> Bool {
  match input {
    CompletedGlobalCountInput(read) =>
      producer_read_matches_operation_input(read, owner, step, 0)
    SuppliedGlobalCountInput(read) =>
      supplied_relation_read_matches_operation_input(read, owner, step, 0)
  }
}

///|
fn global_count_input_schema(input : BoundedGlobalCountInput) -> @schema.Schema {
  match input {
    CompletedGlobalCountInput(read) => producer_read_schema(read)
    SuppliedGlobalCountInput(read) => supplied_relation_read_schema(read)
  }
}

///|
fn global_count_input_count(input : BoundedGlobalCountInput) -> Int {
  match input {
    CompletedGlobalCountInput(read) => producer_read_row_count(read)
    SuppliedGlobalCountInput(read) => supplied_relation_read_row_count(read)
  }
}

///|
fn global_count_input_cell(
  input : BoundedGlobalCountInput,
  row : Int,
  column : Int,
) -> Value? {
  match input {
    CompletedGlobalCountInput(read) => producer_read_cell(read, row, column)
    SuppliedGlobalCountInput(read) =>
      supplied_relation_read_cell(read, row, column).map(capture)
  }
}

///|
fn global_count_trusted_input(
  input : BoundedGlobalCountInput,
) -> TrustedOutputInput {
  match input {
    CompletedGlobalCountInput(read) => trusted_output_relation_input(read)
    SuppliedGlobalCountInput(read) =>
      trusted_output_supplied_relation_input(read)
  }
}

///|
priv enum BoundedGlobalCountPhase {
  ResolveInput
  ResolveKeys
  ResolveAggregates
  ResolveOutput
  ChargeInput
  StartSort
  SortRows
  BeginGroup
  ResetCounts
  CheckGroupBoundary
  CountRows
  BuildOutput
  CommitOutput
  FinishOutput
  Terminal
}

///|
priv struct BoundedGlobalCountState {
  input : BoundedGlobalCountInput
  group : @lower.PreparedCountGroup
  output_schema : @schema.Schema
  control : ControlBudget
  workspace : RowWorkspace
  input_values : ValueBudget
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut phase : BoundedGlobalCountPhase
  ordinals : Map[String, Int]
  mut input_names : Array[String]
  key_names : Map[String, Int]
  mut key_orders : Array[ColumnOrder]
  comparison : BoundedRowComparison
  engine : @bounded.Control
  mut sort_execution : BoundedIndexSort?
  mut sorted_indices : Array[Int]?
  aggregate_names : Map[String, Int]
  mut aggregate_columns : Array[Int?]
  mut counts : Array[Int]
  mut output_columns : Array[(Bool, Int)]
  mut field : Int
  mut charge_row : Int
  mut charge_column : Int
  mut charge_open : Bool
  mut charge_measure : SteppedValueMeasure?
  mut row : Int
  mut group_start : Int
  mut representative : Int
  mut boundary_checked : Bool
  mut aggregate : Int
  mut row_open : Bool
  mut output_row_open : Bool
  mut output_row : Array[@admitted.Value]
  mut output_measure : SteppedValueMeasure?
  mut output_pending : @admitted.Value?
}

///|
pub(all) enum BoundedGlobalCountIssue {
  InvalidExecution
  InputLimit
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedGlobalCountExecution {
  state : BoundedGlobalCountState
  session : @bounded.Session[
    BoundedGlobalCountState,
    CompletedOutput,
    BoundedGlobalCountIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
// Read-only white-box probe for cancellation inside output measurement.
#warnings("-unused_value")
fn bounded_global_count_measuring_output(
  execution : BoundedGlobalCountExecution,
) -> Bool {
  execution.state.phase is BuildOutput &&
  execution.state.output_measure is Some(_)
}

///|
pub enum BoundedGlobalCountPoll {
  BoundedGlobalCountContinue(progress~ : Int64, work~ : Int64)
  BoundedGlobalCountComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedGlobalCountFailed(
    BoundedGlobalCountIssue,
    progress~ : Int64,
    work~ : Int64
  )
  BoundedGlobalCountStopped(
    @bounded.StopReason,
    progress~ : Int64,
    work~ : Int64
  )
}

///|
fn global_count_failure(
  issue : BoundedGlobalCountIssue,
  progress : Int,
  used : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedGlobalCountIssue] {
  @bounded.Failed(issue, progress, used)
}

///|
fn cleanup_bounded_global_count_state(state : BoundedGlobalCountState) -> Bool {
  if state.sort_execution is Some(execution) {
    if !bounded_index_sort_stopped(execution) {
      @bounded.request_cancel(state.engine) |> ignore
      match advance_bounded_index_sort(execution, 1) {
        Ok(BoundedIndexSortStopped(_)) => ()
        Ok(BoundedIndexSortContinue)
        | Ok(BoundedIndexSortComplete(_))
        | Ok(BoundedIndexSortFailed(_))
        | Err(_) => return false
      }
    }
    if !cleanup_bounded_index_sort(execution) {
      return false
    }
    state.sort_execution = None
  }
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.ordinals.clear()
  state.input_names = []
  state.key_names.clear()
  state.key_orders = []
  state.sorted_indices = None
  state.aggregate_names.clear()
  state.aggregate_columns = []
  state.counts = []
  state.output_columns = []
  state.output_row = []
  if state.output_measure is Some(cursor) {
    clear_stepped_measure(cursor)
    state.output_measure = None
  }
  state.output_pending = None
  if state.charge_measure is Some(cursor) {
    clear_stepped_measure(cursor)
    state.charge_measure = None
  }
  release_slots(state.workspace, state.workspace.live)
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
fn bounded_global_count_step(
  state : BoundedGlobalCountState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedGlobalCountIssue] {
  let mut used = 0
  let mut progress = 0
  let width = @schema.field_count(global_count_input_schema(state.input))
  let aggregate_count = @lower.count_group_aggregate_count(state.group)
  let key_count = @lower.count_group_key_count(state.group)
  let output_width = @schema.field_count(state.output_schema)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !global_count_input_available(state.input) {
      return global_count_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      ResolveInput => {
        if state.field == width {
          state.field = 0
          state.phase = ResolveKeys
          continue
        }
        guard @schema.field_at(
            global_count_input_schema(state.input),
            state.field,
          )
          is Some(field) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.name)
        if state.ordinals.contains(name) {
          return global_count_failure(Rows(InvalidRows), progress, used)
        }
        if !reserve_slots(state.workspace, 2) ||
          !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) {
          return global_count_failure(Rows(RowLimit), progress, used)
        }
        state.ordinals[name] = state.field
        state.input_names.push(name)
        state.field += 1
        used += 1
      }
      ResolveKeys => {
        if state.field == key_count {
          state.field = 0
          state.phase = ResolveAggregates
          continue
        }
        guard @lower.count_group_key_at(state.group, state.field) is Some(key) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(key)
        guard state.ordinals.get(name) is Some(column) else {
          return global_count_failure(Rows(InvalidRows), progress, used)
        }
        if !reserve_slots(state.workspace, 1) ||
          !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) {
          return global_count_failure(Rows(RowLimit), progress, used)
        }
        state.key_names[name] = column
        state.key_orders.push({ column, descending: false, nulls_first: true, })
        state.field += 1
        used += 1
      }
      ResolveAggregates => {
        if state.field == aggregate_count {
          state.field = 0
          state.phase = ResolveOutput
          continue
        }
        guard @lower.count_group_aggregate_at(state.group, state.field)
          is Some(aggregate) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        if state.aggregate_names.contains(aggregate.name) {
          return global_count_failure(Rows(InvalidRows), progress, used)
        }
        let column = match aggregate.field {
          None => None
          Some(field) => {
            let name = @schema.reference_name(field)
            if !spend_control_text(state.control, name) {
              return global_count_failure(Rows(RowLimit), progress, used)
            }
            match state.ordinals.get(name) {
              Some(index) => Some(index)
              None =>
                return global_count_failure(Rows(InvalidRows), progress, used)
            }
          }
        }
        if !reserve_slots(state.workspace, 3) ||
          !spend_control(state.control, 1) ||
          !spend_control_text(state.control, aggregate.name) {
          return global_count_failure(Rows(RowLimit), progress, used)
        }
        state.aggregate_names[aggregate.name] = state.field
        state.aggregate_columns.push(column)
        state.counts.push(0)
        state.field += 1
        used += 1
      }
      ResolveOutput => {
        if state.field == output_width {
          state.field = 0
          state.phase = ChargeInput
          continue
        }
        guard @schema.field_at(state.output_schema, state.field) is Some(field) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.name)
        let column = match state.aggregate_names.get(name) {
          Some(index) => (true, index)
          None =>
            match state.key_names.get(name) {
              Some(index) => (false, index)
              None =>
                return global_count_failure(Rows(InvalidRows), progress, used)
            }
        }
        if !reserve_slots(state.workspace, 1) ||
          !spend_control_text(state.control, name) {
          return global_count_failure(Rows(RowLimit), progress, used)
        }
        state.output_columns.push(column)
        state.field += 1
        used += 1
      }
      ChargeInput => {
        if state.charge_row == global_count_input_count(state.input) {
          state.phase = if key_count == 0 { CountRows } else { StartSort }
          continue
        }
        if !state.charge_open {
          if !spend_control(state.control, 1) ||
            !charge_node(state.input_values, 1) {
            return global_count_failure(InputLimit, progress, used)
          }
          state.charge_open = true
          used += 1
        } else if state.charge_column < width {
          if state.charge_measure is None {
            guard global_count_input_cell(
                state.input,
                state.charge_row,
                state.charge_column,
              )
              is Some(value) else {
              return global_count_failure(InvalidExecution, progress, used)
            }
            if !charge_text(
                state.input_values,
                state.input_names[state.charge_column],
              ) {
              return global_count_failure(InputLimit, progress, used)
            }
            guard start_stepped_measure_result(value, state.workspace)
              is Some(cursor) else {
              return global_count_failure(Rows(RowLimit), progress, used)
            }
            state.charge_measure = Some(cursor)
          }
          let cursor = state.charge_measure.unwrap()
          match advance_stepped_measure_result(cursor, state.input_values) {
            SteppedMeasureLimit =>
              return global_count_failure(InputLimit, progress, used)
            SteppedMeasureWorkspaceLimit =>
              return global_count_failure(Rows(RowLimit), progress, used)
            SteppedMeasureContinue => ()
            SteppedMeasureComplete => {
              clear_stepped_measure(cursor)
              state.charge_measure = None
              state.charge_column += 1
            }
          }
          used += 1
        } else {
          state.charge_row += 1
          state.charge_column = 0
          state.charge_open = false
        }
      }
      StartSort => {
        let count = global_count_input_count(state.input)
        if count > (state.workspace.limit - state.workspace.live) / 2 ||
          !reserve_slots(state.workspace, count * 2) {
          return global_count_failure(Rows(RowLimit), progress, used)
        }
        state.sort_execution = start_bounded_index_sort_stepped(
          state.engine,
          count,
          (left, right) => {
            bounded_row_comparison_step_with(
              state.comparison,
              state.key_orders,
              state.control,
              (row, column) => global_count_input_cell(state.input, row, column),
              left,
              right,
              key_count,
            ).map_err(ordering_row_issue)
          },
        )
        guard state.sort_execution is Some(_) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        state.phase = SortRows
        used += 1
      }
      SortRows => {
        let count = global_count_input_count(state.input)
        guard state.sort_execution is Some(execution) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        if state.comparison.phase == -1 && !spend_control(state.control, 1) {
          return global_count_failure(Rows(RowLimit), progress, used)
        }
        match advance_bounded_index_sort(execution, 1) {
          Err(issue) | Ok(BoundedIndexSortFailed(issue)) =>
            return global_count_failure(Rows(issue), progress, used + 1)
          Ok(BoundedIndexSortStopped(reason)) =>
            return @bounded.Stopped(reason, progress, used + 1)
          Ok(BoundedIndexSortContinue) => used += 1
          Ok(BoundedIndexSortComplete(indices)) => {
            cleanup_bounded_index_sort(execution) |> ignore
            state.sort_execution = None
            release_slots(state.workspace, count)
            state.sorted_indices = Some(indices)
            state.row = 0
            state.phase = BeginGroup
            used += 1
          }
        }
      }
      BeginGroup => {
        if state.row == global_count_input_count(state.input) {
          state.phase = FinishOutput
          continue
        }
        guard state.sorted_indices is Some(indices) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        state.group_start = state.row
        state.representative = indices[state.row]
        state.aggregate = 0
        state.phase = ResetCounts
      }
      ResetCounts => {
        if state.aggregate == aggregate_count {
          state.aggregate = 0
          state.row_open = false
          state.boundary_checked = false
          state.phase = CountRows
          continue
        }
        state.counts[state.aggregate] = 0
        state.aggregate += 1
        used += 1
      }
      CheckGroupBoundary => {
        guard state.sorted_indices is Some(indices) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        if state.comparison.phase == -1 && !spend_control(state.control, 1) {
          return global_count_failure(Rows(RowLimit), progress, used)
        }
        match
          bounded_row_comparison_step_with(
            state.comparison,
            state.key_orders,
            state.control,
            (row, column) => global_count_input_cell(state.input, row, column),
            state.representative,
            indices[state.row],
            key_count,
          ) {
          Ok(None) => used += 1
          Ok(Some(comparison)) => {
            state.boundary_checked = true
            state.phase = if comparison == 0 { CountRows } else { BuildOutput }
            used += 1
          }
          Err(issue) =>
            return global_count_failure(
              Rows(ordering_row_issue(issue)),
              progress,
              used + 1,
            )
        }
      }
      CountRows => {
        if state.row == global_count_input_count(state.input) {
          state.field = 0
          state.phase = BuildOutput
          continue
        }
        if key_count > 0 &&
          state.row > state.group_start &&
          !state.boundary_checked {
          state.phase = CheckGroupBoundary
          continue
        }
        if !state.row_open {
          if !spend_control(state.control, 1) {
            return global_count_failure(Rows(RowLimit), progress, used)
          }
          state.row_open = true
          used += 1
        } else if state.aggregate < aggregate_count {
          if !spend_control(state.control, 1) {
            return global_count_failure(Rows(RowLimit), progress, used)
          }
          let counted = match state.aggregate_columns[state.aggregate] {
            None => true
            Some(column) => {
              let source_row = if key_count == 0 {
                state.row
              } else {
                guard state.sorted_indices is Some(indices) else {
                  return global_count_failure(InvalidExecution, progress, used)
                }
                indices[state.row]
              }
              guard global_count_input_cell(state.input, source_row, column)
                is Some(value) else {
                return global_count_failure(InvalidExecution, progress, used)
              }
              !(value is Null)
            }
          }
          if counted {
            state.counts[state.aggregate] += 1
          }
          state.aggregate += 1
          used += 1
        } else {
          state.row += 1
          state.aggregate = 0
          state.row_open = false
          state.boundary_checked = false
        }
      }
      BuildOutput => {
        if state.field == output_width {
          state.phase = CommitOutput
          continue
        }
        guard state.output is Some(output) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        if !state.output_row_open {
          if !output.buffer.open ||
            output.buffer.reading ||
            output.buffer.rows.length() >= output.buffer.max_rows ||
            !charge_node(output.buffer.budget, 1) {
            return global_count_failure(Capture(CaptureLimit), progress, used)
          }
          state.output_row_open = true
          continue
        }
        guard @schema.field_at(state.output_schema, state.field) is Some(field) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        if state.output_measure is None {
          if !reserve_slots(state.workspace, 1) ||
            !spend_control(state.control, 1) {
            return global_count_failure(Rows(RowLimit), progress, used)
          }
          if !charge_text(
              output.buffer.budget,
              @schema.reference_name(field.name),
            ) {
            return global_count_failure(Capture(CaptureLimit), progress, used)
          }
          let (aggregate, index) = state.output_columns[state.field]
          let value = if aggregate {
            Number(state.counts[index].to_double())
          } else {
            guard state.representative >= 0 &&
              global_count_input_cell(state.input, state.representative, index)
              is Some(value) else {
              return global_count_failure(InvalidExecution, progress, used)
            }
            value
          }
          let admitted = match value {
            Captured(captured) => Some(captured)
            Null => Some(@admitted.null_value())
            Boolean(boolean) => Some(@admitted.boolean_value(boolean))
            Number(number) => @admitted.number_value(number)
            Text(text) =>
              @admitted.text_value(text, state.admitted_limits.max_text_bytes)
          }
          guard admitted is Some(admitted) &&
            @admitted.recheck_runtime_value(
              admitted,
              field.contract,
              state.admitted_limits,
            )
            is Some(_) else {
            return global_count_failure(Rows(InvalidRows), progress, used)
          }
          if admitted
            is (@admitted.Null | @admitted.Boolean(_) | @admitted.Number(_)) {
            if !measure_result(Captured(admitted), output.buffer.budget) {
              return global_count_failure(Capture(CaptureLimit), progress, used)
            }
            state.output_row.push(admitted)
            state.field += 1
            used += 1
            continue
          }
          guard start_stepped_measure_result(
              Captured(admitted),
              state.workspace,
            )
            is Some(cursor) else {
            return global_count_failure(Rows(RowLimit), progress, used)
          }
          state.output_pending = Some(admitted)
          state.output_measure = Some(cursor)
        }
        let cursor = state.output_measure.unwrap()
        match advance_stepped_measure_result(cursor, output.buffer.budget) {
          SteppedMeasureLimit =>
            return global_count_failure(Capture(CaptureLimit), progress, used)
          SteppedMeasureWorkspaceLimit =>
            return global_count_failure(Rows(RowLimit), progress, used)
          SteppedMeasureContinue => ()
          SteppedMeasureComplete => {
            clear_stepped_measure(cursor)
            state.output_measure = None
            state.output_row.push(state.output_pending.unwrap())
            state.output_pending = None
            state.field += 1
          }
        }
        used += 1
      }
      CommitOutput => {
        guard state.output is Some(output) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        if !output.buffer.open ||
          output.buffer.reading ||
          output.buffer.rows.length() >= output.buffer.max_rows ||
          state.output_row.length() != output_width ||
          state.output_measure is Some(_) {
          return global_count_failure(InvalidExecution, progress, used + 1)
        }
        // The row node, field names, and every value were charged above.
        // No unchecked or partially measured cell enters the buffer.
        output.buffer.rows.push(state.output_row)
        release_slots(state.workspace, state.output_row.length())
        state.output_row = []
        state.output_row_open = false
        state.field = 0
        state.phase = if key_count == 0 { FinishOutput } else { BeginGroup }
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return global_count_failure(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => global_count_failure(Completion(issue), progress, used)
        }
      }
      Terminal => return global_count_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn start_bounded_global_count_with_input(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : BoundedGlobalCountInput,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedGlobalCountExecution, BoundedGlobalCountIssue] {
  if max_rows < 1 ||
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
    is Some(@lower.RowStep(kernel)) &&
    @lower.kernel_count_group(kernel) is Some(group) &&
    global_count_input_matches(input, owner, step) &&
    global_count_input_available(input) else {
    return Err(InvalidExecution)
  }
  let output_schema = @lower.count_group_output_schema(group)
  if @schema.field_count(output_schema) !=
    @lower.count_group_key_count(group) +
    @lower.count_group_aggregate_count(group) {
    return Err(InvalidExecution)
  }
  let input_values = match value_budget(input_values) {
    Ok(value) => value
    Err(_) => return Err(InputLimit)
  }
  let output = match
    prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      output_values,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
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
      inputs=[global_count_trusted_input(input)],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedGlobalCountState = {
    input,
    group,
    output_schema,
    control: { remaining: max_work, max_frames, },
    workspace: row_workspace(max_entries),
    input_values,
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
    phase: ResolveInput,
    ordinals: Map([]),
    input_names: [],
    key_names: Map([]),
    key_orders: [],
    comparison: {
      left: -1,
      right: -1,
      terms: 0,
      term: 0,
      phase: -1,
      offset: 0,
    },
    engine,
    sort_execution: None,
    sorted_indices: None,
    aggregate_names: Map([]),
    aggregate_columns: [],
    counts: [],
    output_columns: [],
    field: 0,
    charge_row: 0,
    charge_column: 0,
    charge_open: false,
    charge_measure: None,
    row: 0,
    group_start: -1,
    representative: -1,
    boundary_checked: false,
    aggregate: 0,
    row_open: false,
    output_row_open: false,
    output_row: [],
    output_measure: None,
    output_pending: None,
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_global_count_step,
    cleanup_bounded_global_count_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ state, session, token: Some(token), accepted, })
}

///|
pub fn start_bounded_global_count(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : ProducerRead,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedGlobalCountExecution, BoundedGlobalCountIssue] {
  start_bounded_global_count_with_input(
    engine,
    generated,
    CompletedGlobalCountInput(input),
    max_rows,
    input_values,
    output_values,
    max_work,
    max_frames,
    max_entries,
    max_name_bytes,
  )
}

///|
pub fn start_bounded_global_count_supplied(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : SuppliedRelationRead,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedGlobalCountExecution, BoundedGlobalCountIssue] {
  start_bounded_global_count_with_input(
    engine,
    generated,
    SuppliedGlobalCountInput(input),
    max_rows,
    input_values,
    output_values,
    max_work,
    max_frames,
    max_entries,
    max_name_bytes,
  )
}

///|
pub fn advance_bounded_global_count(
  value : BoundedGlobalCountExecution,
  quantum : Int,
) -> Result[BoundedGlobalCountPoll, BoundedGlobalCountIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedGlobalCountContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedGlobalCountComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedGlobalCountFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedGlobalCountStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_global_count(
  value : BoundedGlobalCountExecution,
) -> Result[Bool, BoundedGlobalCountIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}
