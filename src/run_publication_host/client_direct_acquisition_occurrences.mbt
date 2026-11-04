///|
priv enum ClientDirectAcquisitionProgramOwner {
  DirectPure(PreparedClientProgram)
  DirectEffect(PreparedClientEffectComputation)
}

///|
/// Checked acquisition coordinates only. The original Effect owner is retained;
/// this inventory grants neither a physical read nor completion authority.
struct ClientDirectAcquisitionOccurrences {
  program : ClientDirectAcquisitionProgramOwner
  checks : Array[@checked.SourceExecution]
  coordinates : Array[(Int, Int, Int)]
}

///|
pub(all) enum ClientDirectAcquisitionOccurrenceIssue {
  InvalidLimits
  WorkLimit
  ForeignRequest
  UnsupportedShape
  DuplicateCapture
  MissingCapture
}

///|
pub fn select_client_direct_acquisition_occurrences(
  prepared : PreparedClientProgram,
  max_work : Int,
) -> Result[
  ClientDirectAcquisitionOccurrences,
  ClientDirectAcquisitionOccurrenceIssue,
] {
  select_client_direct_acquisition_occurrences_owned(
    DirectPure(prepared),
    prepared,
    max_work,
  )
}

///|
pub fn select_client_effect_direct_acquisition_occurrences(
  prepared : PreparedClientEffectComputation,
  max_work : Int,
) -> Result[
  ClientDirectAcquisitionOccurrences,
  ClientDirectAcquisitionOccurrenceIssue,
] {
  select_client_direct_acquisition_occurrences_owned(
    DirectEffect(prepared),
    client_effect_program_view(prepared),
    max_work,
  )
}

///|
fn select_client_direct_acquisition_occurrences_owned(
  retained : ClientDirectAcquisitionProgramOwner,
  prepared : PreparedClientProgram,
  max_work : Int,
) -> Result[
  ClientDirectAcquisitionOccurrences,
  ClientDirectAcquisitionOccurrenceIssue,
] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let graph = prepared.graph
  let checked = @strategy.graph_program(graph)
  let count = @checked.source_execution_count(checked)
  let captures = @strategy.graph_captured_prefix(graph)
  let remaining = Ref(max_work)
  if count > remaining.val {
    return Err(WorkLimit)
  }
  remaining.val -= count
  if captures > remaining.val {
    return Err(WorkLimit)
  }
  remaining.val -= captures
  let slots : Array[(@checked.SourceExecution, (Int, Int, Int))?] = Array::make(
    captures,
    None,
  )
  for index in 0..<count {
    let check = @checked.source_execution_at(checked, index).unwrap()
    guard @checked.source_execution_kind(check) is @checked.CarrierResponse &&
      @checked.source_execution_subject(check).request
      is @acquisition.Direct(_, _) else {
      continue
    }
    let coordinate = match
      client_direct_acquisition_occurrence_coordinate(
        prepared, check, remaining,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let (_, _, task) = coordinate
    if slots[task] is Some(_) {
      return Err(DuplicateCapture)
    }
    slots[task] = Some((check, coordinate))
  }
  if captures > remaining.val {
    return Err(WorkLimit)
  }
  let checks : Array[@checked.SourceExecution] = []
  let coordinates : Array[(Int, Int, Int)] = []
  for slot in slots {
    guard slot is Some((check, coordinate)) else { return Err(MissingCapture) }
    checks.push(check)
    coordinates.push(coordinate)
  }
  Ok({ program: retained, checks, coordinates, })
}

///|
fn client_direct_acquisition_occurrence_coordinate(
  prepared : PreparedClientProgram,
  check : @checked.SourceExecution,
  remaining : Ref[Int],
) -> Result[(Int, Int, Int), ClientDirectAcquisitionOccurrenceIssue] {
  let graph = prepared.graph
  let identity = @checked.source_identity(@strategy.graph_program(graph))
  let captures = @strategy.graph_captured_prefix(graph)
  let tasks = @strategy.graph_task_count(graph)
  guard @checked.source_execution_kind(check) is @checked.CarrierResponse else {
    return Err(UnsupportedShape)
  }
  let subject = @checked.source_execution_subject(check)
  guard subject.request is @acquisition.Direct(mode, request) else {
    return Err(UnsupportedShape)
  }
  guard physical_equal(subject.owner, identity) &&
    @context.program_identity_stage_requests(identity, subject.stage)
    is Some(requests) &&
    @acquisition.pipeline_request_at(requests, subject.input)
    is Some(@acquisition.Direct(original_mode, original_request)) &&
    physical_equal(mode, original_mode) &&
    physical_equal(request, original_request) else {
    return Err(ForeignRequest)
  }
  // Bound graph matching before inspecting the query capture shape. Query
  // derivation debits its own traversal from the same remaining allowance.
  if tasks > remaining.val {
    return Err(WorkLimit)
  }
  remaining.val -= tasks
  let acquisition = match
    @acquisition.derive_query_acquisition_shape(
      requests,
      subject.input,
      remaining.val,
    ) {
    Ok(value) => value
    Err(@acquisition.WorkLimit) => return Err(WorkLimit)
    Err(_) => return Err(UnsupportedShape)
  }
  remaining.val -= @acquisition.query_acquisition_work(acquisition)
  guard @acquisition.query_acquisition_capture(acquisition)
    is @pipeline.Step(step) &&
    @strategy.graph_stage_operation_task(graph, subject.stage, step)
    is Some(task) &&
    task >= 0 &&
    task < captures &&
    @strategy.graph_task_owner(graph, task) is Some(owner) &&
    physical_equal(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @acquisition.query_acquisition_pipeline(acquisition),
    ) else {
    return Err(UnsupportedShape)
  }
  Ok((subject.stage, subject.input, task))
}

///|
pub fn client_direct_acquisition_occurrence_count(
  value : ClientDirectAcquisitionOccurrences,
) -> Int {
  value.checks.length()
}

///|
/// Ordered by original captured task, not by authored Stage or input ordinal.
pub fn client_direct_acquisition_occurrence_at(
  value : ClientDirectAcquisitionOccurrences,
  index : Int,
) -> (Int, Int, Int)? {
  value.coordinates.get(index)
}

///|
pub fn client_direct_acquisition_occurrences_match_program(
  value : ClientDirectAcquisitionOccurrences,
  prepared : PreparedClientProgram,
) -> Bool {
  match value.program {
    DirectPure(original) => physical_equal(original, prepared)
    DirectEffect(_) => false
  }
}

///|
pub fn client_direct_acquisition_occurrences_match_effect_program(
  value : ClientDirectAcquisitionOccurrences,
  prepared : PreparedClientEffectComputation,
) -> Bool {
  match value.program {
    DirectPure(_) => false
    DirectEffect(original) => physical_equal(original, prepared)
  }
}
