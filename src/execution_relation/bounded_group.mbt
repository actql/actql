///|
/// A bounded `group` over one completed or supplied Relation input. Input
/// cells are charged one measured value step at a time, the operation runs
/// as a `BoundedGroup`, and each emitted row is admitted into the managed
/// output one measured value at a time before the trusted output completes.
/// Aggregates with a filter, an expression argument, or a selected numeric
/// reduction are not in this profile.
priv struct BoundedGroupInputRows {
  input : BoundedGlobalCountInput
  owner : @lower.BoundPrepared
  names : Array[String]
}

///|
impl IndexedRows for BoundedGroupInputRows with fn row_count(self) {
  global_count_input_count(self.input)
}

///|
impl IndexedRows for BoundedGroupInputRows with fn column_count(self) {
  self.names.length()
}

///|
impl IndexedRows for BoundedGroupInputRows with fn row_width(self, _row) {
  self.names.length()
}

///|
impl IndexedRows for BoundedGroupInputRows with fn read_cell(self, row, column) {
  global_count_input_cell(self.input, row, column).unwrap_or(Null)
}

///|
impl RelationRows for BoundedGroupInputRows with fn checked_owner(self) {
  self.owner
}

///|
impl RelationRows for BoundedGroupInputRows with fn relation_id(_self) {
  ""
}

///|
impl RelationRows for BoundedGroupInputRows with fn field_names(self) {
  self.names
}

///|
/// Whether any aggregate needs expression evaluation: a filter or an
/// expression argument.
fn bounded_group_dynamic(group : @lower.PreparedGroup) -> Bool {
  for index in 0..<@lower.group_aggregate_count(group) {
    let aggregate = @lower.group_aggregate_at(group, index).unwrap()
    if @lower.group_aggregate_filter(aggregate) is Some(_) ||
      @lower.group_aggregate_argument(aggregate)
      is @lower.AggregateExpression(_) {
      return true
    }
  }
  false
}

///|
/// The logical budget for this kernel's expressions, derived from its one
/// fragment runtime context exactly as the synchronous sequence does.
fn bounded_group_logical(
  generated : GeneratedSequence,
  kernel : @lower.PreparedKernel,
) -> LogicalBudget? {
  let mut found : LogicalBudget? = None
  for context in generated.contexts {
    if physical_equal(context.kernel, kernel) {
      if found is Some(_) {
        return None
      }
      found = match fragment_runtime_for_kernel(context, kernel) {
        Ok(value) => Some(value)
        Err(_) => return None
      }
    }
  }
  found
}

///|
/// Group steps this bounded kernel executes. Selected numeric reductions
/// additionally need the task's numeric execution at start. Filtered and
/// expression aggregates need the step's fragment runtime context.
pub fn bounded_group_step_supported(
  generated : GeneratedSequence,
  kernel : @lower.PreparedKernel,
) -> Bool {
  if @lower.kernel_pivot(kernel) is Some(pivot) {
    return pivot_execution_supported_with_numeric(pivot)
  }
  guard @lower.kernel_group(kernel) is Some(group) &&
    group_execution_supported_with_numeric(group) else {
    return false
  }
  !bounded_group_dynamic(group) ||
  bounded_group_logical(generated, kernel) is Some(_)
}

///|
/// Whether the kernel runs without the task's numeric execution.
fn bounded_group_supported_without_numeric(
  kernel : @lower.PreparedKernel,
) -> Bool {
  match (@lower.kernel_group(kernel), @lower.kernel_pivot(kernel)) {
    (Some(group), _) => group_execution_supported(group)
    (_, Some(pivot)) => pivot_execution_supported(pivot)
    _ => false
  }
}

///|
priv enum BoundedGroupPhase {
  ChargeInput
  Evaluate
  BuildOutput
  CommitOutput
  FinishOutput
  Terminal
}

///|
priv struct BoundedGroupState {
  input : BoundedGlobalCountInput
  rows_view : BoundedGroupInputRows
  output_schema : @schema.Schema
  output_sources : Array[Int?]
  control : ControlBudget
  workspace : RowWorkspace
  scope : ExpressionRoots?
  input_values : ValueBudget
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut phase : BoundedGroupPhase
  mut evaluation : BoundedRowsEvaluation?
  pending : Array[(Array[Value], Int)]
  mut finished : Bool
  mut field : Int
  mut charge_row : Int
  mut charge_column : Int
  mut charge_open : Bool
  mut charge_measure : SteppedValueMeasure?
  mut output_row_open : Bool
  mut output_row : Array[@admitted.Value]
  mut output_measure : SteppedValueMeasure?
  mut output_pending : @admitted.Value?
}

///|
/// The row-producing operation this kernel drives: a `group` or a `pivot`
/// resumable state. `advance` returns true once every row was accepted.
priv struct BoundedRowsEvaluation {
  advance : () -> Result[Bool, RowIssue]
  close : () -> Unit
}

///|
pub(all) enum BoundedGroupIssue {
  InvalidExecution
  InputLimit
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedGroupExecution {
  session : @bounded.Session[
    BoundedGroupState,
    CompletedOutput,
    BoundedGroupIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum BoundedGroupPoll {
  BoundedGroupContinue(progress~ : Int64, work~ : Int64)
  BoundedGroupComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedGroupFailed(BoundedGroupIssue, progress~ : Int64, work~ : Int64)
  BoundedGroupStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn bounded_group_failure(
  issue : BoundedGroupIssue,
  progress : Int,
  used : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedGroupIssue] {
  @bounded.Failed(issue, progress, used)
}

///|
fn cleanup_bounded_group_state(state : BoundedGroupState) -> Bool {
  if state.evaluation is Some(evaluation) {
    (evaluation.close)()
    state.evaluation = None
  }
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.pending.clear()
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
  if state.scope is Some(scope) {
    cleanup_expression_roots(scope)
  }
  release_slots(state.workspace, state.workspace.live)
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
/// The admitted value published for one output cell, following the count
/// kernel: an exact source contract reuses the input's admitted value,
/// otherwise the runtime value is admitted and rechecked by the output field.
fn bounded_group_admitted_cell(
  state : BoundedGroupState,
  field : @schema.Field,
  value : Value,
  source : Int?,
  representative : Int,
) -> @admitted.Value? {
  let admitted_source = match source {
    None => None
    Some(index) =>
      @schema.field_at(global_count_input_schema(state.input), index).bind(source_field => {
        if physical_equal(source_field.contract, field.contract) {
          global_count_input_admitted_cell(state.input, representative, index)
        } else {
          None
        }
      })
  }
  let admitted = match admitted_source {
    Some(value) => Some(value)
    None =>
      match value {
        Captured(captured) => Some(captured)
        Null => Some(@admitted.null_value())
        Boolean(boolean) => Some(@admitted.boolean_value(boolean))
        Number(number) => @admitted.number_value(number)
        Text(text) =>
          @admitted.text_value(text, state.admitted_limits.max_text_bytes)
      }
  }
  guard admitted is Some(admitted) &&
    (
      admitted_source is Some(_) ||
      @admitted.recheck_runtime_value(
        admitted,
        field.contract,
        state.admitted_limits,
      )
      is Some(_)
    ) else {
    return None
  }
  Some(admitted)
}

///|
fn bounded_group_step(
  state : BoundedGroupState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedGroupIssue] {
  let mut used = 0
  let mut progress = 0
  let width = state.rows_view.names.length()
  let output_width = @schema.field_count(state.output_schema)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !global_count_input_available(state.input) {
      return bounded_group_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      ChargeInput => {
        if state.charge_row == global_count_input_count(state.input) {
          state.phase = Evaluate
          continue
        }
        if !state.charge_open {
          if !spend_control(state.control, 1) ||
            !charge_node(state.input_values, 1) {
            return bounded_group_failure(InputLimit, progress, used)
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
              return bounded_group_failure(InvalidExecution, progress, used)
            }
            if !charge_text(
                state.input_values,
                state.rows_view.names[state.charge_column],
              ) {
              return bounded_group_failure(InputLimit, progress, used)
            }
            guard start_stepped_measure_result(value, state.workspace)
              is Some(cursor) else {
              return bounded_group_failure(Rows(RowLimit), progress, used)
            }
            state.charge_measure = Some(cursor)
          }
          let cursor = state.charge_measure.unwrap()
          match advance_stepped_measure_result(cursor, state.input_values) {
            SteppedMeasureLimit =>
              return bounded_group_failure(InputLimit, progress, used)
            SteppedMeasureWorkspaceLimit =>
              return bounded_group_failure(Rows(RowLimit), progress, used)
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
      Evaluate => {
        if !state.pending.is_empty() {
          state.field = 0
          state.phase = BuildOutput
          continue
        }
        if state.finished {
          state.phase = FinishOutput
          continue
        }
        guard state.evaluation is Some(evaluation) else {
          return bounded_group_failure(InvalidExecution, progress, used)
        }
        match (evaluation.advance)() {
          Err(issue) => {
            state.evaluation = None
            return bounded_group_failure(Rows(issue), progress, used + 1)
          }
          Ok(false) => ()
          Ok(true) => {
            state.evaluation = None
            state.finished = true
          }
        }
        used += 1
      }
      BuildOutput => {
        if state.field == output_width {
          state.phase = CommitOutput
          continue
        }
        guard state.output is Some(output) else {
          return bounded_group_failure(InvalidExecution, progress, used)
        }
        if !state.output_row_open {
          if !output.buffer.open ||
            output.buffer.reading ||
            output.buffer.rows.length() >= output.buffer.max_rows ||
            !charge_node(output.buffer.budget, 1) {
            return bounded_group_failure(Capture(CaptureLimit), progress, used)
          }
          state.output_row_open = true
          continue
        }
        guard @schema.field_at(state.output_schema, state.field) is Some(field) else {
          return bounded_group_failure(InvalidExecution, progress, used)
        }
        if state.output_measure is None {
          if !reserve_slots(state.workspace, 1) ||
            !spend_control(state.control, 1) {
            return bounded_group_failure(Rows(RowLimit), progress, used)
          }
          if !charge_text(
              output.buffer.budget,
              @schema.reference_name(field.name),
            ) {
            return bounded_group_failure(Capture(CaptureLimit), progress, used)
          }
          let (row, representative) = state.pending[0]
          guard bounded_group_admitted_cell(
              state,
              field,
              row[state.field],
              state.output_sources[state.field],
              representative,
            )
            is Some(admitted) else {
            return bounded_group_failure(Rows(InvalidRows), progress, used)
          }
          if admitted
            is (@admitted.Null | @admitted.Boolean(_) | @admitted.Number(_)) {
            if !measure_result(Captured(admitted), output.buffer.budget) {
              return bounded_group_failure(
                Capture(CaptureLimit),
                progress,
                used,
              )
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
            return bounded_group_failure(Rows(RowLimit), progress, used)
          }
          state.output_pending = Some(admitted)
          state.output_measure = Some(cursor)
        }
        let cursor = state.output_measure.unwrap()
        match advance_stepped_measure_result(cursor, output.buffer.budget) {
          SteppedMeasureLimit =>
            return bounded_group_failure(Capture(CaptureLimit), progress, used)
          SteppedMeasureWorkspaceLimit =>
            return bounded_group_failure(Rows(RowLimit), progress, used)
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
          return bounded_group_failure(InvalidExecution, progress, used)
        }
        if !output.buffer.open ||
          output.buffer.reading ||
          output.buffer.rows.length() >= output.buffer.max_rows ||
          state.output_row.length() != output_width ||
          state.output_measure is Some(_) {
          return bounded_group_failure(InvalidExecution, progress, used + 1)
        }
        output.buffer.rows.push(state.output_row)
        release_slots(state.workspace, state.output_row.length())
        state.output_row = []
        state.output_row_open = false
        state.field = 0
        ignore(state.pending.remove(0))
        state.phase = Evaluate
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return bounded_group_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return bounded_group_failure(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => bounded_group_failure(Completion(issue), progress, used)
        }
      }
      Terminal => return bounded_group_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn start_bounded_group_with_input(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : BoundedGlobalCountInput,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  identity_limits : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
  numeric : NumericAggregateExecution?,
) -> Result[BoundedGroupExecution, BoundedGroupIssue] {
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
    bounded_group_step_supported(generated, kernel) &&
    (numeric is Some(_) || bounded_group_supported_without_numeric(kernel)) &&
    global_count_input_matches(input, owner, step) &&
    global_count_input_available(input) else {
    return Err(InvalidExecution)
  }
  let input_schema = global_count_input_schema(input)
  let names = Array::makei(@schema.field_count(input_schema), i => {
    @schema.reference_name(@schema.field_at(input_schema, i).unwrap().name)
  })
  let (output_schema, sourced) = match
    (@lower.kernel_group(kernel), @lower.kernel_pivot(kernel)) {
    (Some(group), _) => {
      let aggregate_names : Map[String, Bool] = Map([])
      for index in 0..<@lower.group_aggregate_count(group) {
        let aggregate_name = @lower.group_aggregate_name(
          @lower.group_aggregate_at(group, index).unwrap(),
        )
        aggregate_names[aggregate_name] = true
      }
      let key_names : Map[String, Bool] = Map([])
      for index in 0..<@lower.group_key_count(group) {
        let name = @schema.reference_name(
          @lower.group_key_at(group, index).unwrap(),
        )
        if !aggregate_names.contains(name) {
          key_names[name] = true
        }
      }
      (@lower.group_output_schema(group), key_names)
    }
    (_, Some(pivot)) => {
      // Output columns named by an index field take its representative cell.
      let index_names : Map[String, Bool] = Map([])
      for index in 0..<@lower.pivot_index_count(pivot) {
        index_names[@schema.reference_name(
          @lower.pivot_index_at(pivot, index).unwrap(),
        )] = true
      }
      (@lower.pivot_output_schema(pivot), index_names)
    }
    _ => return Err(InvalidExecution)
  }
  let output_sources : Array[Int?] = []
  for index in 0..<@schema.field_count(output_schema) {
    let name = @schema.reference_name(
      @schema.field_at(output_schema, index).unwrap().name,
    )
    output_sources.push(
      if sourced.contains(name) {
        names.search(name)
      } else {
        None
      },
    )
  }
  let input_budget = match value_budget(input_values) {
    Ok(value) => value
    Err(_) => return Err(InputLimit)
  }
  let evaluation_output = match value_budget(output_values) {
    Ok(value) => value
    Err(_) => return Err(InvalidExecution)
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
  let control : ControlBudget = { remaining: max_work, max_frames, }
  let workspace = row_workspace(max_entries)
  let scope = bounded_group_logical(generated, kernel).map(budget => {
    ({ budget, slots: [], free: [], limit: max_entries, } : ExpressionRoots)
  })
  let rows_view : BoundedGroupInputRows = { input, owner, names, }
  let pending : Array[(Array[Value], Int)] = []
  let accept = (row : Array[Value], representative : Int) => {
    pending.push((row, representative))
    Ok(())
  }
  let evaluation : BoundedRowsEvaluation = match @lower.kernel_group(kernel) {
    Some(group) => {
      let state = start_bounded_group(
        group,
        rows_view,
        max_rows,
        control,
        evaluation_output,
        workspace,
        scope,
        (row, representative, _names, _sources) => accept(row, representative),
        [],
        identity_limits,
        numeric,
        step=@lower.kernel_step(kernel),
      )
      {
        advance: () => advance_bounded_group(state).map(done => done is Some(_)),
        close: () => close_bounded_group(state),
      }
    }
    None => {
      let state = match
        start_pivot_evaluation(
          kernel,
          rows_view,
          max_rows,
          control,
          evaluation_output,
          workspace,
          numeric,
          @lower.kernel_step(kernel),
          accept,
        ) {
        Ok(value) => value
        Err(_) => {
          cancel_admitted_output(output) |> ignore
          return Err(InvalidExecution)
        }
      }
      {
        advance: () => {
          advance_pivot_evaluation(state).map(done => done is Some(_))
        },
        close: () => close_pivot_evaluation(state),
      }
    }
  }
  let state : BoundedGroupState = {
    input,
    rows_view,
    output_schema,
    output_sources,
    control,
    workspace,
    scope,
    input_values: input_budget,
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
    phase: ChargeInput,
    evaluation: Some(evaluation),
    pending,
    finished: false,
    field: 0,
    charge_row: 0,
    charge_column: 0,
    charge_open: false,
    charge_measure: None,
    output_row_open: false,
    output_row: [],
    output_measure: None,
    output_pending: None,
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_group_step,
    cleanup_bounded_group_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn start_bounded_group_execution(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : ProducerRead,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  identity_limits : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
  numeric? : NumericAggregateExecution? = None,
) -> Result[BoundedGroupExecution, BoundedGroupIssue] {
  start_bounded_group_with_input(
    engine,
    generated,
    CompletedGlobalCountInput(input),
    max_rows,
    input_values,
    output_values,
    identity_limits,
    max_work,
    max_frames,
    max_entries,
    max_name_bytes,
    numeric,
  )
}

///|
pub fn start_bounded_group_execution_supplied(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : SuppliedRelationRead,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  identity_limits : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
  numeric? : NumericAggregateExecution? = None,
) -> Result[BoundedGroupExecution, BoundedGroupIssue] {
  start_bounded_group_with_input(
    engine,
    generated,
    SuppliedGlobalCountInput(input),
    max_rows,
    input_values,
    output_values,
    identity_limits,
    max_work,
    max_frames,
    max_entries,
    max_name_bytes,
    numeric,
  )
}

///|
pub fn advance_bounded_group_execution(
  value : BoundedGroupExecution,
  quantum : Int,
) -> Result[BoundedGroupPoll, BoundedGroupIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedGroupContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedGroupComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedGroupFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedGroupStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_group_execution(
  value : BoundedGroupExecution,
) -> Result[Bool, BoundedGroupIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}
