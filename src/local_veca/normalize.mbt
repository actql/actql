///|
priv enum NormalizePhase {
  BeginRecord
  ReadFields
  FoldNorm
  FinishNorm
  EmitComponents
  CommitRecord
  Finish
}

///|
priv struct NormalizeState {
  input : @records.ProducerRead
  source : @storage.Storage
  mut output : @records.OutputBuilder?
  limits : @storage.Limits
  component_name : String
  dimensions : Int
  mut phase : NormalizePhase
  mut record : Int
  mut field : Int
  mut component_field : Int
  mut fields : Array[(@schema.FieldName, @value.CheckedValue)]
  mut source_vector : @value.CheckedValue?
  mut output_vector : @value.VectorBuilder?
  mut component : Int
  mut norm_squared : Double
  mut divisor : Double
  mut control_work_remaining : Int
}

///|
struct NormalizeExecution {
  session : @bounded.Session[NormalizeState, @records.Completed, NormalizeIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
}

///|
pub enum NormalizePoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@records.Completed, progress~ : Int64, work~ : Int64)
  Failed(NormalizeIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum NormalizeIssue {
  InvalidKernel
  InvalidLimits
  InputUnavailable
  InvalidRecord(Int)
  InvalidVector(Int)
  WorkspaceLimit
  WorkLimit
  Numeric(@numeric.Issue)
  Output(@records.Issue)
  Execution(@bounded.Issue)
} derive(Eq, Debug)

///|
fn begin_record(state : NormalizeState) -> Result[Unit, NormalizeIssue] {
  guard @storage.record_field_count(state.source, state.record)
    is Some(field_count) else {
    return Err(InvalidRecord(state.record))
  }
  let current = match state.output {
    Some(output) => @records.output_workspace_slots(output)
    None => return Err(InvalidKernel)
  }
  if field_count > (2147483647 - 2) / 2 {
    return Err(WorkspaceLimit)
  }
  let field_slots = field_count * 2 + 2
  if state.dimensions > 2147483647 - field_slots {
    return Err(WorkspaceLimit)
  }
  let needed = state.dimensions + field_slots
  if current > state.limits.max_workspace_slots ||
    needed > state.limits.max_workspace_slots - current {
    return Err(WorkspaceLimit)
  }
  state.field = 0
  state.component_field = -1
  state.fields = []
  state.source_vector = None
  state.output_vector = None
  state.component = 0
  state.norm_squared = 0.0
  state.divisor = 0.0
  state.phase = ReadFields
  Ok(())
}

///|
fn read_field(state : NormalizeState) -> Result[Unit, NormalizeIssue] {
  guard @storage.record_field_at(state.source, state.record, state.field)
    is Some((name, checked)) else {
    return Err(InvalidRecord(state.record))
  }
  if @schema.reference_name(name) == state.component_name {
    if state.component_field >= 0 {
      return Err(InvalidRecord(state.record))
    }
    state.component_field = state.field
    state.source_vector = Some(checked)
  }
  state.fields.push((name, checked))
  state.field += 1
  Ok(())
}

///|
fn source_component(
  state : NormalizeState,
  index : Int,
) -> Result[Double, NormalizeIssue] {
  guard state.source_vector is Some(checked) &&
    checked.value is @value.Vector(values) &&
    @value.element_count(values) == state.dimensions &&
    @value.element_at(values, index) is Some(component) else {
    return Err(InvalidVector(state.record))
  }
  Ok(component)
}

///|
fn finish_field_read(state : NormalizeState) -> Result[Unit, NormalizeIssue] {
  if state.component_field < 0 {
    return Err(InvalidVector(state.record))
  }
  match source_component(state, 0) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard @value.prepare_vector_value(state.dimensions) is Some(builder) else {
    return Err(InvalidVector(state.record))
  }
  state.output_vector = Some(builder)
  state.component = 0
  state.phase = FoldNorm
  Ok(())
}

///|
fn fold_component(state : NormalizeState) -> Result[Unit, NormalizeIssue] {
  let component = match source_component(state, state.component) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  state.norm_squared = match
    @numeric.squared_norm_step(state.norm_squared, component) {
    Ok(value) => value
    Err(issue) => return Err(Numeric(issue))
  }
  state.component += 1
  Ok(())
}

///|
fn finish_norm(state : NormalizeState) -> Result[Unit, NormalizeIssue] {
  state.divisor = match @numeric.normalization_divisor(state.norm_squared) {
    Ok(value) => value
    Err(issue) => return Err(Numeric(issue))
  }
  state.component = 0
  state.phase = EmitComponents
  Ok(())
}

///|
fn emit_component(state : NormalizeState) -> Result[Unit, NormalizeIssue] {
  let source = match source_component(state, state.component) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let component = match @numeric.normalize_component(source, state.divisor) {
    Ok(value) => value
    Err(issue) => return Err(Numeric(issue))
  }
  guard state.output_vector is Some(builder) &&
    @value.append_vector_component(builder, component) else {
    return Err(InvalidVector(state.record))
  }
  state.component += 1
  Ok(())
}

///|
fn commit_record(state : NormalizeState) -> Result[Unit, NormalizeIssue] {
  guard state.output is Some(output) &&
    state.output_vector is Some(builder) &&
    state.fields.get(state.component_field) is Some((name, source)) &&
    @value.finish_checked_vector_value(builder, source.contract) is Some(vector) else {
    return Err(InvalidKernel)
  }
  state.output_vector = None
  let index = state.component_field
  state.fields[index] = (name, vector)
  match @records.append_record(output, state.fields) {
    Ok(_) => {
      state.fields = []
      state.source_vector = None
      state.record += 1
      state.phase = BeginRecord
      Ok(())
    }
    Err(issue) => Err(Output(issue))
  }
}

///|
fn normalize_step(
  state : NormalizeState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@records.Completed, NormalizeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@records.producer_read_available(state.input) {
      return @bounded.Failed(InputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(WorkLimit, progress, used)
    }
    match state.phase {
      BeginRecord =>
        if state.record < @storage.record_count(state.source) {
          match begin_record(state) {
            Ok(_) => used += 1
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = Finish
        }
      ReadFields => {
        let count = @storage.record_field_count(state.source, state.record).unwrap_or(
          -1,
        )
        if state.field < count {
          match read_field(state) {
            Ok(_) => used += 1
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          match finish_field_read(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        }
      }
      FoldNorm =>
        if state.component < state.dimensions {
          match fold_component(state) {
            Ok(_) => used += 1
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = FinishNorm
        }
      FinishNorm =>
        match finish_norm(state) {
          Ok(_) => used += 1
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      EmitComponents =>
        if state.component < state.dimensions {
          match emit_component(state) {
            Ok(_) => used += 1
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = CommitRecord
        }
      CommitRecord =>
        match commit_record(state) {
          Ok(_) => {
            used += 1
            progress += 1
          }
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      Finish => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        state.output = None
        return match @records.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(Output(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_state(state : NormalizeState) -> Bool {
  if state.output_vector is Some(builder) {
    @value.cancel_vector_value(builder) |> ignore
    state.output_vector = None
  }
  if state.output is Some(output) {
    @records.cancel_output(output) |> ignore
    state.output = None
  }
  state.fields = []
  state.source_vector = None
  true
}

///|
fn start_normalize_with_control_work_limit(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit : Int,
) -> Result[NormalizeExecution, NormalizeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(@lower.VectorStep(_)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "VEC.normalize_l2" &&
    @records.producer_read_matches_operation_input(input, owner, step, 0) else {
    return Err(InvalidKernel)
  }
  guard @records.producer_read_storage(input) is Some(source) &&
    @storage.carrier(source) is @carrier.VectorValue(vectors) else {
    return Err(InputUnavailable)
  }
  let raw_dimensions = @carrier.vector_dimensions(vectors)
  if raw_dimensions < 1.0 || raw_dimensions > 2147483647.0 {
    return Err(InvalidLimits)
  }
  let dimensions = raw_dimensions.to_int()
  if dimensions.to_double() != raw_dimensions ||
    limits.max_value_nodes < dimensions + 1 ||
    limits.max_workspace_slots < dimensions {
    return Err(InvalidLimits)
  }
  if control_work_limit < 0 {
    return Err(InvalidLimits)
  }
  if control_work_limit == 0 {
    return Err(WorkLimit)
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
    Err(issue) => return Err(Output(issue))
  }
  let state : NormalizeState = {
    input,
    source,
    output: Some(output),
    limits,
    component_name: @schema.reference_name(
      @carrier.vector_components(vectors).name,
    ),
    dimensions,
    phase: BeginRecord,
    record: 0,
    field: 0,
    component_field: -1,
    fields: [],
    source_vector: None,
    output_vector: None,
    component: 0,
    norm_squared: 0.0,
    divisor: 0.0,
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control, state, normalize_step, cleanup_state, @records.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes,
  })
}

///|
pub fn start_normalize(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[NormalizeExecution, NormalizeIssue] {
  start_normalize_with_control_work_limit(
    control,
    sequence,
    step,
    input,
    limits,
    storage_bytes,
    available,
    limits.max_work,
  )
}

///|
pub fn normalize_max_noninterruptible_value_nodes(
  value : NormalizeExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn advance_normalize(
  value : NormalizeExecution,
  quantum : Int,
) -> Result[NormalizePoll, NormalizeIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(Continue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(Complete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(Failed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(Stopped(reason, progress~, work~))
    }
  }
}

///|
pub fn normalize_stopped(value : NormalizeExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn normalize_cleanup_pending(value : NormalizeExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_normalize(
  value : NormalizeExecution,
) -> Result[Bool, NormalizeIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}
