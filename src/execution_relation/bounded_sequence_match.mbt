///|
priv struct BoundedSequencePartial {
  positions : Array[Int]
}

///|
priv enum BoundedSequenceCopy {
  ExtendPartial
  MatchAllow
  MatchDisallow
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
  PrepareCompletionPort
  LoadInputNames
  ResolveColumns
  LoadOutputNames
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
  InitializeAllowPartials
  InitializeRowMatches
  ScanAllowAdjacency
  AllowPattern
  ExtendAllowPattern
  CopyPositions
  ReleaseSelected
  ReleaseGroup
  ReleaseMatches
  ReleaseRowMatches
  ReleasePredicateInput
  SeedAllowPattern
  BuildPredicateInput
  EvaluatePredicate
  PrepareOutput
  BuildOutputRow
  ResolveOutputKey
  ResolveOutputPattern
  CheckOutputRow
  CommitOutputRow
  FinishOutput
  Terminal
}

///|
priv struct BoundedSequenceState {
  input : BoundedSequenceInput
  input_schema : @schema.Schema
  kernel : @lower.PreparedSequenceMatch
  key_columns : Array[Int]
  mut identity_column : Int
  mut time_column : Int
  input_names : Array[String]
  output_schema : @schema.Schema
  output_names : Array[String]
  mut resolve_field : Int
  mut metadata_lookup : ChargedRowMetadataLookup?
  mut name_charge : RowNameCharge?
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
  mut port : TrustedOutputPort[Unit]?
  mut port_preparation : TrustedOutputPreparation?
  mut phase : BoundedSequencePhase
  mut continuation : BoundedSequenceResume
  mut sort : BoundedIndexSort?
  mut comparison : BoundedCompleteValueComparison?
  mut compare_left : Int
  mut compare_right : Int
  mut compare_kind : BoundedSequenceComparisonKind?
  mut compare_column : Int
  mut identity_order : Array[Int]
  mut ordered : Array[Int]
  clocks : Array[Int64]
  predicates : Array[Array[Int]]
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
  selected : Array[Int]
  partials : Array[Array[BoundedSequencePartial]]
  row_matches : Array[Bool]
  matches : Array[BoundedSequencePartial]
  mut copy_source : Array[Int]?
  mut copy_positions : Array[Int]
  mut copy_index : Int
  mut copy_extra : Int?
  mut copy_kind : BoundedSequenceCopy
  mut copy_reserved : Int
  predicate_input : Array[(String, Value)]
  mut predicate_field : Int
  mut predicate_position : Int
  mut predicate_pattern : Int
  mut predicate_execution : PredicateExpressionExecution?
  mut output_match : Int
  mut output_column : Int
  mut output_key : Int
  mut output_pattern : Int
  mut output_name_offset : Int
  mut output_key_started : Bool
  mut output_label_part : Int
  mut output_label_started : Bool
  output_label_charge : BoundedTextCharge
  mut output_scope : SlotScope?
  mut output_row : Array[Value]
  mut checked_row : Array[@admitted.Value]
  mut output_recheck : @admitted.RecheckCursor?
  mut output_charge : BoundedOutputRowCharge?
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
  if state.port_preparation is Some(cursor) {
    cancel_trusted_output_preparation(cursor)
    state.port_preparation = None
  }
  if state.output_recheck is Some(cursor) {
    @admitted.cancel_recheck_runtime_value(cursor)
    state.output_recheck = None
  }
  if state.output_charge is Some(cursor) {
    cleanup_bounded_output_row_charge(cursor)
    state.output_charge = None
  }
  if state.metadata_lookup is Some(cursor) {
    close_row_metadata_lookup(cursor.lookup)
    state.metadata_lookup = None
  }
  if state.name_charge is Some(cursor) {
    close_row_name_charge(cursor)
    state.name_charge = None
  }
  if state.sort is Some(active) {
    // A stopped parent can still own a pending child comparison. Confirm the
    // child's stop before releasing its callback state or borrowed cells.
    if !bounded_index_sort_stopped(active) {
      @bounded.request_cancel(state.engine) |> ignore
      match advance_bounded_index_sort(active, 1) {
        Ok(BoundedIndexSortStopped(_)) => ()
        _ => return false
      }
    }
    if !cleanup_bounded_index_sort(active) {
      return false
    }
    state.sort = None
  }
  clear_bounded_sequence_comparison(state)
  if state.predicate_execution is Some(active) {
    cancel_predicate_expression(active) |> ignore
    state.predicate_execution = None
  }
  if state.output is Some(output) {
    if !reclaim_bounded_admitted_output(output, state.accepted.val) {
      return false
    }
    state.output = None
  }
  if state.output_scope is Some(scope) {
    scope.close() |> ignore
    state.output_scope = None
  }
  // Sources remain owned by selected/partials until stop is confirmed. Keep
  // the parent reservation until all scratch collections have been drained.
  state.copy_source = None
  for _ in 0..<64 {
    if !state.copy_positions.is_empty() {
      state.copy_positions.pop() |> ignore
    } else if !state.selected.is_empty() {
      state.selected.pop() |> ignore
    } else if bounded_sequence_pop_partial(state) {
      ()
    } else if bounded_sequence_pop_match(state) {
      ()
    } else if !state.predicates.is_empty() {
      let cells = state.predicates[state.predicates.length() - 1]
      if cells.is_empty() {
        state.predicates.pop() |> ignore
      } else {
        cells.pop() |> ignore
      }
    } else if !state.row_matches.is_empty() {
      state.row_matches.pop() |> ignore
    } else if !state.predicate_input.is_empty() {
      state.predicate_input.pop() |> ignore
    } else if !state.input_names.is_empty() {
      state.input_names.pop() |> ignore
    } else if !state.output_names.is_empty() {
      state.output_names.pop() |> ignore
    } else if !state.key_columns.is_empty() {
      state.key_columns.pop() |> ignore
    } else if !state.identity_order.is_empty() {
      state.identity_order.pop() |> ignore
    } else if !state.ordered.is_empty() {
      state.ordered.pop() |> ignore
    } else if !state.clocks.is_empty() {
      state.clocks.pop() |> ignore
    } else if !state.output_row.is_empty() {
      state.output_row.pop() |> ignore
    } else if !state.checked_row.is_empty() {
      state.checked_row.pop() |> ignore
    } else {
      state.copy_reserved = 0
      state.predicate_entries.val = 0
      state.workspace.live = 0
      if !state.accepted.val {
        state.rows.val = None
        state.live.val = false
      }
      return true
    }
  }
  false
}

///|
fn bounded_sequence_compare_value(
  state : BoundedSequenceState,
  left : Int,
  right : Int,
  column : Int,
) -> Result[Int?, BoundedSequenceMatchIssue] {
  guard bounded_sequence_input_cell(state.input, left, column) is Some(a) &&
    bounded_sequence_input_cell(state.input, right, column) is Some(b) else {
    return Err(InvalidExecution)
  }
  if state.comparison is None &&
    a is Text(text_a) &&
    b is Text(text_b) &&
    (text_a.length() > 64 || text_b.length() > 64) {
    if !reserve_slots(state.workspace, 2) {
      return Err(Rows(RowLimit))
    }
    state.comparison = Some(bounded_complete_value_comparison())
  }
  if state.comparison is Some(cursor) {
    let result : Result[Int?, BoundedSequenceMatchIssue] = bounded_complete_value_comparison_step(
      cursor,
      a,
      b,
      state.control,
    ).map_err(issue => Rows(ordering_row_issue(issue)))
    if result is Ok(Some(_)) {
      state.comparison = None
      release_slots(state.workspace, 2)
    }
    result
  } else {
    compare_complete_value(a, b, state.control)
    .map(value => Some(value))
    .map_err(issue => Rows(ordering_row_issue(issue)))
  }
}

///|
fn bounded_sequence_compare_identity(
  state : BoundedSequenceState,
  left : Int,
  right : Int,
) -> Result[Int?, RowIssue] {
  if !begin_bounded_sequence_comparison(state, left, right, IdentityComparison) {
    return Err(InvalidRows)
  }
  let result = bounded_sequence_compare_value(
    state,
    left,
    right,
    state.identity_column,
  ).map_err(issue => {
    match issue {
      Rows(issue) => issue
      _ => InvalidRows
    }
  })
  if result is Ok(Some(_)) {
    clear_bounded_sequence_comparison(state)
  }
  result
}

///|
fn bounded_sequence_compare_order(
  state : BoundedSequenceState,
  left : Int,
  right : Int,
) -> Result[Int?, RowIssue] {
  if !begin_bounded_sequence_comparison(state, left, right, OrderedComparison) {
    return Err(InvalidRows)
  }
  if state.compare_column < state.key_columns.length() {
    match
      bounded_sequence_compare_value(
        state,
        left,
        right,
        state.key_columns[state.compare_column],
      ) {
      Ok(None) => return Ok(None)
      Ok(Some(0)) => {
        state.compare_column += 1
        return Ok(None)
      }
      Ok(Some(value)) => {
        clear_bounded_sequence_comparison(state)
        return Ok(Some(value))
      }
      Err(Rows(issue)) => return Err(issue)
      Err(_) => return Err(InvalidRows)
    }
  }
  if state.clocks[left] < state.clocks[right] {
    clear_bounded_sequence_comparison(state)
    return Ok(Some(-1))
  }
  if state.clocks[left] > state.clocks[right] {
    clear_bounded_sequence_comparison(state)
    return Ok(Some(1))
  }
  let result = bounded_sequence_compare_value(
    state,
    left,
    right,
    state.identity_column,
  ).map_err(issue => {
    match issue {
      Rows(issue) => issue
      _ => InvalidRows
    }
  })
  if result is Ok(Some(_)) {
    clear_bounded_sequence_comparison(state)
  }
  result
}

///|
fn bounded_sequence_start_sort(
  state : BoundedSequenceState,
  compare : (Int, Int) -> Result[Int?, RowIssue],
) -> Bool {
  guard bounded_sequence_input_row_count(state.input) is Some(count) else {
    return false
  }
  if count > (state.workspace.limit - state.workspace.live) / 2 ||
    !reserve_slots(state.workspace, count * 2) {
    return false
  }
  state.sort = start_bounded_index_sort_stepped(state.engine, count, compare)
  state.sort is Some(_)
}

///|
fn bounded_sequence_same_key(
  state : BoundedSequenceState,
  left_position : Int,
  right_position : Int,
) -> Result[Bool?, BoundedSequenceMatchIssue] {
  let left = state.ordered[left_position]
  let right = state.ordered[right_position]
  if !begin_bounded_sequence_comparison(state, left, right, PartitionComparison) {
    return Err(InvalidExecution)
  }
  if state.compare_column == state.key_columns.length() {
    clear_bounded_sequence_comparison(state)
    return Ok(Some(true))
  }
  match
    bounded_sequence_compare_value(
      state,
      left,
      right,
      state.key_columns[state.compare_column],
    ) {
    Ok(None) => Ok(None)
    Ok(Some(0)) => {
      state.compare_column += 1
      Ok(None)
    }
    Ok(Some(_)) => {
      clear_bounded_sequence_comparison(state)
      Ok(Some(false))
    }
    Err(issue) => Err(issue)
  }
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
  state.continuation = continuation
  state.phase = BuildPredicateInput
}

///|
/// Compare a checked pattern role without allocating label + suffix. This is
/// exact UTF-16 spelling equality, not identity or normalization. Each call
/// inspects at most 64 units; the caller preserves original label charges.
fn bounded_sequence_pattern_name(
  state : BoundedSequenceState,
  name : String,
  label : String,
  suffix : String,
) -> Bool? {
  if name.length() < label.length() ||
    name.length() - label.length() != suffix.length() {
    state.output_name_offset = 0
    return Some(false)
  }
  let mut used = 0
  while state.output_name_offset < name.length() && used < 64 {
    let offset = state.output_name_offset
    let expected = if offset < label.length() {
      label[offset]
    } else {
      suffix[offset - label.length()]
    }
    state.output_name_offset += 1
    used += 1
    if name[offset] != expected {
      state.output_name_offset = 0
      return Some(false)
    }
  }
  if state.output_name_offset == name.length() {
    state.output_name_offset = 0
    Some(true)
  } else {
    None
  }
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
  state.copy_source = Some(positions)
  state.copy_positions = []
  state.copy_index = 0
  state.copy_extra = None
  state.copy_reserved = positions.length() + 1
  state.copy_kind = if state.phase is DisallowNext {
    MatchDisallow
  } else {
    MatchAllow
  }
  state.phase = CopyPositions
  Ok(())
}

///|
fn bounded_sequence_advance_group(state : BoundedSequenceState) -> Unit {
  state.group_start = state.group_end
  state.group_end = state.group_start
  state.cursor = state.group_start
  state.position = state.group_start
  state.pattern = 0
  state.prior_index = 0
  state.phase = StartGroup
}

///|
// Drop at most one position or container. Partial records have no separate
// slot in the existing accounting contract; their positions and outer
// pattern containers do. Cleanup retains the whole reservation until done.
fn bounded_sequence_pop_partial(state : BoundedSequenceState) -> Bool {
  if state.partials.is_empty() {
    return false
  }
  let patterns = state.partials[state.partials.length() - 1]
  if patterns.is_empty() {
    state.partials.pop() |> ignore
  } else {
    let positions = patterns[patterns.length() - 1].positions
    if positions.is_empty() {
      patterns.pop() |> ignore
    } else {
      positions.pop() |> ignore
    }
  }
  true
}

///|
fn bounded_sequence_pop_match(state : BoundedSequenceState) -> Bool {
  if state.matches.is_empty() {
    return false
  }
  let positions = state.matches[state.matches.length() - 1].positions
  if positions.is_empty() {
    state.matches.pop() |> ignore
  } else {
    positions.pop() |> ignore
  }
  true
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
      PrepareCompletionPort => {
        guard state.port_preparation is Some(cursor) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        match advance_trusted_output_preparation(cursor) {
          Err(issue) =>
            return bounded_sequence_failure(
              Completion(issue),
              progress,
              used + 1,
            )
          Ok(false) => ()
          Ok(true) => {
            let live = state.live
            let rows = state.rows
            state.port = match
              finish_trusted_output_preparation(cursor, fn(_) {
                if live.val {
                  rows.val
                } else {
                  None
                }
              }) {
              Ok(port) => Some(port)
              Err(issue) =>
                return bounded_sequence_failure(
                  Completion(issue),
                  progress,
                  used + 1,
                )
            }
            state.port_preparation = None
            state.phase = LoadInputNames
          }
        }
        used += 1
      }
      LoadInputNames => {
        if state.input_names.length() == @schema.field_count(state.input_schema) {
          state.phase = ResolveColumns
          continue
        }
        guard @schema.field_reference_name_at(
            state.input_schema,
            state.input_names.length(),
          )
          is Some(name) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        state.input_names.push(name)
        used += 1
        progress += 1
      }
      ResolveColumns => {
        let key_count = @lower.sequence_match_key_count(state.kernel)
        if state.resolve_field == key_count + 2 {
          state.phase = LoadOutputNames
          continue
        }
        let field = if state.resolve_field < key_count {
          @lower.sequence_match_key_at(state.kernel, state.resolve_field)
        } else if state.resolve_field == key_count {
          Some(@lower.sequence_match_identity(state.kernel))
        } else {
          Some(@lower.sequence_match_time(state.kernel))
        }
        guard field is Some(field) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        if state.metadata_lookup is None {
          guard start_charged_row_metadata_lookup(
              state.input_schema,
              field,
              state.workspace,
              true,
            )
            is Some(cursor) else {
            return bounded_sequence_failure(Rows(RowLimit), progress, used)
          }
          state.metadata_lookup = Some(cursor)
        }
        match
          advance_charged_row_metadata_lookup(
            state.metadata_lookup.unwrap(),
            state.control,
          ) {
          Err(issue) =>
            return bounded_sequence_failure(Rows(issue), progress, used + 1)
          Ok(None) => ()
          Ok(Some(column)) => {
            state.metadata_lookup = None
            if column < 0 {
              return bounded_sequence_failure(
                InvalidExecution,
                progress,
                used + 1,
              )
            }
            if state.resolve_field < key_count {
              state.key_columns.push(column)
            } else if state.resolve_field == key_count {
              state.identity_column = column
            } else {
              state.time_column = column
            }
            state.resolve_field += 1
          }
        }
        used += 1
        progress += 1
      }
      LoadOutputNames => {
        if state.output_names.length() ==
          @schema.field_count(state.output_schema) {
          state.phase = InitializePredicates
          continue
        }
        guard @schema.field_reference_name_at(
            state.output_schema,
            state.output_names.length(),
          )
          is Some(name) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        state.output_names.push(name)
        used += 1
        progress += 1
      }
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
          Ok(Some(0)) =>
            return bounded_sequence_failure(
              Rows(AssertionDuplicate(before, after)),
              progress,
              used + 1,
            )
          Ok(Some(_)) => state.unique_index += 1
          Ok(None) => ()
          Err(issue) =>
            return bounded_sequence_failure(Rows(issue), progress, used + 1)
        }
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
          Ok(Some(true)) => {
            state.group_end += 1
            state.phase = StartGroup
          }
          Ok(Some(false)) => {
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
          Ok(None) => ()
          Err(issue) =>
            return bounded_sequence_failure(issue, progress, used + 1)
        }
        used += 1
        progress += 1
      }
      DisallowFirst => {
        if state.cursor >= state.group_end {
          state.phase = ReleaseGroup
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
            if !reserve_slots(state.workspace, 1) {
              return bounded_sequence_failure(Rows(RowLimit), progress, used)
            }
            state.selected.push(state.cursor)
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
          state.cursor = state.position + 1
          used += 1
          progress += 1
          continue
        }
        let next = state.position + 1
        if next >= state.group_end {
          state.cursor = state.group_match_start + 1
          state.phase = ReleaseSelected
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
              state.cursor = state.group_match_start + 1
              state.phase = ReleaseSelected
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
              state.cursor = state.group_match_start + 1
              state.phase = ReleaseSelected
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
          state.phase = InitializeAllowPartials
          continue
        }
        if state.position == state.group_end {
          state.phase = ReleaseGroup
          continue
        }
        if state.row_matches.is_empty() {
          state.phase = InitializeRowMatches
          continue
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
      InitializeAllowPartials => {
        if state.partials.length() == state.pattern_count {
          state.phase = PrepareAllowPattern
          continue
        }
        if !reserve_slots(state.workspace, 1) {
          return bounded_sequence_failure(Rows(RowLimit), progress, used)
        }
        state.partials.push([])
        used += 1
        progress += 1
      }
      InitializeRowMatches => {
        if state.row_matches.length() == state.pattern_count {
          state.phase = PrepareAllowPattern
          continue
        }
        if !reserve_slots(state.workspace, 1) {
          return bounded_sequence_failure(Rows(RowLimit), progress, used)
        }
        state.row_matches.push(false)
        used += 1
        progress += 1
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
          state.copy_source = Some(partial.positions)
          state.copy_positions = []
          state.copy_index = 0
          state.copy_extra = Some(state.position)
          state.copy_reserved = needed
          state.copy_kind = ExtendPartial
          state.phase = CopyPositions
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
        state.position += 1
        state.pattern = 0
        state.prior_index = 0
        state.phase = ReleaseRowMatches
        used += 1
        progress += 1
      }
      CopyPositions => {
        guard state.copy_source is Some(source) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        // Destination capacity was reserved once before any append. The
        // added physical resume work does not alter logical control charges.
        if state.copy_index < source.length() {
          if state.copy_positions.length() >= state.copy_reserved {
            return bounded_sequence_failure(Rows(RowLimit), progress, used)
          }
          state.copy_positions.push(source[state.copy_index])
          state.copy_index += 1
        } else if state.copy_extra is Some(extra) {
          if state.copy_positions.length() >= state.copy_reserved {
            return bounded_sequence_failure(Rows(RowLimit), progress, used)
          }
          state.copy_positions.push(extra)
          state.copy_extra = None
        } else {
          let positions = state.copy_positions
          state.copy_positions = []
          state.copy_source = None
          state.copy_reserved = 0
          match state.copy_kind {
            ExtendPartial => {
              state.partials[state.pattern].push({ positions, })
              if state.pattern == state.pattern_count - 1 {
                match bounded_sequence_append_match(state, positions) {
                  Ok(_) => ()
                  Err(issue) =>
                    return bounded_sequence_failure(issue, progress, used + 1)
                }
              } else {
                state.phase = ExtendAllowPattern
              }
            }
            MatchAllow => {
              state.matches.push({ positions, })
              state.phase = ExtendAllowPattern
            }
            MatchDisallow => {
              state.matches.push({ positions, })
              state.phase = ReleaseSelected
            }
          }
        }
        used += 1
        progress += 1
      }
      ReleaseSelected => {
        if state.selected.is_empty() {
          state.phase = DisallowFirst
          continue
        }
        state.selected.pop() |> ignore
        release_slots(state.workspace, 1)
        used += 1
        progress += 1
      }
      ReleaseGroup => {
        if !state.partials.is_empty() {
          let patterns = state.partials[state.partials.length() - 1]
          let slots = if patterns.is_empty() ||
            !patterns[patterns.length() - 1].positions.is_empty() {
            1
          } else {
            0
          }
          bounded_sequence_pop_partial(state) |> ignore
          release_slots(state.workspace, slots)
        } else if !state.row_matches.is_empty() {
          state.row_matches.pop() |> ignore
          release_slots(state.workspace, 1)
        } else if !state.selected.is_empty() {
          state.selected.pop() |> ignore
          release_slots(state.workspace, 1)
        } else {
          bounded_sequence_advance_group(state)
          continue
        }
        used += 1
        progress += 1
      }
      ReleaseMatches => {
        if !bounded_sequence_pop_match(state) {
          state.phase = FinishOutput
          continue
        }
        release_slots(state.workspace, 1)
        used += 1
        progress += 1
      }
      ReleaseRowMatches => {
        if state.row_matches.is_empty() {
          state.phase = PrepareAllowPattern
          continue
        }
        state.row_matches.pop() |> ignore
        release_slots(state.workspace, 1)
        used += 1
        progress += 1
      }
      ReleasePredicateInput => {
        if state.predicate_input.is_empty() {
          bounded_sequence_resume_predicate(state)
          continue
        }
        state.predicate_input.pop() |> ignore
        release_slots(state.workspace, 1)
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
            start_predicate_expression_with_input(
              expression,
              indexed_expression_input(state.predicate_input),
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
        if state.name_charge is None {
          guard start_row_name_charge(
              state.input_names[column],
              state.workspace,
            )
            is Some(cursor) else {
            return bounded_sequence_failure(Rows(RowLimit), progress, used)
          }
          state.name_charge = Some(cursor)
        }
        match
          advance_row_name_charge(
            state.name_charge.unwrap(),
            Some(state.control),
            None,
          ) {
          Err(issue) =>
            return bounded_sequence_failure(Rows(issue), progress, used + 1)
          Ok(false) => {
            used += 1
            continue
          }
          Ok(true) => state.name_charge = None
        }
        guard bounded_sequence_input_cell(state.input, row, column)
          is Some(value) &&
          reserve_slots(state.workspace, 1) else {
          return bounded_sequence_failure(Rows(RowLimit), progress, used)
        }
        state.predicate_input.push((state.input_names[column], value))
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
            state.phase = ReleasePredicateInput
          }
        }
        used += 1
        progress += 1
      }
      PrepareOutput => {
        if state.output_match == state.matches.length() {
          state.phase = ReleaseMatches
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
        state.output_key = 0
        state.output_pattern = 0
        state.output_name_offset = 0
        state.output_key_started = false
        state.output_label_part = 0
        state.output_label_started = false
        reset_bounded_text_charge(state.output_label_charge)
        state.phase = ResolveOutputKey
      }
      ResolveOutputKey => {
        let name = state.output_names[state.output_column]
        let match_ = state.matches[state.output_match]
        let first = state.ordered[match_.positions[0]]
        if state.output_key < state.key_columns.length() {
          guard @lower.sequence_match_key_at(state.kernel, state.output_key)
            is Some(key) else {
            return bounded_sequence_failure(InvalidExecution, progress, used)
          }
          if !state.output_key_started {
            if !spend_control(state.control, 1) {
              return bounded_sequence_failure(Rows(RowLimit), progress, used)
            }
            state.output_key_started = true
          }
          let (order, offset, _) = @schema.compare_reference_fragment(
            key,
            @schema.Unqualified(name),
            state.output_name_offset,
            64,
          )
          state.output_name_offset = offset
          if order is None {
            used += 1
            continue
          }
          state.output_key_started = false
          if order is Some(0) {
            guard bounded_sequence_input_cell(
                state.input,
                first,
                state.key_columns[state.output_key],
              )
              is Some(value) else {
              return bounded_sequence_failure(InvalidExecution, progress, used)
            }
            state.output_row.push(value)
            state.output_column += 1
            state.phase = BuildOutputRow
          } else {
            state.output_key += 1
          }
          used += 1
          progress += 1
        } else if name == "match_start_ms" || name == "match_end_ms" {
          let row = if name == "match_start_ms" {
            first
          } else {
            state.ordered[match_.positions[match_.positions.length() - 1]]
          }
          state.output_row.push(Number(state.clocks[row].to_double()))
          state.output_column += 1
          state.phase = BuildOutputRow
          used += 1
          progress += 1
        } else {
          state.phase = ResolveOutputPattern
        }
      }
      ResolveOutputPattern => {
        if state.output_pattern == state.pattern_count {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        guard @lower.sequence_match_pattern_label(
            state.kernel,
            state.output_pattern,
          )
          is Some(label) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        let name = state.output_names[state.output_column]
        let match_ = state.matches[state.output_match]
        let source = state.ordered[match_.positions[state.output_pattern]]
        if state.output_label_part == 0 || state.output_label_part == 2 {
          if !state.output_label_started {
            if !spend_control(state.control, 1) {
              return bounded_sequence_failure(Rows(RowLimit), progress, used)
            }
            state.output_label_started = true
          }
          match
            advance_bounded_text_charge(
              state.output_label_charge,
              state.control,
              label,
            ) {
            Err(_) =>
              return bounded_sequence_failure(
                Rows(RowLimit),
                progress,
                used + 1,
              )
            Ok(false) => ()
            Ok(true) => {
              if !spend_control(
                  state.control,
                  if state.output_label_part == 0 {
                    3
                  } else {
                    8
                  },
                ) {
                return bounded_sequence_failure(
                  Rows(RowLimit),
                  progress,
                  used + 1,
                )
              }
              state.output_label_part += 1
              state.output_label_started = false
              reset_bounded_text_charge(state.output_label_charge)
            }
          }
          used += 1
          continue
        }
        let matches = bounded_sequence_pattern_name(
          state,
          name,
          label,
          if state.output_label_part == 1 {
            "_id"
          } else {
            "_time_ms"
          },
        )
        if matches is None {
          used += 1
          continue
        }
        if matches is Some(true) && state.output_label_part == 1 {
          guard bounded_sequence_input_cell(
              state.input,
              source,
              state.identity_column,
            )
            is Some(value) else {
            return bounded_sequence_failure(InvalidExecution, progress, used)
          }
          state.output_row.push(value)
          state.output_column += 1
          state.phase = BuildOutputRow
        } else if state.output_label_part == 1 {
          state.output_label_part = 2
        } else if matches is Some(true) {
          state.output_row.push(Number(state.clocks[source].to_double()))
          state.output_column += 1
          state.phase = BuildOutputRow
        } else {
          state.output_pattern += 1
          state.output_label_part = 0
        }
        used += 1
        progress += 1
      }
      CheckOutputRow => {
        if state.output_recheck is Some(cursor) {
          match @admitted.advance_recheck_runtime_value(cursor) {
            RecheckContinue => ()
            RecheckFailed =>
              return bounded_sequence_failure(
                InvalidExecution,
                progress,
                used + 1,
              )
            RecheckComplete(checked, _, _) => {
              state.output_recheck = None
              state.checked_row.push(checked.value)
              state.output_column += 1
            }
          }
          used += 1
          continue
        }
        if state.output_column == state.output_names.length() {
          state.phase = CommitOutputRow
          continue
        }
        guard @schema.field_at(state.output_schema, state.output_column)
          is Some(field) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        let cell = state.output_row[state.output_column]
        if bounded_small_output_value(cell) {
          guard checked_ordered_output_value(
              cell,
              field.contract,
              state.admitted_limits,
            )
            is Some(checked) else {
            return bounded_sequence_failure(InvalidExecution, progress, used)
          }
          state.checked_row.push(checked.value)
          state.output_column += 1
        } else {
          guard start_ordered_output_value_recheck(
              cell,
              field.contract,
              state.admitted_limits,
            )
            is Some(cursor) else {
            return bounded_sequence_failure(InvalidExecution, progress, used)
          }
          state.output_recheck = Some(cursor)
        }
        used += 1
        progress += 1
      }
      CommitOutputRow => {
        guard state.output is Some(output) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        if state.output_charge is None {
          match
            start_bounded_output_row_charge(
              output,
              state.checked_row,
              state.workspace,
            ) {
            Err(OutputCapture(issue)) =>
              return bounded_sequence_failure(
                Capture(issue),
                progress,
                used + 1,
              )
            Err(OutputWorkspace) =>
              return bounded_sequence_failure(
                Rows(RowLimit),
                progress,
                used + 1,
              )
            Ok(cursor) => state.output_charge = Some(cursor)
          }
          used += 1
          continue
        }
        match advance_bounded_output_row_charge(state.output_charge.unwrap()) {
          Err(OutputCapture(issue)) =>
            return bounded_sequence_failure(Capture(issue), progress, used + 1)
          Err(OutputWorkspace) =>
            return bounded_sequence_failure(Rows(RowLimit), progress, used + 1)
          Ok(false) => {
            used += 1
            continue
          }
          Ok(true) => state.output_charge = None
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
        guard state.port is Some(port) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        guard state.output is Some(output) else {
          return bounded_sequence_failure(InvalidExecution, progress, used)
        }
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return bounded_sequence_failure(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(port, ()) {
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
    @lower.sequence_step(sequence, step)
    is Some(@lower.SequenceMatchStep(kernel)) &&
    bounded_sequence_input_row_count(input) is Some(count) else {
    return Err(InvalidExecution)
  }
  if count > max_rows {
    return Err(Rows(RowLimit))
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
  let key_columns : Array[Int] = []
  let mut output_limit = match @lower.sequence_match_output_limit(kernel) {
    Some(value) => Int64::min(value, max_rows.to_int64()).to_int()
    None => max_rows
  }
  let mut per_key_limit = match @lower.sequence_match_per_key_limit(kernel) {
    Some(value) => Int64::min(value, max_rows.to_int64()).to_int()
    None => max_rows
  }
  if output_limit < 0 || per_key_limit < 0 {
    return Err(InvalidExecution)
  }
  if generated_sequence_match_limits(generated, step) is Some((matches, output)) {
    per_key_limit = Int64::min(per_key_limit.to_int64(), matches).to_int()
    output_limit = Int64::min(output_limit.to_int64(), output).to_int()
  }
  let output = match
    prepare_bounded_admitted_output(
      owner,
      @pipeline.Step(step),
      output_limit,
      values,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let rows : Ref[AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let predicate_entries = Ref(0)
  let port_preparation = match
    start_trusted_output_preparation(
      generated_completion_preparation(generated),
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      Some(trusted_inputs),
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedSequenceState = {
    input,
    input_schema: schema,
    kernel,
    key_columns,
    identity_column: -1,
    time_column: -1,
    input_names: [],
    output_schema,
    output_names: [],
    resolve_field: 0,
    metadata_lookup: None,
    name_charge: None,
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
    port: None,
    port_preparation: Some(port_preparation),
    phase: PrepareCompletionPort,
    continuation: ResumeDisallowFirst,
    sort: None,
    comparison: None,
    compare_left: -1,
    compare_right: -1,
    compare_kind: None,
    compare_column: 0,
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
    copy_source: None,
    copy_positions: [],
    copy_index: 0,
    copy_extra: None,
    copy_kind: MatchDisallow,
    copy_reserved: 0,
    predicate_input: [],
    predicate_field: 0,
    predicate_position: 0,
    predicate_pattern: 0,
    predicate_execution: None,
    output_match: 0,
    output_column: 0,
    output_key: 0,
    output_pattern: 0,
    output_name_offset: 0,
    output_key_started: false,
    output_label_part: 0,
    output_label_started: false,
    output_label_charge: { offset: 0, next: 0, remaining: 0, },
    output_scope: None,
    output_row: [],
    checked_row: [],
    output_recheck: None,
    output_charge: None,
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
