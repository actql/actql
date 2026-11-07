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
  let checks : Array[@checked.SourceExecution] = []
  let coordinates : Array[(Int, Int, Int)] = []
  let mut whole = false
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
    let (stage, input, task) = coordinate
    // Three inventory probes and both ordered array shifts spend this same
    // finite selector allowance before examining or extending the arrays.
    if coordinates.length() > remaining.val / 5 {
      return Err(WorkLimit)
    }
    remaining.val -= 5 * coordinates.length()
    if coordinates.any(previous => previous.0 == stage && previous.1 == input) {
      return Err(DuplicateCapture)
    }
    if coordinates.any(previous => previous.2 == task) {
      whole = true
    }
    // Preserve captured-task order for Query callers. Complete inputs in the
    // same task retain their checked Source declaration order.
    let mut position = coordinates.length()
    for offset, previous in coordinates {
      if task < previous.2 {
        position = offset
        break
      }
    }
    coordinates.insert(position, coordinate)
    checks.insert(position, check)
  }
  if coordinates.length() < captures ||
    (!whole && coordinates.length() != captures) {
    return Err(MissingCapture)
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
  let route = match
    @acquisition.select_source_acquisition_route(
      requests,
      subject.input,
      remaining.val,
    ) {
    Ok(value) => value
    Err(@acquisition.QueryShape(@acquisition.WorkLimit))
    | Err(@acquisition.SourceInput(@acquisition.WorkLimit)) =>
      return Err(WorkLimit)
    Err(_) => return Err(UnsupportedShape)
  }
  let (target, pipeline) = match route {
    @acquisition.QueryRoute(acquisition) => {
      remaining.val -= @acquisition.query_acquisition_work(acquisition)
      (
        @acquisition.query_acquisition_capture(acquisition),
        @acquisition.query_acquisition_pipeline(acquisition),
      )
    }
    @acquisition.WholeInputRoute(acquisition) => {
      remaining.val -= @acquisition.source_acquisition_work(acquisition)
      (
        @pipeline.Input(0),
        @acquisition.source_acquisition_pipeline(acquisition),
      )
    }
  }
  let task = match target {
    @pipeline.Step(step) =>
      @strategy.graph_stage_operation_task(graph, subject.stage, step)
    @pipeline.Input(_) =>
      @strategy.graph_stage_operation_task(graph, subject.stage, 0)
  }
  guard task is Some(task) &&
    task >= 0 &&
    task < captures &&
    @strategy.graph_task_owner(graph, task) is Some(owner) &&
    physical_equal(@lower.pipeline(@lower.bound_preparation(owner)), pipeline) else {
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

///|
/// Bounded scalar census of checked Direct reads. This allocates no inventory
/// and grants no source access; Plan selection still checks every original.
pub fn client_effect_direct_acquisition_count(
  prepared : PreparedClientEffectComputation,
  max_work : Int,
) -> Result[Int, ClientDirectAcquisitionOccurrenceIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let checked = @strategy.graph_program(
    @strategy.checked_effect_computation_graph(prepared.graph),
  )
  let count = @checked.source_execution_count(checked)
  if count > max_work {
    return Err(WorkLimit)
  }
  let mut direct = 0
  for index in 0..<count {
    let check = @checked.source_execution_at(checked, index).unwrap()
    if @checked.source_execution_kind(check) is @checked.CarrierResponse &&
      @checked.source_execution_subject(check).request
      is @acquisition.Direct(_, _) {
      direct += 1
    }
  }
  Ok(direct)
}
