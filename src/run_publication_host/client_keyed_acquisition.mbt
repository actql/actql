///|
/// A checked keyed Source port under the existing Program owner. This is a
/// logical acquisition selection, not I/O authority, transport completion or
/// an independently executable Program. Keep Effect ownership when selecting
/// through the private computation view.
priv enum ClientKeyedProgramOwner {
  KeyedPure(PreparedClientProgram)
  KeyedEffect(PreparedClientEffectComputation)
}

///|
struct ClientKeyedAcquisition {
  program : ClientKeyedProgramOwner
  check : @checked.SourceExecution
  binding : @checked.KeyedExecution
  facts : @acquisition.KeyedSourceFacts
  owner : @lower.BoundPrepared
}

///|
pub(all) enum ClientKeyedAcquisitionIssue {
  InvalidLimits
  WorkLimit
  MissingStage
  MissingRequests
  MissingKeyedJoin
  AmbiguousKeyedJoin
  ForeignKeyedJoin
  ForeignPipeline
}

///|
pub fn prepare_client_keyed_acquisition(
  prepared : PreparedClientProgram,
  stage : Int,
  source_index : Int,
  max_work : Int,
  join_step? : Int? = None,
) -> Result[ClientKeyedAcquisition, ClientKeyedAcquisitionIssue] {
  prepare_client_keyed_acquisition_owned(
    KeyedPure(prepared),
    prepared,
    stage,
    source_index,
    max_work,
    join_step,
  )
}

///|
pub fn prepare_client_effect_keyed_acquisition(
  prepared : PreparedClientEffectComputation,
  stage : Int,
  source_index : Int,
  max_work : Int,
  join_step? : Int? = None,
) -> Result[ClientKeyedAcquisition, ClientKeyedAcquisitionIssue] {
  prepare_client_keyed_acquisition_owned(
    KeyedEffect(prepared),
    client_effect_program_view(prepared),
    stage,
    source_index,
    max_work,
    join_step,
  )
}

///|
/// Select the initial single-keyed installed Host profile from the original
/// checked inventory. Absence is distinct from an unsupported keyed shape;
/// adapters must not interpret the latter as a source-free fallback.
pub fn select_client_single_keyed_acquisition(
  prepared : PreparedClientProgram,
) -> Result[ClientKeyedAcquisition?, ClientKeyedAcquisitionIssue] {
  let checked = @strategy.graph_program(prepared.graph)
  let count = @checked.source_execution_count(checked)
  if count > 1000000 {
    return Err(WorkLimit)
  }
  let mut selected : (Int, Int, Int)? = None
  for index in 0..<count {
    let check = @checked.source_execution_at(checked, index).unwrap()
    if @checked.source_execution_kind(check) is @checked.KeyedRequest(binding) {
      if selected is Some(_) {
        return Err(AmbiguousKeyedJoin)
      }
      let subject = @checked.source_execution_subject(check)
      selected = Some(
        (
          subject.stage,
          subject.input,
          @acquisition.keyed_join_step(binding.join),
        ),
      )
    }
  }
  guard selected is Some((stage, input, step)) else { return Ok(None) }
  let acquisition = match
    prepare_client_keyed_acquisition(
      prepared,
      stage,
      input,
      1000000,
      join_step=Some(step),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard client_keyed_direct_acquisition_coordinates(acquisition) is Some(_) else {
    return Err(ForeignPipeline)
  }
  Ok(Some(acquisition))
}

///|
fn prepare_client_keyed_acquisition_owned(
  retained : ClientKeyedProgramOwner,
  prepared : PreparedClientProgram,
  stage : Int,
  source_index : Int,
  max_work : Int,
  join_step : Int?,
) -> Result[ClientKeyedAcquisition, ClientKeyedAcquisitionIssue] {
  if max_work < 0 || source_index < 0 || (join_step is Some(step) && step < 0) {
    return Err(InvalidLimits)
  }
  let checked = @strategy.graph_program(prepared.graph)
  let identity = @checked.source_identity(checked)
  guard @context.program_identity_stage_at(identity, stage) is Some(_) else {
    return Err(MissingStage)
  }
  guard @context.program_identity_stage_requests(identity, stage)
    is Some(requests) else {
    return Err(MissingRequests)
  }
  guard @acquisition.pipeline_request_at(requests, source_index)
    is Some(@acquisition.Keyed(_, request)) else {
    return Err(MissingKeyedJoin)
  }
  let count = @checked.source_execution_count(checked)
  if count > max_work {
    return Err(WorkLimit)
  }
  let mut selected : (@checked.SourceExecution, @checked.KeyedExecution)? = None
  for index in 0..<count {
    let check = @checked.source_execution_at(checked, index).unwrap()
    let subject = @checked.source_execution_subject(check)
    if subject.stage == stage && subject.input == source_index {
      if @checked.source_execution_kind(check) is @checked.KeyedRequest(binding) {
        if join_step is Some(step) &&
          @acquisition.keyed_join_step(binding.join) != step {
          continue
        }
        if selected is Some(_) {
          // A caller must not silently select the first use of a shared input.
          // The optional step selects an exact original operation occurrence.
          return Err(AmbiguousKeyedJoin)
        }
        if !physical_equal(subject.owner, identity) ||
          binding.stage != stage ||
          @acquisition.keyed_join_input(binding.join) != source_index ||
          !physical_equal(
            @acquisition.keyed_join_request(binding.join),
            request,
          ) {
          return Err(ForeignKeyedJoin)
        }
        selected = Some((check, binding))
      }
    }
  }
  guard selected is Some((check, binding)) else { return Err(MissingKeyedJoin) }
  let facts = @acquisition.keyed_rows_facts(
    @acquisition.lookup_bounds_rows(binding.bounds),
  )
  guard @acquisition.keyed_facts_at(facts, binding.index) is Some(facts) &&
    physical_equal(@acquisition.keyed_source_join(facts), binding.join) else {
    return Err(ForeignKeyedJoin)
  }
  // Obtain the exact lowered owner from the existing physical graph. Task
  // splitting may change task ordinals, never the original Stage/step/port.
  guard @strategy.graph_stage_operation_task(
      prepared.graph,
      stage,
      @acquisition.keyed_join_step(binding.join),
    )
    is Some(task) &&
    @strategy.graph_task_owner(prepared.graph, task) is Some(owner) &&
    @checked.unit_pipeline(checked, stage) is Some(pipeline) &&
    physical_equal(@lower.pipeline(@lower.bound_preparation(owner)), pipeline) else {
    return Err(ForeignPipeline)
  }
  Ok({ program: retained, check, binding, facts, owner, })
}

///|
pub fn client_keyed_acquisition_owner(
  value : ClientKeyedAcquisition,
) -> @lower.BoundPrepared {
  value.owner
}

///|
pub fn client_keyed_acquisition_facts(
  value : ClientKeyedAcquisition,
) -> @acquisition.KeyedSourceFacts {
  value.facts
}

///|
pub fn client_keyed_acquisition_check(
  value : ClientKeyedAcquisition,
) -> @checked.SourceExecution {
  value.check
}

///|
pub fn client_keyed_acquisition_binding(
  value : ClientKeyedAcquisition,
) -> @checked.KeyedExecution {
  value.binding
}

///|
/// Coordinates belong to the original checked graph, not an adapter's stage
/// ordinal assumption. They select preparation only, never task completion.
pub fn client_keyed_acquisition_coordinates(
  value : ClientKeyedAcquisition,
) -> (Int, Int, Int)? {
  let prepared = match value.program {
    KeyedPure(prepared) => prepared
    KeyedEffect(prepared) => client_effect_program_view(prepared)
  }
  let stage = value.binding.stage
  let step = @acquisition.keyed_join_step(value.binding.join)
  guard @strategy.graph_stage_operation_task(prepared.graph, stage, step)
    is Some(task) &&
    @strategy.graph_task_owner(prepared.graph, task) is Some(owner) &&
    physical_equal(owner, value.owner) else {
    return None
  }
  Some((stage, task, step))
}

///|
/// Locate the actual Direct root of the initial single-keyed Host profile.
/// Input ordering is not an authority or task-selection rule.
pub fn client_keyed_direct_acquisition_coordinates(
  value : ClientKeyedAcquisition,
) -> (Int, Int, Int)? {
  guard value.program is KeyedPure(prepared) &&
    @strategy.graph_captured_prefix(prepared.graph) == 1 else {
    return None
  }
  let checked = @strategy.graph_program(prepared.graph)
  let mut selected : (Int, Int, Int)? = None
  let mut selections = 0
  let mut keyed = 0
  for index in 0..<@checked.source_execution_count(checked) {
    let check = @checked.source_execution_at(checked, index).unwrap()
    let subject = @checked.source_execution_subject(check)
    match @checked.source_execution_kind(check) {
      @checked.HostCombination => selections += 1
      @checked.CarrierResponse =>
        if subject.request is @acquisition.Direct(_, _) {
          if selected is Some(_) || subject.stage != value.binding.stage {
            return None
          }
          selected = Some((subject.stage, subject.input, 0))
        }
      @checked.KeyedRequest(_) => {
        if !physical_equal(check, value.check) {
          return None
        }
        keyed += 1
      }
      _ => ()
    }
  }
  if selections == 2 && keyed == 1 {
    selected
  } else {
    None
  }
}

///|
pub fn client_keyed_acquisition_source_evidence_facts(
  value : ClientKeyedAcquisition,
) -> @planning.QuerySourceEvidenceFacts? {
  @planning.keyed_source_evidence_facts(value.facts)
}

///|
pub fn client_keyed_acquisition_matches_program(
  value : ClientKeyedAcquisition,
  prepared : PreparedClientProgram,
) -> Bool {
  match value.program {
    KeyedPure(original) => physical_equal(original, prepared)
    KeyedEffect(_) => false
  }
}

///|
pub fn client_keyed_acquisition_matches_effect_program(
  value : ClientKeyedAcquisition,
  prepared : PreparedClientEffectComputation,
) -> Bool {
  match value.program {
    KeyedPure(_) => false
    KeyedEffect(original) => physical_equal(original, prepared)
  }
}

///|
/// The original captured left operation, borrowed through its common producer
/// port. This is neither a copied Relation nor an acquisition completion.
struct ClientKeyedLeftRead {
  acquisition : ClientKeyedAcquisition
  source : @query.CapturedInputSource?
  composed : ClientComposedKeyedOriginal?
  read : @execution.ProducerRead
  mut requests : Int64
  mut attempts : Int64
  mut request_bytes : Int64
  mut response_bytes : Int64
  mut decoded_bytes : Int64
  mut started_ms : Int64?
  mut observed_ms : Int64
  mut lookup_issue : ClientKeyedRequestIssue?
  mut assembly_started : Bool
}

///|
pub(all) enum ClientKeyedRequestIssue {
  ForeignLeft
  Capture(@query.CapturedSourceIssue)
  Read(@execution.ProducerReadIssue)
  Input(@query.KeyedInputRequestIssue)
  Request(@acquisition.KeyedRowRequestIssue)
  Wire(@acquisition.RequestWireIssue)
  LookupLimit(String)
  LookupIncomplete
  InvalidObservation
  Identity(@publication.AcquisitionRelationIssue)
  Assembly(String)
  Physical(@resources.LedgerIssue)
  Row(@execution.AdmittedOutputRowIssue)
  InputCapture(@execution.CaptureIssue)
}

///|
pub fn prepare_client_keyed_capture_left_read(
  acquisition : ClientKeyedAcquisition,
  source : @query.CapturedInputSource,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[ClientKeyedLeftRead, ClientKeyedRequestIssue] {
  let prepared = match acquisition.program {
    KeyedPure(value) => value
    KeyedEffect(value) => client_effect_program_view(value)
  }
  let identity = @checked.source_identity(
    @strategy.graph_program(prepared.graph),
  )
  if !@query.captured_source_matches(source, identity, acquisition.owner) {
    return Err(ForeignLeft)
  }
  let bound = match
    @query.bind_captured_source_operation(
      source,
      acquisition.owner,
      @acquisition.keyed_join_step(acquisition.binding.join),
      0,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  @execution.prepare_producer_read(
    acquisition.owner,
    bound,
    max_entries,
    max_name_bytes,
  )
  .map(read => {
    acquisition,
    source: Some(source),
    composed: None,
    read,
    requests: 0L,
    attempts: 0L,
    request_bytes: 0L,
    response_bytes: 0L,
    decoded_bytes: 0L,
    started_ms: None,
    observed_ms: 0L,
    lookup_issue: None,
    assembly_started: false,
  })
  .map_err(issue => Read(issue))
}

///|
pub fn client_keyed_left_read_rows(left : ClientKeyedLeftRead) -> Int? {
  if client_keyed_left_available(left) {
    Some(@execution.producer_read_row_count(left.read))
  } else {
    None
  }
}

///|
pub fn client_keyed_left_matches_acquisition(
  left : ClientKeyedLeftRead,
  acquisition : ClientKeyedAcquisition,
) -> Bool {
  physical_equal(left.acquisition, acquisition) &&
  client_keyed_left_available(left)
}

///|
/// A continuation of the existing bounded request cursor, retaining the exact
/// borrowed producer. It adds no scheduler, physical owner or success receipt.
struct ClientKeyedRequestPreparation {
  left : ClientKeyedLeftRead
  row : Int
  cursor : @acquisition.KeyedRowRequestCursor
  extraction_work : Int
}

///|
struct ClientKeyedRequest {
  left : ClientKeyedLeftRead
  request : @acquisition.KeyedRowRequest
  mut attempts : Int64
  mut io_complete : Bool
  row : Int
  work : Int
  mut assembly_accounting : ClientKeyedLookupInput?
}

///|
pub enum ClientKeyedRequestPoll {
  ClientKeyedRequestContinue(work~ : Int)
  ClientKeyedRequestComplete(ClientKeyedRequest, work~ : Int)
  ClientKeyedRequestFailed(ClientKeyedRequestIssue, work~ : Int)
}

///|
pub fn start_client_keyed_row_request(
  left : ClientKeyedLeftRead,
  row : Int,
  limits : @acquisition.RequestLimits,
) -> Result[ClientKeyedRequestPreparation, ClientKeyedRequestIssue] {
  @query.start_produced_keyed_request(
    left.acquisition.owner,
    left.acquisition.binding.join,
    left.read,
    row,
    limits,
  )
  .map(pair => {
    let (cursor, extraction_work) = pair
    { left, row, cursor, extraction_work, }
  })
  .map_err(issue => Input(issue))
}

///|
pub fn client_keyed_request_preparation_work(
  preparation : ClientKeyedRequestPreparation,
) -> Int {
  // The inner cursor's maximum is reduced by extraction_work before creation.
  // Their sum is bounded by the original RequestLimits.max_work.
  preparation.extraction_work +
  @acquisition.keyed_row_request_work(preparation.cursor)
}

///|
pub fn cancel_client_keyed_row_request(
  preparation : ClientKeyedRequestPreparation,
) -> Unit {
  @acquisition.cancel_keyed_row_request(preparation.cursor)
}

///|
pub fn advance_client_keyed_row_request(
  preparation : ClientKeyedRequestPreparation,
) -> ClientKeyedRequestPoll {
  if !client_keyed_left_available(preparation.left) {
    cancel_client_keyed_row_request(preparation)
    return ClientKeyedRequestFailed(
      ForeignLeft,
      work=client_keyed_request_preparation_work(preparation),
    )
  }
  let poll = @acquisition.advance_keyed_row_request(preparation.cursor)
  let work = client_keyed_request_preparation_work(preparation)
  match poll {
    KeyedRowRequestContinue => ClientKeyedRequestContinue(work~)
    KeyedRowRequestComplete(request) =>
      ClientKeyedRequestComplete(
        {
          left: preparation.left,
          request,
          attempts: 0L,
          io_complete: false,
          row: preparation.row,
          work,
          assembly_accounting: None,
        },
        work~,
      )
    KeyedRowRequestFailed(issue) =>
      ClientKeyedRequestFailed(Request(issue), work~)
  }
}

///|
pub fn client_keyed_request_matches_acquisition(
  request : ClientKeyedRequest,
  acquisition : ClientKeyedAcquisition,
) -> Bool {
  physical_equal(request.left.acquisition, acquisition) &&
  client_keyed_left_available(request.left) &&
  @execution.producer_read_matches_operation_input(
    request.left.read,
    acquisition.owner,
    @acquisition.keyed_join_step(acquisition.binding.join),
    0,
  ) &&
  physical_equal(
    @acquisition.keyed_row_request_owner(request.request),
    @acquisition.keyed_join_request(acquisition.binding.join),
  )
}

///|
pub fn client_keyed_request_value(
  request : ClientKeyedRequest,
  acquisition : ClientKeyedAcquisition,
) -> @acquisition.KeyedRowRequest? {
  if client_keyed_request_matches_acquisition(request, acquisition) {
    Some(request.request)
  } else {
    None
  }
}

///|
/// Encode only this original, still-live request. Capacity reservation and
/// current Source authorization remain the physical acquisition caller's job.
pub fn client_keyed_request_wire(
  request : ClientKeyedRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, ClientKeyedRequestIssue] {
  if !client_keyed_request_matches_acquisition(
      request,
      request.left.acquisition,
    ) {
    return Err(ForeignLeft)
  }
  @acquisition.keyed_row_request_wire(
    request.request,
    max_bytes,
    max_nodes,
    max_depth,
  ).map_err(issue => Wire(issue))
}

///|
/// Register the same selected keyed occurrence with the shared attempt owner.
/// The original keyed profile is retained as-is; a Direct evidence contract
/// is neither accepted nor synthesized. The callback observes physical
/// settlement of the exact attempt, not successful private row admission.
pub fn[A] register_client_keyed_acquisition(
  value : ClientKeyedAcquisition,
  nonce : String,
  transport_matches : (A) -> Bool,
) -> Result[
  @planning.QueryEvidenceRegistration[
    @acquisition.KeyedSourceFacts,
    @checked.KeyedExecution,
    A,
  ],
  @planning.QueryEvidenceCustodyIssue,
] {
  @planning.register_query_evidence_issuer(
    value.facts,
    value.binding,
    nonce,
    128,
    "keyed-source-issuer",
    transport_matches,
  )
}

///|
/// Reserve only the exact selected payload and original checked occurrence.
/// Attempt numbering, liveness and close remain in the shared issuer owner.
pub fn[A] reserve_client_keyed_acquisition_attempt(
  registration : @planning.QueryEvidenceRegistration[
    @acquisition.KeyedSourceFacts,
    @checked.KeyedExecution,
    A,
  ],
  choice : @planning.AcquisitionChoice[@checked.KeyedExecution],
  candidate : @planning.PreparedAcquisition[
    @checked.KeyedExecution,
    ClientKeyedAcquisition,
  ],
) -> Result[
  (
    ClientKeyedAcquisition,
    @planning.QueryEvidenceAttemptAuthority[
      @acquisition.KeyedSourceFacts,
      @checked.KeyedExecution,
      A,
    ],
  ),
  @planning.QueryEvidenceCustodyIssue,
] {
  @planning.reserve_selected_query_evidence_attempt(
    registration,
    choice,
    candidate,
    value => value.binding,
  )
}
