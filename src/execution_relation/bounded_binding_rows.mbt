///|
priv enum BoundedBindingRowsPhase {
  ChargeInput
  RetainInputs
  ChargeSortNames
  ChargeSortRows
  PrepareSortTerms
  StartSort
  SortIdentityRows
  SortRows
  ChargeSortedRows
  ChargeTakeNames
  BeginRow
  SnapshotRow
  EvaluateBindings
  EvaluatePredicate
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
priv struct ProducerReadIndexedRows {
  input : ProducerRead
  width : Int
}

///|
impl IndexedRows for ProducerReadIndexedRows with fn row_count(self) {
  producer_read_row_count(self.input)
}

///|
impl IndexedRows for ProducerReadIndexedRows with fn column_count(self) {
  self.width
}

///|
impl IndexedRows for ProducerReadIndexedRows with fn row_width(self, _row) {
  self.width
}

///|
impl IndexedRows for ProducerReadIndexedRows with fn read_cell(
  self,
  row,
  column,
) {
  producer_read_cell(self.input, row, column).unwrap()
}

///|
priv struct BoundedBindingRowsState {
  input : ProducerRead
  available : () -> Bool
  bindings : Array[(String, @lower.Expression)]
  predicate : @lower.Expression?
  assertion : Bool
  input_names : Array[String]
  output_names : Array[String]
  input_ordinals : Map[String, Int]
  binding_ordinals : Map[String, Int]
  projection_ordinals : Map[String, Int]?
  take_range : (Int, Int)?
  sort_kernel : @lower.PreparedKernel?
  sort_only : Bool
  engine : @bounded.Control
  mut sort_orders : Array[ColumnOrder]
  mut sort_execution : BoundedIndexSort?
  mut sorted_indices : Array[Int]?
  mut sort_row : Int
  mut sort_column : Int
  mut sort_charge_open : Bool
  ordered : Bool
  output_schema : @schema.Schema
  admitted_limits : @admitted.Limits
  input_values : ValueBudget
  output_values : ValueBudget
  logical : LogicalBudget?
  scope : ExpressionRoots?
  control : ControlBudget
  workspace : RowWorkspace
  mut input_roots : Array[ExpressionRootLease]
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut phase : BoundedBindingRowsPhase
  mut charge_row : Int
  mut charge_column : Int
  mut charge_open : Bool
  mut input_row : Int
  mut row : Int
  mut column : Int
  mut snapshot : Map[String, Value]
  mut binding_execution : OrderedBindingsExecution?
  mut predicate_execution : ExpressionFrame?
  mut values : Array[Value]
  mut slot_roots : Array[ExpressionRootLease]
  mut output_row : Array[Value]
  mut checked_row : Array[@admitted.CheckedValue]
}

///|
pub(all) enum BoundedBindingRowsIssue {
  InvalidExecution
  InputLimit
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
  if state.sort_execution is Some(execution) {
    cleanup_bounded_index_sort(execution) |> ignore
    state.sort_execution = None
  }
  state.sort_orders = []
  state.sorted_indices = None
  if state.binding_execution is Some(execution) {
    cancel_ordered_bindings_execution(execution)
    state.binding_execution = None
  }
  if state.predicate_execution is Some(execution) {
    close_expression_frame(execution)
    state.predicate_execution = None
  }
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if state.scope is Some(scope) {
    cleanup_expression_roots(scope)
  }
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
      ChargeInput => {
        if state.charge_row == count {
          state.phase = RetainInputs
          continue
        }
        if !state.charge_open {
          if !spend_control(state.control, 1) ||
            !charge_node(state.input_values, 1) {
            return fail_bounded_binding_rows(InputLimit, progress, used)
          }
          state.charge_open = true
          used += 1
        } else if state.charge_column < state.input_names.length() {
          let column = state.charge_column
          guard producer_read_cell(state.input, state.charge_row, column)
            is Some(value) else {
            return fail_bounded_binding_rows(InvalidExecution, progress, used)
          }
          if !charge_text(state.input_values, state.input_names[column]) ||
            !measure_result(value, state.input_values) {
            return fail_bounded_binding_rows(InputLimit, progress, used)
          }
          state.charge_column += 1
          used += 1
        } else {
          if state.take_range is Some(_) && !spend_control(state.control, 1) {
            return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
          }
          state.charge_row += 1
          state.charge_column = 0
          state.charge_open = false
          if state.take_range is Some(_) {
            used += 1
          }
        }
      }
      RetainInputs => {
        if state.take_range is Some(_) {
          state.column = 0
          state.phase = if state.sort_kernel is Some(_) {
            ChargeSortNames
          } else {
            ChargeTakeNames
          }
          continue
        }
        if state.logical is None {
          state.phase = BeginRow
          continue
        }
        if state.input_row == count {
          state.phase = BeginRow
          continue
        }
        guard state.logical is Some(logical) && state.scope is Some(scope) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        let source : ProducerReadRow = {
          input: state.input,
          row: state.input_row,
          width: state.input_names.length(),
        }
        let root = match
          retain_logical_row(logical, state.input_names, source) {
          Ok(value) => value
          Err(issue) =>
            return fail_bounded_binding_rows(
              Rows(LogicalRows(issue)),
              progress,
              used,
            )
        }
        let lease = match register_scope_root(scope, root) {
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
      ChargeSortNames => {
        if state.column == state.input_names.length() {
          state.sort_row = 0
          state.phase = ChargeSortRows
          continue
        }
        if !spend_control(state.control, 1) ||
          !spend_control_text(state.control, state.input_names[state.column]) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        state.column += 1
        used += 1
      }
      ChargeSortRows => {
        if state.sort_row == count {
          state.column = 0
          state.phase = PrepareSortTerms
          continue
        }
        if !spend_control(state.control, 1) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        state.sort_row += 1
        used += 1
      }
      PrepareSortTerms => {
        guard state.sort_kernel is Some(kernel) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        if state.column == @lower.kernel_sort_term_count(kernel) {
          state.phase = StartSort
          continue
        }
        guard @lower.kernel_sort_term_at(kernel, state.column)
          is Some((field, descending, nulls_first)) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field)
        if !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        guard state.input_ordinals.get(name) is Some(column) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        state.sort_orders.push({ column, descending, nulls_first, })
        state.column += 1
        used += 1
      }
      StartSort => {
        if state.sort_orders.is_empty() {
          if !reserve_slots(state.workspace, count) {
            return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
          }
          state.sorted_indices = Some([])
          state.sort_row = 0
          state.phase = SortIdentityRows
          continue
        }
        // The merge owns two index arrays. Reserve both before its first step.
        if count > (state.workspace.limit - state.workspace.live) / 2 ||
          !reserve_slots(state.workspace, count * 2) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        let rows : ProducerReadIndexedRows = {
          input: state.input,
          width: state.input_names.length(),
        }
        state.sort_execution = start_bounded_index_sort(state.engine, count, fn(
          left,
          right,
        ) {
          compare_row_indices(
            rows,
            left,
            right,
            state.sort_orders,
            state.control,
          ).map_err(ordering_row_issue)
        })
        guard state.sort_execution is Some(_) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        state.phase = SortRows
        used += 1
      }
      SortIdentityRows => {
        if state.sort_row == count {
          state.sort_row = 0
          state.phase = if state.sort_only {
            BeginRow
          } else {
            ChargeSortedRows
          }
          continue
        }
        if !spend_control(state.control, 1) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        guard state.sorted_indices is Some(indices) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        indices.push(state.sort_row)
        state.sort_row += 1
        used += 1
      }
      SortRows => {
        guard state.sort_execution is Some(execution) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        if !spend_control(state.control, 1) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        match advance_bounded_index_sort(execution, 1) {
          Err(issue) | Ok(BoundedIndexSortFailed(issue)) =>
            return fail_bounded_binding_rows(Rows(issue), progress, used)
          Ok(BoundedIndexSortStopped(reason)) =>
            return @bounded.Stopped(reason, progress, used + 1)
          Ok(BoundedIndexSortContinue) => used += 1
          Ok(BoundedIndexSortComplete(indices)) => {
            cleanup_bounded_index_sort(execution) |> ignore
            state.sort_execution = None
            release_slots(state.workspace, count)
            state.sorted_indices = Some(indices)
            state.sort_row = 0
            state.sort_column = 0
            state.sort_charge_open = false
            state.phase = if state.sort_only {
              BeginRow
            } else {
              ChargeSortedRows
            }
            used += 1
          }
        }
      }
      ChargeSortedRows => {
        if state.sort_row == count {
          state.column = 0
          state.phase = ChargeTakeNames
          continue
        }
        guard state.sorted_indices is Some(indices) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        if !state.sort_charge_open {
          if !spend_control(state.control, 1) ||
            !charge_node(state.output_values, 1) {
            return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
          }
          state.sort_charge_open = true
          used += 1
        } else if state.sort_column < state.input_names.length() {
          guard producer_read_cell(
              state.input,
              indices[state.sort_row],
              state.sort_column,
            )
            is Some(value) else {
            return fail_bounded_binding_rows(InvalidExecution, progress, used)
          }
          if !spend_control(state.control, 1) ||
            !charge_text(
              state.output_values,
              state.input_names[state.sort_column],
            ) ||
            !measure_result(value, state.output_values) {
            return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
          }
          state.sort_column += 1
          used += 1
        } else {
          state.sort_row += 1
          state.sort_column = 0
          state.sort_charge_open = false
        }
      }
      ChargeTakeNames => {
        if state.column == state.output_names.length() {
          guard state.take_range is Some((start, _)) else {
            return fail_bounded_binding_rows(InvalidExecution, progress, used)
          }
          state.row = start
          state.phase = BeginRow
          continue
        }
        if !spend_control(state.control, 1) ||
          !spend_control_text(state.control, state.output_names[state.column]) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        state.column += 1
        used += 1
      }
      BeginRow => {
        if state.take_range is Some((_, end)) && state.row >= end {
          state.phase = FinishOutput
          continue
        }
        if state.row == count {
          state.phase = FinishOutput
          continue
        }
        if state.control.remaining == 0 {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        state.control.remaining -= 1
        if state.logical is Some(logical) {
          match charge_logical_work(logical, 1L) {
            Err(issue) =>
              return fail_bounded_binding_rows(
                Rows(LogicalRows(issue)),
                progress,
                used,
              )
            Ok(_) => ()
          }
        }
        state.snapshot = Map([])
        state.output_row = []
        state.checked_row = []
        state.column = 0
        state.phase = if state.projection_ordinals is Some(_) {
          BuildOutputRow
        } else {
          SnapshotRow
        }
        used += 1
      }
      SnapshotRow => {
        if state.column == state.input_names.length() {
          match state.predicate {
            Some(predicate) => {
              guard state.logical is Some(logical) else {
                return fail_bounded_binding_rows(
                  InvalidExecution,
                  progress,
                  used,
                )
              }
              if !reserve_slots(state.workspace, 2) {
                return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
              }
              state.predicate_execution = match
                expression_frame(
                  predicate,
                  state.snapshot,
                  [],
                  state.control,
                  state.workspace,
                  Some(expression_roots(logical, state.control.max_frames)),
                ) {
                Ok(value) => Some(value)
                Err(issue) =>
                  return fail_bounded_binding_rows(
                    Rows(evaluation_row_issue(state.row, 0, issue)),
                    progress,
                    used,
                  )
              }
              state.phase = EvaluatePredicate
            }
            None => {
              guard state.scope is Some(scope) else {
                return fail_bounded_binding_rows(
                  InvalidExecution,
                  progress,
                  used,
                )
              }
              state.binding_execution = Some(
                if state.ordered {
                  start_ordered_bindings_execution(
                    state.bindings,
                    state.snapshot,
                    state.control,
                    state.workspace,
                    scope,
                    state.row,
                  )
                } else {
                  start_snapshot_bindings_execution(
                    state.bindings,
                    state.snapshot,
                    state.control,
                    state.workspace,
                    scope,
                    state.row,
                  )
                },
              )
              state.phase = EvaluateBindings
            }
          }
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
      EvaluatePredicate => {
        guard state.predicate_execution is Some(execution) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        match advance_expression_frame(execution) {
          Err(issue) =>
            return fail_bounded_binding_rows(
              Rows(evaluation_row_issue(state.row, 0, issue)),
              progress,
              used,
            )
          Ok(None) => used += 1
          Ok(Some(evaluated)) => {
            state.predicate_execution = None
            release_slots(state.workspace, 2)
            if evaluated.root is Some(root) {
              match release_logical_root(root.owner, root) {
                Err(issue) =>
                  return fail_bounded_binding_rows(
                    Rows(LogicalRows(issue)),
                    progress,
                    used,
                  )
                Ok(_) => ()
              }
            }
            match evaluated.value {
              Boolean(true) => {
                state.column = 0
                state.phase = BuildOutputRow
              }
              Boolean(false) | Null => {
                if state.assertion {
                  return fail_bounded_binding_rows(
                    Rows(AssertionPredicate(state.row)),
                    progress,
                    used,
                  )
                }
                match release_expression_root(state.input_roots[state.row]) {
                  Err(issue) =>
                    return fail_bounded_binding_rows(
                      Rows(LogicalRows(issue)),
                      progress,
                      used,
                    )
                  Ok(_) => ()
                }
                release_slots(state.workspace, state.snapshot.length())
                state.snapshot = Map([])
                state.row += 1
                state.phase = BeginRow
              }
              Number(_) | Text(_) | Captured(_) =>
                return fail_bounded_binding_rows(
                  Rows(
                    if state.assertion {
                      AssertionPredicate(state.row)
                    } else {
                      InvalidRows
                    },
                  ),
                  progress,
                  used,
                )
            }
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
          (if state.take_range is Some(_) {
            !spend_control(state.control, 1)
          } else {
            !spend_control_text(state.control, state.output_names[state.column])
          }) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        let name = state.output_names[state.column]
        let source_row = match state.sorted_indices {
          Some(indices) => indices[state.row]
          None => state.row
        }
        let value = match state.projection_ordinals {
          Some(projection) =>
            match projection.get(name) {
              Some(index) => producer_read_cell(state.input, source_row, index)
              None => None
            }
          None =>
            match state.binding_ordinals.get(name) {
              Some(index) => state.values.get(index)
              None =>
                match state.input_ordinals.get(name) {
                  Some(index) =>
                    producer_read_cell(state.input, state.row, index)
                  None => None
                }
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
        if state.scope is Some(scope) {
          guard state.input_roots.get(state.row) is Some(root) else {
            return fail_bounded_binding_rows(InvalidExecution, progress, used)
          }
          match
            row_event_output(
              scope,
              state.output_names,
              state.output_row,
              state.slot_roots,
              root,
            ) {
            Err(issue) =>
              return fail_bounded_binding_rows(Rows(issue), progress, used)
            Ok(_) => ()
          }
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
        if state.scope is Some(scope) {
          cleanup_expression_roots(scope)
        }
        state.input_roots = []
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return fail_bounded_binding_rows(Capture(issue), progress, used)
        }
        if state.sorted_indices is Some(_) {
          release_slots(state.workspace, count)
          state.sorted_indices = None
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
  input_values : ValueLimits,
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
  guard generated_sequence_step_index_at(generated, 0) is Some(step) &&
    generated_sequence_step_index_at(generated, 1) is None &&
    @lower.sequence_step(sequence, step) is Some(@lower.RowStep(kernel)) &&
    producer_read_matches_operation_input(input, owner, step, 0) &&
    producer_read_has_cell_access(input) &&
    producer_read_row_count(input) <= max_rows &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
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
  let (bindings, ordered, predicate, select_mode, take_range, sort_kernel) = match
    @lower.kernel_body(kernel) {
    @lower.OrderedBindings(bindings) =>
      (bindings, true, None, false, None, None)
    @lower.SnapshotMap(bindings) => (bindings, false, None, false, None, None)
    @lower.Filter(expression) =>
      ([], false, Some(expression), false, None, None)
    @lower.AssertAll(expression) =>
      ([], false, Some(expression), false, None, None)
    @lower.Select(_) => ([], false, None, true, None, None)
    @lower.StableSort(_) =>
      (
        [],
        false,
        None,
        false,
        Some((0, producer_read_row_count(input))),
        Some(kernel),
      )
    @lower.Limit(take_count, offset, _) => {
      let prepared = @lower.bound_preparation(owner)
      guard @lower.node_at(prepared, step) is Some(node) &&
        take_count > 0L &&
        offset >= 0L else {
        return Err(InvalidExecution)
      }
      let size = producer_read_row_count(input)
      let start = if offset >= size.to_int64() { size } else { offset.to_int() }
      let remaining = size - start
      let selected = if take_count >= remaining.to_int64() {
        remaining
      } else {
        take_count.to_int()
      }
      let sort_kernel = if @lower.order_node_id(node) is Some(_) {
        Some(kernel)
      } else {
        None
      }
      ([], false, None, false, Some((start, start + selected)), sort_kernel)
    }
    _ => return Err(InvalidExecution)
  }
  let sort_only = @lower.kernel_body(kernel) is @lower.StableSort(_)
  let assertion = @lower.kernel_body(kernel) is @lower.AssertAll(_)
  if take_range is None && !select_mode && bindings.length() != binding_count {
    return Err(InvalidExecution)
  }
  if take_range is Some(_) && !admit_metadata(output_width) {
    return Err(InvalidExecution)
  }
  if sort_kernel is Some(sort) &&
    !admit_metadata(@lower.kernel_sort_term_count(sort)) {
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
  if !select_mode && take_range is None {
    guard logical is Some(logical) else { return Err(InvalidExecution) }
    match
      admit_logical_rows(logical, producer_read_row_count(input).to_int64()) {
      Err(issue) => return Err(Rows(LogicalRows(issue)))
      Ok(_) => ()
    }
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
  let projection_ordinals : Map[String, Int]? = match
    @lower.kernel_body(kernel) {
    @lower.Select(fields) => {
      let projection : Map[String, Int] = Map([])
      for field in fields {
        let output_name = @schema.reference_name(field.output)
        guard input_ordinals.get(@schema.reference_name(field.input))
          is Some(index) &&
          !projection.contains(output_name) else {
          return Err(InvalidExecution)
        }
        projection[output_name] = index
      }
      if projection.length() != output_width {
        return Err(InvalidExecution)
      }
      Some(projection)
    }
    @lower.StableSort(_) | @lower.Limit(_, _, _) => {
      let projection : Map[String, Int] = Map([])
      for name in output_names {
        guard input_ordinals.get(name) is Some(index) else {
          return Err(InvalidExecution)
        }
        projection[name] = index
      }
      if projection.length() != output_width || input_width != output_width {
        return Err(InvalidExecution)
      }
      Some(projection)
    }
    _ => None
  }
  let output = match
    prepare_admitted_output(owner, @pipeline.Step(step), max_rows, values) {
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
  let input_values = match value_budget(input_values) {
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
      @pipeline.Step(step),
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
  let workspace = row_workspace(max_entries)
  if !reserve_slots(workspace, metadata_entries) {
    cancel_admitted_output(output) |> ignore
    return Err(Rows(RowLimit))
  }
  let state : BoundedBindingRowsState = {
    input,
    available: fn() { producer_read_available(input) },
    bindings,
    predicate,
    assertion,
    input_names,
    output_names,
    input_ordinals,
    binding_ordinals,
    projection_ordinals,
    take_range,
    sort_kernel,
    sort_only,
    engine,
    sort_orders: [],
    sort_execution: None,
    sorted_indices: None,
    sort_row: 0,
    sort_column: 0,
    sort_charge_open: false,
    ordered,
    output_schema,
    admitted_limits: {
      max_nodes: values.max_nodes,
      max_depth: values.max_depth,
      max_text_bytes: values.max_text_bytes,
    },
    input_values,
    output_values,
    logical,
    scope: logical.map(logical => expression_roots(logical, max_frames)),
    control,
    workspace,
    input_roots: [],
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    phase: ChargeInput,
    charge_row: 0,
    charge_column: 0,
    charge_open: false,
    input_row: 0,
    row: 0,
    column: 0,
    snapshot: Map([]),
    binding_execution: None,
    predicate_execution: None,
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
