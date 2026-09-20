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
priv enum RankingPhase {
  BeginRecord
  ReadField
  FinishRecord
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
  PrepareOutputSort
  PrepareOutputMerge
  MergeOutputs
  CopyOutputPass
  EmitOutput
  FinishRanking
}

///|
priv struct RankingState {
  inputs : Array[@execution.ProducerRead]
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
  mut phase : RankingPhase
  mut input : Int
  mut row : Int
  mut field : Int
  mut group_values : Array[@value.CheckedValue?]
  mut candidate_value : @value.CheckedValue?
  mut tie_values : Array[@value.CheckedValue?]
  mut score_value : Double?
  mut rank_value : Double?
  mut records : Array[RankingRecord]
  mut record_scratch : Array[RankingRecord?]
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
  max_noninterruptible_value_nodes : Int
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
fn ranking_workspace(rows : Int, by : Int, tie : Int, inputs : Int) -> Int? {
  guard ranking_checked_add(by, tie) is Some(key_width) &&
    ranking_checked_add(key_width, 8) is Some(record_width) &&
    ranking_checked_add(key_width, 5) is Some(output_width) &&
    ranking_checked_add(key_width, 16) is Some(fixed_width) &&
    ranking_checked_multiply(rows, record_width) is Some(records) &&
    ranking_checked_multiply(rows, output_width) is Some(outputs) &&
    ranking_checked_add(records, rows) is Some(first) &&
    ranking_checked_add(first, outputs) is Some(second) &&
    ranking_checked_add(second, rows) is Some(third) &&
    ranking_checked_add(third, inputs) is Some(fourth) &&
    ranking_checked_add(fourth, fixed_width) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn ranking_values_compare(
  left : Array[@value.CheckedValue],
  right : Array[@value.CheckedValue],
) -> Result[Int, RankingIssue] {
  if left.length() != right.length() {
    return Err(InvalidRankingKernel)
  }
  for index in 0..<left.length() {
    let comparison = match
      @value.compare_key_values(left[index], right[index]) {
      Ok(value) => value
      Err(issue) => return Err(RankingKeyOrder(issue))
    }
    if comparison != 0 {
      return Ok(comparison)
    }
  }
  Ok(0)
}

///|
fn ranking_record_compare(
  left : RankingRecord,
  right : RankingRecord,
  order : RankingRecordOrder,
) -> Result[Int, RankingIssue] {
  match order {
    InputCandidateOrder | InputRankOrder =>
      if left.input != right.input {
        return Ok(if left.input < right.input { -1 } else { 1 })
      }
    CandidateInputOrder => ()
  }
  let group = match ranking_values_compare(left.group, right.group) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if group != 0 {
    return Ok(group)
  }
  if order is InputRankOrder {
    guard left.rank is Some(a) && right.rank is Some(b) else {
      return Err(InvalidRankingKernel)
    }
    if a != b {
      return Ok(if a < b { -1 } else { 1 })
    }
  }
  let candidate = match
    @value.compare_key_values(left.candidate, right.candidate) {
    Ok(value) => value
    Err(issue) => return Err(RankingKeyOrder(issue))
  }
  if candidate != 0 {
    return Ok(candidate)
  }
  if order is CandidateInputOrder && left.input != right.input {
    return Ok(if left.input < right.input { -1 } else { 1 })
  }
  Ok(0)
}

///|
fn fused_ranking_compare(
  left : FusedRanking,
  right : FusedRanking,
) -> Result[Int, RankingIssue] {
  let group = match ranking_values_compare(left.group, right.group) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if group != 0 {
    return Ok(group)
  }
  if left.score != right.score {
    return Ok(if left.score > right.score { -1 } else { 1 })
  }
  let tie = match ranking_values_compare(left.tie, right.tie) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if tie != 0 {
    return Ok(tie)
  }
  match @value.compare_key_values(left.candidate, right.candidate) {
    Ok(value) => Ok(value)
    Err(issue) => Err(RankingKeyOrder(issue))
  }
}

///|
fn ranking_same_group(
  left : Array[@value.CheckedValue],
  right : Array[@value.CheckedValue],
) -> Result[Bool, RankingIssue] {
  ranking_values_compare(left, right).map(value => value == 0)
}

///|
fn ranking_same_candidate(
  left : RankingRecord,
  right : RankingRecord,
) -> Result[Bool, RankingIssue] {
  let same_group = match ranking_same_group(left.group, right.group) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !same_group {
    return Ok(false)
  }
  match @value.compare_key_values(left.candidate, right.candidate) {
    Ok(value) => Ok(value == 0)
    Err(issue) => Err(RankingKeyOrder(issue))
  }
}

///|
fn ranking_output_value(
  value : @value.CheckedValue,
  contract : @contract.Contract,
  limits : @value.Limits,
) -> @value.CheckedValue? {
  @value.recheck_runtime_value(value.value, contract, limits)
}

///|
fn ranking_input_available(state : RankingState) -> RankingIssue? {
  for index, input in state.inputs {
    if !@execution.producer_read_available(input) {
      return Some(RankingInputUnavailable(index))
    }
  }
  None
}

///|
fn begin_ranking_record(state : RankingState) -> Unit {
  state.field = 0
  state.group_values = Array::make(state.by.length(), None)
  state.candidate_value = None
  state.tie_values = Array::make(state.tie.length(), None)
  state.score_value = None
  state.rank_value = None
  state.phase = ReadField
}

///|
fn read_ranking_field(state : RankingState) -> Result[Unit, RankingIssue] {
  let read = state.inputs[state.input]
  let schema = @execution.producer_read_schema(read)
  guard @schema.field_at(schema, state.field) is Some(field) &&
    @execution.producer_read_checked_cell(
      read,
      state.row,
      state.field,
      state.value_limits,
    )
    is Some(value) else {
    return Err(InvalidRankingRecord(state.input, state.row))
  }
  let name = @schema.reference_name(field.name)
  for index, expected in state.by {
    if name == expected {
      state.group_values[index] = Some(value)
    }
  }
  if name == state.candidate_name {
    state.candidate_value = Some(value)
  }
  for index, expected in state.tie {
    if name == expected {
      state.tie_values[index] = Some(value)
    }
  }
  if state.score_name is Some(expected) && name == expected {
    guard value.value is @value.Number(number) else {
      return Err(InvalidRankingRecord(state.input, state.row))
    }
    state.score_value = Some(number)
  }
  if state.rank_name is Some(expected) && name == expected {
    guard value.value is @value.Number(number) else {
      return Err(InvalidRankingRecord(state.input, state.row))
    }
    state.rank_value = Some(number)
  }
  state.field += 1
  Ok(())
}

///|
fn finish_ranking_record(state : RankingState) -> Result[Unit, RankingIssue] {
  let group : Array[@value.CheckedValue] = []
  for value in state.group_values {
    guard value is Some(value) else {
      return Err(InvalidRankingRecord(state.input, state.row))
    }
    match @value.compare_key_values(value, value) {
      Ok(_) => group.push(value)
      Err(issue) => return Err(RankingKeyOrder(issue))
    }
  }
  guard state.candidate_value is Some(candidate) else {
    return Err(InvalidRankingRecord(state.input, state.row))
  }
  match @value.compare_key_values(candidate, candidate) {
    Ok(_) => ()
    Err(issue) => return Err(RankingKeyOrder(issue))
  }
  let tie : Array[@value.CheckedValue] = []
  for value in state.tie_values {
    guard value is Some(value) else {
      return Err(InvalidRankingRecord(state.input, state.row))
    }
    match @value.compare_key_values(value, value) {
      Ok(_) => tie.push(value)
      Err(issue) => return Err(RankingKeyOrder(issue))
    }
  }
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
  state.records.push({
    input: state.input,
    group,
    candidate,
    tie,
    score: state.score_value,
    rank: state.rank_value,
  })
  state.row += 1
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
      ranking_record_compare(
        state.records[state.left_index],
        state.records[state.right_index],
        state.record_order,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    emit_ranking_record_merge(state, comparison <= 0)
  }
  Ok(())
}

///|
fn start_ranking_record_sort(
  state : RankingState,
  order : RankingRecordOrder,
) -> Unit {
  state.record_order = order
  state.record_scratch = Array::make(state.records.length(), None)
  state.width = 1
  state.phase = PrepareRecordSort
}

///|
fn finish_ranking_record_sort(state : RankingState) -> Unit {
  state.record_scratch = []
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
    let same = match ranking_same_candidate(left, right) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if same {
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
    let same_group = match ranking_same_group(prior.group, current.group) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if same_input && same_group {
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
    ranking_same_candidate(
      state.records[state.fusion_start],
      state.records[state.fusion_end],
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if same {
    state.fusion_end += 1
  } else {
    state.phase = FoldFusion
  }
  Ok(())
}

///|
fn validate_ranking_tie(
  state : RankingState,
  record : RankingRecord,
) -> Result[Unit, RankingIssue] {
  let first = state.records[state.fusion_start]
  let comparison = match ranking_values_compare(first.tie, record.tie) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if comparison != 0 {
    Err(ConflictingRankingTie(state.fusion_record))
  } else {
    Ok(())
  }
}

///|
fn fold_ranking_input(state : RankingState) -> Result[Unit, RankingIssue] {
  let mut record : RankingRecord? = None
  if state.fusion_record < state.fusion_end &&
    state.records[state.fusion_record].input == state.fusion_input {
    record = Some(state.records[state.fusion_record])
    state.fusion_record += 1
  }
  match state.policy {
    Maximum =>
      if record is Some(record) {
        guard record.score is Some(score) else {
          return Err(InvalidRankingKernel)
        }
        match validate_ranking_tie(state, record) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
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
          match validate_ranking_tie(state, record) {
            Ok(_) => ()
            Err(issue) => return Err(issue)
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
      fused_ranking_compare(
        state.fused[state.left_index],
        state.fused[state.right_index],
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    emit_ranking_output_merge(state, comparison <= 0)
  }
  Ok(())
}

///|
fn ranking_group_value(
  state : RankingState,
  row : FusedRanking,
  name : String,
) -> @value.CheckedValue? {
  for index, expected in state.by {
    if name == expected {
      return row.group.get(index)
    }
  }
  None
}

///|
fn emit_ranking_result(state : RankingState) -> Result[Bool, RankingIssue] {
  let row = state.fused[state.emit_index]
  let same_group = match state.emitted_group {
    Some(group) =>
      match ranking_same_group(group, row.group) {
        Ok(value) => value
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
    return Ok(false)
  }
  guard state.output is Some(output) else { return Err(InvalidRankingKernel) }
  let supplied : Array[@value.CheckedValue] = []
  for field_index in 0..<@schema.field_count(state.output_schema) {
    guard @schema.field_at(state.output_schema, field_index) is Some(field) else {
      return Err(InvalidRankingKernel)
    }
    let name = @schema.reference_name(field.name)
    let value = if name == state.candidate_name {
      ranking_output_value(row.candidate, field.contract, state.value_limits)
    } else if name == "score" {
      @value.checked_number_value(row.score, field.contract)
    } else if name == "rank" {
      @value.checked_number_value(state.emit_rank.to_double(), field.contract)
    } else {
      ranking_group_value(state, row, name).bind(value => {
        ranking_output_value(value, field.contract, state.value_limits)
      })
    }
    guard value is Some(value) else { return Err(InvalidRankingKernel) }
    supplied.push(value)
  }
  match @execution.append_admitted_output(output, supplied) {
    Ok(_) => Ok(true)
    Err(issue) => Err(RankingOutput(issue))
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
    match state.phase {
      BeginRecord =>
        if state.input >= state.inputs.length() {
          start_ranking_record_sort(state, InputCandidateOrder)
        } else if state.row <
          @execution.producer_read_row_count(state.inputs[state.input]) {
          begin_ranking_record(state)
        } else {
          state.input += 1
          state.row = 0
        }
      ReadField => {
        let schema = @execution.producer_read_schema(state.inputs[state.input])
        if state.field < @schema.field_count(schema) {
          used += 1
          match read_ranking_field(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = FinishRecord
        }
      }
      FinishRecord => {
        used += 1
        match finish_ranking_record(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
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
          state.fused_scratch = Array::make(state.fused.length(), None)
          state.width = 1
          state.phase = PrepareOutputSort
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
      PrepareOutputSort =>
        if state.width >= state.fused.length() {
          state.fused_scratch = []
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
          match emit_ranking_result(state) {
            Ok(emitted) => {
              if emitted {
                progress += 1
              }
              state.emit_index += 1
            }
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = FinishRanking
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
  @bounded.Continue(progress, used)
}

///|
fn cleanup_ranking_state(state : RankingState) -> Bool {
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  state.group_values = []
  state.tie_values = []
  state.records = []
  state.record_scratch = []
  state.fused = []
  state.fused_scratch = []
  state.candidate_value = None
  state.emitted_group = None
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
) -> Result[RankingExecution, RankingIssue] {
  if max_rows < 0 ||
    max_workspace_slots < 0 ||
    max_entries < 0 ||
    max_name_bytes < 0 ||
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
  let occurrence_inputs : Array[@execution.ProducerRead] = []
  for edge in 0..<input_count {
    let mut matched = None
    for input in inputs {
      if @execution.producer_read_matches_operation_input(
          input, owner, step, edge,
        ) {
        if matched is Some(_) {
          return Err(InvalidRankingKernel)
        }
        matched = Some(input)
      }
    }
    guard matched is Some(input) else { return Err(InvalidRankingKernel) }
    occurrence_inputs.push(input)
  }
  for input in inputs {
    let mut matched = false
    for edge in 0..<input_count {
      if @execution.producer_read_matches_operation_input(
          input, owner, step, edge,
        ) {
        matched = true
      }
    }
    if !matched {
      return Err(InvalidRankingKernel)
    }
  }
  let tie_count = @lower.vector_ranking_tie_break_count(prepared).unwrap_or(0)
  guard prepared_ranking_names(tie_count, index => {
      @lower.vector_ranking_tie_break_at(prepared, index)
    })
    is Some(tie) else {
    return Err(InvalidRankingKernel)
  }
  let mut total_rows = 0
  for input in occurrence_inputs {
    guard ranking_checked_add(
        total_rows,
        @execution.producer_read_row_count(input),
      )
      is Some(next) else {
      return Err(RankingWorkspaceLimit)
    }
    total_rows = next
  }
  guard ranking_workspace(total_rows, by_count, tie_count, input_count)
    is Some(workspace) &&
    workspace <= max_workspace_slots else {
    return Err(RankingWorkspaceLimit)
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
  let port = match
    @execution.prepare_trusted_output_port(
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
    phase: BeginRecord,
    input: 0,
    row: 0,
    field: 0,
    group_values: [],
    candidate_value: None,
    tie_values: [],
    score_value: None,
    rank_value: None,
    records: [],
    record_scratch: [],
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
