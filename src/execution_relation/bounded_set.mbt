///|
/// Checked complete-row EXCEPT/INTERSECT over two managed reads. Input
/// admission, field resolution, both private complete-row orders, the
/// sort-merge survivor selection and output construction advance one bounded
/// step at a time. Survivors are emitted in left logical order, as the
/// synchronous `evaluate_set_rows` does. Text comparison pays one UTF-8 byte
/// per advance; admitted arrays, objects and vectors retain accounted frames
/// and expose their recursive traversal between advances.
priv enum BoundedSetPhase {
  ChargeInput
  Metadata
  ResolveField
  Seed
  SortLeft
  SortRight
  InitKeep
  Merge
  BeginRow
  BuildCell
  CommitRow
  FinishOutput
  Terminal
}

///|
/// One complete-row comparison, one column step per advance.
priv struct BoundedSetRowComparison {
  mut column : Int
  value : BoundedCompleteValueComparison
  mut tree : BoundedCompleteTreeComparison?
}

///|
priv struct BoundedSetState {
  left : ProducerRead
  right : ProducerRead
  kernel : @lower.PreparedSetKernel
  output_schema : @schema.Schema
  max_rows : Int
  control : ControlBudget
  workspace : RowWorkspace
  input_scan : BoundedBinaryInputScan
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  names : Array[String]
  left_columns : Array[Int]
  right_columns : Array[Int]
  comparison : BoundedSetRowComparison
  mut phase : BoundedSetPhase
  mut field : Int
  name_charge : BoundedTextCharge
  mut sorter : AggregateMergeSort[Int]?
  mut seed : Array[Int]
  mut seed_left : Bool
  mut left_order : Array[Int]
  mut right_order : Array[Int]
  keep : Array[Bool]
  // Sort-merge coordinates.
  mut merge_phase : Int
  mut left_position : Int
  mut left_end : Int
  mut right_position : Int
  mut right_next : Int
  mut right_count : Int
  mut marked : Int
  mut selected : Int
  // Output.
  mut output_row : Int
  mut emitted : Int
  mut column : Int
  mut checked_row : Array[@admitted.Value]
  mut output_recheck : @admitted.RecheckCursor?
  mut output_charge : BoundedOutputRowCharge?
}

///|
pub(all) enum BoundedSetIssue {
  InvalidExecution
  InputLimit
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedSetExecution {
  session : @bounded.Session[BoundedSetState, CompletedOutput, BoundedSetIssue]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  state : BoundedSetState
}

///|
pub enum BoundedSetPoll {
  BoundedSetContinue(progress~ : Int64, work~ : Int64)
  BoundedSetComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedSetFailed(BoundedSetIssue, progress~ : Int64, work~ : Int64)
  BoundedSetStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn bounded_set_failure(
  issue : BoundedSetIssue,
  progress : Int,
  work : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedSetIssue] {
  @bounded.Failed(issue, progress, work)
}

///|
fn cleanup_bounded_set_state(state : BoundedSetState) -> Bool {
  if state.comparison.tree is Some(cursor) {
    close_complete_tree_comparison(cursor)
    state.comparison.tree = None
  }
  cleanup_binary_input_scan(state.input_scan)
  if state.output_recheck is Some(cursor) {
    @admitted.cancel_recheck_runtime_value(cursor)
    state.output_recheck = None
  }
  if state.output_charge is Some(cursor) {
    cleanup_bounded_output_row_charge(cursor)
    state.output_charge = None
  }
  if state.sorter is Some(sorter) {
    close_aggregate_merge_sort(sorter)
    state.sorter = None
  }
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.left_order = []
  state.right_order = []
  state.keep.clear()
  state.checked_row = []
  release_slots(state.workspace, state.workspace.live)
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
/// Compare two complete rows, one column comparison step per advance.
fn bounded_set_compare_step(
  state : BoundedSetState,
  left : ProducerRead,
  left_row : Int,
  left_columns : Array[Int],
  right : ProducerRead,
  right_row : Int,
  right_columns : Array[Int],
) -> Result[Int?, RowIssue] {
  let cursor = state.comparison
  if cursor.column >= left_columns.length() {
    cursor.column = 0
    return Ok(Some(0))
  }
  guard producer_read_cell(left, left_row, left_columns[cursor.column])
    is Some(a) &&
    producer_read_cell(right, right_row, right_columns[cursor.column])
    is Some(b) else {
    return Err(InvalidRows)
  }
  if cursor.tree is None &&
    a is Captured(left) &&
    b is Captured(right) &&
    (match (left, right) {
      (@admitted.Array(_), @admitted.Array(_))
      | (@admitted.Object(_), @admitted.Object(_))
      | (@admitted.Vector(_), @admitted.Vector(_)) => true
      _ => false
    }) {
    match
      start_complete_tree_comparison(
        left,
        right,
        state.control,
        state.workspace,
      ) {
      Ok(value) => cursor.tree = Some(value)
      Err(issue) => return Err(ordering_row_issue(issue))
    }
  }
  let compared = match cursor.tree {
    Some(tree) => advance_complete_tree_comparison(tree, state.control)
    None =>
      bounded_complete_value_comparison_step(cursor.value, a, b, state.control)
  }
  if compared is Ok(Some(_)) && cursor.tree is Some(tree) {
    close_complete_tree_comparison(tree)
    cursor.tree = None
  }
  match compared {
    Err(issue) => Err(ordering_row_issue(issue))
    Ok(None) => Ok(None)
    Ok(Some(0)) => {
      cursor.column += 1
      Ok(None)
    }
    Ok(Some(order)) => {
      cursor.column = 0
      Ok(Some(order))
    }
  }
}

///|
/// Begin seeding one side's row coordinates; the merge sort starts once the
/// seed holds every row. Source, target and seed coordinates stay reserved.
fn bounded_set_begin_seed(state : BoundedSetState, left : Bool) -> Bool {
  let read = if left { state.left } else { state.right }
  let count = producer_read_row_count(read)
  if !reserve_slots(state.workspace, count) ||
    !reserve_slots(state.workspace, count) ||
    !reserve_slots(state.workspace, count) {
    return false
  }
  state.seed = []
  state.seed_left = left
  state.phase = Seed
  true
}

///|
fn bounded_set_start_sort(state : BoundedSetState) -> Unit {
  let left = state.seed_left
  let read = if left { state.left } else { state.right }
  let columns = if left { state.left_columns } else { state.right_columns }
  state.sorter = Some(
    start_aggregate_merge_sort(state.seed, (a, b) => {
      bounded_set_compare_step(state, read, a, columns, read, b, columns)
    }),
  )
  state.seed = []
  state.phase = if left { SortLeft } else { SortRight }
}

///|
/// One sort-merge step. Returns true once every left group has been decided.
fn bounded_set_merge_step(state : BoundedSetState) -> Result[Bool, RowIssue] {
  let left_count = state.left_order.length()
  let right_count = state.right_order.length()
  match state.merge_phase {
    // Start the next left group.
    0 => {
      if state.left_position >= left_count {
        return Ok(true)
      }
      state.left_end = state.left_position + 1
      state.merge_phase = 1
      Ok(false)
    }
    // Extend the left group of equal rows.
    1 => {
      if state.left_end >= left_count {
        state.merge_phase = 2
        return Ok(false)
      }
      match
        bounded_set_compare_step(
          state,
          state.left,
          state.left_order[state.left_position],
          state.left_columns,
          state.left,
          state.left_order[state.left_end],
          state.left_columns,
        ) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(false)
        Ok(Some(0)) => {
          state.left_end += 1
          Ok(false)
        }
        Ok(Some(_)) => {
          state.merge_phase = 2
          Ok(false)
        }
      }
    }
    // Skip right groups ordered before the left group.
    2 => {
      if state.right_position >= right_count {
        state.right_count = 0
        state.merge_phase = 5
        return Ok(false)
      }
      match
        bounded_set_compare_step(
          state,
          state.left,
          state.left_order[state.left_position],
          state.left_columns,
          state.right,
          state.right_order[state.right_position],
          state.right_columns,
        ) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(false)
        Ok(Some(order)) => {
          if order < 0 {
            state.right_count = 0
            state.merge_phase = 5
          } else if order == 0 {
            state.right_next = state.right_position + 1
            state.merge_phase = 4
          } else {
            state.right_next = state.right_position + 1
            state.merge_phase = 3
          }
          Ok(false)
        }
      }
    }
    // Skip one smaller right group.
    3 => {
      if state.right_next >= right_count {
        state.right_position = state.right_next
        state.merge_phase = 2
        return Ok(false)
      }
      match
        bounded_set_compare_step(
          state,
          state.right,
          state.right_order[state.right_position],
          state.right_columns,
          state.right,
          state.right_order[state.right_next],
          state.right_columns,
        ) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(false)
        Ok(Some(0)) => {
          state.right_next += 1
          Ok(false)
        }
        Ok(Some(_)) => {
          state.right_position = state.right_next
          state.merge_phase = 2
          Ok(false)
        }
      }
    }
    // Extend the equal right group.
    4 => {
      let finish = fn() {
        state.right_count = state.right_next - state.right_position
        state.right_position = state.right_next
        state.merge_phase = 5
      }
      if state.right_next >= right_count {
        finish()
        return Ok(false)
      }
      match
        bounded_set_compare_step(
          state,
          state.right,
          state.right_order[state.right_position],
          state.right_columns,
          state.right,
          state.right_order[state.right_next],
          state.right_columns,
        ) {
        Err(issue) => Err(issue)
        Ok(None) => Ok(false)
        Ok(Some(0)) => {
          state.right_next += 1
          Ok(false)
        }
        Ok(Some(_)) => {
          finish()
          Ok(false)
        }
      }
    }
    // Decide how many left occurrences survive.
    5 => {
      let group = state.left_end - state.left_position
      state.selected = match
        (
          @lower.set_kernel_operation(state.kernel),
          @lower.set_kernel_duplicates(state.kernel),
        ) {
        (@set.Except, @set.All) => Int::max(group - state.right_count, 0)
        (@set.Intersect, @set.All) => Int::min(group, state.right_count)
        (@set.Except, @set.Distinct) =>
          if state.right_count == 0 {
            1
          } else {
            0
          }
        (@set.Intersect, @set.Distinct) =>
          if state.right_count > 0 {
            1
          } else {
            0
          }
      }
      state.marked = 0
      state.merge_phase = 6
      Ok(false)
    }
    // Mark one survivor per advance.
    _ => {
      if state.marked < state.selected {
        state.keep[state.left_order[state.left_position + state.marked]] = true
        state.marked += 1
        return Ok(false)
      }
      state.left_position = state.left_end
      state.merge_phase = 0
      Ok(false)
    }
  }
}

///|
fn bounded_set_step(
  state : BoundedSetState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedSetIssue] {
  let mut used = 0
  let mut progress = 0
  let width = @lower.set_kernel_field_count(state.kernel)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !producer_read_available(state.left) ||
      !producer_read_available(state.right) {
      return bounded_set_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      ChargeInput => {
        match advance_binary_input_scan(state.input_scan) {
          Ok(true) => state.phase = Metadata
          Ok(false) => ()
          Err(ValueLimit) =>
            return bounded_set_failure(InputLimit, progress, used + 1)
          Err(ControlLimit) | Err(WorkspaceLimit) =>
            return bounded_set_failure(Rows(RowLimit), progress, used + 1)
          Err(InputUnavailable) =>
            return bounded_set_failure(InvalidExecution, progress, used + 1)
        }
        used += 1
      }
      Metadata => {
        if !reserve_set_metadata(state.workspace, width) {
          return bounded_set_failure(Rows(RowLimit), progress, used + 1)
        }
        state.phase = ResolveField
        used += 1
      }
      ResolveField => {
        if state.field == width {
          if !bounded_set_begin_seed(state, true) {
            return bounded_set_failure(Rows(RowLimit), progress, used + 1)
          }
          used += 1
          continue
        }
        guard @lower.set_kernel_field_at(state.kernel, state.field)
          is Some((field, left_column, right_column)) &&
          @schema.field_at(producer_read_schema(state.left), left_column)
          is Some(left_field) &&
          @schema.field_at(producer_read_schema(state.right), right_column)
          is Some(right_field) else {
          return bounded_set_failure(Rows(InputMismatch), progress, used)
        }
        let name = @schema.reference_name(field)
        if @schema.reference_name(left_field.name) != name ||
          @schema.reference_name(right_field.name) != name {
          return bounded_set_failure(Rows(InputMismatch), progress, used)
        }
        // One field entry unit, then its name one UTF-8 byte per advance.
        if state.names.length() == state.field {
          if !spend_control(state.control, 1) {
            return bounded_set_failure(Rows(RowLimit), progress, used + 1)
          }
          state.names.push(name)
          used += 1
          continue
        }
        match
          advance_bounded_text_charge(state.name_charge, state.control, name) {
          Err(_) =>
            return bounded_set_failure(Rows(RowLimit), progress, used + 1)
          Ok(false) => ()
          Ok(true) => {
            reset_bounded_text_charge(state.name_charge)
            state.left_columns.push(left_column)
            state.right_columns.push(right_column)
            state.field += 1
          }
        }
        used += 1
      }
      Seed => {
        let read = if state.seed_left { state.left } else { state.right }
        if state.seed.length() < producer_read_row_count(read) {
          if !spend_control(state.control, 1) {
            return bounded_set_failure(Rows(RowLimit), progress, used + 1)
          }
          state.seed.push(state.seed.length())
        } else {
          bounded_set_start_sort(state)
        }
        used += 1
      }
      SortLeft | SortRight => {
        guard state.sorter is Some(sorter) else {
          return bounded_set_failure(InvalidExecution, progress, used)
        }
        // A recursive comparison resumes the same logical merge action.
        // Charge that action once, not once per newly exposed tree frame.
        if state.comparison.tree is None && !spend_control(state.control, 1) {
          return bounded_set_failure(Rows(RowLimit), progress, used + 1)
        }
        match advance_aggregate_merge_sort(sorter) {
          Err(issue) => {
            state.sorter = None
            return bounded_set_failure(Rows(issue), progress, used + 1)
          }
          Ok(None) => ()
          Ok(Some(order)) => {
            state.sorter = None
            if state.phase is SortLeft {
              state.left_order = order
              if !bounded_set_begin_seed(state, false) {
                return bounded_set_failure(Rows(RowLimit), progress, used + 1)
              }
            } else {
              state.right_order = order
              if !reserve_slots(state.workspace, state.left_order.length()) {
                return bounded_set_failure(Rows(RowLimit), progress, used + 1)
              }
              state.phase = InitKeep
            }
          }
        }
        used += 1
      }
      InitKeep => {
        if state.keep.length() < state.left_order.length() {
          if !spend_control(state.control, 1) {
            return bounded_set_failure(Rows(RowLimit), progress, used + 1)
          }
          state.keep.push(false)
        } else {
          state.phase = Merge
        }
        used += 1
      }
      Merge => {
        match bounded_set_merge_step(state) {
          Err(issue) =>
            return bounded_set_failure(Rows(issue), progress, used + 1)
          Ok(true) => state.phase = BeginRow
          Ok(false) => ()
        }
        used += 1
      }
      BeginRow => {
        if state.output_row >= state.keep.length() {
          state.phase = FinishOutput
          continue
        }
        // Skip one non-surviving left row per advance.
        if !state.keep[state.output_row] {
          state.output_row += 1
          used += 1
          continue
        }
        if state.emitted >= state.max_rows ||
          !spend_control(state.control, 1) ||
          !reserve_slots(state.workspace, width) {
          return bounded_set_failure(Rows(RowLimit), progress, used + 1)
        }
        state.column = 0
        state.checked_row = []
        state.phase = BuildCell
        used += 1
      }
      BuildCell => {
        if state.output_recheck is Some(cursor) {
          match @admitted.advance_recheck_runtime_value(cursor) {
            RecheckContinue => ()
            RecheckFailed =>
              return bounded_set_failure(
                Rows(InputMismatch),
                progress,
                used + 1,
              )
            RecheckComplete(checked, _, _) => {
              state.output_recheck = None
              state.checked_row.push(checked.value)
              state.column += 1
            }
          }
          used += 1
          continue
        }
        if state.column == width {
          state.phase = CommitRow
          continue
        }
        guard producer_read_cell(
            state.left,
            state.output_row,
            state.left_columns[state.column],
          )
          is Some(value) &&
          @schema.field_at(state.output_schema, state.column) is Some(field) else {
          return bounded_set_failure(InvalidExecution, progress, used)
        }
        if !spend_control(state.control, 1) {
          return bounded_set_failure(Rows(RowLimit), progress, used + 1)
        }
        if bounded_small_output_value(value) {
          guard checked_ordered_output_value(
              value,
              field.contract,
              state.admitted_limits,
            )
            is Some(checked) else {
            return bounded_set_failure(Rows(InputMismatch), progress, used + 1)
          }
          state.checked_row.push(checked.value)
          state.column += 1
        } else {
          guard start_ordered_output_value_recheck(
              value,
              field.contract,
              state.admitted_limits,
            )
            is Some(cursor) else {
            return bounded_set_failure(Rows(InputMismatch), progress, used + 1)
          }
          state.output_recheck = Some(cursor)
        }
        used += 1
      }
      CommitRow => {
        guard state.output is Some(output) else {
          return bounded_set_failure(InvalidExecution, progress, used)
        }
        if state.output_charge is None {
          match
            start_bounded_output_row_charge(
              output,
              state.checked_row,
              state.workspace,
            ) {
            Err(OutputCapture(issue)) =>
              return bounded_set_failure(Capture(issue), progress, used + 1)
            Err(OutputWorkspace) =>
              return bounded_set_failure(Rows(RowLimit), progress, used + 1)
            Ok(cursor) => state.output_charge = Some(cursor)
          }
          used += 1
          continue
        }
        match advance_bounded_output_row_charge(state.output_charge.unwrap()) {
          Err(OutputCapture(issue)) =>
            return bounded_set_failure(Capture(issue), progress, used + 1)
          Err(OutputWorkspace) =>
            return bounded_set_failure(Rows(RowLimit), progress, used + 1)
          Ok(false) => {
            used += 1
            continue
          }
          Ok(true) => state.output_charge = None
        }
        release_slots(state.workspace, state.checked_row.length())
        state.checked_row = []
        state.output_row += 1
        state.emitted += 1
        state.phase = BeginRow
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return bounded_set_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return bounded_set_failure(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => bounded_set_failure(Completion(issue), progress, used)
        }
      }
      Terminal => return bounded_set_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
pub fn start_bounded_set(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  left : ProducerRead,
  right : ProducerRead,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedSetExecution, BoundedSetIssue] {
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
    is Some(@lower.SetStep(kernel)) &&
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
  if producer_read_row_count(left) > max_rows ||
    producer_read_row_count(right) > max_rows {
    return Err(Rows(RowLimit))
  }
  let width = @lower.set_kernel_field_count(kernel)
  if width != @schema.field_count(output_schema) ||
    width > @schema.field_count(producer_read_schema(left)) ||
    width > @schema.field_count(producer_read_schema(right)) {
    return Err(Rows(RowLimit))
  }
  let workspace = row_workspace(max_entries)
  let control : ControlBudget = { remaining: max_work, max_frames, }
  guard binary_input_scan(left, right, input_values, control, workspace)
    is Some(input_scan) else {
    return Err(InvalidExecution)
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
  let state : BoundedSetState = {
    left,
    right,
    kernel,
    output_schema,
    max_rows,
    control,
    workspace,
    input_scan,
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
    left_columns: [],
    right_columns: [],
    comparison: {
      column: 0,
      value: bounded_complete_value_comparison(),
      tree: None,
    },
    phase: ChargeInput,
    field: 0,
    name_charge: { offset: 0, next: 0, remaining: 0, },
    sorter: None,
    seed: [],
    seed_left: true,
    left_order: [],
    right_order: [],
    keep: [],
    merge_phase: 0,
    left_position: 0,
    left_end: 0,
    right_position: 0,
    right_next: 0,
    right_count: 0,
    marked: 0,
    selected: 0,
    output_row: 0,
    emitted: 0,
    column: 0,
    checked_row: [],
    output_recheck: None,
    output_charge: None,
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_set_step,
    cleanup_bounded_set_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, state, })
}

///|
pub fn advance_bounded_set(
  value : BoundedSetExecution,
  quantum : Int,
) -> Result[BoundedSetPoll, BoundedSetIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedSetContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedSetComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedSetFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedSetStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_set(
  value : BoundedSetExecution,
) -> Result[Bool, BoundedSetIssue] {
  let changed = match @bounded.cleanup(value.session) {
    Ok(changed) => changed
    Err(issue) => return Err(Execution(issue))
  }
  if !@bounded.cleanup_pending(value.session) &&
    (
      value.state.input_scan.frames.length() != 0 ||
      value.state.comparison.tree is Some(_) ||
      value.state.workspace.live != 0
    ) {
    return Err(InvalidExecution)
  }
  Ok(changed)
}
