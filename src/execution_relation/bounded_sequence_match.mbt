///|
priv struct BoundedSequencePartial {
  positions : Array[Int]
}

///|
priv enum BoundedSequenceResume {
  ResumeDisallowFirst
  ResumeDisallowNext
  ResumeAllowPattern
}

///|
priv enum BoundedSequenceInput {
  RelationInput(ProducerRead)
  EventsInput(@managed_carrier.ProducerView)
}

///|
fn bounded_sequence_input_available(input : BoundedSequenceInput) -> Bool {
  match input {
    RelationInput(value) => producer_read_available(value)
    EventsInput(value) =>
      @managed_carrier.producer_view_record_count(value) is Some(_)
  }
}

///|
fn bounded_sequence_input_row_count(input : BoundedSequenceInput) -> Int? {
  match input {
    RelationInput(value) => Some(producer_read_row_count(value))
    EventsInput(value) => @managed_carrier.producer_view_record_count(value)
  }
}

///|
fn bounded_sequence_input_cell(
  input : BoundedSequenceInput,
  row : Int,
  column : Int,
) -> Value? {
  match input {
    RelationInput(value) => producer_read_cell(value, row, column)
    EventsInput(value) =>
      match @managed_carrier.producer_view_record_field(value, row, column) {
        Ok((_, checked)) => Some(capture(checked.value))
        Err(_) => None
      }
  }
}

///|
priv enum BoundedSequencePhase {
  InitializePredicates
  ValidateIdentity
  ReadClocks
  StartIdentitySort
  IdentitySort
  CheckUnique
  StartOrderSort
  OrderSort
  StartGroup
  CompareGroupKey
  DisallowFirst
  DisallowNext
  PrepareAllowPattern
  ScanAllowAdjacency
  AllowPattern
  ExtendAllowPattern
  SeedAllowPattern
  BuildPredicateInput
  EvaluatePredicate
  PrepareOutput
  BuildOutputRow
  CheckOutputRow
  CommitOutputRow
  FinishOutput
  Terminal
}

///|
priv struct BoundedSequenceState {
  input : BoundedSequenceInput
  kernel : @lower.PreparedSequenceMatch
  key_columns : Array[Int]
  identity_column : Int
  time_column : Int
  input_names : Array[String]
  output_schema : @schema.Schema
  output_names : Array[String]
  timestamp : Bool
  pattern_count : Int
  per_key_limit : Int
  output_limit : Int
  engine : @bounded.Control
  control : ControlBudget
  workspace : RowWorkspace
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut phase : BoundedSequencePhase
  mut continuation : BoundedSequenceResume
  mut sort : BoundedIndexSort?
  mut identity_order : Array[Int]
  mut ordered : Array[Int]
  mut clocks : Array[Int64]
  mut predicates : Array[Array[Int]]
  predicate_entries : Ref[Int]
  mut predicate_initialize_pattern : Int
  mut predicate_initialize_row : Int
  mut identity_row : Int
  mut unique_index : Int
  mut group_start : Int
  mut group_end : Int
  mut group_match_start : Int
  mut cursor : Int
  mut position : Int
  mut pattern : Int
  mut prior_index : Int
  mut per_key_start : Int
  mut selected : Array[Int]
  mut partials : Array[Array[BoundedSequencePartial]]
  mut row_matches : Array[Bool]
  mut matches : Array[BoundedSequencePartial]
  predicate_input : Map[String, Value]
  mut predicate_field : Int
  mut predicate_position : Int
  mut predicate_pattern : Int
  mut predicate_execution : PredicateExpressionExecution?
  mut output_match : Int
  mut output_column : Int
  mut output_scope : SlotScope?
  mut output_row : Array[Value]
  mut checked_row : Array[@admitted.CheckedValue]
}

///|
pub(all) enum BoundedSequenceMatchIssue {
  InvalidExecution
  Rows(RowIssue)
  Predicate(EvalIssueKind)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedSequenceMatchExecution {
  session : @bounded.Session[
    BoundedSequenceState,
    CompletedOutput,
    BoundedSequenceMatchIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  state : BoundedSequenceState
}

///|
fn bounded_sequence_match_state(
  value : BoundedSequenceMatchExecution,
) -> BoundedSequenceState {
  value.state
}

///|
pub enum BoundedSequenceMatchPoll {
  BoundedSequenceMatchContinue(progress~ : Int64, work~ : Int64)
  BoundedSequenceMatchComplete(
    CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  BoundedSequenceMatchFailed(
    BoundedSequenceMatchIssue,
    progress~ : Int64,
    work~ : Int64
  )
  BoundedSequenceMatchStopped(
    @bounded.StopReason,
    progress~ : Int64,
    work~ : Int64
  )
}

///|
fn bounded_sequence_failure(
  issue : BoundedSequenceMatchIssue,
  progress : Int,
  work : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedSequenceMatchIssue] {
  @bounded.Failed(issue, progress, work)
}

///|
fn cleanup_bounded_sequence_state(state : BoundedSequenceState) -> Bool {
  if state.sort is Some(active) {
    cleanup_bounded_index_sort(active) |> ignore
    state.sort = None
  }
  if state.predicate_execution is Some(active) {
    cancel_predicate_expression(active) |> ignore
    state.predicate_execution = None
  }
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.identity_order = []
  state.ordered = []
  state.clocks = []
  for predicate in state.predicates {
    predicate.clear()
  }
  state.predicates = []
  state.predicate_entries.val = 0
  state.selected = []
  for patterns in state.partials {
    for partial in patterns {
      partial.positions.clear()
    }
    patterns.clear()
  }
  state.partials = []
  state.row_matches = []
  for match_ in state.matches {
    match_.positions.clear()
  }
  state.matches = []
  if state.output_scope is Some(scope) {
    scope.close() |> ignore
    state.output_scope = None
  }
  state.output_row = []
  state.checked_row = []
  state.predicate_input.clear()
  state.workspace.live = 0
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
fn bounded_sequence_compare_value(
  state : BoundedSequenceState,
  left : Int,
  right : Int,
  column : Int,
) -> Result[Int, BoundedSequenceMatchIssue] {
  guard bounded_sequence_input_cell(state.input, left, column) is Some(a) &&
    bounded_sequence_input_cell(state.input, right, column) is Some(b) else {
    return Err(InvalidExecution)
  }
  compare_complete_value(a, b, state.control).map_err(issue => {
    Rows(ordering_row_issue(issue))
  })
}

///|
fn bounded_sequence_compare_identity(
  state : BoundedSequenceState,
  left : Int,
  right : Int,
) -> Result[Int, RowIssue] {
  bounded_sequence_compare_value(state, left, right, state.identity_column).map_err(issue => {
      match issue {
        Rows(issue) => issue
        _ => InvalidRows
      }
    },
  )
}

///|
fn bounded_sequence_compare_order(
  state : BoundedSequenceState,
  left : Int,
  right : Int,
) -> Result[Int, RowIssue] {
  for column in state.key_columns {
    match bounded_sequence_compare_value(state, left, right, column) {
      Ok(0) => ()
      Ok(value) => return Ok(value)
      Err(Rows(issue)) => return Err(issue)
      Err(_) => return Err(InvalidRows)
    }
  }
  if state.clocks[left] < state.clocks[right] {
    return Ok(-1)
  }
  if state.clocks[left] > state.clocks[right] {
    return Ok(1)
  }
  bounded_sequence_compare_identity(state, left, right)
}

///|
fn bounded_sequence_start_sort(
  state : BoundedSequenceState,
  compare : (Int, Int) -> Result[Int, RowIssue],
) -> Bool {
  guard bounded_sequence_input_row_count(state.input) is Some(count) else {
    return false
  }
  if count > (state.workspace.limit - state.workspace.live) / 2 ||
    !reserve_slots(state.workspace, count * 2) {
    return false
  }
  state.sort = start_bounded_index_sort(state.engine, count, compare)
  state.sort is Some(_)
}

///|
fn bounded_sequence_same_key(
  state : BoundedSequenceState,
  left_position : Int,
  right_position : Int,
) -> Result[Bool, BoundedSequenceMatchIssue] {
  let left = state.ordered[left_position]
  let right = state.ordered[right_position]
  for column in state.key_columns {
    match bounded_sequence_compare_value(state, left, right, column) {
      Ok(0) => ()
      Ok(_) => return Ok(false)
      Err(issue) => return Err(issue)
    }
  }
  Ok(true)
}

///|
fn bounded_sequence_cached_predicate(
  state : BoundedSequenceState,
  position : Int,
  pattern : Int,
) -> Bool? {
  let row = state.ordered[position]
  if state.predicates[pattern][row] < 0 {
    None
  } else {
    Some(state.predicates[pattern][row] == 1)
  }
}

///|
fn bounded_sequence_request_predicate(
  state : BoundedSequenceState,
  position : Int,
  pattern : Int,
  continuation : BoundedSequenceResume,
) -> Unit {
  state.predicate_position = position
  state.predicate_pattern = pattern
  state.predicate_field = 0
  state.predicate_input.clear()
  state.continuation = continuation
  state.phase = BuildPredicateInput
}

///|
fn bounded_sequence_resume_predicate(state : BoundedSequenceState) -> Unit {
  state.phase = match state.continuation {
    ResumeDisallowFirst => DisallowFirst
    ResumeDisallowNext => DisallowNext
    ResumeAllowPattern => AllowPattern
  }
}

///|
fn bounded_sequence_append_match(
  state : BoundedSequenceState,
  positions : Array[Int],
) -> Result[Unit, BoundedSequenceMatchIssue] {
  if state.matches.length() - state.per_key_start >= state.per_key_limit ||
    state.matches.length() >= state.output_limit ||
    positions.length() >= state.workspace.limit - state.workspace.live ||
    !reserve_slots(state.workspace, positions.length() + 1) {
    return Err(Rows(RowLimit))
  }
  state.matches.push({ positions: positions.copy(), })
  Ok(())
}

///|
fn bounded_sequence_advance_group(state : BoundedSequenceState) -> Unit {
  let mut released = state.partials.length() + state.row_matches.length()
  for patterns in state.partials {
    for partial in patterns {
      released += partial.positions.length()
    }
  }
  released += state.selected.length()
  release_slots(state.workspace, released)
  state.group_start = state.group_end
  state.group_end = state.group_start
  state.cursor = state.group_start
  state.position = state.group_start
  state.pattern = 0
  state.prior_index = 0
  state.selected = []
  state.partials = []
  state.row_matches = []
  state.phase = StartGroup
}

///|
fn bounded_sequence_within(first : Int64, last : Int64, within : Int64) -> Bool {
  if within < 0L || last < first {
    return false
  }
  if first > 9223372036854775807L - within {
    true
  } else {
    last <= first + within
  }
}

///|
fn bounded_sequence_release_matches(state : BoundedSequenceState) -> Unit {
  let mut released = state.matches.length()
  for match_ in state.matches {
    released += match_.positions.length()
  }
  state.matches.clear()
  release_slots(state.workspace, released)
}

///|
fn bounded_sequence_output_value(
  state : BoundedSequenceState,
  match_ : BoundedSequencePartial,
  name : String,
) -> Result[Value?, BoundedSequenceMatchIssue] {
  let first = state.ordered[match_.positions[0]]
  let last = state.ordered[match_.positions[match_.positions.length() - 1]]
  for index in 0..<state.key_columns.length() {
    if @lower.sequence_match_key_at(state.kernel, index).map(
        @schema.reference_name,
      ) ==
      Some(name) {
      return Ok(
        bounded_sequence_input_cell(
          state.input,
          first,
          state.key_columns[index],
        ),
      )
    }
  }
  if name == "match_start_ms" {
    return Ok(Some(Number(state.clocks[first].to_double())))
  }
  if name == "match_end_ms" {
    return Ok(Some(Number(state.clocks[last].to_double())))
  }
  for pattern in 0..<state.pattern_count {
    guard @lower.sequence_match_pattern_label(state.kernel, pattern)
      is Some(label) else {
      return Ok(None)
    }
    let source = state.ordered[match_.positions[pattern]]
    if !charge_text_append(state.control, label, 3) {
      return Err(Rows(RowLimit))
    }
    if name == label + "_id" {
      return Ok(
        bounded_sequence_input_cell(state.input, source, state.identity_column),
      )
    }
    if !charge_text_append(state.control, label, 8) {
      return Err(Rows(RowLimit))
    }
    if name == label + "_time_ms" {
      return Ok(Some(Number(state.clocks[source].to_double())))
    }
  }
  Ok(None)
}

///|
fn bounded_sequence_step(
  state : BoundedSequenceState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedSequenceMatchIssue] {
  let mut used = 0
  let mut progress = 0
  guard bounded_sequence_input_row_count(state.input) is Some(count) else {
    return bounded_sequence_failure(InvalidExecution, 0, 0)
  }
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !bounded_sequence_input_available(state.input) {
      return bounded_sequence_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      InitializePredicates => {
        if state.predicate_initialize_pattern == state.pattern_count {
          state.phase = ValidateIdentity
          continue
        }
        if state.predicate_initialize_pattern == state.predicates.length() {
          state.predicates.push([])
          used += 1
          progress += 1
          continue
        }
        if state.predicate_initialize_row == count {
          state.predicate_initialize_pattern += 1
          state.predicate_initialize_row = 0
          continue
        }
        state.predicates[state.predicate_initialize_pattern].push(-1)
        state.predicate_entries.val += 1
        state.predicate_initialize_row += 1
        used += 1
        progress += 1
      }
      ValidateIdentity => {
        if state.identity_row == count {
          state.identity_row = 0
          state.phase = ReadClocks
          continue
        }
        guard bounded_sequence_input_cell(
            state.input,
            state.identity_row,
            state.identity_column,
          )
          is Some(value) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        if value is Null {
          return bounded_sequence_failure(
            Rows(AssertionNullKey(state.identity_row, 0)),
            progress,
            used + 1,
          )
        }
        state.identity_row += 1
        used += 1
        progress += 1
      }
      ReadClocks => {
        if state.identity_row == count {
          state.phase = StartIdentitySort
          continue
        }
        guard bounded_sequence_input_cell(
            state.input,
            state.identity_row,
            state.time_column,
          )
          is Some(value) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        match interval_clock(value, state.timestamp, state.control) {
          Ok(clock) => state.clocks.push(clock)
          Err(issue) =>
            return bounded_sequence_failure(Rows(issue), progress, used + 1)
        }
        state.identity_row += 1
        used += 1
        progress += 1
      }
      StartIdentitySort => {
        if !bounded_sequence_start_sort(state, fn(left, right) {
            bounded_sequence_compare_identity(state, left, right)
          }) {
          return bounded_sequence_failure(Rows(RowLimit), progress, used)
        }
        state.phase = IdentitySort
      }
      IdentitySort => {
        guard state.sort is Some(active) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        match advance_bounded_index_sort(active, 1) {
          Err(issue) | Ok(BoundedIndexSortFailed(issue)) =>
            return bounded_sequence_failure(Rows(issue), progress, used + 1)
          Ok(BoundedIndexSortContinue) => ()
          Ok(BoundedIndexSortComplete(order)) => {
            cleanup_bounded_index_sort(active) |> ignore
            state.sort = None
            release_slots(state.workspace, count)
            state.identity_order = order
            state.unique_index = 1
            state.phase = CheckUnique
          }
          Ok(BoundedIndexSortStopped(reason)) =>
            return @bounded.Stopped(reason, progress, used + 1)
        }
        used += 1
        progress += 1
      }
      CheckUnique => {
        if state.unique_index >= count {
          state.identity_order = []
          release_slots(state.workspace, count)
          state.phase = StartOrderSort
          continue
        }
        let before = state.identity_order[state.unique_index - 1]
        let after = state.identity_order[state.unique_index]
        match bounded_sequence_compare_identity(state, before, after) {
          Ok(0) =>
            return bounded_sequence_failure(
              Rows(AssertionDuplicate(before, after)),
              progress,
              used + 1,
            )
          Ok(_) => ()
          Err(issue) =>
            return bounded_sequence_failure(Rows(issue), progress, used + 1)
        }
        state.unique_index += 1
        used += 1
        progress += 1
      }
      StartOrderSort => {
        if !bounded_sequence_start_sort(state, fn(left, right) {
            bounded_sequence_compare_order(state, left, right)
          }) {
          return bounded_sequence_failure(Rows(RowLimit), progress, used)
        }
        state.phase = OrderSort
      }
      OrderSort => {
        guard state.sort is Some(active) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        match advance_bounded_index_sort(active, 1) {
          Err(issue) | Ok(BoundedIndexSortFailed(issue)) =>
            return bounded_sequence_failure(Rows(issue), progress, used + 1)
          Ok(BoundedIndexSortContinue) => ()
          Ok(BoundedIndexSortComplete(order)) => {
            cleanup_bounded_index_sort(active) |> ignore
            state.sort = None
            release_slots(state.workspace, count)
            state.ordered = order
            state.group_start = 0
            state.group_end = 0
            state.phase = StartGroup
          }
          Ok(BoundedIndexSortStopped(reason)) =>
            return @bounded.Stopped(reason, progress, used + 1)
        }
        used += 1
        progress += 1
      }
      StartGroup => {
        if state.group_start == count {
          state.output_match = 0
          state.output_column = 0
          state.phase = PrepareOutput
          continue
        }
        if state.group_end == state.group_start {
          state.group_end += 1
          state.per_key_start = state.matches.length()
        }
        if state.group_end == count {
          state.cursor = state.group_start
          state.position = state.group_start
          state.pattern = 0
          state.phase = if @lower.sequence_match_overlap(state.kernel) ==
            @relation.SequenceOverlap::Disallow {
            DisallowFirst
          } else {
            PrepareAllowPattern
          }
          continue
        }
        state.phase = CompareGroupKey
      }
      CompareGroupKey => {
        match
          bounded_sequence_same_key(state, state.group_start, state.group_end) {
          Ok(true) => {
            state.group_end += 1
            state.phase = StartGroup
          }
          Ok(false) => {
            state.cursor = state.group_start
            state.position = state.group_start
            state.pattern = 0
            state.phase = if @lower.sequence_match_overlap(state.kernel) ==
              @relation.SequenceOverlap::Disallow {
              DisallowFirst
            } else {
              PrepareAllowPattern
            }
          }
          Err(issue) =>
            return bounded_sequence_failure(issue, progress, used + 1)
        }
        used += 1
        progress += 1
      }
      DisallowFirst => {
        if state.cursor >= state.group_end {
          bounded_sequence_advance_group(state)
          continue
        }
        match bounded_sequence_cached_predicate(state, state.cursor, 0) {
          None => {
            bounded_sequence_request_predicate(
              state,
              state.cursor,
              0,
              ResumeDisallowFirst,
            )
            continue
          }
          Some(false) => state.cursor += 1
          Some(true) => {
            state.group_match_start = state.cursor
            state.position = state.cursor
            state.pattern = 1
            state.selected = [state.cursor]
            if !reserve_slots(state.workspace, 1) {
              return bounded_sequence_failure(Rows(RowLimit), progress, used)
            }
            state.phase = DisallowNext
          }
        }
        used += 1
        progress += 1
      }
      DisallowNext => {
        if state.pattern == state.pattern_count {
          match bounded_sequence_append_match(state, state.selected) {
            Ok(_) => ()
            Err(issue) =>
              return bounded_sequence_failure(issue, progress, used + 1)
          }
          release_slots(state.workspace, state.selected.length())
          state.cursor = state.position + 1
          state.selected = []
          state.phase = DisallowFirst
          used += 1
          progress += 1
          continue
        }
        let next = state.position + 1
        if next >= state.group_end {
          release_slots(state.workspace, state.selected.length())
          state.selected = []
          state.cursor = state.group_match_start + 1
          state.phase = DisallowFirst
          continue
        }
        if @lower.sequence_match_contiguity(state.kernel) ==
          @relation.SequenceContiguity::Adjacent &&
          next != state.position + 1 {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        match bounded_sequence_cached_predicate(state, next, state.pattern) {
          None => {
            bounded_sequence_request_predicate(
              state,
              next,
              state.pattern,
              ResumeDisallowNext,
            )
            continue
          }
          Some(false) =>
            if @lower.sequence_match_contiguity(state.kernel) ==
              @relation.SequenceContiguity::Adjacent {
              release_slots(state.workspace, state.selected.length())
              state.selected = []
              state.cursor = state.group_match_start + 1
              state.phase = DisallowFirst
            } else {
              state.position = next
            }
          Some(true) => {
            let first = state.ordered[state.group_match_start]
            let row = state.ordered[next]
            if !bounded_sequence_within(
                state.clocks[first],
                state.clocks[row],
                @lower.sequence_match_within(state.kernel),
              ) {
              release_slots(state.workspace, state.selected.length())
              state.selected = []
              state.cursor = state.group_match_start + 1
              state.phase = DisallowFirst
            } else if !reserve_slots(state.workspace, 1) {
              return bounded_sequence_failure(Rows(RowLimit), progress, used)
            } else {
              state.selected.push(next)
              state.position = next
              state.pattern += 1
            }
          }
        }
        used += 1
        progress += 1
      }
      PrepareAllowPattern => {
        if state.partials.is_empty() {
          if !reserve_slots(state.workspace, state.pattern_count) {
            return bounded_sequence_failure(Rows(RowLimit), progress, used)
          }
          state.partials = Array::makei(state.pattern_count, _ => [])
        }
        if state.position == state.group_end {
          bounded_sequence_advance_group(state)
          continue
        }
        if state.row_matches.is_empty() {
          if !reserve_slots(state.workspace, state.pattern_count) {
            return bounded_sequence_failure(Rows(RowLimit), progress, used)
          }
          state.row_matches = Array::make(state.pattern_count, false)
        }
        if state.pattern == state.pattern_count {
          state.pattern = state.pattern_count - 1
          state.prior_index = 0
          state.phase = ExtendAllowPattern
          continue
        }
        if state.pattern == 0 || state.partials[state.pattern - 1].is_empty() {
          state.phase = AllowPattern
          continue
        }
        if @lower.sequence_match_contiguity(state.kernel) ==
          @relation.SequenceContiguity::Subsequence {
          state.phase = AllowPattern
          continue
        }
        state.prior_index = 0
        state.phase = ScanAllowAdjacency
      }
      ScanAllowAdjacency => {
        let prior = state.partials[state.pattern - 1]
        if state.prior_index == prior.length() {
          state.pattern += 1
          state.phase = PrepareAllowPattern
          continue
        }
        let positions = prior[state.prior_index].positions
        if positions[positions.length() - 1] == state.position - 1 {
          state.phase = AllowPattern
        } else {
          state.prior_index += 1
        }
        used += 1
        progress += 1
      }
      AllowPattern => {
        let demanded = state.pattern == 0 ||
          !state.partials[state.pattern - 1].is_empty()
        if !demanded {
          state.pattern += 1
          state.phase = PrepareAllowPattern
          continue
        }
        match
          bounded_sequence_cached_predicate(
            state,
            state.position,
            state.pattern,
          ) {
          None => {
            bounded_sequence_request_predicate(
              state,
              state.position,
              state.pattern,
              ResumeAllowPattern,
            )
            continue
          }
          Some(value) => state.row_matches[state.pattern] = value
        }
        state.pattern += 1
        state.phase = PrepareAllowPattern
        used += 1
        progress += 1
      }
      ExtendAllowPattern => {
        if state.pattern < 1 {
          state.phase = SeedAllowPattern
          continue
        }
        if !state.row_matches[state.pattern] {
          state.pattern -= 1
          state.prior_index = 0
          continue
        }
        let prior = state.partials[state.pattern - 1]
        if state.prior_index == prior.length() {
          state.pattern -= 1
          state.prior_index = 0
          continue
        }
        let partial = prior[state.prior_index]
        state.prior_index += 1
        let last = partial.positions[partial.positions.length() - 1]
        let allowed = @lower.sequence_match_contiguity(state.kernel) ==
          @relation.SequenceContiguity::Subsequence ||
          state.position == last + 1
        let first = partial.positions[0]
        let row = state.ordered[state.position]
        let first_row = state.ordered[first]
        if allowed &&
          bounded_sequence_within(
            state.clocks[first_row],
            state.clocks[row],
            @lower.sequence_match_within(state.kernel),
          ) {
          let needed = partial.positions.length() + 1
          if !reserve_slots(state.workspace, needed) {
            return bounded_sequence_failure(Rows(RowLimit), progress, used)
          }
          let extended = partial.positions.copy()
          extended.push(state.position)
          state.partials[state.pattern].push({ positions: extended, })
          if state.pattern == state.pattern_count - 1 {
            match bounded_sequence_append_match(state, extended) {
              Ok(_) => ()
              Err(issue) =>
                return bounded_sequence_failure(issue, progress, used + 1)
            }
          }
        }
        used += 1
        progress += 1
      }
      SeedAllowPattern => {
        if state.row_matches[0] {
          if !reserve_slots(state.workspace, 1) {
            return bounded_sequence_failure(Rows(RowLimit), progress, used)
          }
          state.partials[0].push({ positions: [state.position], })
        }
        release_slots(state.workspace, state.row_matches.length())
        state.row_matches = []
        state.position += 1
        state.pattern = 0
        state.prior_index = 0
        state.phase = PrepareAllowPattern
        used += 1
        progress += 1
      }
      BuildPredicateInput => {
        if state.predicate_field == state.input_names.length() {
          guard @lower.sequence_match_predicate(
              state.kernel,
              state.predicate_pattern,
            )
            is Some(expression) else {
            return bounded_sequence_failure(InvalidExecution, progress, used)
          }
          match
            start_predicate_expression(
              expression,
              state.predicate_input,
              state.control.remaining,
              state.control.max_frames,
              state.workspace.limit - state.workspace.live,
            ) {
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.phase = EvaluatePredicate
            }
            Err(issue) =>
              return bounded_sequence_failure(
                Predicate(issue.kind),
                progress,
                used,
              )
          }
          continue
        }
        let row = state.ordered[state.predicate_position]
        let column = state.predicate_field
        guard bounded_sequence_input_cell(state.input, row, column)
          is Some(value) &&
          spend_control_text(state.control, state.input_names[column]) else {
          return bounded_sequence_failure(Rows(RowLimit), progress, used)
        }
        state.predicate_input[state.input_names[column]] = value
        state.predicate_field += 1
        used += 1
        progress += 1
      }
      EvaluatePredicate => {
        guard state.predicate_execution is Some(execution) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        match advance_predicate_expression(execution) {
          Err(issue) => {
            state.control.remaining = predicate_expression_remaining(execution)
            state.predicate_execution = None
            return bounded_sequence_failure(
              Predicate(issue.kind),
              progress,
              used + 1,
            )
          }
          Ok(PredicateExpressionContinue) => ()
          Ok(PredicateExpressionComplete(value)) => {
            state.control.remaining = predicate_expression_remaining(execution)
            state.predicate_execution = None
            let row = state.ordered[state.predicate_position]
            state.predicates[state.predicate_pattern][row] = if value {
              1
            } else {
              0
            }
            state.predicate_input.clear()
            bounded_sequence_resume_predicate(state)
          }
        }
        used += 1
        progress += 1
      }
      PrepareOutput => {
        if state.output_match == state.matches.length() {
          bounded_sequence_release_matches(state)
          state.phase = FinishOutput
          continue
        }
        guard charge_row(
            state.workspace,
            state.control,
            state.output_names.length(),
          )
          is Some(scope) else {
          return bounded_sequence_failure(Rows(RowLimit), progress, used)
        }
        state.output_scope = Some(scope)
        if !reserve_slots(state.workspace, state.output_names.length()) {
          scope.close() |> ignore
          state.output_scope = None
          return bounded_sequence_failure(Rows(RowLimit), progress, used)
        }
        state.output_column = 0
        state.output_row = []
        state.checked_row = []
        state.phase = BuildOutputRow
      }
      BuildOutputRow => {
        if state.output_column == state.output_names.length() {
          state.output_column = 0
          state.phase = CheckOutputRow
          continue
        }
        let value = match
          bounded_sequence_output_value(
            state,
            state.matches[state.output_match],
            state.output_names[state.output_column],
          ) {
          Ok(Some(value)) => value
          Ok(None) =>
            return bounded_sequence_failure(InvalidExecution, progress, used)
          Err(issue) => return bounded_sequence_failure(issue, progress, used)
        }
        state.output_row.push(value)
        state.output_column += 1
        used += 1
        progress += 1
      }
      CheckOutputRow => {
        if state.output_column == state.output_names.length() {
          state.phase = CommitOutputRow
          continue
        }
        guard @schema.field_at(state.output_schema, state.output_column)
          is Some(field) &&
          checked_ordered_output_value(
            state.output_row[state.output_column],
            field.contract,
            state.admitted_limits,
          )
          is Some(value) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        state.checked_row.push(value)
        state.output_column += 1
        used += 1
        progress += 1
      }
      CommitOutputRow => {
        guard state.output is Some(output) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        match append_admitted_output(output, state.checked_row) {
          Ok(_) => ()
          Err(issue) =>
            return bounded_sequence_failure(Capture(issue), progress, used + 1)
        }
        guard state.output_scope is Some(scope) && scope.close() else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        state.output_scope = None
        state.output_row = []
        state.checked_row = []
        state.output_match += 1
        state.phase = PrepareOutput
        used += 1
        progress += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return bounded_sequence_failure(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) =>
            bounded_sequence_failure(Completion(issue), progress, used)
        }
      }
      Terminal =>
        return bounded_sequence_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn start_bounded_sequence_match_input(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : BoundedSequenceInput,
  schema : @schema.Schema,
  step : Int,
  trusted_inputs : Array[TrustedOutputInput],
  max_rows : Int,
  values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedSequenceMatchExecution, BoundedSequenceMatchIssue] {
  if max_rows < 0 ||
    max_work < 0 ||
    max_frames < 0 ||
    max_entries < 0 ||
    max_name_bytes < 0 {
    return Err(InvalidExecution)
  }
  let sequence = generated.sequence
  let owner = @lower.sequence_owner(sequence)
  guard step >= 0 &&
    step == @lower.sequence_count(sequence) - 1 &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.SequenceMatchStep(kernel)) &&
    bounded_sequence_input_row_count(input) is Some(count) &&
    count <= max_rows else {
    return Err(InvalidExecution)
  }
  let output_schema = @lower.sequence_match_output_schema(kernel)
  let control : ControlBudget = { remaining: max_work, max_frames, }
  let workspace = row_workspace(max_entries)
  let pattern_count = @lower.sequence_match_pattern_count(kernel)
  let input_name_count = @schema.field_count(schema)
  let key_count = @lower.sequence_match_key_count(kernel)
  let output_name_count = @schema.field_count(output_schema)
  if pattern_count < 2 ||
    (pattern_count != 0 && count > max_entries / pattern_count) {
    return Err(Rows(RowLimit))
  }
  let predicates_slots = count * pattern_count
  let mut metadata = 0
  for
    slots in [
      input_name_count, key_count, count, pattern_count, predicates_slots, output_name_count,
    ] {
    if slots < 0 || slots > max_entries - metadata {
      return Err(Rows(RowLimit))
    }
    metadata += slots
  }
  if !reserve_slots(workspace, metadata) {
    return Err(Rows(RowLimit))
  }
  let input_names : Array[String] = []
  for index in 0..<@schema.field_count(schema) {
    guard @schema.field_at(schema, index) is Some(field) else {
      return Err(InvalidExecution)
    }
    input_names.push(@schema.reference_name(field.name))
  }
  let resolve = fn(field : @schema.FieldName) -> Int? {
    let name = @schema.reference_name(field)
    for index, candidate in input_names {
      if !spend_control(control, 1) || !spend_control_text(control, name) {
        return None
      }
      if candidate == name {
        return Some(index)
      }
    }
    None
  }
  let key_columns : Array[Int] = []
  for index in 0..<key_count {
    guard @lower.sequence_match_key_at(kernel, index) is Some(field) &&
      resolve(field) is Some(column) else {
      return Err(InvalidExecution)
    }
    key_columns.push(column)
  }
  guard resolve(@lower.sequence_match_identity(kernel)) is Some(identity_column) &&
    resolve(@lower.sequence_match_time(kernel)) is Some(time_column) else {
    return Err(InvalidExecution)
  }
  let output_names : Array[String] = []
  for index in 0..<@schema.field_count(output_schema) {
    guard @schema.field_at(output_schema, index) is Some(field) else {
      return Err(InvalidExecution)
    }
    output_names.push(@schema.reference_name(field.name))
  }
  let output_limit = match @lower.sequence_match_output_limit(kernel) {
    Some(value) => Int64::min(value, max_rows.to_int64()).to_int()
    None => max_rows
  }
  let per_key_limit = match @lower.sequence_match_per_key_limit(kernel) {
    Some(value) => Int64::min(value, max_rows.to_int64()).to_int()
    None => max_rows
  }
  if output_limit < 0 || per_key_limit < 0 {
    return Err(InvalidExecution)
  }
  let output = match
    prepare_admitted_output(owner, @pipeline.Step(step), output_limit, values) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let rows : Ref[AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let predicate_entries = Ref(0)
  let port = match
    prepare_trusted_output_port_with_inputs(
      generated_completion_preparation(generated),
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=trusted_inputs,
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedSequenceState = {
    input,
    kernel,
    key_columns,
    identity_column,
    time_column,
    input_names,
    output_schema,
    output_names,
    timestamp: @lower.sequence_match_uses_timestamp(kernel),
    pattern_count,
    per_key_limit,
    output_limit,
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
    phase: InitializePredicates,
    continuation: ResumeDisallowFirst,
    sort: None,
    identity_order: [],
    ordered: [],
    clocks: [],
    predicates: [],
    predicate_entries,
    predicate_initialize_pattern: 0,
    predicate_initialize_row: 0,
    identity_row: 0,
    unique_index: 1,
    group_start: 0,
    group_end: 0,
    group_match_start: 0,
    cursor: 0,
    position: 0,
    pattern: 0,
    prior_index: 0,
    per_key_start: 0,
    selected: [],
    partials: [],
    row_matches: [],
    matches: [],
    predicate_input: Map([]),
    predicate_field: 0,
    predicate_position: 0,
    predicate_pattern: 0,
    predicate_execution: None,
    output_match: 0,
    output_column: 0,
    output_scope: None,
    output_row: [],
    checked_row: [],
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_sequence_step,
    cleanup_bounded_sequence_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, state, })
}

///|
pub fn start_bounded_sequence_match(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : ProducerRead,
  max_rows : Int,
  values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedSequenceMatchExecution, BoundedSequenceMatchIssue] {
  let sequence = generated.sequence
  let owner = @lower.sequence_owner(sequence)
  guard generated_sequence_step_count(generated) == 1 &&
    generated_sequence_step_index_at(generated, 0) is Some(step) &&
    producer_read_matches_operation_input(input, owner, step, 0) &&
    producer_read_has_cell_access(input) else {
    return Err(InvalidExecution)
  }
  start_bounded_sequence_match_input(
    engine,
    generated,
    RelationInput(input),
    producer_read_schema(input),
    step,
    [trusted_output_relation_input(input)],
    max_rows,
    values,
    max_work,
    max_frames,
    max_entries,
    max_name_bytes,
  )
}

///|
pub fn start_bounded_sequence_match_events(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : @managed_carrier.ProducerView,
  max_rows : Int,
  values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedSequenceMatchExecution, BoundedSequenceMatchIssue] {
  let sequence = generated.sequence
  let owner = @lower.sequence_owner(sequence)
  let prepared = @lower.bound_preparation(owner)
  let reference = @managed_carrier.producer_view_read_reference(input)
  guard generated_sequence_step_count(generated) == 1 &&
    generated_sequence_step_index_at(generated, 0) is Some(step) &&
    @lower.node_at(prepared, step) is Some(node) &&
    @lower.node_input_target(node, 0) is Some(input_target) &&
    @managed_carrier.producer_view_kind(input) == @carrier.EventsKind &&
    @managed_carrier.producer_read_reference_matches_operation_input(
      reference, owner, step, 0,
    ) &&
    @lower.preparation_carrier_at(prepared, input_target)
    is Some(@carrier.EventValue(events)) &&
    @carrier.complete_schema(@carrier.event_records(events)) is Some(schema) else {
    return Err(InvalidExecution)
  }
  start_bounded_sequence_match_input(
    engine,
    generated,
    EventsInput(input),
    schema,
    step,
    [trusted_output_carrier_input(reference)],
    max_rows,
    values,
    max_work,
    max_frames,
    max_entries,
    max_name_bytes,
  )
}

///|
pub fn advance_bounded_sequence_match(
  value : BoundedSequenceMatchExecution,
  quantum : Int,
) -> Result[BoundedSequenceMatchPoll, BoundedSequenceMatchIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedSequenceMatchContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedSequenceMatchComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedSequenceMatchFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedSequenceMatchStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_sequence_match(
  value : BoundedSequenceMatchExecution,
) -> Result[Bool, BoundedSequenceMatchIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}

///|
pub fn bounded_sequence_match_cleanup_pending(
  value : BoundedSequenceMatchExecution,
) -> Bool {
  bounded_sequence_match_state(value).output_scope is Some(_) ||
  @bounded.cleanup_pending(value.session)
}
