///|
priv enum BoundedAsOfPhase {
  ValidateIdentity
  StartIdentitySort
  IdentitySort
  CheckUnique
  ReadLeftClocks
  ReadRightClocks
  StartOutputSort
  OutputSort
  CompareKey
  EvaluateCandidate
  CompareTie
  FinishLeft
  BuildOutputRow
  CheckOutputRow
  CommitOutputRow
  FinishOutput
  Terminal
}

///|
priv struct BoundedAsOfState {
  left : ProducerRead
  right : ProducerRead
  left_time : Int
  right_time : Int
  keys : Array[(Int, Int)]
  identities : Array[Int]
  ties : Array[Int]
  columns : Array[(Bool, Int)]
  output_schema : @schema.Schema
  kind : @join.Kind
  direction : @asof.AsOfDirection
  tolerance : Int64
  left_timestamp : Bool
  right_timestamp : Bool
  search_ceiling : Int64
  output_ceiling : Int
  engine : @bounded.Control
  control : ControlBudget
  workspace : RowWorkspace
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut phase : BoundedAsOfPhase
  mut identity_field : Int
  mut identity_row : Int
  mut sort : BoundedIndexSort?
  mut identity_order : Array[Int]
  mut ordered_left : Array[Int]
  mut unique_index : Int
  mut left_clocks : Array[Int64]
  mut right_clocks : Array[Int64]
  mut clock_row : Int
  mut ordered_index : Int
  mut left_row : Int
  mut right_row : Int
  mut key_index : Int
  mut tie_index : Int
  mut visited : Int64
  mut best : Int?
  mut best_distance : Int64
  mut best_tied_with : Int?
  mut candidate : Int
  mut emitted : Int
  mut column : Int
  mut output_row : Array[Value]
  mut checked_row : Array[@admitted.CheckedValue]
}

///|
pub(all) enum BoundedAsOfJoinIssue {
  InvalidExecution
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedAsOfJoinExecution {
  session : @bounded.Session[
    BoundedAsOfState,
    CompletedOutput,
    BoundedAsOfJoinIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum BoundedAsOfJoinPoll {
  BoundedAsOfJoinContinue(progress~ : Int64, work~ : Int64)
  BoundedAsOfJoinComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedAsOfJoinFailed(BoundedAsOfJoinIssue, progress~ : Int64, work~ : Int64)
  BoundedAsOfJoinStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn bounded_asof_failure(
  issue : BoundedAsOfJoinIssue,
  progress : Int,
  work : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedAsOfJoinIssue] {
  @bounded.Failed(issue, progress, work)
}

///|
fn cleanup_bounded_asof_state(state : BoundedAsOfState) -> Bool {
  if state.sort is Some(active) {
    cleanup_bounded_index_sort(active) |> ignore
    state.sort = None
  }
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.identity_order = []
  state.ordered_left = []
  state.left_clocks = []
  state.right_clocks = []
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
fn bounded_asof_inputs_available(state : BoundedAsOfState) -> Bool {
  producer_read_available(state.left) && producer_read_available(state.right)
}

///|
fn bounded_asof_compare_columns(
  input : ProducerRead,
  first : Int,
  second : Int,
  columns : Array[Int],
  control : ControlBudget,
  nulls_last : Bool,
) -> Result[Int, RowIssue] {
  for column in columns {
    guard producer_read_cell(input, first, column) is Some(left) &&
      producer_read_cell(input, second, column) is Some(right) else {
      return Err(InvalidRows)
    }
    let left_null = asof_null(left)
    let right_null = asof_null(right)
    if left_null || right_null {
      if !spend_control(control, 1) {
        return Err(RowLimit)
      }
      if left_null != right_null {
        return Ok(if left_null == nulls_last { 1 } else { -1 })
      }
    }
    match compare_complete_value(left, right, control) {
      Ok(0) => ()
      Ok(value) => return Ok(value)
      Err(issue) => return Err(ordering_row_issue(issue))
    }
  }
  Ok(0)
}

///|
fn bounded_asof_start_sort(
  state : BoundedAsOfState,
  compare : (Int, Int) -> Result[Int, RowIssue],
) -> Bool {
  let count = producer_read_row_count(state.left)
  if count > (state.workspace.limit - state.workspace.live) / 2 ||
    !reserve_slots(state.workspace, count * 2) {
    return false
  }
  state.sort = start_bounded_index_sort(state.engine, count, compare)
  state.sort is Some(_)
}

///|
fn bounded_asof_schedule_output(state : BoundedAsOfState) -> Bool {
  if state.emitted >= state.output_ceiling {
    return false
  }
  state.column = 0
  state.output_row = []
  state.checked_row = []
  state.phase = BuildOutputRow
  true
}

///|
fn bounded_asof_next_left(state : BoundedAsOfState) -> Unit {
  state.ordered_index += 1
  state.right_row = 0
  state.key_index = 0
  state.tie_index = 0
  state.best = None
  state.best_distance = 0L
  state.best_tied_with = None
  state.phase = CompareKey
}

///|
fn bounded_asof_step(
  state : BoundedAsOfState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedAsOfJoinIssue] {
  let mut used = 0
  let mut progress = 0
  let left_count = producer_read_row_count(state.left)
  let right_count = producer_read_row_count(state.right)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !bounded_asof_inputs_available(state) {
      return bounded_asof_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      ValidateIdentity => {
        if state.identity_field == state.identities.length() {
          state.phase = StartIdentitySort
          continue
        }
        if state.identity_row == left_count {
          state.identity_field += 1
          state.identity_row = 0
          continue
        }
        guard producer_read_cell(
            state.left,
            state.identity_row,
            state.identities[state.identity_field],
          )
          is Some(value) else {
          return bounded_asof_failure(InvalidExecution, progress, used)
        }
        if asof_null(value) {
          return bounded_asof_failure(
            Rows(AssertionNullKey(state.identity_row, state.identity_field)),
            progress,
            used + 1,
          )
        }
        state.identity_row += 1
        used += 1
        progress += 1
      }
      StartIdentitySort => {
        if !bounded_asof_start_sort(state, fn(first, second) {
            bounded_asof_compare_columns(
              state.left,
              first,
              second,
              state.identities,
              state.control,
              true,
            )
          }) {
          return bounded_asof_failure(Rows(RowLimit), progress, used)
        }
        state.phase = IdentitySort
        used += 1
      }
      IdentitySort => {
        guard state.sort is Some(active) else {
          return bounded_asof_failure(InvalidExecution, progress, used)
        }
        match advance_bounded_index_sort(active, 1) {
          Ok(BoundedIndexSortContinue) => {
            used += 1
            progress += 1
          }
          Ok(BoundedIndexSortComplete(indices)) => {
            cleanup_bounded_index_sort(active) |> ignore
            state.sort = None
            release_slots(state.workspace, left_count)
            state.identity_order = indices
            state.unique_index = 1
            state.phase = CheckUnique
            used += 1
          }
          Ok(BoundedIndexSortFailed(issue)) | Err(issue) =>
            return bounded_asof_failure(Rows(issue), progress, used + 1)
          Ok(BoundedIndexSortStopped(reason)) =>
            return @bounded.Stopped(reason, progress, used + 1)
        }
      }
      CheckUnique => {
        if state.unique_index == state.identity_order.length() {
          state.identity_order = []
          release_slots(state.workspace, left_count)
          state.phase = ReadLeftClocks
          continue
        }
        let first = state.identity_order[state.unique_index - 1]
        let second = state.identity_order[state.unique_index]
        match
          bounded_asof_compare_columns(
            state.left,
            first,
            second,
            state.identities,
            state.control,
            true,
          ) {
          Ok(0) =>
            return bounded_asof_failure(
              Rows(AssertionDuplicate(first, second)),
              progress,
              used + 1,
            )
          Ok(_) => ()
          Err(issue) =>
            return bounded_asof_failure(Rows(issue), progress, used + 1)
        }
        state.unique_index += 1
        used += 1
        progress += 1
      }
      ReadLeftClocks => {
        if state.clock_row == left_count {
          state.clock_row = 0
          state.phase = ReadRightClocks
          continue
        }
        guard producer_read_cell(state.left, state.clock_row, state.left_time)
          is Some(raw) else {
          return bounded_asof_failure(InvalidExecution, progress, used)
        }
        match interval_clock(raw, state.left_timestamp, state.control) {
          Ok(value) => state.left_clocks.push(value)
          Err(issue) =>
            return bounded_asof_failure(Rows(issue), progress, used + 1)
        }
        state.clock_row += 1
        used += 1
        progress += 1
      }
      ReadRightClocks => {
        if state.clock_row == right_count {
          state.clock_row = 0
          state.phase = StartOutputSort
          continue
        }
        guard producer_read_cell(state.right, state.clock_row, state.right_time)
          is Some(raw) else {
          return bounded_asof_failure(InvalidExecution, progress, used)
        }
        match interval_clock(raw, state.right_timestamp, state.control) {
          Ok(value) => state.right_clocks.push(value)
          Err(issue) =>
            return bounded_asof_failure(Rows(issue), progress, used + 1)
        }
        state.clock_row += 1
        used += 1
        progress += 1
      }
      StartOutputSort => {
        if !bounded_asof_start_sort(state, fn(first, second) {
            if state.left_clocks[first] < state.left_clocks[second] {
              Ok(-1)
            } else if state.left_clocks[first] > state.left_clocks[second] {
              Ok(1)
            } else {
              bounded_asof_compare_columns(
                state.left,
                first,
                second,
                state.identities,
                state.control,
                true,
              )
            }
          }) {
          return bounded_asof_failure(Rows(RowLimit), progress, used)
        }
        state.phase = OutputSort
        used += 1
      }
      OutputSort => {
        guard state.sort is Some(active) else {
          return bounded_asof_failure(InvalidExecution, progress, used)
        }
        match advance_bounded_index_sort(active, 1) {
          Ok(BoundedIndexSortContinue) => {
            used += 1
            progress += 1
          }
          Ok(BoundedIndexSortComplete(indices)) => {
            cleanup_bounded_index_sort(active) |> ignore
            state.sort = None
            release_slots(state.workspace, left_count)
            state.ordered_left = indices
            state.ordered_index = 0
            state.phase = CompareKey
            used += 1
          }
          Ok(BoundedIndexSortFailed(issue)) | Err(issue) =>
            return bounded_asof_failure(Rows(issue), progress, used + 1)
          Ok(BoundedIndexSortStopped(reason)) =>
            return @bounded.Stopped(reason, progress, used + 1)
        }
      }
      CompareKey => {
        if state.ordered_index == state.ordered_left.length() {
          state.phase = FinishOutput
          continue
        }
        state.left_row = state.ordered_left[state.ordered_index]
        if state.right_row == right_count {
          state.phase = FinishLeft
          continue
        }
        if state.visited >= state.search_ceiling {
          return bounded_asof_failure(Rows(RowLimit), progress, used)
        }
        if state.key_index == state.keys.length() {
          state.phase = EvaluateCandidate
          continue
        }
        let pair = state.keys[state.key_index]
        guard producer_read_cell(state.left, state.left_row, pair.0)
          is Some(left_value) &&
          producer_read_cell(state.right, state.right_row, pair.1)
          is Some(right_value) else {
          return bounded_asof_failure(InvalidExecution, progress, used)
        }
        if asof_null(left_value) || asof_null(right_value) {
          state.visited += 1L
          state.right_row += 1
          state.key_index = 0
          progress += 1
        } else {
          match compare_complete_value(left_value, right_value, state.control) {
            Ok(0) => state.key_index += 1
            Ok(_) => {
              state.visited += 1L
              state.right_row += 1
              state.key_index = 0
              progress += 1
            }
            Err(issue) =>
              return bounded_asof_failure(
                Rows(ordering_row_issue(issue)),
                progress,
                used + 1,
              )
          }
        }
        used += 1
      }
      EvaluateCandidate => {
        state.visited += 1L
        let left_clock = state.left_clocks[state.left_row]
        let right_clock = state.right_clocks[state.right_row]
        let eligible = match state.direction {
          @asof.AsOfDirection::Backward => right_clock <= left_clock
          @asof.AsOfDirection::Forward => right_clock >= left_clock
          @asof.AsOfDirection::Nearest => true
        }
        let distance = if right_clock <= left_clock {
          left_clock - right_clock
        } else {
          right_clock - left_clock
        }
        if eligible && distance <= state.tolerance {
          match state.best {
            None => {
              state.best = Some(state.right_row)
              state.best_distance = distance
              state.best_tied_with = None
            }
            Some(_) if distance < state.best_distance => {
              state.best = Some(state.right_row)
              state.best_distance = distance
              state.best_tied_with = None
            }
            Some(_) if distance == state.best_distance => {
              state.candidate = state.right_row
              state.tie_index = 0
              state.phase = CompareTie
              used += 1
              progress += 1
              continue
            }
            _ => ()
          }
        }
        state.right_row += 1
        state.key_index = 0
        state.phase = CompareKey
        used += 1
        progress += 1
      }
      CompareTie => {
        guard state.best is Some(best) else {
          return bounded_asof_failure(InvalidExecution, progress, used)
        }
        if state.tie_index == state.ties.length() {
          state.best_tied_with = Some(state.candidate)
          state.right_row += 1
          state.key_index = 0
          state.phase = CompareKey
          used += 1
          progress += 1
          continue
        }
        let column = state.ties[state.tie_index]
        guard producer_read_cell(state.right, state.candidate, column)
          is Some(candidate) &&
          producer_read_cell(state.right, best, column) is Some(prior) else {
          return bounded_asof_failure(InvalidExecution, progress, used)
        }
        let candidate_null = asof_null(candidate)
        let prior_null = asof_null(prior)
        let comparison = if candidate_null || prior_null {
          if !spend_control(state.control, 1) {
            return bounded_asof_failure(Rows(RowLimit), progress, used + 1)
          }
          if candidate_null == prior_null {
            0
          } else if candidate_null {
            1
          } else {
            -1
          }
        } else {
          match compare_complete_value(candidate, prior, state.control) {
            Ok(value) => value
            Err(issue) =>
              return bounded_asof_failure(
                Rows(ordering_row_issue(issue)),
                progress,
                used + 1,
              )
          }
        }
        if comparison < 0 {
          state.best = Some(state.candidate)
          state.best_tied_with = None
          state.right_row += 1
          state.key_index = 0
          state.phase = CompareKey
        } else if comparison > 0 {
          state.right_row += 1
          state.key_index = 0
          state.phase = CompareKey
        } else {
          state.tie_index += 1
        }
        used += 1
        progress += 1
      }
      FinishLeft => {
        if state.best is Some(prior) && state.best_tied_with is Some(other) {
          return bounded_asof_failure(
            Rows(AsOfTopTie(state.left_row, prior, other)),
            progress,
            used + 1,
          )
        }
        if state.best is Some(_) || state.kind == @join.Left {
          if !bounded_asof_schedule_output(state) {
            return bounded_asof_failure(Rows(RowLimit), progress, used)
          }
        } else {
          bounded_asof_next_left(state)
        }
        used += 1
        progress += 1
      }
      BuildOutputRow => {
        if state.column == state.columns.length() {
          state.column = 0
          state.phase = CheckOutputRow
          continue
        }
        let source = state.columns[state.column]
        let value = if source.0 {
          producer_read_cell(state.left, state.left_row, source.1)
        } else {
          match state.best {
            Some(row) => producer_read_cell(state.right, row, source.1)
            None => Some(Null)
          }
        }
        guard value is Some(value) && reserve_slots(state.workspace, 1) else {
          return bounded_asof_failure(Rows(RowLimit), progress, used)
        }
        state.output_row.push(value)
        state.column += 1
        used += 1
      }
      CheckOutputRow => {
        if state.column == state.columns.length() {
          state.phase = CommitOutputRow
          continue
        }
        guard @schema.field_at(state.output_schema, state.column) is Some(field) &&
          checked_ordered_output_value(
            state.output_row[state.column],
            field.contract,
            state.admitted_limits,
          )
          is Some(value) &&
          reserve_slots(state.workspace, 1) else {
          return bounded_asof_failure(InvalidExecution, progress, used)
        }
        state.checked_row.push(value)
        state.column += 1
        used += 1
      }
      CommitOutputRow => {
        guard state.output is Some(output) else {
          return bounded_asof_failure(InvalidExecution, progress, used)
        }
        match append_admitted_output(output, state.checked_row) {
          Ok(_) => ()
          Err(issue) =>
            return bounded_asof_failure(Capture(issue), progress, used + 1)
        }
        release_slots(
          state.workspace,
          state.output_row.length() + state.checked_row.length(),
        )
        state.output_row = []
        state.checked_row = []
        state.emitted += 1
        bounded_asof_next_left(state)
        used += 1
        progress += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return bounded_asof_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return bounded_asof_failure(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => bounded_asof_failure(Completion(issue), progress, used)
        }
      }
      Terminal => return bounded_asof_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
pub fn start_bounded_asof_join(
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
) -> Result[BoundedAsOfJoinExecution, BoundedAsOfJoinIssue] {
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
    @lower.sequence_step(sequence, 0) is Some(@lower.AsOfJoinStep(kernel)) &&
    producer_read_matches_operation_input(left, owner, 0, 0) &&
    producer_read_matches_operation_input(right, owner, 0, 1) &&
    producer_read_has_cell_access(left) &&
    producer_read_has_cell_access(right) &&
    producer_read_row_count(left) <= max_rows &&
    producer_read_row_count(right) <= max_rows &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(0),
    )
    is Some(output_schema) else {
    return Err(InvalidExecution)
  }
  let search_ceiling = match generated_asof_search_ceiling(generated, 0) {
    Some(value) if value >= 0L => value
    _ => return Err(InvalidExecution)
  }
  let left_count = producer_read_row_count(left)
  let right_count = producer_read_row_count(right)
  if right_count != 0 &&
    left_count.to_int64() > search_ceiling / right_count.to_int64() {
    return Err(Rows(RowLimit))
  }
  let mut output_ceiling = max_rows
  if generated_join_output_ceiling(generated, 0) is Some(value) &&
    value < output_ceiling.to_int64() {
    if value < 0L {
      return Err(InvalidExecution)
    }
    output_ceiling = value.to_int()
  }
  let control : ControlBudget = { remaining: max_work, max_frames, }
  let workspace = row_workspace(max_entries)
  let resolve = fn(input : ProducerRead, field : @schema.FieldName) -> Int? {
    let schema = producer_read_schema(input)
    let name = @schema.reference_name(field)
    for index in 0..<@schema.field_count(schema) {
      if !spend_control(control, 1) || !spend_control_text(control, name) {
        return None
      }
      guard @schema.field_at(schema, index) is Some(candidate) else {
        return None
      }
      if @schema.reference_name(candidate.name) == name {
        return Some(index)
      }
    }
    None
  }
  guard resolve(left, @lower.asof_join_time(kernel, true)) is Some(left_time) &&
    resolve(right, @lower.asof_join_time(kernel, false)) is Some(right_time) else {
    return Err(InvalidExecution)
  }
  let keys : Array[(Int, Int)] = []
  for index in 0..<@lower.asof_join_key_count(kernel) {
    guard @lower.asof_join_key_at(kernel, index) is Some(pair) &&
      resolve(left, pair.0) is Some(left_column) &&
      resolve(right, pair.1) is Some(right_column) else {
      return Err(InvalidExecution)
    }
    keys.push((left_column, right_column))
  }
  let identities : Array[Int] = []
  for index in 0..<@lower.asof_join_identity_count(kernel) {
    guard @lower.asof_join_identity_at(kernel, index) is Some(field) &&
      resolve(left, field) is Some(column) else {
      return Err(InvalidExecution)
    }
    identities.push(column)
  }
  if identities.is_empty() {
    return Err(InvalidExecution)
  }
  let ties : Array[Int] = []
  for index in 0..<@lower.asof_join_tie_break_count(kernel) {
    guard @lower.asof_join_tie_break_at(kernel, index) is Some(field) &&
      resolve(right, field) is Some(column) else {
      return Err(InvalidExecution)
    }
    ties.push(column)
  }
  let columns : Array[(Bool, Int)] = []
  for index in 0..<@lower.asof_join_field_count(kernel) {
    guard @lower.asof_join_field_at(kernel, index) is Some(field) else {
      return Err(InvalidExecution)
    }
    let (on_left, source) = match field.input {
      @schema.Qualified(side, name) =>
        (side == @schema.Left, @schema.Unqualified(name))
      _ => return Err(InvalidExecution)
    }
    guard resolve(if on_left { left } else { right }, source) is Some(column) else {
      return Err(InvalidExecution)
    }
    columns.push((on_left, column))
  }
  if keys.length() > max_entries / 2 ||
    columns.length() > max_entries / 2 ||
    identities.length() > max_entries ||
    ties.length() > max_entries {
    return Err(Rows(RowLimit))
  }
  let key_slots = keys.length() * 2
  let column_slots = columns.length() * 2
  if key_slots > max_entries - column_slots ||
    identities.length() > max_entries - key_slots - column_slots ||
    ties.length() > max_entries - key_slots - column_slots - identities.length() {
    return Err(Rows(RowLimit))
  }
  let metadata = key_slots + column_slots + identities.length() + ties.length()
  if left_count > max_entries - metadata ||
    right_count > max_entries - metadata - left_count ||
    !reserve_slots(workspace, metadata) ||
    !reserve_slots(workspace, left_count) ||
    !reserve_slots(workspace, right_count) {
    return Err(Rows(RowLimit))
  }
  let output = match
    prepare_admitted_output(owner, @pipeline.Step(0), output_ceiling, values) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
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
      inputs=[left, right],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedAsOfState = {
    left,
    right,
    left_time,
    right_time,
    keys,
    identities,
    ties,
    columns,
    output_schema,
    kind: @lower.asof_join_kind(kernel),
    direction: @lower.asof_join_direction(kernel),
    tolerance: @lower.asof_join_tolerance(kernel),
    left_timestamp: @lower.asof_join_uses_timestamp(kernel, true),
    right_timestamp: @lower.asof_join_uses_timestamp(kernel, false),
    search_ceiling,
    output_ceiling,
    engine,
    control,
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
    phase: ValidateIdentity,
    identity_field: 0,
    identity_row: 0,
    sort: None,
    identity_order: [],
    ordered_left: [],
    unique_index: 0,
    left_clocks: [],
    right_clocks: [],
    clock_row: 0,
    ordered_index: 0,
    left_row: 0,
    right_row: 0,
    key_index: 0,
    tie_index: 0,
    visited: 0L,
    best: None,
    best_distance: 0L,
    best_tied_with: None,
    candidate: 0,
    emitted: 0,
    column: 0,
    output_row: [],
    checked_row: [],
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_asof_step,
    cleanup_bounded_asof_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn advance_bounded_asof_join(
  value : BoundedAsOfJoinExecution,
  quantum : Int,
) -> Result[BoundedAsOfJoinPoll, BoundedAsOfJoinIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedAsOfJoinContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedAsOfJoinComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedAsOfJoinFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedAsOfJoinStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_asof_join(
  value : BoundedAsOfJoinExecution,
) -> Result[Bool, BoundedAsOfJoinIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}

///|
pub fn bounded_asof_join_cleanup_pending(
  value : BoundedAsOfJoinExecution,
) -> Bool {
  @bounded.cleanup_pending(value.session)
}
