///|
priv struct ScoredRecord {
  source_index : Int
  score : Double
  identities : Array[@value.CheckedValue]
}

///|
priv enum ScorePhase {
  ScoreValidateQuery
  ScoreInitializeScratch
  ScoreBeginRecord
  ScoreReadField
  ScoreMatchIdentity
  ScoreValidateIdentities
  ScoreFoldComponents
  ScoreFinishFold
  ScorePreparePass
  ScorePrepareMerge
  ScoreMerge
  ScoreCompareTie
  ScoreCopyPass
  ScoreBeginEmit
  ScoreReadEmitFields
  ScoreAppendValue
  ScoreCommitRecord
  ScoreFinish
}

///|
priv struct ScoreState {
  input : @records.ProducerRead
  source : @storage.Storage
  vectors : @carrier.Vectors
  prepared : @lower.PreparedVector
  mut output : @records.OutputBuilder?
  score_contract : @contract.Contract
  metric : @numeric.Metric
  dimensions : Int
  identity_count : Int
  component_name : String
  mut query : Array[Double]
  mut phase : ScorePhase
  mut record : Int
  mut field : Int
  mut identity_probe : Int
  mut current_field : (@schema.FieldName, @value.CheckedValue)?
  mut source_vector : @value.CheckedValue?
  mut identity_values : Array[@value.CheckedValue?]
  mut collected_identities : Array[@value.CheckedValue]
  mut component : Int
  mut fold : @numeric.ScoreFold?
  mut finished_score : Double
  mut order : Array[ScoredRecord]
  mut scratch : Array[ScoredRecord?]
  mut width : Int
  mut run_start : Int
  mut left_index : Int
  mut middle : Int
  mut right_index : Int
  mut run_end : Int
  mut merge_index : Int
  mut tie_index : Int
  mut copy_index : Int
  mut emit_index : Int
  mut emit_field : Int
  mut emit_fields : Array[(@schema.FieldName, @value.CheckedValue)]
}

///|
struct ScoreExecution {
  session : @bounded.Session[ScoreState, @records.Completed, ScoreIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum ScorePoll {
  ScoreContinue(progress~ : Int64, work~ : Int64)
  ScoreComplete(@records.Completed, progress~ : Int64, work~ : Int64)
  ScoreFailed(ScoreIssue, progress~ : Int64, work~ : Int64)
  ScoreStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum ScoreIssue {
  InvalidScoreKernel
  InvalidScoreLimits
  ScoreInputUnavailable
  InvalidScoreRecord(Int)
  InvalidScoreVector(Int)
  InvalidScoreIdentity(Int)
  ScoreWorkspaceLimit
  ScoreNumeric(@numeric.Issue)
  ScoreKeyOrder(@value.KeyOrderIssue)
  ScoreOutput(@records.Issue)
  ScoreExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn checked_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn checked_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn score_workspace(
  records : Int,
  dimensions : Int,
  identities : Int,
  output_fields : Int,
) -> Int? {
  guard checked_add(identities, 2) is Some(score_slots) &&
    checked_multiply(records, score_slots) is Some(scored) &&
    checked_add(output_fields, 2) is Some(record_slots) &&
    checked_multiply(records, record_slots) is Some(retained) &&
    checked_add(dimensions, scored) is Some(first) &&
    checked_add(first, retained) is Some(second) &&
    checked_add(second, output_fields) is Some(third) &&
    checked_add(third, identities) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn query_component(state : ScoreState, index : Int) -> Double? {
  @lower.vector_score_query_at(state.prepared, index)
}

///|
fn validate_query_component(state : ScoreState) -> Result[Unit, ScoreIssue] {
  guard query_component(state, state.component) is Some(raw) else {
    return Err(InvalidScoreKernel)
  }
  match @numeric.quantize(raw) {
    Ok(value) => {
      state.query.push(value)
      state.component += 1
      Ok(())
    }
    Err(issue) => Err(ScoreNumeric(issue))
  }
}

///|
fn begin_score_record(state : ScoreState) -> Result[Unit, ScoreIssue] {
  guard @storage.record_field_count(state.source, state.record) is Some(_) else {
    return Err(InvalidScoreRecord(state.record))
  }
  state.field = 0
  state.identity_probe = 0
  state.current_field = None
  state.source_vector = None
  state.identity_values = Array::make(state.identity_count, None)
  state.collected_identities = []
  state.component = 0
  state.fold = None
  state.finished_score = 0.0
  state.phase = ScoreReadField
  Ok(())
}

///|
fn load_score_field(state : ScoreState) -> Result[Unit, ScoreIssue] {
  guard @storage.record_field_at(state.source, state.record, state.field)
    is Some((name, checked)) else {
    return Err(InvalidScoreRecord(state.record))
  }
  if @schema.reference_name(name) == state.component_name {
    if state.source_vector is Some(_) {
      return Err(InvalidScoreRecord(state.record))
    }
    state.source_vector = Some(checked)
  }
  state.current_field = Some((name, checked))
  state.identity_probe = 0
  state.phase = ScoreMatchIdentity
  Ok(())
}

///|
fn match_score_identity(state : ScoreState) -> Result[Unit, ScoreIssue] {
  guard state.current_field is Some((name, checked)) &&
    @carrier.vector_identity_at(state.vectors, state.identity_probe)
    is Some(identity) else {
    return Err(InvalidScoreRecord(state.record))
  }
  if @schema.reference_name(name) == @schema.reference_name(identity.name) {
    if state.identity_values[state.identity_probe] is Some(_) {
      return Err(InvalidScoreIdentity(state.record))
    }
    state.identity_values[state.identity_probe] = Some(checked)
  }
  state.identity_probe += 1
  if state.identity_probe >= state.identity_count {
    state.current_field = None
    state.field += 1
    state.phase = ScoreReadField
  }
  Ok(())
}

///|
fn finish_score_fields(state : ScoreState) -> Result[Unit, ScoreIssue] {
  guard state.source_vector is Some(checked) &&
    checked.value is @value.Vector(values) &&
    @value.element_count(values) == state.dimensions else {
    return Err(InvalidScoreVector(state.record))
  }
  state.collected_identities = []
  state.identity_probe = 0
  state.phase = ScoreValidateIdentities
  Ok(())
}

///|
fn validate_score_identity(state : ScoreState) -> Result[Unit, ScoreIssue] {
  guard state.identity_values[state.identity_probe] is Some(value) else {
    return Err(InvalidScoreIdentity(state.record))
  }
  match @value.compare_key_values(value, value) {
    Ok(_) => ()
    Err(issue) => return Err(ScoreKeyOrder(issue))
  }
  state.collected_identities.push(value)
  state.identity_probe += 1
  if state.identity_probe >= state.identity_count {
    state.fold = Some(@numeric.prepare_score(state.metric))
    state.component = 0
    state.phase = ScoreFoldComponents
  }
  Ok(())
}

///|
fn fold_score_component(state : ScoreState) -> Result[Unit, ScoreIssue] {
  guard state.source_vector is Some(checked) &&
    checked.value is @value.Vector(values) &&
    @value.element_at(values, state.component) is Some(component) &&
    state.query.get(state.component) is Some(query) &&
    state.fold is Some(fold) else {
    return Err(InvalidScoreVector(state.record))
  }
  match @numeric.score_step(fold, component, query) {
    Ok(_) => {
      state.component += 1
      Ok(())
    }
    Err(issue) => Err(ScoreNumeric(issue))
  }
}

///|
fn finish_score_fold(state : ScoreState) -> Result[Unit, ScoreIssue] {
  guard state.fold is Some(fold) else { return Err(InvalidScoreKernel) }
  state.finished_score = match @numeric.finish_score(fold) {
    Ok(value) => value
    Err(issue) => return Err(ScoreNumeric(issue))
  }
  state.fold = None
  state.order.push({
    source_index: state.record,
    score: state.finished_score,
    identities: state.collected_identities,
  })
  state.identity_values = []
  state.collected_identities = []
  state.source_vector = None
  state.record += 1
  state.phase = ScoreBeginRecord
  Ok(())
}

///|
fn capped_run_end(start : Int, width : Int, count : Int) -> Int {
  if width >= count - start {
    count
  } else {
    start + width
  }
}

///|
fn prepare_score_merge(state : ScoreState) -> Unit {
  state.middle = capped_run_end(
    state.run_start,
    state.width,
    state.order.length(),
  )
  state.run_end = capped_run_end(
    state.middle,
    state.width,
    state.order.length(),
  )
  state.left_index = state.run_start
  state.right_index = state.middle
  state.merge_index = state.run_start
  state.tie_index = 0
  state.phase = ScoreMerge
}

///|
fn emit_score_merge(state : ScoreState, take_left : Bool) -> Unit {
  let selected = if take_left {
    let value = state.order[state.left_index]
    state.left_index += 1
    value
  } else {
    let value = state.order[state.right_index]
    state.right_index += 1
    value
  }
  state.scratch[state.merge_index] = Some(selected)
  state.merge_index += 1
  if state.merge_index >= state.run_end {
    state.run_start = state.run_end
    state.phase = ScorePrepareMerge
  }
}

///|
fn merge_score_record(state : ScoreState) -> Unit {
  if state.left_index >= state.middle {
    emit_score_merge(state, false)
    return
  }
  if state.right_index >= state.run_end {
    emit_score_merge(state, true)
    return
  }
  let left = state.order[state.left_index]
  let right = state.order[state.right_index]
  if left.score > right.score {
    emit_score_merge(state, true)
  } else if left.score < right.score {
    emit_score_merge(state, false)
  } else {
    state.tie_index = 0
    state.phase = ScoreCompareTie
  }
}

///|
fn compare_score_tie(state : ScoreState) -> Result[Unit, ScoreIssue] {
  let left = state.order[state.left_index]
  let right = state.order[state.right_index]
  if state.tie_index >= state.identity_count {
    emit_score_merge(state, true)
    return Ok(())
  }
  let comparison = match
    @value.compare_key_values(
      left.identities[state.tie_index],
      right.identities[state.tie_index],
    ) {
    Ok(value) => value
    Err(issue) => return Err(ScoreKeyOrder(issue))
  }
  if comparison < 0 {
    emit_score_merge(state, true)
  } else if comparison > 0 {
    emit_score_merge(state, false)
  } else {
    state.tie_index += 1
  }
  Ok(())
}

///|
fn begin_emit_record(state : ScoreState) -> Unit {
  state.emit_field = 0
  state.emit_fields = []
  state.phase = ScoreReadEmitFields
}

///|
fn read_emit_field(state : ScoreState) -> Result[Unit, ScoreIssue] {
  let source_index = state.order[state.emit_index].source_index
  guard @storage.record_field_at(state.source, source_index, state.emit_field)
    is Some(field) else {
    return Err(InvalidScoreRecord(source_index))
  }
  state.emit_fields.push(field)
  state.emit_field += 1
  Ok(())
}

///|
fn append_score_value(state : ScoreState) -> Result[Unit, ScoreIssue] {
  guard @value.checked_number_value(
      state.order[state.emit_index].score,
      state.score_contract,
    )
    is Some(score) else {
    return Err(InvalidScoreKernel)
  }
  state.emit_fields.push((@schema.Unqualified("score"), score))
  state.phase = ScoreCommitRecord
  Ok(())
}

///|
fn commit_score_record(state : ScoreState) -> Result[Unit, ScoreIssue] {
  guard state.output is Some(output) else { return Err(InvalidScoreKernel) }
  match @records.append_record(output, state.emit_fields) {
    Ok(_) => {
      state.emit_fields = []
      state.emit_index += 1
      state.phase = ScoreBeginEmit
      Ok(())
    }
    Err(issue) => Err(ScoreOutput(issue))
  }
}

///|
fn score_step(
  state : ScoreState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@records.Completed, ScoreIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@records.producer_read_available(state.input) {
      return @bounded.Failed(ScoreInputUnavailable, progress, used)
    }
    match state.phase {
      ScoreValidateQuery =>
        if state.component < state.dimensions {
          used += 1
          match validate_query_component(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = ScoreInitializeScratch
        }
      ScoreInitializeScratch =>
        if state.scratch.length() < @storage.record_count(state.source) {
          state.scratch.push(None)
          used += 1
        } else {
          state.phase = ScoreBeginRecord
        }
      ScoreBeginRecord =>
        if state.record < @storage.record_count(state.source) {
          used += 1
          match begin_score_record(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = ScorePreparePass
        }
      ScoreReadField => {
        let count = @storage.record_field_count(state.source, state.record).unwrap_or(
          -1,
        )
        if state.field < count {
          used += 1
          match load_score_field(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          used += 1
          match finish_score_fields(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        }
      }
      ScoreMatchIdentity => {
        used += 1
        match match_score_identity(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ScoreValidateIdentities => {
        used += 1
        match validate_score_identity(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ScoreFoldComponents =>
        if state.component < state.dimensions {
          used += 1
          match fold_score_component(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = ScoreFinishFold
        }
      ScoreFinishFold => {
        used += 1
        match finish_score_fold(state) {
          Ok(_) => progress += 1
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ScorePreparePass =>
        if state.width >= state.order.length() {
          state.scratch.clear()
          state.emit_index = 0
          state.phase = ScoreBeginEmit
        } else {
          state.run_start = 0
          state.phase = ScorePrepareMerge
        }
      ScorePrepareMerge =>
        if state.run_start >= state.order.length() {
          state.copy_index = 0
          state.phase = ScoreCopyPass
        } else {
          prepare_score_merge(state)
        }
      ScoreMerge => {
        merge_score_record(state)
        used += 1
      }
      ScoreCompareTie => {
        used += 1
        match compare_score_tie(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ScoreCopyPass =>
        if state.copy_index < state.order.length() {
          guard state.scratch[state.copy_index] is Some(record) else {
            return @bounded.Failed(InvalidScoreKernel, progress, used)
          }
          state.order[state.copy_index] = record
          state.scratch[state.copy_index] = None
          state.copy_index += 1
          used += 1
        } else {
          state.width = if state.width > state.order.length() / 2 {
            state.order.length()
          } else {
            state.width * 2
          }
          state.phase = ScorePreparePass
        }
      ScoreBeginEmit =>
        if state.emit_index < state.order.length() {
          begin_emit_record(state)
        } else {
          state.phase = ScoreFinish
        }
      ScoreReadEmitFields => {
        let source_index = state.order[state.emit_index].source_index
        let count = @storage.record_field_count(state.source, source_index).unwrap_or(
          -1,
        )
        if state.emit_field < count {
          used += 1
          match read_emit_field(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = ScoreAppendValue
        }
      }
      ScoreAppendValue => {
        used += 1
        match append_score_value(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ScoreCommitRecord => {
        used += 1
        match commit_score_record(state) {
          Ok(_) => progress += 1
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ScoreFinish => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidScoreKernel, progress, used)
        }
        state.output = None
        return match @records.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(ScoreOutput(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_score_state(state : ScoreState) -> Bool {
  if state.output is Some(output) {
    @records.cancel_output(output) |> ignore
    state.output = None
  }
  state.query = []
  state.identity_values = []
  state.collected_identities = []
  state.order = []
  state.scratch = []
  state.emit_fields = []
  state.source_vector = None
  state.fold = None
  true
}

///|
pub fn start_score(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[ScoreExecution, ScoreIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.VectorStep(prepared)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "VEC.score_sort" &&
    physical_equal(@records.producer_read_receiver(input), owner) &&
    @records.producer_read_input_index(input) == 0 else {
    return Err(InvalidScoreKernel)
  }
  guard @records.producer_read_storage(input) is Some(source) &&
    @storage.carrier(source) is @carrier.VectorValue(vectors) &&
    @lower.vector_output_carrier(prepared)
    is @carrier.VectorValue(output_vectors) &&
    @carrier.lookup(
      @carrier.vector_records(output_vectors),
      @schema.Unqualified("score"),
    )
    is @carrier.Present({ contract: Some(score_contract), .. }) &&
    score_contract.shape is @contract.Number &&
    !score_contract.nullable else {
    return Err(ScoreInputUnavailable)
  }
  let raw_dimensions = @carrier.vector_dimensions(vectors)
  guard raw_dimensions >= 1.0 && raw_dimensions <= 2147483647.0 else {
    return Err(InvalidScoreLimits)
  }
  let dimensions = raw_dimensions.to_int()
  guard dimensions.to_double() == raw_dimensions &&
    @lower.vector_score_query_count(prepared) == Some(dimensions) &&
    @lower.vector_score_metric(prepared) is Some(metric) else {
    return Err(InvalidScoreKernel)
  }
  let identity_count = @carrier.vector_identity_count(vectors)
  let output_fields = @carrier.field_count(
    @carrier.vector_records(output_vectors),
  )
  guard identity_count > 0 &&
    score_workspace(
      @storage.record_count(source),
      dimensions,
      identity_count,
      output_fields,
    )
    is Some(workspace) &&
    workspace <= limits.max_workspace_slots else {
    return Err(ScoreWorkspaceLimit)
  }
  let numeric_metric = match metric {
    @lower.CosineScore => @numeric.Cosine
    @lower.DotScore => @numeric.Dot
    @lower.L2Score => @numeric.L2
  }
  let output = match
    @records.prepare_output(
      owner,
      @pipeline.Step(step),
      limits,
      storage_bytes,
      available,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ScoreOutput(issue))
  }
  let state : ScoreState = {
    input,
    source,
    vectors,
    prepared,
    output: Some(output),
    score_contract,
    metric: numeric_metric,
    dimensions,
    identity_count,
    component_name: @schema.reference_name(
      @carrier.vector_components(vectors).name,
    ),
    query: [],
    phase: ScoreValidateQuery,
    record: 0,
    field: 0,
    identity_probe: 0,
    current_field: None,
    source_vector: None,
    identity_values: [],
    collected_identities: [],
    component: 0,
    fold: None,
    finished_score: 0.0,
    order: [],
    scratch: [],
    width: 1,
    run_start: 0,
    left_index: 0,
    middle: 0,
    right_index: 0,
    run_end: 0,
    merge_index: 0,
    tie_index: 0,
    copy_index: 0,
    emit_index: 0,
    emit_field: 0,
    emit_fields: [],
  }
  let (session, token) = @bounded.start(
    control, state, score_step, cleanup_score_state,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes,
    max_noninterruptible_value_bytes: limits.max_value_bytes,
  })
}

///|
pub fn score_max_noninterruptible_value_nodes(value : ScoreExecution) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn score_max_noninterruptible_value_bytes(value : ScoreExecution) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn advance_score(
  value : ScoreExecution,
  quantum : Int,
) -> Result[ScorePoll, ScoreIssue] {
  guard value.token is Some(token) else {
    return Err(ScoreExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(ScoreExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(ScoreContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(ScoreComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(ScoreFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(ScoreStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn score_stopped(value : ScoreExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn score_cleanup_pending(value : ScoreExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_score(value : ScoreExecution) -> Result[Bool, ScoreIssue] {
  @bounded.cleanup(value.session).map_err(issue => ScoreExecutionIssue(issue))
}
