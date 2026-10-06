///|
priv enum RankingPolicy {
  Maximum
  Weighted(Double, Double)
  Rrf(Double, Array[Double], Double)
}

///|
priv struct RankingRecord {
  input : Int
  group : Array[@value.CheckedValue]
  candidate : @value.CheckedValue
  tie : Array[@value.CheckedValue]
  score : Double?
  rank : Double?
}

///|
priv struct FusedRanking {
  group : Array[@value.CheckedValue]
  candidate : @value.CheckedValue
  tie : Array[@value.CheckedValue]
  score : Double
}

///|
priv enum RankingRecordOrder {
  InputCandidateOrder
  InputRankOrder
  CandidateInputOrder
}

///|
/// Exact Relation input for ranking execution. Supplied Local rows retain
/// their own binding and are never represented as a completed producer.
pub enum RankingInput {
  RankingProducer(@execution.ProducerRead)
  RankingSupplied(@execution.SuppliedRelationRead)
}

///|
priv enum RankingPhase {
  BeginRecord
  InitializeGroupValues
  InitializeTieValues
  ReadField
  RecheckField
  MatchField
  ValidateGroup
  ValidateCandidate
  ValidateTie
  ValidateRecordPolicy
  StoreRecord
  InitializeRecordScratch
  PrepareRecordSort
  PrepareRecordMerge
  MergeRecords
  CopyRecordPass
  ValidateDuplicates
  ValidateRanks
  PrepareFusion
  FindFusionEnd
  FoldFusion
  FinishFusion
  InitializeFusedScratch
  PrepareOutputSort
  PrepareOutputMerge
  MergeOutputs
  CopyOutputPass
  EmitOutput
  ReadOutputField
  ResolveOutputGroup
  StartOutputRow
  EmitOutputRow
  FinishRanking
}

///|
priv struct RankingState {
  inputs : Array[RankingInput]
  output_schema : @schema.Schema
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  policy : RankingPolicy
  by : Array[String]
  candidate_name : String
  score_name : String?
  rank_name : String?
  tie : Array[String]
  k : Int
  score_minimum : Double?
  score_maximum : Double?
  value_limits : @value.Limits
  mut input_recheck : @value.RecheckCursor?
  mut pending_field : (@schema.FieldName, @value.CheckedValue)?
  mut name_probe : Int
  name_offset : Ref[Int]
  input_value_units : Ref[Int]
  mut comparison : RankingComparisonCursor?
  comparison_units : Ref[Int]
  mut phase : RankingPhase
  mut input : Int
  mut row : Int
  mut field : Int
  mut group_values : Array[@value.CheckedValue?]
  mut candidate_value : @value.CheckedValue?
  mut tie_values : Array[@value.CheckedValue?]
  mut score_value : Double?
  mut rank_value : Double?
  mut validation_index : Int
  mut validated_group : Array[@value.CheckedValue]
  mut validated_tie : Array[@value.CheckedValue]
  mut records : Array[RankingRecord]
  mut record_scratch : Array[RankingRecord?]
  scratch_slots : Ref[Int]
  mut record_order : RankingRecordOrder
  mut width : Int
  mut run_start : Int
  mut middle : Int
  mut run_end : Int
  mut left_index : Int
  mut right_index : Int
  mut merge_index : Int
  mut copy_index : Int
  mut validate_index : Int
  mut fusion_start : Int
  mut fusion_end : Int
  mut fusion_record : Int
  mut fusion_input : Int
  mut fusion_score : Double
  mut fusion_maximum : Double?
  mut fusion_participates : Bool
  mut fused : Array[FusedRanking]
  mut fused_scratch : Array[FusedRanking?]
  mut emit_index : Int
  mut emit_rank : Int
  mut emitted_group : Array[@value.CheckedValue]?
  mut output_field : Int
  mut output_values : Array[@value.Value]
  mut output_group_index : Int
  mut output_row : @execution.AdmittedOutputRowCursor?
  output_row_units : Ref[Int]
  output_field_slots : Ref[Int]
  mut control_work_remaining : Int
}

///|
pub fn ranking_producer_input(value : @execution.ProducerRead) -> RankingInput {
  RankingProducer(value)
}

///|
pub fn ranking_supplied_input(
  value : @execution.SuppliedRelationRead,
) -> RankingInput {
  RankingSupplied(value)
}

///|
fn ranking_input_available_value(value : RankingInput) -> Bool {
  match value {
    RankingProducer(read) => @execution.producer_read_available(read)
    RankingSupplied(read) => @execution.supplied_relation_read_available(read)
  }
}

///|
fn ranking_input_matches_operation(
  value : RankingInput,
  owner : @lower.BoundPrepared,
  step : Int,
  edge : Int,
) -> Bool {
  match value {
    RankingProducer(read) =>
      @execution.producer_read_matches_operation_input(read, owner, step, edge)
    RankingSupplied(read) =>
      @execution.supplied_relation_read_matches_operation_input(
        read, owner, step, edge,
      )
  }
}

///|
fn ranking_input_port(value : RankingInput) -> Int {
  match value {
    RankingProducer(read) => @execution.producer_read_input_index(read)
    RankingSupplied(read) => @execution.supplied_relation_read_input_index(read)
  }
}

///|
fn ranking_input_schema(value : RankingInput) -> @schema.Schema {
  match value {
    RankingProducer(read) => @execution.producer_read_schema(read)
    RankingSupplied(read) => @execution.supplied_relation_read_schema(read)
  }
}

///|
fn ranking_input_row_count(value : RankingInput) -> Int {
  match value {
    RankingProducer(read) => @execution.producer_read_row_count(read)
    RankingSupplied(read) => @execution.supplied_relation_read_row_count(read)
  }
}

///|
fn ranking_input_recheck(
  value : RankingInput,
  row : Int,
  column : Int,
  limits : @value.Limits,
) -> @value.RecheckCursor? {
  guard @schema.field_at(ranking_input_schema(value), column) is Some(field) else {
    return None
  }
  match value {
    RankingProducer(read) =>
      relation_cell_recheck(read, row, column, limits).map(pair => pair.1)
    RankingSupplied(read) => {
      guard @execution.supplied_relation_read_cell(read, row, column)
        is Some(raw) else {
        return None
      }
      @value.start_recheck_runtime_value(raw, field.contract, limits)
    }
  }
}

///|
fn ranking_trusted_input(value : RankingInput) -> @execution.TrustedOutputInput {
  match value {
    RankingProducer(read) => @execution.trusted_output_relation_input(read)
    RankingSupplied(read) =>
      @execution.trusted_output_supplied_relation_input(read)
  }
}

///|
struct RankingExecution {
  session : @bounded.Session[
    RankingState,
    @execution.CompletedOutput,
    RankingIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  scratch_slots : Ref[Int]
  output_field_slots : Ref[Int]
  comparison_units : Ref[Int]
  output_row_units : Ref[Int]
  input_value_units : Ref[Int]
  max_noninterruptible_value_nodes : Int
  name_offset : Ref[Int]
  max_noninterruptible_value_bytes : Int
}

///|
pub enum RankingPoll {
  RankingContinue(progress~ : Int64, work~ : Int64)
  RankingComplete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  RankingFailed(RankingIssue, progress~ : Int64, work~ : Int64)
  RankingStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum RankingIssue {
  InvalidRankingKernel
  InvalidRankingLimits
  RankingInputUnavailable(Int)
  InvalidRankingRecord(Int, Int)
  DuplicateRankingCandidate(Int, Int)
  InvalidRankingPosition(Int, Int)
  ConflictingRankingTie(Int)
  RankingWorkspaceLimit
  RankingWorkLimit
  RankingNumeric(@numeric.Issue)
  RankingKeyOrder(@value.KeyOrderIssue)
  RankingOutput(@execution.CaptureIssue)
  RankingCompletion(@execution.TrustedOutputIssue)
  RankingExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn ranking_checked_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn ranking_checked_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn ranking_workspace(
  rows : Int,
  by : Int,
  tie : Int,
  logical_inputs : Int,
  physical_inputs : Int,
  max_value_depth? : Int = 0,
) -> Int? {
  // Output keys are flat KeyComparable values. The row scope needs width+1
  // borrowed slots and one shared text-measurement frame: (by+3)+2.
  // A pending input owns at most one continuation per admitted depth,
  // plus its current node/text frame. Reserve depth+2 before any read.
  guard ranking_checked_add(by, tie) is Some(key_width) &&
    ranking_checked_add(key_width, 8) is Some(record_width) &&
    ranking_checked_add(key_width, 5) is Some(output_width) &&
    // One borrowed name/value pair, probe and offset remain owned across yields.
    ranking_checked_add(key_width, 48) is Some(fixed_width) &&
    ranking_checked_add(max_value_depth, 2) is Some(recheck_frames) &&
    ranking_checked_add(by, 5) is Some(row_slots) &&
    ranking_checked_multiply(rows, record_width) is Some(records) &&
    ranking_checked_multiply(rows, output_width) is Some(outputs) &&
    ranking_checked_add(records, rows) is Some(first) &&
    ranking_checked_add(first, outputs) is Some(second) &&
    ranking_checked_add(second, rows) is Some(third) &&
    ranking_checked_multiply(physical_inputs, 2) is Some(port_slots) &&
    ranking_checked_add(logical_inputs, port_slots) is Some(input_slots) &&
    ranking_checked_add(third, input_slots) is Some(fourth) &&
    ranking_checked_add(fourth, fixed_width) is Some(fifth) &&
    ranking_checked_add(fifth, row_slots) is Some(sixth) &&
    ranking_checked_add(sixth, recheck_frames) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn ranking_input_available(state : RankingState) -> RankingIssue? {
  for index, input in state.inputs {
    if !ranking_input_available_value(input) {
      return Some(RankingInputUnavailable(index))
    }
  }
  None
}

///|
fn begin_ranking_record(state : RankingState) -> Unit {
  state.field = 0
  state.pending_field = None
  state.name_probe = 0
  state.name_offset.val = 0
  state.group_values = []
  state.candidate_value = None
  state.tie_values = []
  state.score_value = None
  state.rank_value = None
  state.validation_index = 0
  state.validated_group = []
  state.validated_tie = []
  state.phase = InitializeGroupValues
}

///|
fn read_ranking_field(state : RankingState) -> Result[Unit, RankingIssue] {
  let read = state.inputs[state.input]
  guard ranking_input_recheck(read, state.row, state.field, state.value_limits)
    is Some(cursor) else {
    return Err(InvalidRankingRecord(state.input, state.row))
  }
  state.input_recheck = Some(cursor)
  state.phase = RecheckField
  Ok(())
}

///|
fn bind_ranking_field(
  state : RankingState,
  value : @value.CheckedValue,
) -> Result[Unit, RankingIssue] {
  let schema = ranking_input_schema(state.inputs[state.input])
  guard @schema.field_at(schema, state.field) is Some(field) else {
    return Err(InvalidRankingRecord(state.input, state.row))
  }
  state.pending_field = Some((field.name, value))
  state.name_probe = 0
  state.name_offset.val = 0
  state.phase = MatchField
  match_ranking_field(state)
}

///|
fn validate_ranking_group(state : RankingState) -> Result[Unit, RankingIssue] {
  guard state.group_values[state.validation_index] is Some(value) else {
    return Err(InvalidRankingRecord(state.input, state.row))
  }
  match ranking_compare(state, ScalarComparison(value, value, 0)) {
    Ok(Some(_)) => {
      state.validated_group.push(value)
      state.validation_index += 1
      Ok(())
    }
    Ok(None) => Ok(())
    Err(issue) => Err(issue)
  }
}

///|
fn validate_ranking_candidate(
  state : RankingState,
) -> Result[Bool, RankingIssue] {
  guard state.candidate_value is Some(candidate) else {
    return Err(InvalidRankingRecord(state.input, state.row))
  }
  ranking_compare(state, ScalarComparison(candidate, candidate, 2)).map(order => {
    order is Some(_)
  })
}

///|
fn validate_ranking_tie_value(
  state : RankingState,
) -> Result[Unit, RankingIssue] {
  guard state.tie_values[state.validation_index] is Some(value) else {
    return Err(InvalidRankingRecord(state.input, state.row))
  }
  match ranking_compare(state, ScalarComparison(value, value, 1)) {
    Ok(Some(_)) => {
      state.validated_tie.push(value)
      state.validation_index += 1
      Ok(())
    }
    Ok(None) => Ok(())
    Err(issue) => Err(issue)
  }
}

///|
fn validate_ranking_record_policy(
  state : RankingState,
) -> Result[Unit, RankingIssue] {
  match state.policy {
    Maximum | Weighted(_, _) => {
      guard state.score_value is Some(score) &&
        state.score_minimum is Some(minimum) &&
        state.score_maximum is Some(maximum) &&
        !score.is_nan() &&
        !score.is_inf() &&
        score >= minimum &&
        score <= maximum else {
        return Err(InvalidRankingRecord(state.input, state.row))
      }
    }
    Rrf(_, _, _) => {
      guard state.rank_value is Some(rank) &&
        @scalar.read_safe_integer(rank) is Some(position) &&
        position > 0L else {
        return Err(InvalidRankingRecord(state.input, state.row))
      }
    }
  }
  Ok(())
}

///|
fn store_ranking_record(state : RankingState) -> Result[Unit, RankingIssue] {
  guard state.candidate_value is Some(candidate) else {
    return Err(InvalidRankingKernel)
  }
  state.records.push({
    input: state.input,
    group: state.validated_group,
    candidate,
    tie: state.validated_tie,
    score: state.score_value,
    rank: state.rank_value,
  })
  state.row += 1
  state.validated_group = []
  state.validated_tie = []
  state.phase = BeginRecord
  Ok(())
}

///|
fn ranking_capped_end(start : Int, width : Int, count : Int) -> Int {
  if width >= count - start {
    count
  } else {
    start + width
  }
}

///|
fn prepare_ranking_record_merge(state : RankingState) -> Unit {
  state.middle = ranking_capped_end(
    state.run_start,
    state.width,
    state.records.length(),
  )
  state.run_end = ranking_capped_end(
    state.middle,
    state.width,
    state.records.length(),
  )
  state.left_index = state.run_start
  state.right_index = state.middle
  state.merge_index = state.run_start
  state.phase = MergeRecords
}

///|
fn emit_ranking_record_merge(state : RankingState, take_left : Bool) -> Unit {
  let selected = if take_left {
    let value = state.records[state.left_index]
    state.left_index += 1
    value
  } else {
    let value = state.records[state.right_index]
    state.right_index += 1
    value
  }
  state.record_scratch[state.merge_index] = Some(selected)
  state.merge_index += 1
  if state.merge_index >= state.run_end {
    state.run_start = state.run_end
    state.phase = PrepareRecordMerge
  }
}

///|
fn merge_ranking_record(state : RankingState) -> Result[Unit, RankingIssue] {
  if state.left_index >= state.middle {
    emit_ranking_record_merge(state, false)
  } else if state.right_index >= state.run_end {
    emit_ranking_record_merge(state, true)
  } else {
    let comparison = match
      ranking_compare(
        state,
        RecordComparison(
          state.records[state.left_index],
          state.records[state.right_index],
          state.record_order,
        ),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if comparison is Some(order) {
      emit_ranking_record_merge(state, order <= 0)
    }
  }
  Ok(())
}

///|
fn start_ranking_record_sort(
  state : RankingState,
  order : RankingRecordOrder,
) -> Unit {
  state.record_order = order
  state.record_scratch = []
  state.scratch_slots.val = 0
  state.width = 1
  state.phase = InitializeRecordScratch
}

///|
fn finish_ranking_record_sort(state : RankingState) -> Unit {
  state.record_scratch = []
  state.scratch_slots.val = 0
  state.validate_index = 0
  match state.record_order {
    InputCandidateOrder => state.phase = ValidateDuplicates
    InputRankOrder => state.phase = ValidateRanks
    CandidateInputOrder => {
      state.fusion_start = 0
      state.phase = PrepareFusion
    }
  }
}

///|
fn validate_ranking_duplicate(
  state : RankingState,
) -> Result[Unit, RankingIssue] {
  if state.validate_index == 0 {
    state.validate_index = 1
    return Ok(())
  }
  if state.validate_index >= state.records.length() {
    match state.policy {
      Rrf(_, _, _) => start_ranking_record_sort(state, InputRankOrder)
      Maximum | Weighted(_, _) =>
        start_ranking_record_sort(state, CandidateInputOrder)
    }
    return Ok(())
  }
  let left = state.records[state.validate_index - 1]
  let right = state.records[state.validate_index]
  if left.input == right.input {
    let same = match ranking_compare(state, CandidateComparison(left, right)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard same is Some(order) else { return Ok(()) }
    if order == 0 {
      return Err(DuplicateRankingCandidate(right.input, state.validate_index))
    }
  }
  state.validate_index += 1
  Ok(())
}

///|
fn validate_ranking_position(
  state : RankingState,
) -> Result[Unit, RankingIssue] {
  if state.validate_index >= state.records.length() {
    start_ranking_record_sort(state, CandidateInputOrder)
    return Ok(())
  }
  let current = state.records[state.validate_index]
  guard current.rank is Some(rank) &&
    @scalar.read_safe_integer(rank) is Some(position) else {
    return Err(InvalidRankingPosition(current.input, state.validate_index))
  }
  let expected = if state.validate_index == 0 {
    1L
  } else {
    let prior = state.records[state.validate_index - 1]
    let same_input = prior.input == current.input
    let same_group = match
      ranking_compare(state, GroupComparison(prior.group, current.group)) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard same_group is Some(order) else { return Ok(()) }
    if same_input && order == 0 {
      guard prior.rank is Some(prior_rank) &&
        @scalar.read_safe_integer(prior_rank) is Some(prior_position) &&
        prior_position < 9007199254740991L else {
        return Err(InvalidRankingPosition(current.input, state.validate_index))
      }
      prior_position + 1L
    } else {
      1L
    }
  }
  if position != expected {
    return Err(InvalidRankingPosition(current.input, state.validate_index))
  }
  state.validate_index += 1
  Ok(())
}

///|
fn begin_ranking_fusion(state : RankingState) -> Unit {
  state.fusion_end = state.fusion_start + 1
  state.fusion_record = state.fusion_start
  state.fusion_input = 0
  state.fusion_score = 0.0
  state.fusion_maximum = None
  state.fusion_participates = false
  state.phase = FindFusionEnd
}

///|
fn find_ranking_fusion_end(state : RankingState) -> Result[Unit, RankingIssue] {
  if state.fusion_end >= state.records.length() {
    state.phase = FoldFusion
    return Ok(())
  }
  let same = match
    ranking_compare(
      state,
      CandidateComparison(
        state.records[state.fusion_start],
        state.records[state.fusion_end],
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard same is Some(order) else { return Ok(()) }
  if order == 0 {
    state.fusion_end += 1
  } else {
    state.phase = FoldFusion
  }
  Ok(())
}

///|
fn fold_ranking_input(state : RankingState) -> Result[Unit, RankingIssue] {
  let mut record : RankingRecord? = None
  if state.fusion_record < state.fusion_end &&
    state.records[state.fusion_record].input == state.fusion_input {
    let selected = state.records[state.fusion_record]
    match state.policy {
      Maximum | Weighted(_, _) => {
        let comparison = match
          ranking_compare(
            state,
            TieComparison(state.records[state.fusion_start].tie, selected.tie),
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        guard comparison is Some(order) else { return Ok(()) }
        if order != 0 {
          return Err(ConflictingRankingTie(state.fusion_record + 1))
        }
      }
      Rrf(_, _, _) => ()
    }
    record = Some(selected)
    state.fusion_record += 1
  }
  match state.policy {
    Maximum =>
      if record is Some(record) {
        guard record.score is Some(score) else {
          return Err(InvalidRankingKernel)
        }
        state.fusion_maximum = Some(
          match state.fusion_maximum {
            Some(current) => Double::max(current, score)
            None => score
          },
        )
        state.fusion_participates = true
      }
    Weighted(left, right) => {
      let weight = if state.fusion_input == 0 { left } else { right }
      let contribution = match record {
        Some(record) => {
          guard record.score is Some(score) else {
            return Err(InvalidRankingKernel)
          }
          match @numeric.ranking_weighted_contribution(score, weight) {
            Ok(value) => value
            Err(issue) => return Err(RankingNumeric(issue))
          }
        }
        None => 0.0
      }
      state.fusion_score = match
        @numeric.ranking_fuse_step(state.fusion_score, contribution) {
        Ok(value) => value
        Err(issue) => return Err(RankingNumeric(issue))
      }
      if record is Some(_) {
        state.fusion_participates = true
      }
    }
    Rrf(rank_constant, weights, rank_window) => {
      let contribution = match record {
        Some(record) => {
          guard record.rank is Some(rank) else {
            return Err(InvalidRankingKernel)
          }
          if rank <= rank_window {
            state.fusion_participates = true
            match
              @numeric.ranking_rrf_contribution(
                weights[state.fusion_input],
                rank_constant,
                rank,
              ) {
              Ok(value) => value
              Err(issue) => return Err(RankingNumeric(issue))
            }
          } else {
            0.0
          }
        }
        None => 0.0
      }
      state.fusion_score = match
        @numeric.ranking_fuse_step(state.fusion_score, contribution) {
        Ok(value) => value
        Err(issue) => return Err(RankingNumeric(issue))
      }
    }
  }
  state.fusion_input += 1
  if state.fusion_input >= state.inputs.length() {
    state.phase = FinishFusion
  }
  Ok(())
}

///|
fn finish_ranking_fusion(state : RankingState) -> Result[Unit, RankingIssue] {
  let first = state.records[state.fusion_start]
  if state.fusion_participates {
    let score = match state.policy {
      Maximum =>
        match state.fusion_maximum {
          Some(value) => value
          None => return Err(InvalidRankingKernel)
        }
      Weighted(_, _) | Rrf(_, _, _) => state.fusion_score
    }
    if score.is_nan() || score.is_inf() {
      return Err(RankingNumeric(@numeric.NonFinite))
    }
    state.fused.push({
      group: first.group,
      candidate: first.candidate,
      tie: first.tie,
      score,
    })
  }
  state.fusion_start = state.fusion_end
  state.phase = PrepareFusion
  Ok(())
}

///|
fn prepare_ranking_output_merge(state : RankingState) -> Unit {
  state.middle = ranking_capped_end(
    state.run_start,
    state.width,
    state.fused.length(),
  )
  state.run_end = ranking_capped_end(
    state.middle,
    state.width,
    state.fused.length(),
  )
  state.left_index = state.run_start
  state.right_index = state.middle
  state.merge_index = state.run_start
  state.phase = MergeOutputs
}

///|
fn emit_ranking_output_merge(state : RankingState, take_left : Bool) -> Unit {
  let selected = if take_left {
    let value = state.fused[state.left_index]
    state.left_index += 1
    value
  } else {
    let value = state.fused[state.right_index]
    state.right_index += 1
    value
  }
  state.fused_scratch[state.merge_index] = Some(selected)
  state.merge_index += 1
  if state.merge_index >= state.run_end {
    state.run_start = state.run_end
    state.phase = PrepareOutputMerge
  }
}

///|
fn merge_ranking_output(state : RankingState) -> Result[Unit, RankingIssue] {
  if state.left_index >= state.middle {
    emit_ranking_output_merge(state, false)
  } else if state.right_index >= state.run_end {
    emit_ranking_output_merge(state, true)
  } else {
    let comparison = match
      ranking_compare(
        state,
        OutputComparison(
          state.fused[state.left_index],
          state.fused[state.right_index],
        ),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if comparison is Some(order) {
      emit_ranking_output_merge(state, order <= 0)
    }
  }
  Ok(())
}

///|
fn begin_ranking_result(state : RankingState) -> Result[Bool?, RankingIssue] {
  let row = state.fused[state.emit_index]
  let same_group = match state.emitted_group {
    Some(group) =>
      match ranking_compare(state, GroupComparison(group, row.group)) {
        Ok(Some(order)) => order == 0
        Ok(None) => return Ok(None)
        Err(issue) => return Err(issue)
      }
    None => false
  }
  if same_group {
    state.emit_rank += 1
  } else {
    state.emitted_group = Some(row.group)
    state.emit_rank = 1
  }
  if state.emit_rank > state.k {
    return Ok(Some(false))
  }
  Ok(Some(true))
}

///|
fn append_ranking_output_field(
  state : RankingState,
  value : @value.Value,
) -> Unit {
  state.output_values.push(value)
  state.output_field_slots.val += 1
  state.output_field += 1
  state.name_probe = -3
  state.name_offset.val = 0
  state.phase = ReadOutputField
}

///|
fn read_ranking_output_field(
  state : RankingState,
) -> Result[Unit, RankingIssue] {
  let row = state.fused[state.emit_index]
  guard @schema.field_at(state.output_schema, state.output_field) is Some(field) else {
    return Err(InvalidRankingKernel)
  }
  let mut remaining = 64
  for _ in 0..<3 {
    let expected = match state.name_probe {
      -3 => state.candidate_name
      -2 => "score"
      -1 => "rank"
      _ => return Err(InvalidRankingKernel)
    }
    let (equal, spent) = ranking_name_equal_budget(
      state,
      field.name,
      @schema.Unqualified(expected),
      remaining,
    )
    remaining -= spent
    guard equal is Some(equal) else { return Ok(()) }
    if equal {
      let value = match state.name_probe {
        -3 => Some(row.candidate.value)
        -2 =>
          @value.checked_number_value(row.score, field.contract).map(value => {
            value.value
          })
        _ =>
          @value.checked_number_value(
            state.emit_rank.to_double(),
            field.contract,
          ).map(value => value.value)
      }
      guard value is Some(value) else { return Err(InvalidRankingKernel) }
      append_ranking_output_field(state, value)
      return Ok(())
    }
    state.name_probe += 1
    if state.name_probe == 0 {
      state.output_group_index = 0
      state.phase = ResolveOutputGroup
      return Ok(())
    }
    if remaining == 0 {
      return Ok(())
    }
  }
  Ok(())
}

///|
fn resolve_ranking_output_group(
  state : RankingState,
) -> Result[Unit, RankingIssue] {
  guard @schema.field_at(state.output_schema, state.output_field) is Some(field) &&
    state.output_group_index < state.by.length() else {
    return Err(InvalidRankingKernel)
  }
  let index = state.output_group_index
  let (equal, _) = ranking_name_equal_budget(
    state,
    field.name,
    @schema.Unqualified(state.by[index]),
    64,
  )
  guard equal is Some(equal) else { return Ok(()) }
  state.output_group_index += 1
  if equal {
    guard state.fused[state.emit_index].group.get(index) is Some(value) else {
      return Err(InvalidRankingKernel)
    }
    append_ranking_output_field(state, value.value)
  }
  Ok(())
}

///|
fn ranking_output_row_issue(
  issue : @execution.AdmittedOutputRowIssue,
) -> RankingIssue {
  match issue {
    @execution.OutputRowCapture(issue) => RankingOutput(issue)
    @execution.OutputRowWorkspace => RankingWorkspaceLimit
  }
}

///|
fn ranking_step(
  state : RankingState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, RankingIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if ranking_input_available(state) is Some(issue) {
      return @bounded.Failed(issue, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(RankingWorkLimit, progress, used)
    }
    match state.phase {
      BeginRecord =>
        if state.input >= state.inputs.length() {
          start_ranking_record_sort(state, InputCandidateOrder)
        } else if state.row < ranking_input_row_count(state.inputs[state.input]) {
          begin_ranking_record(state)
        } else {
          state.input += 1
          state.row = 0
        }
      InitializeGroupValues =>
        if state.group_values.length() < state.by.length() {
          state.group_values.push(None)
          used += 1
        } else {
          state.phase = InitializeTieValues
        }
      InitializeTieValues =>
        if state.tie_values.length() < state.tie.length() {
          state.tie_values.push(None)
          used += 1
        } else {
          state.phase = ReadField
        }
      ReadField => {
        let schema = ranking_input_schema(state.inputs[state.input])
        if state.field < @schema.field_count(schema) {
          used += 1
          match read_ranking_field(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.validation_index = 0
          state.phase = ValidateGroup
        }
      }
      ValidateGroup =>
        if state.validation_index < state.group_values.length() {
          used += 1
          match validate_ranking_group(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = ValidateCandidate
        }
      ValidateCandidate => {
        used += 1
        match validate_ranking_candidate(state) {
          Ok(false) => ()
          Ok(true) => {
            state.validation_index = 0
            state.phase = ValidateTie
          }
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      RecheckField => {
        used += 1
        state.input_value_units.val += 1
        guard state.input_recheck is Some(cursor) else {
          return @bounded.Failed(InvalidRankingKernel, progress, used)
        }
        match @value.advance_recheck_runtime_value(cursor) {
          @value.RecheckContinue => ()
          @value.RecheckComplete(value, _, _) => {
            state.input_recheck = None
            match bind_ranking_field(state, value) {
              Ok(_) => ()
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          }
          @value.RecheckFailed =>
            return @bounded.Failed(
              InvalidRankingRecord(state.input, state.row),
              progress,
              used,
            )
        }
      }
      MatchField => {
        used += 1
        match match_ranking_field(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ValidateTie =>
        if state.validation_index < state.tie_values.length() {
          used += 1
          match validate_ranking_tie_value(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = ValidateRecordPolicy
        }
      ValidateRecordPolicy => {
        used += 1
        match validate_ranking_record_policy(state) {
          Ok(_) => state.phase = StoreRecord
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      StoreRecord => {
        used += 1
        match store_ranking_record(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      InitializeRecordScratch =>
        if state.record_scratch.length() < state.records.length() {
          state.record_scratch.push(None)
          state.scratch_slots.val += 1
          used += 1
        } else {
          state.phase = PrepareRecordSort
        }
      PrepareRecordSort =>
        if state.width >= state.records.length() {
          finish_ranking_record_sort(state)
        } else {
          state.run_start = 0
          state.phase = PrepareRecordMerge
        }
      PrepareRecordMerge =>
        if state.run_start >= state.records.length() {
          state.copy_index = 0
          state.phase = CopyRecordPass
        } else {
          prepare_ranking_record_merge(state)
        }
      MergeRecords => {
        used += 1
        match merge_ranking_record(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyRecordPass =>
        if state.copy_index < state.records.length() {
          guard state.record_scratch[state.copy_index] is Some(record) else {
            return @bounded.Failed(InvalidRankingKernel, progress, used)
          }
          state.records[state.copy_index] = record
          state.record_scratch[state.copy_index] = None
          state.copy_index += 1
          used += 1
        } else {
          state.width = if state.width > state.records.length() / 2 {
            state.records.length()
          } else {
            state.width * 2
          }
          state.phase = PrepareRecordSort
        }
      ValidateDuplicates => {
        used += 1
        match validate_ranking_duplicate(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ValidateRanks => {
        used += 1
        match validate_ranking_position(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      PrepareFusion =>
        if state.fusion_start < state.records.length() {
          begin_ranking_fusion(state)
        } else {
          state.records = []
          state.fused_scratch = []
          state.scratch_slots.val = 0
          state.width = 1
          state.phase = InitializeFusedScratch
        }
      FindFusionEnd => {
        used += 1
        match find_ranking_fusion_end(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      FoldFusion => {
        used += 1
        match fold_ranking_input(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      FinishFusion => {
        used += 1
        match finish_ranking_fusion(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      InitializeFusedScratch =>
        if state.fused_scratch.length() < state.fused.length() {
          state.fused_scratch.push(None)
          state.scratch_slots.val += 1
          used += 1
        } else {
          state.phase = PrepareOutputSort
        }
      PrepareOutputSort =>
        if state.width >= state.fused.length() {
          state.fused_scratch = []
          state.scratch_slots.val = 0
          state.emit_index = 0
          state.emit_rank = 0
          state.emitted_group = None
          state.phase = EmitOutput
        } else {
          state.run_start = 0
          state.phase = PrepareOutputMerge
        }
      PrepareOutputMerge =>
        if state.run_start >= state.fused.length() {
          state.copy_index = 0
          state.phase = CopyOutputPass
        } else {
          prepare_ranking_output_merge(state)
        }
      MergeOutputs => {
        used += 1
        match merge_ranking_output(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyOutputPass =>
        if state.copy_index < state.fused.length() {
          guard state.fused_scratch[state.copy_index] is Some(row) else {
            return @bounded.Failed(InvalidRankingKernel, progress, used)
          }
          state.fused[state.copy_index] = row
          state.fused_scratch[state.copy_index] = None
          state.copy_index += 1
          used += 1
        } else {
          state.width = if state.width > state.fused.length() / 2 {
            state.fused.length()
          } else {
            state.width * 2
          }
          state.phase = PrepareOutputSort
        }
      EmitOutput =>
        if state.emit_index < state.fused.length() {
          used += 1
          match begin_ranking_result(state) {
            Ok(Some(true)) => {
              state.output_field = 0
              state.name_probe = -3
              state.name_offset.val = 0
              state.output_values = []
              state.output_field_slots.val = 0
              state.phase = ReadOutputField
            }
            Ok(Some(false)) => state.emit_index += 1
            Ok(None) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = FinishRanking
        }
      ReadOutputField =>
        if state.output_field < @schema.field_count(state.output_schema) {
          used += 1
          match read_ranking_output_field(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = StartOutputRow
        }
      ResolveOutputGroup => {
        used += 1
        match resolve_ranking_output_group(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      StartOutputRow => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidRankingKernel, progress, used)
        }
        match
          @execution.start_admitted_output_row(output, state.by.length() + 5, column => {
            state.output_values.get(column)
          }) {
          Ok(row) => {
            state.output_row = Some(row)
            state.phase = EmitOutputRow
          }
          Err(issue) =>
            return @bounded.Failed(
              ranking_output_row_issue(issue),
              progress,
              used,
            )
        }
      }
      EmitOutputRow => {
        used += 1
        state.output_row_units.val += 1
        guard state.output_row is Some(row) else {
          return @bounded.Failed(InvalidRankingKernel, progress, used)
        }
        match @execution.advance_admitted_output_row(row) {
          Ok(false) => ()
          Ok(true) => {
            if !@execution.cleanup_admitted_output_row(row) {
              return @bounded.Failed(RankingWorkspaceLimit, progress, used)
            }
            state.output_row = None
            state.output_values = []
            state.output_field_slots.val = 0
            state.emit_index += 1
            progress += 1
            state.phase = EmitOutput
          }
          Err(issue) =>
            return @bounded.Failed(
              ranking_output_row_issue(issue),
              progress,
              used,
            )
        }
      }
      FinishRanking => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidRankingKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(RankingOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(RankingCompletion(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_ranking_state(state : RankingState) -> Bool {
  if state.input_recheck is Some(cursor) {
    @value.cancel_recheck_runtime_value(cursor)
    state.input_recheck = None
  }
  state.input_value_units.val = 0
  state.pending_field = None
  state.name_probe = 0
  state.name_offset.val = 0
  if state.output_row is Some(row) {
    if !@execution.cleanup_admitted_output_row(row) {
      return false
    }
    state.output_row = None
  }
  state.output_row_units.val = 0
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  state.comparison = None
  state.comparison_units.val = 0
  state.group_values = []
  state.tie_values = []
  state.validated_group = []
  state.validated_tie = []
  state.records = []
  state.record_scratch = []
  state.fused = []
  state.fused_scratch = []
  state.scratch_slots.val = 0
  state.candidate_value = None
  state.emitted_group = None
  state.output_values = []
  state.output_field_slots.val = 0
  true
}

///|
fn prepared_ranking_policy(
  prepared : @lower.PreparedVector,
  input_count : Int,
) -> RankingPolicy? {
  match @lower.vector_ranking_policy(prepared) {
    Some(@lower.RankingMaximum) if input_count == 2 => Some(Maximum)
    Some(@lower.RankingWeightedSum(left, right)) if input_count == 2 =>
      Some(Weighted(left, right))
    Some(@lower.RankingRrf(rank_constant, weights, rank_window)) if weights.length() ==
      input_count => Some(Rrf(rank_constant, weights, rank_window))
    _ => None
  }
}

///|
fn prepared_ranking_names(count : Int, at : (Int) -> String?) -> Array[String]? {
  let values : Array[String] = []
  for index in 0..<count {
    guard at(index) is Some(value) else { return None }
    values.push(value)
  }
  Some(values)
}

///|
pub fn start_ranking(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@execution.ProducerRead],
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  control_work_limit? : Int? = None,
) -> Result[RankingExecution, RankingIssue] {
  start_ranking_inputs(
    control,
    preparation,
    sequence,
    step,
    inputs.map(ranking_producer_input),
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    control_work_limit~,
  )
}

///|
pub fn start_ranking_inputs(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[RankingInput],
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  control_work_limit? : Int? = None,
) -> Result[RankingExecution, RankingIssue] {
  let control_work_limit = control_work_limit.unwrap_or(limits.max_work)
  if max_rows < 0 ||
    max_workspace_slots < 0 ||
    max_entries < 0 ||
    max_name_bytes < 0 ||
    control_work_limit < 0 ||
    inputs.is_empty() {
    return Err(InvalidRankingLimits)
  }
  let owner = @lower.sequence_owner(sequence)
  if !physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) {
    return Err(InvalidRankingKernel)
  }
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.VectorStep(prepared)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "VEC.merge_rankings" &&
    @lower.vector_ranking_input_count(prepared) is Some(input_count) &&
    @lower.vector_ranking_by_count(prepared) is Some(by_count) &&
    prepared_ranking_names(by_count, index => {
      @lower.vector_ranking_by_at(prepared, index)
    })
    is Some(by) &&
    @lower.vector_ranking_candidate(prepared) is Some(candidate_name) &&
    @lower.vector_ranking_k(prepared) is Some(k64) &&
    k64 > 0L &&
    k64 <= 2147483647L &&
    prepared_ranking_policy(prepared, input_count) is Some(policy) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(output_schema) else {
    return Err(InvalidRankingKernel)
  }
  let tie_count = @lower.vector_ranking_tie_break_count(prepared).unwrap_or(0)
  guard prepared_ranking_names(tie_count, index => {
      @lower.vector_ranking_tie_break_at(prepared, index)
    })
    is Some(tie) &&
    ranking_workspace(
      0,
      by_count,
      tie_count,
      input_count,
      inputs.length(),
      max_value_depth=limits.max_depth,
    )
    is Some(input_workspace) &&
    input_workspace <= max_workspace_slots else {
    return Err(RankingWorkspaceLimit)
  }
  // Physical receiving ports and authored operation positions are distinct.
  // One exact input can occur at several positions without losing its order.
  let by_port : Map[Int, (RankingInput, Bool)] = Map([])
  for input in inputs {
    let port = ranking_input_port(input)
    if port < 0 || by_port.contains(port) {
      return Err(InvalidRankingKernel)
    }
    by_port[port] = (input, false)
  }
  let occurrence_inputs : Array[RankingInput] = []
  let mut unmatched = inputs.length()
  for edge in 0..<input_count {
    guard @lower.node_input_target(node, edge) is Some(target) else {
      return Err(InvalidRankingKernel)
    }
    let port = match target {
      @pipeline.Input(index) => index
      @pipeline.Step(_) => edge
    }
    guard by_port.get(port) is Some((input, matched)) else {
      return Err(InvalidRankingKernel)
    }
    if !ranking_input_matches_operation(input, owner, step, edge) {
      return Err(InvalidRankingKernel)
    }
    occurrence_inputs.push(input)
    if !matched {
      by_port[port] = (input, true)
      unmatched -= 1
    }
  }
  if unmatched != 0 {
    return Err(InvalidRankingKernel)
  }
  let mut total_rows = 0
  for input in occurrence_inputs {
    guard ranking_checked_add(total_rows, ranking_input_row_count(input))
      is Some(next) else {
      return Err(RankingWorkspaceLimit)
    }
    total_rows = next
  }
  guard ranking_workspace(
      total_rows,
      by_count,
      tie_count,
      input_count,
      inputs.length(),
      max_value_depth=limits.max_depth,
    )
    is Some(workspace) &&
    workspace <= max_workspace_slots else {
    return Err(RankingWorkspaceLimit)
  }
  if control_work_limit == 0 {
    return Err(RankingWorkLimit)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(RankingOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let scratch_slots = Ref(0)
  let output_field_slots = Ref(0)
  let port = match
    @execution.prepare_trusted_output_port_with_inputs(
      preparation,
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=inputs.map(ranking_trusted_input),
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(RankingCompletion(issue))
    }
  }
  let state : RankingState = {
    inputs: occurrence_inputs,
    output_schema,
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    policy,
    by,
    candidate_name,
    score_name: @lower.vector_ranking_score(prepared),
    rank_name: @lower.vector_ranking_rank(prepared),
    tie,
    k: k64.to_int(),
    score_minimum: @lower.vector_ranking_score_minimum(prepared),
    score_maximum: @lower.vector_ranking_score_maximum(prepared),
    value_limits: {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_text_bytes,
    },
    comparison: None,
    input_recheck: None,
    pending_field: None,
    name_probe: 0,
    name_offset: Ref(0),
    input_value_units: Ref(0),
    comparison_units: Ref(0),
    phase: BeginRecord,
    input: 0,
    row: 0,
    field: 0,
    group_values: [],
    candidate_value: None,
    tie_values: [],
    score_value: None,
    rank_value: None,
    validation_index: 0,
    validated_group: [],
    validated_tie: [],
    records: [],
    record_scratch: [],
    scratch_slots,
    record_order: InputCandidateOrder,
    width: 1,
    run_start: 0,
    middle: 0,
    run_end: 0,
    left_index: 0,
    right_index: 0,
    merge_index: 0,
    copy_index: 0,
    validate_index: 0,
    fusion_start: 0,
    fusion_end: 0,
    fusion_record: 0,
    fusion_input: 0,
    fusion_score: 0.0,
    fusion_maximum: None,
    fusion_participates: false,
    fused: [],
    fused_scratch: [],
    emit_index: 0,
    emit_rank: 0,
    emitted_group: None,
    output_field: 0,
    output_values: [],
    output_group_index: 0,
    output_row: None,
    output_row_units: Ref(0),
    output_field_slots,
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    ranking_step,
    cleanup_ranking_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({
    session,
    token: Some(token),
    accepted,
    scratch_slots,
    output_field_slots,
    comparison_units: state.comparison_units,
    output_row_units: state.output_row_units,
    input_value_units: state.input_value_units,
    name_offset: state.name_offset,
    max_noninterruptible_value_nodes: limits.max_nodes,
    max_noninterruptible_value_bytes: limits.max_text_bytes,
  })
}

///|
pub fn advance_ranking(
  value : RankingExecution,
  quantum : Int,
) -> Result[RankingPoll, RankingIssue] {
  guard value.token is Some(token) else {
    return Err(RankingExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(RankingExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(RankingContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(RankingComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(RankingFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(RankingStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn ranking_max_noninterruptible_value_nodes(
  value : RankingExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
/// Structural sort scratch retained by the current bounded phase.
pub fn ranking_scratch_slots(value : RankingExecution) -> Int {
  value.scratch_slots.val
}

///|
/// Charged key units visited by the current execution, cleared by cleanup.
pub fn ranking_comparison_units(value : RankingExecution) -> Int {
  value.comparison_units.val
}

///|
/// Output fields retained by the current bounded row assembly phase.
pub fn ranking_output_field_slots(value : RankingExecution) -> Int {
  value.output_field_slots.val
}

///|
/// Charged shared row-cursor polls, cleared by stopped cleanup.
pub fn ranking_output_row_units(value : RankingExecution) -> Int {
  value.output_row_units.val
}

///|
/// Charged input-value recheck polls, cleared only by stopped cleanup.
pub fn ranking_input_value_units(value : RankingExecution) -> Int {
  value.input_value_units.val
}

///|
/// Read-only fixture observation of retained reference matching, cleared by
/// stopped cleanup. This is not input admission or completion evidence.
pub fn ranking_name_offset(value : RankingExecution) -> Int {
  value.name_offset.val
}

///|
pub fn ranking_max_noninterruptible_value_bytes(
  value : RankingExecution,
) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn ranking_stopped(value : RankingExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn ranking_cleanup_pending(value : RankingExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_ranking(value : RankingExecution) -> Result[Bool, RankingIssue] {
  @bounded.cleanup(value.session).map_err(issue => RankingExecutionIssue(issue))
}
