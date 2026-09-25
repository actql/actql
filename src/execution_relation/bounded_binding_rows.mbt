///|
priv enum BoundedBindingRowsPhase {
  PrepareDistinctTerms
  InitializeDistinctKeep
  MarkDistinct
  CheckUniqueKeys
  CheckUniquePairs
  ChargeInput
  RetainInputs
  ChargeSortNames
  ChargeSortRows
  PrepareSortTerms
  StartSort
  SortIdentityRows
  SortRows
  InitializeLagValues
  BuildLagValues
  ChargeSortedRows
  ChargeTakeNames
  BeginRow
  PickJson
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
/// Keep the two exact receiving authorities distinct while sharing the
/// bounded row evaluator. A supplied input is not a completed producer.
priv enum BoundedBindingInput {
  CompletedBindingInput(ProducerRead)
  SuppliedBindingInput(SuppliedRelationRead)
}

///|
fn bounded_binding_input_row_count(input : BoundedBindingInput) -> Int {
  match input {
    CompletedBindingInput(read) => producer_read_row_count(read)
    SuppliedBindingInput(read) => supplied_relation_read_row_count(read)
  }
}

///|
fn bounded_binding_input_schema(input : BoundedBindingInput) -> @schema.Schema {
  match input {
    CompletedBindingInput(read) => producer_read_schema(read)
    SuppliedBindingInput(read) => supplied_relation_read_schema(read)
  }
}

///|
fn bounded_binding_input_cell(
  input : BoundedBindingInput,
  row : Int,
  column : Int,
) -> Value? {
  match input {
    CompletedBindingInput(read) => producer_read_cell(read, row, column)
    SuppliedBindingInput(read) =>
      supplied_relation_read_cell(read, row, column).map(capture)
  }
}

///|
fn bounded_binding_input_available(input : BoundedBindingInput) -> Bool {
  match input {
    CompletedBindingInput(read) =>
      producer_read_available(read) && producer_read_has_cell_access(read)
    SuppliedBindingInput(read) => supplied_relation_read_available(read)
  }
}

///|
fn bounded_binding_input_matches(
  input : BoundedBindingInput,
  owner : @lower.BoundPrepared,
  step : Int,
) -> Bool {
  match input {
    CompletedBindingInput(read) =>
      producer_read_matches_operation_input(read, owner, step, 0)
    SuppliedBindingInput(read) =>
      supplied_relation_read_matches_operation_input(read, owner, step, 0)
  }
}

///|
fn bounded_binding_trusted_input(
  input : BoundedBindingInput,
) -> TrustedOutputInput {
  match input {
    CompletedBindingInput(read) => trusted_output_relation_input(read)
    SuppliedBindingInput(read) => trusted_output_supplied_relation_input(read)
  }
}

///|
priv struct BoundedBindingRow {
  input : BoundedBindingInput
  row : Int
  width : Int
}

///|
impl RowValues for BoundedBindingRow with fn value_count(self) {
  self.width
}

///|
impl RowValues for BoundedBindingRow with fn value_at(self, column) {
  bounded_binding_input_cell(self.input, self.row, column).unwrap()
}

///|
/// One comparison cursor is reused by the merge and partition-boundary
/// phases. Text charging and comparison each advance by one UTF-16 scalar or
/// code unit, so an equal long prefix never occupies a whole resume step.
priv struct BoundedRowComparison {
  mut left : Int
  mut right : Int
  mut terms : Int
  mut term : Int
  mut phase : Int
  mut offset : Int
}

///|
fn bounded_row_comparison_step_with(
  cursor : BoundedRowComparison,
  orders : Array[ColumnOrder],
  control : ControlBudget,
  read_cell : (Int, Int) -> Value?,
  left_row : Int,
  right_row : Int,
  terms : Int,
) -> Result[Int?, OrderingIssue] {
  if terms < 0 || terms > orders.length() {
    return Err(InvalidInput)
  }
  if cursor.phase == -1 {
    cursor.left = left_row
    cursor.right = right_row
    cursor.terms = terms
    cursor.term = 0
    cursor.phase = 0
    cursor.offset = 0
  } else if cursor.left != left_row ||
    cursor.right != right_row ||
    cursor.terms != terms {
    return Err(InvalidInput)
  }
  if cursor.term == terms {
    cursor.phase = -1
    return Ok(Some(0))
  }
  let order = orders[cursor.term]
  let left = read_cell(left_row, order.column)
  let right = read_cell(right_row, order.column)
  guard left is Some(left) && right is Some(right) else {
    return Err(InvalidInput)
  }
  match cursor.phase {
    0 => {
      if !spend_control(control, 1) {
        return Err(Limit)
      }
      cursor.phase = 1
      Ok(None)
    }
    1 => {
      match left {
        Text(value) =>
          if cursor.offset < value.length() {
            cursor.offset = match
              bounded_text_charge_step(control, value, cursor.offset) {
              Ok(next) => next
              Err(issue) => return Err(issue)
            }
            return Ok(None)
          }
        _ =>
          match charge_comparison_operand(control, left) {
            Ok(_) => ()
            Err(ComparisonChargeLimit) => return Err(Limit)
            Err(ComparisonChargeInvalidOperand) =>
              return Err(Scalar(InvalidOperand))
          }
      }
      cursor.phase = 2
      cursor.offset = 0
      Ok(None)
    }
    2 => {
      match right {
        Text(value) =>
          if cursor.offset < value.length() {
            cursor.offset = match
              bounded_text_charge_step(control, value, cursor.offset) {
              Ok(next) => next
              Err(issue) => return Err(issue)
            }
            return Ok(None)
          }
        _ =>
          match charge_comparison_operand(control, right) {
            Ok(_) => ()
            Err(ComparisonChargeLimit) => return Err(Limit)
            Err(ComparisonChargeInvalidOperand) =>
              return Err(Scalar(InvalidOperand))
          }
      }
      cursor.phase = 3
      cursor.offset = 0
      Ok(None)
    }
    3 => {
      let compared = match (left, right) {
        (Text(a), Text(b)) =>
          if cursor.offset < a.length() && cursor.offset < b.length() {
            let a_unit = a[cursor.offset]
            let b_unit = b[cursor.offset]
            if a_unit == b_unit {
              cursor.offset += 1
              return Ok(None)
            }
            if a_unit < b_unit {
              -1
            } else {
              1
            }
          } else if a.length() < b.length() {
            -1
          } else if a.length() > b.length() {
            1
          } else {
            0
          }
        (Null, Null) => 0
        (Null, _) => if order.nulls_first { -1 } else { 1 }
        (_, Null) => if order.nulls_first { 1 } else { -1 }
        _ =>
          match compare(left, right) {
            Ok(value) => value
            Err(issue) => return Err(Scalar(issue))
          }
      }
      let compared = if left is Null || right is Null || !order.descending {
        compared
      } else {
        -compared
      }
      if compared != 0 {
        cursor.phase = -1
        Ok(Some(compared))
      } else {
        cursor.term += 1
        cursor.phase = 0
        cursor.offset = 0
        Ok(None)
      }
    }
    _ => Err(InvalidInput)
  }
}

///|
fn bounded_row_comparison_step(
  state : BoundedBindingRowsState,
  left_row : Int,
  right_row : Int,
  terms : Int,
) -> Result[Int?, OrderingIssue] {
  bounded_row_comparison_step_with(
    state.comparison,
    state.sort_orders,
    state.control,
    (row, column) => bounded_binding_input_cell(state.input, row, column),
    left_row,
    right_row,
    terms,
  )
}

///|
priv struct BoundedBindingRowsState {
  input : BoundedBindingInput
  available : () -> Bool
  bindings : Array[(String, @lower.Expression)]
  predicate : @lower.Expression?
  assertion : Bool
  unique_keys : Array[@schema.FieldName]?
  distinct : Bool
  mut distinct_keep : Array[Bool]
  mut distinct_cursor : Int
  input_names : Array[String]
  output_names : Array[String]
  input_ordinals : Map[String, Int]
  binding_ordinals : Map[String, Int]
  projection_ordinals : Map[String, Int]?
  json_path : Array[String]?
  json_source_column : Int
  json_output_name : String
  watermark : (
    Int,
    Bool,
    @relation.LatePolicy,
    @lower.PreparedWatermarkThreshold,
  )?
  mut watermark_times : Array[Double]
  mut watermark_prefix_max : Double
  mut watermark_has_prefix : Bool
  mut watermark_checked : Bool
  mut watermark_current : Double
  mut watermark_late : Bool
  lag : (Int, String, Int64)?
  mut lag_values : Array[Value]
  mut lag_values_reserved : Bool
  mut lag_position : Int
  mut lag_partition_start : Int
  mut lag_row_open : Bool
  mut json_current : @admitted.Value?
  mut json_picked : Value?
  mut json_segment : Int
  mut json_field : Int
  mut json_name_offset : Int
  mut json_name_open : Bool
  mut json_name_matches : Bool
  take_range : (Int, Int)?
  partition_limit : Int64?
  partition_terms : Int
  mut partition_leader : Int
  mut partition_taken : Int64
  mut partition_checked : Bool
  comparison : BoundedRowComparison
  sort_kernel : @lower.PreparedKernel?
  sort_only : Bool
  engine : @bounded.Control
  mut sort_orders : Array[ColumnOrder]
  mut sort_execution : BoundedIndexSort?
  mut sorted_indices : Array[Int]?
  mut sort_row : Int
  mut sort_column : Int
  mut sort_charge_open : Bool
  mut sort_measure : SteppedValueMeasure?
  mut unique_key : Int
  mut unique_row : Int
  mut unique_pair : Int
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
  mut charge_measure : SteppedValueMeasure?
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
  UnsupportedDistinctField(@schema.FieldName)
  InputLimit
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedBindingRowsExecution {
  state : BoundedBindingRowsState
  session : @bounded.Session[
    BoundedBindingRowsState,
    CompletedOutput,
    BoundedBindingRowsIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
// This read-only probe is used by white-box cancellation tests.
#warnings("-unused_value")
fn bounded_binding_rows_comparison_state(
  value : BoundedBindingRowsExecution,
) -> (BoundedBindingRowsPhase, Int, Int) {
  (value.state.phase, value.state.comparison.phase, value.state.comparison.term)
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
    // The parent may already be stopped while its child sort still owns two
    // private arrays. Observe the child's stop before releasing its custody.
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
  state.sort_orders = []
  state.sorted_indices = None
  state.lag_values = []
  state.distinct_keep = []
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
  state.json_current = None
  state.json_picked = None
  state.watermark_times = []
  if state.charge_measure is Some(cursor) {
    clear_stepped_measure(cursor)
    state.charge_measure = None
  }
  if state.sort_measure is Some(cursor) {
    clear_stepped_measure(cursor)
    state.sort_measure = None
  }
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
  let count = bounded_binding_input_row_count(state.input)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !(state.available)() {
      return fail_bounded_binding_rows(InvalidExecution, progress, used)
    }
    match state.phase {
      PrepareDistinctTerms => {
        if state.column == state.output_names.length() {
          state.column = 0
          state.phase = ChargeInput
          continue
        }
        guard @schema.field_at(state.output_schema, state.column) is Some(field) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        if !supported_comparison(field.contract, field.contract) {
          return fail_bounded_binding_rows(
            UnsupportedDistinctField(field.name),
            progress,
            used,
          )
        }
        if !reserve_slots(state.workspace, 1) ||
          !spend_control(state.control, 1) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        guard state.projection_ordinals is Some(projection) &&
          projection.get(@schema.reference_name(field.name)) is Some(source) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        state.sort_orders.push({
          column: source,
          descending: false,
          nulls_first: false,
        })
        state.column += 1
        used += 1
      }
      InitializeDistinctKeep => {
        if state.distinct_keep.length() == count {
          state.distinct_cursor = 0
          state.phase = MarkDistinct
          continue
        }
        if !spend_control(state.control, 1) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        state.distinct_keep.push(false)
        used += 1
      }
      MarkDistinct => {
        if state.distinct_cursor == count {
          release_slots(state.workspace, count + state.sort_orders.length())
          state.sorted_indices = None
          state.sort_orders = []
          state.row = 0
          state.phase = BeginRow
          continue
        }
        guard state.sorted_indices is Some(indices) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        if state.comparison.phase == -1 && !spend_control(state.control, 1) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        let first = if state.distinct_cursor == 0 {
          true
        } else {
          match
            bounded_row_comparison_step(
              state,
              indices[state.distinct_cursor - 1],
              indices[state.distinct_cursor],
              state.sort_orders.length(),
            ) {
            Ok(Some(comparison)) => comparison != 0
            Ok(None) => {
              used += 1
              continue
            }
            Err(issue) =>
              return fail_bounded_binding_rows(
                Rows(ordering_row_issue(issue)),
                progress,
                used + 1,
              )
          }
        }
        if first {
          state.distinct_keep[indices[state.distinct_cursor]] = true
        }
        state.distinct_cursor += 1
        used += 1
      }
      CheckUniqueKeys => {
        guard state.unique_keys is Some(keys) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        if state.unique_key == keys.length() {
          state.phase = StartSort
          continue
        }
        let name = @schema.reference_name(keys[state.unique_key])
        if state.unique_row < 0 {
          if !reserve_slots(state.workspace, 1) ||
            !spend_control(state.control, 1) ||
            !spend_control_text(state.control, name) {
            return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
          }
          guard state.input_ordinals.get(name) is Some(column) else {
            return fail_bounded_binding_rows(Rows(InvalidRows), progress, used)
          }
          state.sort_orders.push({
            column,
            descending: false,
            nulls_first: false,
          })
          state.unique_row = 0
          used += 1
        } else if state.unique_row < count {
          if !spend_control(state.control, 1) {
            return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
          }
          let column = state.sort_orders[state.unique_key].column
          guard bounded_binding_input_cell(
              state.input,
              state.unique_row,
              column,
            )
            is Some(value) else {
            return fail_bounded_binding_rows(InvalidExecution, progress, used)
          }
          if value is Null {
            return fail_bounded_binding_rows(
              Rows(AssertionNullKey(state.unique_row, state.unique_key)),
              progress,
              used + 1,
            )
          }
          state.unique_row += 1
          used += 1
        } else {
          state.unique_key += 1
          state.unique_row = -1
        }
      }
      CheckUniquePairs => {
        if state.unique_pair >= count {
          release_slots(state.workspace, count + state.sort_orders.length())
          state.sorted_indices = None
          state.sort_orders = []
          state.phase = ChargeInput
          continue
        }
        guard state.sorted_indices is Some(indices) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        if state.comparison.phase == -1 && !spend_control(state.control, 1) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        let left = indices[state.unique_pair - 1]
        let right = indices[state.unique_pair]
        match
          bounded_row_comparison_step(
            state,
            left,
            right,
            state.sort_orders.length(),
          ) {
          Ok(None) => {
            used += 1
            continue
          }
          Ok(Some(0)) =>
            return fail_bounded_binding_rows(
              Rows(AssertionDuplicate(left, right)),
              progress,
              used + 1,
            )
          Ok(Some(_)) => ()
          Err(issue) =>
            return fail_bounded_binding_rows(
              Rows(ordering_row_issue(issue)),
              progress,
              used + 1,
            )
        }
        state.unique_pair += 1
        used += 1
      }
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
          if state.charge_measure is None {
            guard bounded_binding_input_cell(
                state.input,
                state.charge_row,
                column,
              )
              is Some(value) else {
              return fail_bounded_binding_rows(InvalidExecution, progress, used)
            }
            if !charge_text(state.input_values, state.input_names[column]) {
              return fail_bounded_binding_rows(InputLimit, progress, used)
            }
            guard start_stepped_measure_result(value, state.workspace)
              is Some(cursor) else {
              return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
            }
            state.charge_measure = Some(cursor)
          }
          let cursor = state.charge_measure.unwrap()
          match advance_stepped_measure_result(cursor, state.input_values) {
            SteppedMeasureLimit =>
              return fail_bounded_binding_rows(InputLimit, progress, used)
            SteppedMeasureWorkspaceLimit =>
              return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
            SteppedMeasureContinue => ()
            SteppedMeasureComplete => {
              clear_stepped_measure(cursor)
              state.charge_measure = None
              state.charge_column += 1
            }
          }
          used += 1
        } else {
          if state.watermark is Some((column, timestamp, _, _)) {
            if !spend_control(state.control, 1) {
              return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
            }
            guard bounded_binding_input_cell(
                state.input,
                state.charge_row,
                column,
              )
              is Some(value) else {
              return fail_bounded_binding_rows(InvalidExecution, progress, used)
            }
            let time = match
              window_time_milliseconds(value, timestamp, state.control) {
              Ok(time) => time
              Err(issue) =>
                return fail_bounded_binding_rows(
                  Rows(window_time_row_issue(issue, state.charge_row)),
                  progress,
                  used,
                )
            }
            state.watermark_times.push(time)
            used += 1
          }
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
        if state.distinct {
          state.phase = StartSort
          continue
        }
        if state.lag is Some(_) {
          state.column = 0
          state.phase = ChargeSortNames
          continue
        }
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
        let source : BoundedBindingRow = {
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
        if state.column ==
          state.partition_terms + @lower.kernel_sort_term_count(kernel) {
          state.phase = StartSort
          continue
        }
        let (field, descending, nulls_first) = if state.column <
          state.partition_terms {
          let field = if state.lag is Some(_) {
            @lower.kernel_lag_partition_at(kernel, state.column)
          } else {
            @lower.kernel_top_k_partition_at(kernel, state.column)
          }
          guard field is Some(field) else {
            return fail_bounded_binding_rows(InvalidExecution, progress, used)
          }
          (field, false, true)
        } else {
          guard @lower.kernel_sort_term_at(
              kernel,
              state.column - state.partition_terms,
            )
            is Some(order) else {
            return fail_bounded_binding_rows(InvalidExecution, progress, used)
          }
          order
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
        state.sort_execution = start_bounded_index_sort_stepped(
          state.engine,
          count,
          fn(left, right) {
            bounded_row_comparison_step(
              state,
              left,
              right,
              state.sort_orders.length(),
            ).map_err(ordering_row_issue)
          },
        )
        guard state.sort_execution is Some(_) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        state.phase = SortRows
        used += 1
      }
      SortIdentityRows => {
        if state.sort_row == count {
          state.sort_row = 0
          state.phase = if state.distinct {
            if !reserve_slots(state.workspace, count) {
              return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
            }
            InitializeDistinctKeep
          } else if state.lag is Some(_) {
            InitializeLagValues
          } else if state.sort_only {
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
        if state.comparison.phase == -1 && !spend_control(state.control, 1) {
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
            state.phase = if state.unique_keys is Some(_) {
              CheckUniquePairs
            } else if state.distinct {
              if !reserve_slots(state.workspace, count) {
                return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
              }
              InitializeDistinctKeep
            } else if state.lag is Some(_) {
              InitializeLagValues
            } else if state.sort_only {
              BeginRow
            } else {
              ChargeSortedRows
            }
            used += 1
          }
        }
      }
      InitializeLagValues => {
        if !state.lag_values_reserved {
          if !reserve_slots(state.workspace, count) {
            return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
          }
          state.lag_values_reserved = true
        }
        if state.lag_values.length() == count {
          state.lag_position = 0
          state.lag_partition_start = 0
          state.phase = BuildLagValues
          continue
        }
        if !spend_control(state.control, 1) {
          return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
        }
        state.lag_values.push(Null)
        used += 1
      }
      BuildLagValues => {
        guard state.lag is Some((source_column, _, offset)) &&
          state.sorted_indices is Some(indices) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        if state.lag_position == count {
          release_slots(state.workspace, count)
          state.sorted_indices = None
          state.phase = BeginRow
          continue
        }
        if !state.lag_row_open {
          if !spend_control(state.control, 1) {
            return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
          }
          state.lag_row_open = true
          used += 1
          continue
        }
        let position = state.lag_position
        if position > 0 {
          let same = match
            bounded_row_comparison_step(
              state,
              indices[position - 1],
              indices[position],
              state.partition_terms,
            ) {
            Ok(Some(value)) => value == 0
            Ok(None) => {
              used += 1
              continue
            }
            Err(issue) =>
              return fail_bounded_binding_rows(
                Rows(ordering_row_issue(issue)),
                progress,
                used + 1,
              )
          }
          if !same {
            state.lag_partition_start = position
          }
        }
        let within = position - state.lag_partition_start
        if within.to_int64() >= offset {
          guard bounded_binding_input_cell(
              state.input,
              indices[position - offset.to_int()],
              source_column,
            )
            is Some(value) else {
            return fail_bounded_binding_rows(InvalidExecution, progress, used)
          }
          state.lag_values[indices[position]] = value
        }
        state.lag_position += 1
        state.lag_row_open = false
        used += 1
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
          if state.sort_measure is None {
            guard bounded_binding_input_cell(
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
              ) {
              return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
            }
            guard start_stepped_measure_result(value, state.workspace)
              is Some(cursor) else {
              return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
            }
            state.sort_measure = Some(cursor)
          }
          let cursor = state.sort_measure.unwrap()
          match advance_stepped_measure_result(cursor, state.output_values) {
            SteppedMeasureLimit | SteppedMeasureWorkspaceLimit =>
              return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
            SteppedMeasureContinue => ()
            SteppedMeasureComplete => {
              clear_stepped_measure(cursor)
              state.sort_measure = None
              state.sort_column += 1
            }
          }
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
        if state.watermark is Some((_, _, policy, threshold)) &&
          !state.watermark_checked {
          if !spend_control(state.control, 1) {
            return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
          }
          guard state.watermark_times.get(state.row) is Some(time) else {
            return fail_bounded_binding_rows(InvalidExecution, progress, used)
          }
          let watermark = match threshold {
            @lower.FixedWatermark(value) => value
            @lower.PrefixWatermark(skew, _) => {
              if !state.watermark_has_prefix ||
                time > state.watermark_prefix_max {
                state.watermark_prefix_max = time
                state.watermark_has_prefix = true
              }
              let value = state.watermark_prefix_max - skew.to_double()
              if value.is_nan() || value.is_inf() {
                return fail_bounded_binding_rows(
                  Rows(WindowArithmetic(state.row)),
                  progress,
                  used,
                )
              }
              if value == 0.0 {
                0.0
              } else {
                value
              }
            }
          }
          state.watermark_current = watermark
          state.watermark_late = time < watermark
          if state.watermark_late && policy is @relation.DropLate {
            state.row += 1
          } else {
            state.watermark_checked = true
          }
          used += 1
          continue
        }
        if state.partition_limit is Some(limit) && !state.partition_checked {
          if state.comparison.phase == -1 && !spend_control(state.control, 1) {
            return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
          }
          guard state.sorted_indices is Some(indices) else {
            return fail_bounded_binding_rows(InvalidExecution, progress, used)
          }
          let source = indices[state.row]
          let different = if state.partition_leader < 0 {
            true
          } else {
            match
              bounded_row_comparison_step(
                state,
                state.partition_leader,
                source,
                state.partition_terms,
              ) {
              Ok(Some(value)) => value != 0
              Ok(None) => {
                used += 1
                continue
              }
              Err(issue) =>
                return fail_bounded_binding_rows(
                  Rows(ordering_row_issue(issue)),
                  progress,
                  used + 1,
                )
            }
          }
          if different {
            state.partition_leader = source
            state.partition_taken = 0L
          }
          state.partition_checked = true
          used += 1
          if state.partition_taken >= limit {
            state.row += 1
            state.partition_checked = false
          } else {
            state.partition_taken += 1L
          }
          continue
        }
        if state.distinct {
          if !spend_control(state.control, 1) {
            return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
          }
          if !state.distinct_keep[state.row] {
            state.row += 1
            used += 1
            continue
          }
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
        state.phase = if state.json_path is Some(_) {
          PickJson
        } else if state.projection_ordinals is Some(_) {
          BuildOutputRow
        } else {
          SnapshotRow
        }
        used += 1
      }
      PickJson => {
        guard state.json_path is Some(path) else {
          return fail_bounded_binding_rows(InvalidExecution, progress, used)
        }
        if state.json_segment < 0 {
          guard bounded_binding_input_cell(
              state.input,
              state.row,
              state.json_source_column,
            )
            is Some(source) else {
            return fail_bounded_binding_rows(InvalidExecution, progress, used)
          }
          state.json_current = match source {
            Null => None
            Captured(value) => Some(value)
            _ =>
              return fail_bounded_binding_rows(
                Rows(InvalidRows),
                progress,
                used,
              )
          }
          state.json_segment = 0
          used += 1
          continue
        }
        if state.json_segment == path.length() {
          state.json_picked = Some(
            match state.json_current {
              None => Null
              Some(value) => capture(value)
            },
          )
          state.column = 0
          state.phase = BuildOutputRow
          used += 1
          continue
        }
        match state.json_current {
          None | Some(@admitted.Null) => {
            state.json_picked = Some(Null)
            state.column = 0
            state.phase = BuildOutputRow
            used += 1
          }
          Some(@admitted.Object(fields)) => {
            if state.json_field == @admitted.element_count(fields) {
              return fail_bounded_binding_rows(
                Rows(InvalidRows),
                progress,
                used,
              )
            }
            guard @admitted.element_at(fields, state.json_field)
              is Some((name, value)) else {
              return fail_bounded_binding_rows(InvalidExecution, progress, used)
            }
            if !state.json_name_open {
              if !spend_control(state.control, 1) {
                return fail_bounded_binding_rows(Rows(RowLimit), progress, used)
              }
              state.json_name_open = true
              used += 1
              continue
            }
            if state.json_name_offset < name.length() {
              let offset = state.json_name_offset
              let next = match
                bounded_text_charge_step(state.control, name, offset) {
                Ok(next) => next
                Err(_) =>
                  return fail_bounded_binding_rows(
                    Rows(RowLimit),
                    progress,
                    used,
                  )
              }
              let segment = path[state.json_segment]
              if next > segment.length() ||
                name[offset] != segment[offset] ||
                (next == offset + 2 && name[offset + 1] != segment[offset + 1]) {
                state.json_name_matches = false
              }
              state.json_name_offset = next
              used += 1
              continue
            }
            if state.json_name_matches &&
              name.length() == path[state.json_segment].length() {
              state.json_current = Some(value)
              state.json_segment += 1
              state.json_field = 0
            } else {
              state.json_field += 1
            }
            state.json_name_offset = 0
            state.json_name_open = false
            state.json_name_matches = true
            used += 1
          }
          Some(_) =>
            return fail_bounded_binding_rows(Rows(InvalidRows), progress, used)
        }
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
        guard bounded_binding_input_cell(state.input, state.row, state.column)
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
              Some(index) =>
                bounded_binding_input_cell(state.input, source_row, index)
              None =>
                if name == state.json_output_name {
                  state.json_picked
                } else if state.watermark is Some(_) {
                  match name {
                    "watermark_ms" => Some(Number(state.watermark_current))
                    "watermark_late" => Some(Boolean(state.watermark_late))
                    "watermark_decision" =>
                      Some(
                        Text(if state.watermark_late { "mark" } else { "keep" }),
                      )
                    _ => None
                  }
                } else if state.lag is Some((_, output, _)) && name == output {
                  state.lag_values.get(source_row)
                } else {
                  None
                }
            }
          None =>
            match state.binding_ordinals.get(name) {
              Some(index) => state.values.get(index)
              None =>
                match state.input_ordinals.get(name) {
                  Some(index) =>
                    bounded_binding_input_cell(state.input, state.row, index)
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
        state.json_current = None
        state.json_picked = None
        state.json_segment = -1
        state.json_field = 0
        state.json_name_offset = 0
        state.json_name_open = false
        state.json_name_matches = true
        state.watermark_checked = false
        state.row += 1
        state.partition_checked = false
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
        if state.watermark is Some(_) {
          release_slots(state.workspace, state.watermark_times.length())
          state.watermark_times = []
        }
        if state.lag_values_reserved {
          release_slots(state.workspace, state.lag_values.length())
          state.lag_values = []
          state.lag_values_reserved = false
        }
        if state.distinct {
          release_slots(state.workspace, state.distinct_keep.length())
          state.distinct_keep = []
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
  start_bounded_binding_rows_with_input(
    engine,
    generated,
    CompletedBindingInput(input),
    max_rows,
    input_values,
    values,
    max_work,
    max_frames,
    max_entries,
    max_name_bytes,
  )
}

///|
/// A supplied Local input keeps its own exact checked binding. It is not
/// converted into, or charged as, a completed upstream Relation.
pub fn start_bounded_binding_rows_supplied(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : SuppliedRelationRead,
  max_rows : Int,
  input_values : ValueLimits,
  values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedBindingRowsExecution, BoundedBindingRowsIssue] {
  start_bounded_binding_rows_with_input(
    engine,
    generated,
    SuppliedBindingInput(input),
    max_rows,
    input_values,
    values,
    max_work,
    max_frames,
    max_entries,
    max_name_bytes,
  )
}

///|
fn start_bounded_binding_rows_with_input(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : BoundedBindingInput,
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
    bounded_binding_input_matches(input, owner, step) &&
    bounded_binding_input_available(input) &&
    bounded_binding_input_row_count(input) <= max_rows &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(output_schema) else {
    return Err(InvalidExecution)
  }
  let input_schema = bounded_binding_input_schema(input)
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
  // Admit the copied typed view before reading it. Name arrays and ordinal
  // maps are admitted below using their actual sizes before construction.
  if !admit_metadata(binding_count) {
    return Err(InvalidExecution)
  }
  let body = @lower.kernel_body(kernel)
  let (bindings, ordered, predicate, select_mode, take_range, sort_kernel) = match
    body {
    @lower.OrderedBindings(bindings) =>
      (bindings, true, None, false, None, None)
    @lower.SnapshotMap(bindings) => (bindings, false, None, false, None, None)
    @lower.Filter(expression) =>
      ([], false, Some(expression), false, None, None)
    @lower.AssertAll(expression) =>
      ([], false, Some(expression), false, None, None)
    @lower.AssertUnique(_) => ([], false, None, false, None, None)
    @lower.JsonPick(_, _, _) => ([], false, None, false, None, None)
    @lower.Watermark(_, _, _, _) => ([], false, None, false, None, None)
    @lower.Lag(_, _) => ([], false, None, false, None, Some(kernel))
    @lower.Select(_) => ([], false, None, true, None, None)
    @lower.DistinctRows => ([], false, None, false, None, None)
    @lower.StableSort(_) =>
      (
        [],
        false,
        None,
        false,
        Some((0, bounded_binding_input_row_count(input))),
        Some(kernel),
      )
    @lower.TopK(top_count, _) => {
      if top_count < 1L {
        return Err(InvalidExecution)
      }
      let size = bounded_binding_input_row_count(input)
      let selected = if top_count >= size.to_int64() {
        size
      } else {
        top_count.to_int()
      }
      ([], false, None, false, Some((0, selected)), Some(kernel))
    }
    @lower.PartitionedTopK(top_count, _) => {
      if top_count < 1L {
        return Err(InvalidExecution)
      }
      (
        [],
        false,
        None,
        false,
        Some((0, bounded_binding_input_row_count(input))),
        Some(kernel),
      )
    }
    @lower.Limit(take_count, offset, _) => {
      let prepared = @lower.bound_preparation(owner)
      guard @lower.node_at(prepared, step) is Some(node) &&
        take_count > 0L &&
        offset >= 0L else {
        return Err(InvalidExecution)
      }
      let size = bounded_binding_input_row_count(input)
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
  if !admit_metadata(input_width) ||
    !admit_metadata(output_width) ||
    !admit_metadata(input_width) ||
    !admit_metadata(bindings.length()) {
    return Err(InvalidExecution)
  }
  let sort_only = body is @lower.StableSort(_) ||
    body is @lower.TopK(_, _) ||
    body is @lower.PartitionedTopK(_, _)
  let partition_limit = match body {
    @lower.PartitionedTopK(count, _) => Some(count)
    _ => None
  }
  let partition_terms = if body is @lower.Lag(_, _) {
    @lower.kernel_lag_partition_count(kernel)
  } else if partition_limit is Some(_) {
    @lower.kernel_top_k_partition_count(kernel)
  } else {
    0
  }
  let distinct = body is @lower.DistinctRows
  let assertion = body is @lower.AssertAll(_)
  let unique_keys = match body {
    @lower.AssertUnique(keys) => Some(keys)
    _ => None
  }
  let json_pick = match body {
    @lower.JsonPick(column, path, output) =>
      Some((@schema.reference_name(column), path, output))
    _ => None
  }
  let watermark_kind = body is @lower.Watermark(_, _, _, _)
  let lag_kind = body is @lower.Lag(_, _)
  if watermark_kind && output_width != input_width + 3 {
    return Err(InvalidExecution)
  }
  if lag_kind && output_width != input_width + 1 {
    return Err(InvalidExecution)
  }
  if json_pick is Some((_, path, _)) &&
    (path.is_empty() || output_width != input_width + 1) {
    return Err(InvalidExecution)
  }
  if unique_keys is Some(keys) && keys.is_empty() {
    return Err(InvalidExecution)
  }
  if take_range is None &&
    !select_mode &&
    !distinct &&
    unique_keys is None &&
    json_pick is None &&
    !watermark_kind &&
    !lag_kind &&
    bindings.length() != binding_count {
    return Err(InvalidExecution)
  }
  if (
      select_mode ||
      take_range is Some(_) ||
      distinct ||
      json_pick is Some(_) ||
      watermark_kind ||
      lag_kind
    ) &&
    !admit_metadata(output_width) {
    return Err(InvalidExecution)
  }
  if sort_kernel is Some(sort) &&
    (
      !admit_metadata(@lower.kernel_sort_term_count(sort)) ||
      !admit_metadata(partition_terms)
    ) {
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
  if !select_mode &&
    !distinct &&
    unique_keys is None &&
    take_range is None &&
    json_pick is None &&
    !watermark_kind &&
    !lag_kind {
    guard logical is Some(logical) else { return Err(InvalidExecution) }
    match
      admit_logical_rows(
        logical,
        bounded_binding_input_row_count(input).to_int64(),
      ) {
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
  let watermark = match body {
    @lower.Watermark(time, timestamp, policy, threshold) => {
      guard input_ordinals.get(@schema.reference_name(time)) is Some(column) else {
        return Err(InvalidExecution)
      }
      Some((column, timestamp, policy, threshold))
    }
    _ => None
  }
  let lag = if lag_kind {
    guard @lower.kernel_lag(kernel) is Some((field, output, offset)) &&
      input_ordinals.get(@schema.reference_name(field)) is Some(column) &&
      !input_ordinals.contains(output) &&
      output_names.contains(output) else {
      return Err(InvalidExecution)
    }
    Some((column, output, offset))
  } else {
    None
  }
  let binding_ordinals : Map[String, Int] = Map([])
  for index, binding in bindings {
    binding_ordinals[binding.0] = index
  }
  let projection_ordinals : Map[String, Int]? = match body {
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
    @lower.DistinctRows => {
      let projection : Map[String, Int] = Map([])
      match @lower.kernel_distinct_projection(kernel) {
        Some(view) =>
          for field in @lower.projection_fields(view) {
            let output_name = @schema.reference_name(field.output)
            guard input_ordinals.get(@schema.reference_name(field.input))
              is Some(index) &&
              !projection.contains(output_name) else {
              return Err(InvalidExecution)
            }
            projection[output_name] = index
          }
        None =>
          for name in output_names {
            guard input_ordinals.get(name) is Some(index) else {
              return Err(InvalidExecution)
            }
            projection[name] = index
          }
      }
      if projection.length() != output_width {
        return Err(InvalidExecution)
      }
      Some(projection)
    }
    @lower.StableSort(_)
    | @lower.TopK(_, _)
    | @lower.PartitionedTopK(_, _)
    | @lower.Limit(_, _, _)
    | @lower.AssertUnique(_) => {
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
    @lower.JsonPick(source, _, output) => {
      let projection : Map[String, Int] = Map([])
      let source_name = @schema.reference_name(source)
      if input_ordinals.get(source_name) is None ||
        input_ordinals.contains(output) ||
        output_names[output_width - 1] != output {
        return Err(InvalidExecution)
      }
      for name in input_names {
        guard input_ordinals.get(name) is Some(index) else {
          return Err(InvalidExecution)
        }
        projection[name] = index
      }
      Some(projection)
    }
    @lower.Watermark(_, _, _, _) => {
      let projection : Map[String, Int] = Map([])
      for name in input_names {
        guard input_ordinals.get(name) is Some(index) else {
          return Err(InvalidExecution)
        }
        projection[name] = index
      }
      if !output_names.contains("watermark_ms") ||
        !output_names.contains("watermark_late") ||
        !output_names.contains("watermark_decision") {
        return Err(InvalidExecution)
      }
      Some(projection)
    }
    @lower.Lag(_, _) => {
      let projection : Map[String, Int] = Map([])
      for name in input_names {
        guard input_ordinals.get(name) is Some(index) else {
          return Err(InvalidExecution)
        }
        projection[name] = index
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
    prepare_trusted_output_port_with_inputs(
      generated_completion_preparation(generated),
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=[bounded_binding_trusted_input(input)],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let control : ControlBudget = { remaining: max_work, max_frames, }
  let workspace = row_workspace(max_entries)
  if !reserve_slots(workspace, metadata_entries) ||
    (
      watermark_kind &&
      !reserve_slots(workspace, bounded_binding_input_row_count(input))
    ) {
    cancel_admitted_output(output) |> ignore
    return Err(Rows(RowLimit))
  }
  let state : BoundedBindingRowsState = {
    input,
    available: fn() { bounded_binding_input_available(input) },
    bindings,
    predicate,
    assertion,
    unique_keys,
    distinct,
    distinct_keep: [],
    distinct_cursor: 0,
    input_names,
    output_names,
    input_ordinals,
    binding_ordinals,
    projection_ordinals,
    json_path: match json_pick {
      Some((_, path, _)) => Some(path)
      None => None
    },
    json_source_column: match json_pick {
      Some((source, _, _)) => input_ordinals.get(source).unwrap_or(-1)
      None => -1
    },
    json_output_name: match json_pick {
      Some((_, _, output)) => output
      None => ""
    },
    watermark,
    watermark_times: [],
    watermark_prefix_max: 0.0,
    watermark_has_prefix: false,
    watermark_checked: false,
    watermark_current: 0.0,
    watermark_late: false,
    lag,
    lag_values: [],
    lag_values_reserved: false,
    lag_position: 0,
    lag_partition_start: 0,
    lag_row_open: false,
    json_current: None,
    json_picked: None,
    json_segment: -1,
    json_field: 0,
    json_name_offset: 0,
    json_name_open: false,
    json_name_matches: true,
    take_range,
    partition_limit,
    partition_terms,
    partition_leader: -1,
    partition_taken: 0L,
    partition_checked: false,
    comparison: {
      left: -1,
      right: -1,
      terms: 0,
      term: 0,
      phase: -1,
      offset: 0,
    },
    sort_kernel,
    sort_only,
    engine,
    sort_orders: [],
    sort_execution: None,
    sorted_indices: None,
    sort_row: 0,
    sort_column: 0,
    sort_charge_open: false,
    sort_measure: None,
    unique_key: 0,
    unique_row: -1,
    unique_pair: 1,
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
    phase: if distinct {
      PrepareDistinctTerms
    } else if unique_keys is Some(_) {
      CheckUniqueKeys
    } else {
      ChargeInput
    },
    charge_row: 0,
    charge_column: 0,
    charge_open: false,
    charge_measure: None,
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
  Ok({ state, session, token: Some(token), accepted, })
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
