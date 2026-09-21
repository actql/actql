///|
priv enum BoundedBindingRowsPhase {
  RetainInputs
  BeginRow
  SnapshotRow
  EvaluateBindings
  BuildOutputRow
  CheckOutputRow
  CommitOutputRow
  FinishOutput
  Terminal
}

///|
priv struct ProducerReadRow {
  input : ProducerRead
  row : Int
  width : Int
}

///|
impl RowValues for ProducerReadRow with fn value_count(self) {
  self.width
}

///|
impl RowValues for ProducerReadRow with fn value_at(self, column) {
  producer_read_cell(self.input, self.row, column).unwrap()
}

///|
priv struct BoundedBindingRowsState {
  input : ProducerRead
  available : () -> Bool
  bindings : Array[(String, @lower.Expression)]
  input_names : Array[String]
  output_names : Array[String]
  input_ordinals : Map[String, Int]
  binding_ordinals : Map[String, Int]
  ordered : Bool
  output_schema : @schema.Schema
  admitted_limits : @admitted.Limits
  output_values : ValueBudget
  logical : LogicalBudget
  scope : ExpressionRoots
  control : ControlBudget
  workspace : RowWorkspace
  mut input_roots : Array[ExpressionRootLease]
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut phase : BoundedBindingRowsPhase
  mut input_row : Int
  mut row : Int
  mut column : Int
  mut snapshot : Map[String, Value]
  mut binding_execution : OrderedBindingsExecution?
  mut values : Array[Value]
  mut slot_roots : Array[ExpressionRootLease]
  mut output_row : Array[Value]
  mut checked_row : Array[@admitted.CheckedValue]
}

///|
pub(all) enum BoundedBindingRowsIssue {
  InvalidExecution
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedBindingRowsExecution {
  session : @bounded.Session[
    BoundedBindingRowsState,
    CompletedOutput,
    BoundedBindingRowsIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum BoundedBindingRowsPoll {
  BoundedBindingRowsContinue(progress~ : Int64, work~ : Int64)
  BoundedBindingRowsComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedBindingRowsFailed(
    BoundedBindingRowsIssue,
    progress~ : Int64,
    work~ : Int64
  )
  BoundedBindingRowsStopped(
    @bounded.StopReason,
    progress~ : Int64,
    work~ : Int64
  )
}

///|
fn checked_ordered_output_value(
  value : Value,
  contract : @contract.Contract,
  limits : @admitted.Limits,
) -> @admitted.CheckedValue? {
  let admitted = match value {
    Null => Some(@admitted.null_value())
    Number(number) => @admitted.number_value(number)
    Boolean(boolean) => Some(@admitted.boolean_value(boolean))
    Text(text) => @admitted.text_value(text, limits.max_text_bytes)
    Captured(captured) => Some(captured)
  }
  guard admitted is Some(admitted) else { return None }
  @admitted.recheck_runtime_value(admitted, contract, limits)
}

///|
fn cleanup_bounded_binding_rows_state(state : BoundedBindingRowsState) -> Bool {
  if state.binding_execution is Some(execution) {
    cancel_ordered_bindings_execution(execution)
    state.binding_execution = None
  }
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  cleanup_expression_roots(state.scope)
  state.input_roots = []
  state.slot_roots = []
  state.values = []
  state.snapshot = Map([])
  state.output_row = []
  state.checked_row = []
  state.workspace.live = 0
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
fn fail_bounded_binding_rows(
  issue : BoundedBindingRowsIssue,
  progress : Int,
  used : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedBindingRowsIssue] {
  @bounded.Failed(issue, progress, used)
}

///|
fn bounded_binding_rows_step(
  state : BoundedBindingRowsState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedBindingRowsIssue] {
  let mut used = 0
  let mut progress = 0
  let count = producer_read_row_count(state.input)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !(state.available)() {
      return fail_bounded_binding_rows(InvalidExecution, progress, used)
    }
    match state.phase {
      RetainInputs => {
        if state.input_row == count {
          state.phase = BeginRow
          continue
        }
        let source : ProducerReadRow = {
          input: state.input,
          row: state.input_row,
          width: state.input_names.length(),
        }
        let root = match
          retain_logical_row(state.logical, state.input_names, source) {
          Ok(value) => value
          Err(issue) =>
            return fail_bounded_binding_rows(
              Rows(LogicalRows(issue)),
              progress,
              used,
            )
        }
        let lease = match register_scope_root(state.scope, root) {
          Ok(value) => value
          Err(issue) =>
            return fail_bounded_binding_rows(
              Rows(LogicalRows(issue)),
              progress,
              used,
            )
        }
        if !reserve_slots(state.workspace, 1) {
          release_expression_root(lease) |> ignore
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        state.input_roots.push(lease)
        state.input_row += 1
        used += 1
      }
      BeginRow => {
        if state.row == count {
          state.phase = FinishOutput
          continue
        }
        if state.control.remaining == 0 {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        state.control.remaining -= 1
        match charge_logical_work(state.logical, 1L) {
          Err(issue) =>
            return fail_bounded_binding_rows(
              Rows(LogicalRows(issue)),
              progress,
              used,
            )
          Ok(_) => ()
        }
        state.snapshot = Map([])
        state.output_row = []
        state.checked_row = []
        state.column = 0
        state.phase = SnapshotRow
        used += 1
      }
      SnapshotRow => {
        if state.column == state.input_names.length() {
          state.binding_execution = Some(
            if state.ordered {
              start_ordered_bindings_execution(
                state.bindings,
                state.snapshot,
                state.control,
                state.workspace,
                state.scope,
                state.row,
              )
            } else {
              start_snapshot_bindings_execution(
                state.bindings,
                state.snapshot,
                state.control,
                state.workspace,
                state.scope,
                state.row,
              )
            },
          )
          state.phase = EvaluateBindings
          continue
        }
        if !reserve_slots(state.workspace, 1) ||
          !spend_control(state.control, 1) ||
          !spend_control_text(state.control, state.input_names[state.column]) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        guard producer_read_cell(state.input, state.row, state.column)
          is Some(value) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        state.snapshot[state.input_names[state.column]] = value
        state.column += 1
        used += 1
      }
      EvaluateBindings => {
        guard state.binding_execution is Some(execution) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        match advance_ordered_bindings_execution(execution) {
          Err(issue) =>
            return fail_bounded_binding_rows(Rows(issue), progress, used)
          Ok(OrderedBindingsContinue) => used += 1
          Ok(OrderedBindingsComplete(values, roots)) => {
            state.values = values
            state.slot_roots = roots
            state.binding_execution = None
            state.column = 0
            state.phase = BuildOutputRow
            used += 1
          }
        }
      }
      BuildOutputRow => {
        if state.column == state.output_names.length() {
          state.column = 0
          state.phase = CheckOutputRow
          continue
        }
        if !reserve_slots(state.workspace, 1) ||
          !spend_control_text(state.control, state.output_names[state.column]) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        let name = state.output_names[state.column]
        let value = match state.binding_ordinals.get(name) {
          Some(index) => state.values.get(index)
          None =>
            match state.input_ordinals.get(name) {
              Some(index) => producer_read_cell(state.input, state.row, index)
              None => None
            }
        }
        guard value is Some(value) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        state.output_row.push(value)
        state.column += 1
        used += 1
      }
      CheckOutputRow => {
        if state.column == state.output_names.length() {
          state.phase = CommitOutputRow
          continue
        }
        guard @schema.field_at(state.output_schema, state.column) is Some(field) &&
          checked_ordered_output_value(
            state.output_row[state.column],
            field.contract,
            state.admitted_limits,
          )
          is Some(value) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        if !reserve_slots(state.workspace, 1) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        state.checked_row.push(value)
        state.column += 1
        used += 1
      }
      CommitOutputRow => {
        if !retain_row(
            state.output_row,
            state.output_names,
            state.output_values,
          ) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        match
          row_event_output(
            state.scope,
            state.output_names,
            state.output_row,
            state.slot_roots,
            state.input_roots[state.row],
          ) {
          Err(issue) =>
            return fail_bounded_binding_rows(Rows(issue), progress, used)
          Ok(_) => ()
        }
        guard state.output is Some(output) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        match append_admitted_output(output, state.checked_row) {
          Err(issue) =>
            return fail_bounded_binding_rows(Capture(issue), progress, used)
          Ok(_) => ()
        }
        release_slots(
          state.workspace,
          state.snapshot.length() +
          state.values.length() * 2 +
          state.output_row.length() +
          state.checked_row.length(),
        )
        state.snapshot = Map([])
        state.values = []
        state.slot_roots = []
        state.output_row = []
        state.checked_row = []
        state.row += 1
        state.phase = BeginRow
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        state.output = None
        cleanup_expression_roots(state.scope)
        state.input_roots = []
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return fail_bounded_binding_rows(Capture(issue), progress, used)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) =>
            fail_bounded_binding_rows(Completion(issue), progress, used)
        }
      }
      Terminal =>
        return fail_bounded_binding_rows(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
pub fn start_bounded_binding_rows(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : ProducerRead,
  max_rows : Int,
  values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedBindingRowsExecution, BoundedBindingRowsIssue] {
  if max_rows < 0 ||
    max_work < 0 ||
    max_frames < 0 ||
    max_entries < 0 ||
    max_name_bytes < 0 {
    return Err(InvalidExecution)
  }
  let sequence = generated.sequence
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_count(sequence) == 1 &&
    @lower.sequence_step(sequence, 0) is Some(@lower.RowStep(kernel)) &&
    producer_read_matches_operation_input(input, owner, 0, 0) &&
    producer_read_has_cell_access(input) &&
    producer_read_row_count(input) <= max_rows &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(0),
    )
    is Some(output_schema) else {
    return Err(InvalidExecution)
  }
  let input_schema = producer_read_schema(input)
  let input_width = @schema.field_count(input_schema)
  let output_width = @schema.field_count(output_schema)
  let binding_count = @lower.kernel_view_entries(kernel)
  let mut metadata_entries = 0
  fn admit_metadata(count : Int) -> Bool {
    if count < 0 || count > max_entries - metadata_entries {
      false
    } else {
      metadata_entries += count
      true
    }
  }
  // The copied binding view, both name arrays, and both ordinal maps coexist
  // for the complete session. Admit all entries before constructing any of
  // those containers.
  if !admit_metadata(binding_count) ||
    !admit_metadata(input_width) ||
    !admit_metadata(output_width) ||
    !admit_metadata(input_width) ||
    !admit_metadata(binding_count) {
    return Err(InvalidExecution)
  }
  let (bindings, ordered) = match @lower.kernel_body(kernel) {
    @lower.OrderedBindings(bindings) => (bindings, true)
    @lower.SnapshotMap(bindings) => (bindings, false)
    _ => return Err(InvalidExecution)
  }
  if bindings.length() != binding_count {
    return Err(InvalidExecution)
  }
  let mut logical : LogicalBudget? = None
  for context in generated.contexts {
    if physical_equal(context.kernel, kernel) {
      if logical is Some(_) {
        return Err(InvalidExecution)
      }
      logical = match fragment_runtime_for_kernel(context, kernel) {
        Ok(value) => Some(value)
        Err(_) => return Err(InvalidExecution)
      }
    }
  }
  guard logical is Some(logical) else { return Err(InvalidExecution) }
  match admit_logical_rows(logical, producer_read_row_count(input).to_int64()) {
    Err(issue) => return Err(Rows(LogicalRows(issue)))
    Ok(_) => ()
  }
  let input_names = Array::makei(input_width, index => {
    @schema.reference_name(@schema.field_at(input_schema, index).unwrap().name)
  })
  let output_names = Array::makei(output_width, index => {
    @schema.reference_name(@schema.field_at(output_schema, index).unwrap().name)
  })
  let input_ordinals : Map[String, Int] = Map([])
  for index, name in input_names {
    if input_ordinals.contains(name) {
      return Err(InvalidExecution)
    }
    input_ordinals[name] = index
  }
  let binding_ordinals : Map[String, Int] = Map([])
  for index, binding in bindings {
    binding_ordinals[binding.0] = index
  }
  let output = match
    prepare_admitted_output(owner, @pipeline.Step(0), max_rows, values) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let output_values = match value_budget(values) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Capture(issue))
    }
  }
  let rows : Ref[AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    prepare_trusted_output_port(
      generated_completion_preparation(generated),
      @pipeline.Step(0),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=[input],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let control : ControlBudget = { remaining: max_work, max_frames, }
  let workspace : RowWorkspace = {
    limit: max_entries,
    live: metadata_entries,
    peak: metadata_entries,
  }
  let state : BoundedBindingRowsState = {
    input,
    available: fn() { producer_read_available(input) },
    bindings,
    input_names,
    output_names,
    input_ordinals,
    binding_ordinals,
    ordered,
    output_schema,
    admitted_limits: {
      max_nodes: values.max_nodes,
      max_depth: values.max_depth,
      max_text_bytes: values.max_text_bytes,
    },
    output_values,
    logical,
    scope: expression_roots(logical, max_frames),
    control,
    workspace,
    input_roots: [],
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    phase: RetainInputs,
    input_row: 0,
    row: 0,
    column: 0,
    snapshot: Map([]),
    binding_execution: None,
    values: [],
    slot_roots: [],
    output_row: [],
    checked_row: [],
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_binding_rows_step,
    cleanup_bounded_binding_rows_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn advance_bounded_binding_rows(
  value : BoundedBindingRowsExecution,
  quantum : Int,
) -> Result[BoundedBindingRowsPoll, BoundedBindingRowsIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedBindingRowsContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedBindingRowsComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedBindingRowsFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedBindingRowsStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_binding_rows(
  value : BoundedBindingRowsExecution,
) -> Result[Bool, BoundedBindingRowsIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}

///|
pub fn bounded_binding_rows_cleanup_pending(
  value : BoundedBindingRowsExecution,
) -> Bool {
  @bounded.cleanup_pending(value.session)
}
