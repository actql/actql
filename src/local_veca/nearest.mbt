///|
priv struct NearestInputView {
  source : NearestProducerInputValue
  vectors : @carrier.Vectors
  records : Int
  identity_count : Int
  component_name : String
  dimensions : Int
}

///|
/// One exact checked producer use site for a nearest-neighbor operand.
/// Relation and Vectors inputs retain their distinct runtime authorities.
struct NearestProducerInput {
  value : NearestProducerInputValue
}

///|
priv enum NearestProducerInputValue {
  RelationProducer(@execution.ProducerRead)
  CarrierProducer(@carrier_runtime.ProducerView)
}

///|
pub fn nearest_relation_producer(
  value : @execution.ProducerRead,
) -> NearestProducerInput {
  { value: RelationProducer(value), }
}

///|
pub fn nearest_carrier_producer(
  value : @carrier_runtime.ProducerView,
) -> NearestProducerInput {
  { value: CarrierProducer(value), }
}

///|
/// Bind a Vectors generation produced by an earlier step in this sequence.
pub fn nearest_record_producer(
  value : @records.ProducerRead,
) -> NearestProducerInput? {
  match @records.producer_read_view(value) {
    Ok(view) => Some({ value: CarrierProducer(view), })
    Err(_) => None
  }
}

///|
priv struct NearestRecord {
  identities : Array[@value.CheckedValue]
  vector : @value.CheckedValue
}

///|
priv struct NearestScore {
  candidate : Int
  score : Double
}

///|
priv enum NearestSortTarget {
  SortCandidates
  SortQueries
}

///|
priv enum NearestPhase {
  BeginInputRecord
  InitializeIdentitySlots
  ReadInputField
  RecheckInputField
  MatchInputIdentity
  FinishInputRecord
  ValidateInputComponent
  InitializeRecordScratch
  PrepareRecordSort
  PrepareRecordMerge
  MergeRecords
  CompareRecordIdentity
  CopyRecordPass
  ValidateUniqueRecords
  BeginQuery
  InitializeScoreScratch
  BeginCandidateScore
  FoldCandidateScore
  PrepareScoreSort
  PrepareScoreMerge
  MergeScores
  CompareScoreIdentity
  CopyScorePass
  BeginEmit
  BuildQueryIdentity
  BuildCandidateIdentity
  StartOutputRow
  EmitResult
  FinishNearest
}

///|
priv struct NearestState {
  candidates_input : NearestInputView
  queries_input : NearestInputView
  output_schema : @schema.Schema
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  metric : @numeric.Metric
  k : Int
  value_limits : @value.Limits
  mut input_recheck : (@schema.FieldName, @value.RecheckCursor)?
  mut phase : NearestPhase
  mut reading_queries : Bool
  mut record : Int
  mut field : Int
  mut identity_probe : Int
  mut current_field : (@schema.FieldName, @value.CheckedValue)?
  mut identity_values : Array[@value.CheckedValue?]
  mut validated_identities : Array[@value.CheckedValue]
  mut key_comparison : @value.BoundedKeyComparison?
  mut source_vector : @value.CheckedValue?
  mut candidates : Array[NearestRecord]
  mut queries : Array[NearestRecord]
  mut sort_target : NearestSortTarget
  mut sorting : Array[NearestRecord]
  mut record_scratch : Array[NearestRecord?]
  mut width : Int
  mut run_start : Int
  mut left_index : Int
  mut middle : Int
  mut right_index : Int
  mut run_end : Int
  mut merge_index : Int
  mut tie_index : Int
  mut copy_index : Int
  mut unique_index : Int
  mut query_index : Int
  mut candidate_index : Int
  mut component : Int
  mut fold : @numeric.ScoreFold?
  mut scores : Array[NearestScore]
  mut score_scratch : Array[NearestScore?]
  mut emit_index : Int
  mut query_output_identity : @value.Value?
  mut candidate_output_identity : @value.Value?
  mut identity_builder : @value.ObjectBuilder?
  mut output_identity_index : Int
  mut output_row : @execution.AdmittedOutputRowCursor?
  mut control_work_remaining : Int
}

///|
struct NearestExecution {
  session : @bounded.Session[
    NearestState,
    @execution.CompletedOutput,
    NearestIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum NearestPoll {
  NearestContinue(progress~ : Int64, work~ : Int64)
  NearestComplete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  NearestFailed(NearestIssue, progress~ : Int64, work~ : Int64)
  NearestStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum NearestIssue {
  InvalidNearestKernel
  InvalidNearestLimits
  NearestInputUnavailable
  InvalidNearestRecord(Bool, Int)
  DuplicateNearestIdentity(Bool, Int)
  NearestWorkspaceLimit
  NearestWorkLimit
  NearestOutputLimit
  NearestNumeric(@numeric.Issue)
  NearestKeyOrder(@value.KeyOrderIssue)
  NearestOutput(@execution.CaptureIssue)
  NearestCompletion(@execution.TrustedOutputIssue)
  NearestExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn nearest_checked_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn nearest_checked_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn nearest_workspace(
  candidates : Int,
  queries : Int,
  candidate_ids : Int,
  query_ids : Int,
  recheck_slots? : Int = 0,
) -> Int? {
  // Identity scratch is used while reading inputs, then reused for the two
  // provisional composite output identities. Those phases never overlap.
  // Eight additional fixed slots cover the four-field row and its traversal
  // frames; output values themselves use the existing logical output budget.
  guard nearest_checked_add(candidate_ids, 2) is Some(candidate_width) &&
    nearest_checked_add(query_ids, 2) is Some(query_width) &&
    nearest_checked_multiply(candidates, candidate_width)
    is Some(candidate_records) &&
    nearest_checked_multiply(queries, query_width) is Some(query_records) &&
    nearest_checked_multiply(candidates, 4) is Some(scores) &&
    nearest_checked_multiply(
      Int::max(candidates, queries),
      Int::max(candidate_width, query_width),
    )
    is Some(record_scratch) &&
    nearest_checked_add(candidate_records, query_records) is Some(first) &&
    nearest_checked_add(first, scores) is Some(second) &&
    nearest_checked_add(second, record_scratch) is Some(third) &&
    nearest_checked_add(candidate_ids, query_ids) is Some(identity_slots) &&
    nearest_checked_add(identity_slots, 16) is Some(fixed_slots) &&
    nearest_checked_add(third, fixed_slots) is Some(fourth) &&
    nearest_checked_add(fourth, recheck_slots) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn nearest_input_available(input : NearestInputView) -> Bool {
  match input.source {
    RelationProducer(read) => @execution.producer_read_available(read)
    CarrierProducer(view) =>
      @carrier_runtime.producer_view_record_count(view) is Some(_)
  }
}

///|
fn nearest_input_field_count(input : NearestInputView, record : Int) -> Int? {
  match input.source {
    RelationProducer(read) =>
      if record >= 0 && record < input.records {
        Some(@schema.field_count(@execution.producer_read_schema(read)))
      } else {
        None
      }
    CarrierProducer(view) =>
      match @carrier_runtime.producer_view_record_field_count(view, record) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn nearest_input_field(
  input : NearestInputView,
  record : Int,
  field : Int,
) -> (@schema.FieldName, @value.CheckedValue)? {
  match input.source {
    // Relation input is authorized only by the completed common recheck.
    RelationProducer(_) => None
    CarrierProducer(view) =>
      match @carrier_runtime.producer_view_record_field(view, record, field) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn current_input(state : NearestState) -> NearestInputView {
  if state.reading_queries {
    state.queries_input
  } else {
    state.candidates_input
  }
}

///|
fn current_records(state : NearestState) -> Array[NearestRecord] {
  if state.reading_queries {
    state.queries
  } else {
    state.candidates
  }
}

///|
fn begin_nearest_record(state : NearestState) -> Unit {
  state.field = 0
  state.identity_probe = 0
  state.current_field = None
  state.identity_values = []
  state.validated_identities = []
  state.source_vector = None
  state.phase = InitializeIdentitySlots
}

///|
fn read_nearest_field(state : NearestState) -> Result[Unit, NearestIssue] {
  let input = current_input(state)
  if input.source is RelationProducer(read) {
    guard relation_cell_recheck(read, state.record, state.field, state.value_limits)
      is Some(pending) else {
      return Err(InvalidNearestRecord(state.reading_queries, state.record))
    }
    state.input_recheck = Some(pending)
    state.phase = RecheckInputField
    return Ok(())
  }
  guard nearest_input_field(input, state.record, state.field)
    is Some((name, value)) else {
    return Err(InvalidNearestRecord(state.reading_queries, state.record))
  }
  bind_nearest_field(state, name, value)
}

///|
fn bind_nearest_field(
  state : NearestState,
  name : @schema.FieldName,
  value : @value.CheckedValue,
) -> Result[Unit, NearestIssue] {
  let input = current_input(state)
  if @schema.reference_name(name) == input.component_name {
    if state.source_vector is Some(_) {
      return Err(InvalidNearestRecord(state.reading_queries, state.record))
    }
    state.source_vector = Some(value)
  }
  state.current_field = Some((name, value))
  state.identity_probe = 0
  state.phase = MatchInputIdentity
  Ok(())
}

///|
fn match_nearest_identity(state : NearestState) -> Result[Unit, NearestIssue] {
  let input = current_input(state)
  guard state.current_field is Some((name, value)) &&
    @carrier.vector_identity_at(input.vectors, state.identity_probe)
    is Some(identity) else {
    return Err(InvalidNearestRecord(state.reading_queries, state.record))
  }
  if name == identity.name {
    if state.identity_values[state.identity_probe] is Some(_) {
      return Err(InvalidNearestRecord(state.reading_queries, state.record))
    }
    state.identity_values[state.identity_probe] = Some(value)
  }
  state.identity_probe += 1
  if state.identity_probe >= input.identity_count {
    state.current_field = None
    state.field += 1
    state.phase = ReadInputField
  }
  Ok(())
}

///|
fn finish_nearest_record(state : NearestState) -> Result[Unit, NearestIssue] {
  let input = current_input(state)
  guard state.source_vector is Some(vector) &&
    vector.value is @value.Vector(components) &&
    @value.element_count(components) == input.dimensions else {
    return Err(InvalidNearestRecord(state.reading_queries, state.record))
  }
  let index = state.validated_identities.length()
  guard index < state.identity_values.length() &&
    state.identity_values[index] is Some(value) else {
    return Err(InvalidNearestRecord(state.reading_queries, state.record))
  }
  match compare_nearest_values(state, value, value) {
    Ok(None) => return Ok(())
    Ok(Some(_)) => state.validated_identities.push(value)
    Err(issue) => return Err(issue)
  }
  if state.validated_identities.length() < input.identity_count {
    return Ok(())
  }
  current_records(state).push({
    identities: state.validated_identities,
    vector,
  })
  state.validated_identities = []
  state.identity_values = []
  state.source_vector = None
  state.record += 1
  state.component = 0
  state.phase = ValidateInputComponent
  Ok(())
}

///|
fn validate_nearest_input_component(
  state : NearestState,
) -> Result[Unit, NearestIssue] {
  let input = current_input(state)
  if state.component >= input.dimensions {
    state.phase = BeginInputRecord
    return Ok(())
  }
  guard current_records(state)[state.record - 1].vector.value
    is @value.Vector(components) &&
    @value.element_at(components, state.component) is Some(component) else {
    return Err(InvalidNearestRecord(state.reading_queries, state.record - 1))
  }
  match @numeric.quantize(component) {
    Ok(_) => {
      state.component += 1
      Ok(())
    }
    Err(issue) => Err(NearestNumeric(issue))
  }
}

///|
fn capped_nearest_run_end(start : Int, width : Int, count : Int) -> Int {
  if width >= count - start {
    count
  } else {
    start + width
  }
}

///|
fn prepare_nearest_record_merge(state : NearestState) -> Unit {
  state.middle = capped_nearest_run_end(
    state.run_start,
    state.width,
    state.sorting.length(),
  )
  state.run_end = capped_nearest_run_end(
    state.middle,
    state.width,
    state.sorting.length(),
  )
  state.left_index = state.run_start
  state.right_index = state.middle
  state.merge_index = state.run_start
  state.tie_index = 0
  state.phase = MergeRecords
}

///|
fn emit_nearest_record_merge(state : NearestState, take_left : Bool) -> Unit {
  let selected = if take_left {
    let value = state.sorting[state.left_index]
    state.left_index += 1
    value
  } else {
    let value = state.sorting[state.right_index]
    state.right_index += 1
    value
  }
  state.record_scratch[state.merge_index] = Some(selected)
  state.merge_index += 1
  if state.merge_index >= state.run_end {
    state.run_start = state.run_end
    state.phase = PrepareRecordMerge
  } else {
    state.phase = MergeRecords
  }
}

///|
fn merge_nearest_record(state : NearestState) -> Unit {
  if state.left_index >= state.middle {
    emit_nearest_record_merge(state, false)
  } else if state.right_index >= state.run_end {
    emit_nearest_record_merge(state, true)
  } else {
    state.tie_index = 0
    state.phase = CompareRecordIdentity
  }
}

///|
/// Scan one unit under the common typed key owner. Pending comparisons keep
/// their phase, record pair and component index until the cursor completes.
fn compare_nearest_values(
  state : NearestState,
  left : @value.CheckedValue,
  right : @value.CheckedValue,
) -> Result[Int?, NearestIssue] {
  let active = match state.key_comparison {
    Some(value) => value
    None => {
      let value = match @value.start_bounded_key_comparison(left, right) {
        Ok(value) => value
        Err(issue) => return Err(NearestKeyOrder(issue))
      }
      state.key_comparison = Some(value)
      value
    }
  }
  match @value.advance_bounded_key_comparison(active, 1) {
    Ok(@value.KeyComparisonContinue(_)) => Ok(None)
    Ok(@value.KeyComparisonComplete(order~, ..)) => {
      state.key_comparison = None
      Ok(Some(order))
    }
    Err(issue) => Err(NearestKeyOrder(issue))
  }
}

///|
fn compare_nearest_record(state : NearestState) -> Result[Unit, NearestIssue] {
  let left = state.sorting[state.left_index]
  let right = state.sorting[state.right_index]
  if state.tie_index >= left.identities.length() {
    emit_nearest_record_merge(state, true)
    return Ok(())
  }
  let comparison = match
    compare_nearest_values(
      state,
      left.identities[state.tie_index],
      right.identities[state.tie_index],
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Ok(())
    Err(issue) => return Err(issue)
  }
  if comparison < 0 {
    emit_nearest_record_merge(state, true)
  } else if comparison > 0 {
    emit_nearest_record_merge(state, false)
  } else {
    state.tie_index += 1
  }
  Ok(())
}

///|
fn finish_nearest_record_sort(state : NearestState) -> Unit {
  match state.sort_target {
    SortCandidates => {
      state.candidates = state.sorting
      state.sorting = []
      state.record_scratch = []
      state.unique_index = 1
      state.tie_index = 0
      state.phase = ValidateUniqueRecords
    }
    SortQueries => {
      state.queries = state.sorting
      state.sorting = []
      state.record_scratch = []
      state.unique_index = 1
      state.tie_index = 0
      state.phase = ValidateUniqueRecords
    }
  }
}

///|
fn validate_nearest_unique(state : NearestState) -> Result[Unit, NearestIssue] {
  let records = match state.sort_target {
    SortCandidates => state.candidates
    SortQueries => state.queries
  }
  if state.unique_index < records.length() {
    let left = records[state.unique_index - 1]
    let right = records[state.unique_index]
    if state.tie_index >= left.identities.length() {
      return Err(
        DuplicateNearestIdentity(
          state.sort_target is SortQueries,
          state.unique_index,
        ),
      )
    }
    let compared = match
      compare_nearest_values(
        state,
        left.identities[state.tie_index],
        right.identities[state.tie_index],
      ) {
      Ok(Some(value)) => value
      Ok(None) => return Ok(())
      Err(issue) => return Err(issue)
    }
    if compared == 0 {
      state.tie_index += 1
    } else {
      state.unique_index += 1
      state.tie_index = 0
    }
    Ok(())
  } else {
    match state.sort_target {
      SortCandidates => {
        state.reading_queries = true
        state.record = 0
        state.phase = BeginInputRecord
      }
      SortQueries => {
        state.query_index = 0
        state.phase = BeginQuery
      }
    }
    Ok(())
  }
}

///|
fn finish_candidate_score(state : NearestState) -> Result[Unit, NearestIssue] {
  guard state.fold is Some(fold) else { return Err(InvalidNearestKernel) }
  let score = match @numeric.finish_score(fold) {
    Ok(value) => value
    Err(issue) => return Err(NearestNumeric(issue))
  }
  state.scores.push({ candidate: state.candidate_index, score, })
  state.fold = None
  state.candidate_index += 1
  state.phase = BeginCandidateScore
  Ok(())
}

///|
fn prepare_nearest_score_merge(state : NearestState) -> Unit {
  state.middle = capped_nearest_run_end(
    state.run_start,
    state.width,
    state.scores.length(),
  )
  state.run_end = capped_nearest_run_end(
    state.middle,
    state.width,
    state.scores.length(),
  )
  state.left_index = state.run_start
  state.right_index = state.middle
  state.merge_index = state.run_start
  state.tie_index = 0
  state.phase = MergeScores
}

///|
fn emit_nearest_score_merge(state : NearestState, take_left : Bool) -> Unit {
  let selected = if take_left {
    let value = state.scores[state.left_index]
    state.left_index += 1
    value
  } else {
    let value = state.scores[state.right_index]
    state.right_index += 1
    value
  }
  state.score_scratch[state.merge_index] = Some(selected)
  state.merge_index += 1
  if state.merge_index >= state.run_end {
    state.run_start = state.run_end
    state.phase = PrepareScoreMerge
  } else {
    state.phase = MergeScores
  }
}

///|
fn merge_nearest_score(state : NearestState) -> Unit {
  if state.left_index >= state.middle {
    emit_nearest_score_merge(state, false)
  } else if state.right_index >= state.run_end {
    emit_nearest_score_merge(state, true)
  } else {
    let left = state.scores[state.left_index]
    let right = state.scores[state.right_index]
    if left.score > right.score {
      emit_nearest_score_merge(state, true)
    } else if left.score < right.score {
      emit_nearest_score_merge(state, false)
    } else {
      state.tie_index = 0
      state.phase = CompareScoreIdentity
    }
  }
}

///|
fn compare_nearest_score(state : NearestState) -> Result[Unit, NearestIssue] {
  let left = state.scores[state.left_index]
  let right = state.scores[state.right_index]
  let left_id = state.candidates[left.candidate].identities
  let right_id = state.candidates[right.candidate].identities
  if state.tie_index >= left_id.length() {
    emit_nearest_score_merge(state, true)
    return Ok(())
  }
  let comparison = match
    compare_nearest_values(
      state,
      left_id[state.tie_index],
      right_id[state.tie_index],
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Ok(())
    Err(issue) => return Err(issue)
  }
  if comparison < 0 {
    emit_nearest_score_merge(state, true)
  } else if comparison > 0 {
    emit_nearest_score_merge(state, false)
  } else {
    state.tie_index += 1
  }
  Ok(())
}

///|
fn build_nearest_output_identity(
  state : NearestState,
  query : Bool,
) -> Result[Unit, NearestIssue] {
  let identities = if query {
    state.queries[state.query_index].identities
  } else {
    state.candidates[state.scores[state.emit_index].candidate].identities
  }
  let name = if query { "query_id" } else { "candidate_id" }
  guard @schema.lookup(state.output_schema, @schema.Unqualified(name))
    is Some(contract) else {
    return Err(InvalidNearestKernel)
  }
  let value = if identities.length() == 1 {
    Some(identities[0].value)
  } else {
    guard contract.shape is @contract.Object(fields) &&
      @contract.field_count(fields) == identities.length() &&
      identities.length() < state.value_limits.max_nodes else {
      return Err(InvalidNearestKernel)
    }
    if state.identity_builder is None {
      guard @value.prepare_object_value(identities.length()) is Some(builder) else {
        return Err(InvalidNearestKernel)
      }
      state.identity_builder = Some(builder)
      state.output_identity_index = 0
      return Ok(())
    }
    let builder = state.identity_builder.unwrap()
    if state.output_identity_index < identities.length() {
      guard @contract.field_at(fields, state.output_identity_index)
        is Some(field) &&
        field.name.length() <= 10 &&
        @scalar.read_decimal_int64(field.name) is Ok(index) &&
        index >= 0L &&
        index < identities.length().to_int64() &&
        index.to_string() == field.name &&
        @value.append_object_field(
          builder,
          field.name,
          identities[index.to_int()].value,
        ) else {
        return Err(InvalidNearestKernel)
      }
      state.output_identity_index += 1
      return Ok(())
    }
    let value = @value.finish_object_value(builder)
    state.identity_builder = None
    value
  }
  guard value is Some(value) else { return Err(InvalidNearestKernel) }
  if query {
    state.query_output_identity = Some(value)
    state.phase = BuildCandidateIdentity
  } else {
    state.candidate_output_identity = Some(value)
    state.phase = StartOutputRow
  }
  Ok(())
}

///|
fn nearest_output_cell(state : NearestState, column : Int) -> @value.Value? {
  guard @schema.field_at(state.output_schema, column) is Some(field) else {
    return None
  }
  match @schema.reference_name(field.name) {
    "query_id" => state.query_output_identity
    "candidate_id" => state.candidate_output_identity
    "score" =>
      @value.checked_number_value(
        state.scores[state.emit_index].score,
        field.contract,
      ).map(value => value.value)
    "rank" =>
      @value.checked_number_value(
        (state.emit_index + 1).to_double(),
        field.contract,
      ).map(value => value.value)
    _ => None
  }
}

///|
fn nearest_output_row_issue(
  issue : @execution.AdmittedOutputRowIssue,
) -> NearestIssue {
  match issue {
    @execution.OutputRowCapture(@execution.InvalidCheckedRow) =>
      InvalidNearestKernel
    @execution.OutputRowCapture(issue) => NearestOutput(issue)
    @execution.OutputRowWorkspace => NearestWorkspaceLimit
  }
}

///|
fn nearest_step(
  state : NearestState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, NearestIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !nearest_input_available(state.candidates_input) ||
      !nearest_input_available(state.queries_input) {
      return @bounded.Failed(NearestInputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(NearestWorkLimit, progress, used)
    }
    match state.phase {
      BeginInputRecord => {
        let input = current_input(state)
        if state.record < input.records {
          begin_nearest_record(state)
        } else {
          state.sort_target = if state.reading_queries {
            SortQueries
          } else {
            SortCandidates
          }
          state.sorting = current_records(state)
          if state.reading_queries {
            state.queries = []
          } else {
            state.candidates = []
          }
          state.record_scratch = []
          state.width = 1
          state.phase = InitializeRecordScratch
        }
      }
      InitializeIdentitySlots =>
        if state.identity_values.length() < current_input(state).identity_count {
          state.identity_values.push(None)
          used += 1
        } else {
          state.phase = ReadInputField
        }
      ReadInputField => {
        let input = current_input(state)
        guard nearest_input_field_count(input, state.record)
          is Some(field_count) else {
          return @bounded.Failed(
            InvalidNearestRecord(state.reading_queries, state.record),
            progress,
            used,
          )
        }
        if state.field < field_count {
          used += 1
          match read_nearest_field(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = FinishInputRecord
        }
      }
      RecheckInputField => {
        used += 1
        guard state.input_recheck is Some((name, cursor)) else {
          return @bounded.Failed(InvalidNearestKernel, progress, used)
        }
        match @value.advance_recheck_runtime_value(cursor) {
          @value.RecheckContinue => ()
          @value.RecheckComplete(checked, _, _) => {
            state.input_recheck = None
            match bind_nearest_field(state, name, checked) {
              Ok(_) => ()
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          }
          @value.RecheckFailed =>
            return @bounded.Failed(
              InvalidNearestRecord(state.reading_queries, state.record), progress, used,
            )
        }
      }
      MatchInputIdentity => {
        used += 1
        match match_nearest_identity(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      FinishInputRecord => {
        used += 1
        match finish_nearest_record(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ValidateInputComponent => {
        used += 1
        match validate_nearest_input_component(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      InitializeRecordScratch =>
        if state.record_scratch.length() < state.sorting.length() {
          state.record_scratch.push(None)
          used += 1
        } else {
          state.phase = PrepareRecordSort
        }
      PrepareRecordSort =>
        if state.width >= state.sorting.length() {
          finish_nearest_record_sort(state)
        } else {
          state.run_start = 0
          state.phase = PrepareRecordMerge
        }
      PrepareRecordMerge =>
        if state.run_start >= state.sorting.length() {
          state.copy_index = 0
          state.phase = CopyRecordPass
        } else {
          prepare_nearest_record_merge(state)
        }
      MergeRecords => {
        merge_nearest_record(state)
        used += 1
      }
      CompareRecordIdentity => {
        used += 1
        match compare_nearest_record(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyRecordPass =>
        if state.copy_index < state.sorting.length() {
          guard state.record_scratch[state.copy_index] is Some(record) else {
            return @bounded.Failed(InvalidNearestKernel, progress, used)
          }
          state.sorting[state.copy_index] = record
          state.record_scratch[state.copy_index] = None
          state.copy_index += 1
          used += 1
        } else {
          state.width = if state.width > state.sorting.length() / 2 {
            state.sorting.length()
          } else {
            state.width * 2
          }
          state.phase = PrepareRecordSort
        }
      ValidateUniqueRecords => {
        used += 1
        match validate_nearest_unique(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      BeginQuery =>
        if state.query_index < state.queries.length() {
          state.candidate_index = 0
          state.scores = []
          state.score_scratch = []
          state.phase = InitializeScoreScratch
        } else {
          state.phase = FinishNearest
        }
      InitializeScoreScratch =>
        if state.score_scratch.length() < state.candidates.length() {
          state.score_scratch.push(None)
          used += 1
        } else {
          state.phase = BeginCandidateScore
        }
      BeginCandidateScore =>
        if state.candidate_index < state.candidates.length() {
          state.component = 0
          state.fold = Some(@numeric.prepare_score(state.metric))
          state.phase = FoldCandidateScore
        } else {
          state.width = 1
          state.phase = PrepareScoreSort
        }
      FoldCandidateScore =>
        if state.component < state.candidates_input.dimensions {
          let query = state.queries[state.query_index]
          let candidate = state.candidates[state.candidate_index]
          guard query.vector.value is @value.Vector(query_values) &&
            candidate.vector.value is @value.Vector(candidate_values) &&
            @value.element_at(query_values, state.component)
            is Some(query_value) &&
            @value.element_at(candidate_values, state.component)
            is Some(candidate_value) &&
            state.fold is Some(fold) else {
            return @bounded.Failed(InvalidNearestKernel, progress, used)
          }
          used += 1
          match @numeric.score_step(fold, candidate_value, query_value) {
            Ok(_) => state.component += 1
            Err(issue) =>
              return @bounded.Failed(NearestNumeric(issue), progress, used)
          }
        } else {
          used += 1
          match finish_candidate_score(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        }
      PrepareScoreSort =>
        if state.width >= state.scores.length() {
          state.score_scratch = []
          state.emit_index = 0
          state.phase = BeginEmit
        } else {
          state.run_start = 0
          state.phase = PrepareScoreMerge
        }
      PrepareScoreMerge =>
        if state.run_start >= state.scores.length() {
          state.copy_index = 0
          state.phase = CopyScorePass
        } else {
          prepare_nearest_score_merge(state)
        }
      MergeScores => {
        merge_nearest_score(state)
        used += 1
      }
      CompareScoreIdentity => {
        used += 1
        match compare_nearest_score(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyScorePass =>
        if state.copy_index < state.scores.length() {
          guard state.score_scratch[state.copy_index] is Some(score) else {
            return @bounded.Failed(InvalidNearestKernel, progress, used)
          }
          state.scores[state.copy_index] = score
          state.score_scratch[state.copy_index] = None
          state.copy_index += 1
          used += 1
        } else {
          state.width = if state.width > state.scores.length() / 2 {
            state.scores.length()
          } else {
            state.width * 2
          }
          state.phase = PrepareScoreSort
        }
      BeginEmit =>
        if state.emit_index < Int::min(state.k, state.scores.length()) {
          state.query_output_identity = None
          state.candidate_output_identity = None
          state.output_identity_index = 0
          state.phase = BuildQueryIdentity
        } else {
          state.query_index += 1
          state.scores = []
          state.phase = BeginQuery
        }
      BuildQueryIdentity | BuildCandidateIdentity => {
        used += 1
        match
          build_nearest_output_identity(
            state,
            state.phase is BuildQueryIdentity,
          ) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      StartOutputRow => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidNearestKernel, progress, used)
        }
        match
          @execution.start_admitted_output_row(output, 8, column => {
            nearest_output_cell(state, column)
          }) {
          Ok(row) => {
            state.output_row = Some(row)
            state.phase = EmitResult
          }
          Err(issue) =>
            return @bounded.Failed(
              nearest_output_row_issue(issue),
              progress,
              used,
            )
        }
      }
      EmitResult => {
        used += 1
        guard state.output_row is Some(row) else {
          return @bounded.Failed(InvalidNearestKernel, progress, used)
        }
        match @execution.advance_admitted_output_row(row) {
          Ok(true) => {
            @execution.cleanup_admitted_output_row(row) |> ignore
            state.output_row = None
            state.query_output_identity = None
            state.candidate_output_identity = None
            state.emit_index += 1
            progress += 1
            state.phase = BeginEmit
          }
          Ok(false) => ()
          Err(issue) =>
            return @bounded.Failed(
              nearest_output_row_issue(issue),
              progress,
              used,
            )
        }
      }
      FinishNearest => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidNearestKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(NearestOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(NearestCompletion(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_nearest_state(state : NearestState) -> Bool {
  if state.input_recheck is Some((_, cursor)) {
    @value.cancel_recheck_runtime_value(cursor)
    state.input_recheck = None
  }
  state.current_field = None
  if state.output_row is Some(row) {
    @execution.cleanup_admitted_output_row(row) |> ignore
    state.output_row = None
  }
  if state.identity_builder is Some(builder) {
    @value.cancel_object_value(builder) |> ignore
    state.identity_builder = None
  }
  state.query_output_identity = None
  state.candidate_output_identity = None
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  state.identity_values = []
  state.validated_identities = []
  state.key_comparison = None
  state.candidates = []
  state.queries = []
  state.sorting = []
  state.record_scratch = []
  state.scores = []
  state.score_scratch = []
  state.source_vector = None
  state.fold = None
  true
}

///|
fn nearest_producer_view(
  prepared : @lower.PreparedVector,
  side : @vector.NearestSide,
  input : NearestProducerInput,
  owner : @lower.BoundPrepared,
  step : Int,
  edge : Int,
) -> NearestInputView? {
  guard @lower.vector_nearest_input_vectors(prepared, side) is Some(vectors) else {
    return None
  }
  let (source, records) = match input.value {
    RelationProducer(read) => {
      guard @lower.vector_nearest_requires_bridge(prepared, side) == Some(true) &&
        @execution.producer_read_matches_operation_input(
          read, owner, step, edge,
        ) else {
        return None
      }
      (RelationProducer(read), @execution.producer_read_row_count(read))
    }
    CarrierProducer(view) => {
      let reference = @carrier_runtime.producer_view_read_reference(view)
      guard @lower.vector_nearest_requires_bridge(prepared, side) == Some(false) &&
        @carrier_runtime.producer_view_kind(view) == @carrier.VectorsKind &&
        @carrier_runtime.producer_read_reference_matches_operation_input(
          reference, owner, step, edge,
        ) &&
        @carrier_runtime.producer_view_record_count(view) is Some(records) else {
        return None
      }
      (CarrierProducer(view), records)
    }
  }
  let dimensions = @carrier.vector_dimensions(vectors)
  if dimensions < 1.0 ||
    dimensions > 2147483647.0 ||
    dimensions.to_int().to_double() != dimensions {
    return None
  }
  Some({
    source,
    vectors,
    records,
    identity_count: @carrier.vector_identity_count(vectors),
    component_name: @schema.reference_name(
      @carrier.vector_components(vectors).name,
    ),
    dimensions: dimensions.to_int(),
  })
}

///|
fn start_nearest_producers(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  candidates : NearestProducerInput,
  queries : NearestProducerInput,
  max_rows : Int,
  limits : @execution.ValueLimits,
  control_work_limit : Int,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.TrustedOutputInput],
) -> Result[NearestExecution, NearestIssue] {
  if max_rows < 0 ||
    max_workspace_slots < 0 ||
    max_entries < 0 ||
    max_name_bytes < 0 ||
    control_work_limit < 0 {
    return Err(InvalidNearestLimits)
  }
  let owner = @lower.sequence_owner(sequence)
  if !physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) {
    return Err(InvalidNearestKernel)
  }
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.VectorStep(prepared)) else {
    return Err(InvalidNearestKernel)
  }
  guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "VEC.knn_join" else {
    return Err(InvalidNearestKernel)
  }
  guard nearest_producer_view(
      prepared,
      @evidence.Candidates,
      candidates,
      owner,
      step,
      0,
    )
    is Some(candidate_input) else {
    return Err(InvalidNearestKernel)
  }
  guard nearest_producer_view(
      prepared,
      @evidence.Queries,
      queries,
      owner,
      step,
      1,
    )
    is Some(query_input) else {
    return Err(InvalidNearestKernel)
  }
  guard candidate_input.dimensions == query_input.dimensions &&
    candidate_input.identity_count > 0 &&
    query_input.identity_count > 0 &&
    @lower.vector_nearest_k(prepared) is Some(k64) &&
    k64 <= 2147483647L &&
    @lower.vector_nearest_metric(prepared) is Some(metric) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(output_schema) else {
    return Err(InvalidNearestKernel)
  }
  let k = k64.to_int()
  let candidate_count = candidate_input.records
  let query_count = query_input.records
  let selected = Int::min(k, candidate_count)
  guard nearest_checked_multiply(query_count, selected) is Some(output_rows) &&
    output_rows <= max_rows else {
    return Err(NearestOutputLimit)
  }
  // One pending Relation recheck is reused across both ports. Already
  // admitted Carrier views keep their existing control/workspace contract.
  let has_relation = candidate_input.source is RelationProducer(_) ||
    query_input.source is RelationProducer(_)
  let recheck_slots = if has_relation {
    nearest_checked_add(limits.max_depth, 10)
  } else {
    Some(0)
  }
  guard recheck_slots is Some(recheck_slots) &&
    nearest_workspace(
      candidate_count,
      query_count,
      candidate_input.identity_count,
      query_input.identity_count,
      recheck_slots~,
    )
    is Some(workspace) &&
    workspace <= max_workspace_slots else {
    return Err(NearestWorkspaceLimit)
  }
  if control_work_limit == 0 {
    return Err(NearestWorkLimit)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(NearestOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    @execution.prepare_trusted_output_port_with_inputs(
      preparation,
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs~,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(NearestCompletion(issue))
    }
  }
  let state : NearestState = {
    candidates_input: candidate_input,
    queries_input: query_input,
    output_schema,
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    metric: match metric {
      @lower.CosineScore => @numeric.Cosine
      @lower.DotScore => @numeric.Dot
      @lower.L2Score => @numeric.L2
    },
    k,
    value_limits: {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_text_bytes,
    },
    input_recheck: None,
    phase: BeginInputRecord,
    reading_queries: false,
    record: 0,
    field: 0,
    identity_probe: 0,
    current_field: None,
    identity_values: [],
    validated_identities: [],
    key_comparison: None,
    source_vector: None,
    candidates: [],
    queries: [],
    sort_target: SortCandidates,
    sorting: [],
    record_scratch: [],
    width: 1,
    run_start: 0,
    left_index: 0,
    middle: 0,
    right_index: 0,
    run_end: 0,
    merge_index: 0,
    tie_index: 0,
    copy_index: 0,
    unique_index: 0,
    query_index: 0,
    candidate_index: 0,
    component: 0,
    fold: None,
    scores: [],
    score_scratch: [],
    emit_index: 0,
    query_output_identity: None,
    candidate_output_identity: None,
    identity_builder: None,
    output_identity_index: 0,
    output_row: None,
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    nearest_step,
    cleanup_nearest_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({
    session,
    token: Some(token),
    accepted,
    max_noninterruptible_value_nodes: limits.max_nodes,
    max_noninterruptible_value_bytes: limits.max_text_bytes,
  })
}

///|
fn nearest_trusted_input(
  value : NearestProducerInput,
) -> @execution.TrustedOutputInput {
  match value.value {
    RelationProducer(read) => @execution.trusted_output_relation_input(read)
    CarrierProducer(view) =>
      @execution.trusted_output_carrier_input(
        @carrier_runtime.producer_view_read_reference(view),
      )
  }
}

///|
/// Start nearest-neighbor execution from its exact ordered Relation or Vectors
/// producer use sites. Each side is checked against its prepared Carrier role.
pub fn start_nearest_inputs(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  candidates : NearestProducerInput,
  queries : NearestProducerInput,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[NearestExecution, NearestIssue] {
  start_nearest_inputs_with_control_work_limit(
    control,
    preparation,
    sequence,
    step,
    candidates,
    queries,
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    limits.max_work,
  )
}

///|
/// Bound kernel control work independently of admitted output value work.
pub fn start_nearest_inputs_with_control_work_limit(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  candidates : NearestProducerInput,
  queries : NearestProducerInput,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  control_work_limit : Int,
) -> Result[NearestExecution, NearestIssue] {
  start_nearest_producers(
    control,
    preparation,
    sequence,
    step,
    candidates,
    queries,
    max_rows,
    limits,
    control_work_limit,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    [nearest_trusted_input(candidates), nearest_trusted_input(queries)],
  )
}

///|
/// Start a fused nearest pipeline whose runtime operands may be intermediate
/// Vectors while its completion remains bound to the exact external Relations.
pub fn start_nearest_inputs_with_relations(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  candidates : NearestProducerInput,
  queries : NearestProducerInput,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
) -> Result[NearestExecution, NearestIssue] {
  start_nearest_inputs_with_relations_control_work_limit(
    control,
    preparation,
    sequence,
    step,
    candidates,
    queries,
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
    limits.max_work,
  )
}

///|
/// Bound fused Relation-input control work separately from output value work.
pub fn start_nearest_inputs_with_relations_control_work_limit(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  candidates : NearestProducerInput,
  queries : NearestProducerInput,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit : Int,
) -> Result[NearestExecution, NearestIssue] {
  start_nearest_producers(
    control,
    preparation,
    sequence,
    step,
    candidates,
    queries,
    max_rows,
    limits,
    control_work_limit,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs.map(@execution.trusted_output_relation_input),
  )
}

///|
pub fn nearest_max_noninterruptible_value_nodes(
  value : NearestExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn nearest_max_noninterruptible_value_bytes(
  value : NearestExecution,
) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn advance_nearest(
  value : NearestExecution,
  quantum : Int,
) -> Result[NearestPoll, NearestIssue] {
  guard value.token is Some(token) else {
    return Err(NearestExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(NearestExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(NearestContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(NearestComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(NearestFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(NearestStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn nearest_stopped(value : NearestExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn nearest_cleanup_pending(value : NearestExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_nearest(value : NearestExecution) -> Result[Bool, NearestIssue] {
  @bounded.cleanup(value.session).map_err(issue => NearestExecutionIssue(issue))
}
