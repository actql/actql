///|
/// Ordinary acquired rows and keyed rows share the original RowRun custody.
/// Explicit Host limits create the existing physical Ledger, not a keyed
/// accounting owner. The installed adapter always receives the Run's ledger.
#export_name("clientProgramAcquisitionLedger")
pub fn client_program_acquisition_ledger(
  attempts : Int,
  holdings : Int,
  transfer_bytes : Int64,
  retained_bytes : Int64,
  execution_bytes : Int64,
  planning_work : Int?,
) -> Result[@resources.Ledger, @resources.LedgerIssue] {
  @resources.create_ledger({
    planning_work: planning_work.unwrap_or(0),
    attempts,
    holdings,
    transfer_bytes,
    retained_bytes,
    execution_bytes,
  })
}

///|
/// Both opaque domains are admitted by the trusted Host, not the Site driver.
#export_name("clientProgramRowReferenceIssuer")
pub fn client_program_row_reference_issuer(
  validate_resource : (String, String) -> Bool,
  validate_content : (String?, String) -> Bool,
  authorize : (String) -> Bool,
) -> @admitted.ReferenceIssuer {
  @admitted.bind_reference_issuer(
    (contract, wire) => {
      match contract.shape {
        @parameter_contract.ResourceRef(resource_kind~) =>
          validate_resource(resource_kind, wire)
        @parameter_contract.ContentRef(media_type~) =>
          validate_content(media_type, wire)
        _ => false
      }
    },
    authorize,
  )
}

///|
#export_name("clientProgramRowContentReferenceIssuer")
pub fn client_program_row_content_reference_issuer(
  resource : @admitted.ReferenceIssuer,
  content : @admitted.ReferenceIssuer,
) -> @admitted.ReferenceIssuer {
  @admitted.bind_reference_domains(resource, content)
}

///|
#export_name("clientProgramRowSourceCaptureBegin")
pub fn client_program_row_source_capture_begin(
  run : @client_row_source_host.RowRun,
) -> Result[Bool, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.begin_row_capture(run).map(_ => true)
}

///|
#export_name("clientProgramRowSourceCaptureAdvance")
pub fn client_program_row_source_capture_advance(
  run : @client_row_source_host.RowRun,
  quantum : Int,
) -> Result[(Bool, Int64), @client_row_source_host.RowHostIssue] {
  @client_row_source_host.advance_row_capture(run, quantum)
}

///|
#export_name("clientProgramRowSourceCaptureCleanup")
pub fn client_program_row_source_capture_cleanup(
  run : @client_row_source_host.RowRun,
) -> Result[Bool, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.cleanup_row_capture(run)
}

///|
#export_name("clientProgramRowSourceCaptureCleanupAdvance")
pub fn client_program_row_source_capture_cleanup_advance(
  run : @client_row_source_host.RowRun,
  quantum : Int,
) -> Result[Bool, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.advance_row_capture_cleanup(run, quantum)
}

///|
/// Installed Host requests borrow the original checked left operation. No
/// author/provider JSON can create this request or substitute its producer.
#export_name("clientProgramKeyedCaptureLeftRead")
pub fn client_program_keyed_capture_left_read(
  acquisition : @publication_host.ClientKeyedAcquisition,
  source : @query.CapturedInputSource,
) -> Result[
  @publication_host.ClientKeyedLeftRead,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.prepare_client_keyed_capture_left_read(
    acquisition, source, 100, 10000,
  )
}

///|
#export_name("clientProgramKeyedAcquisitionMatchesEffectProgram")
pub fn client_program_keyed_acquisition_matches_effect_program(
  acquisition : @publication_host.ClientKeyedAcquisition,
  prepared : @publication_host.PreparedClientEffectComputation,
) -> Bool {
  @publication_host.client_keyed_acquisition_matches_effect_program(
    acquisition, prepared,
  )
}

///|
#export_name("clientProgramKeyedLeftReadRows")
pub fn client_program_keyed_left_read_rows(
  left : @publication_host.ClientKeyedLeftRead,
) -> Int? {
  @publication_host.client_keyed_left_read_rows(left)
}

///|
#export_name("clientProgramKeyedFileLocatorStart")
pub fn client_program_keyed_file_locator_start(
  lookup : @publication_host.ClientKeyedLookupInput,
  request : @publication_host.ClientKeyedRequest,
  source : @query.CapturedInputSource,
  read : @execution.SuppliedRelationRead,
) -> Result[
  @publication_host.ClientKeyedFileLocator,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.start_client_keyed_file_locator(
    lookup, request, source, read,
  )
}

///|
#export_name("clientProgramRowSourceOriginalRead")
pub fn client_program_row_source_original_read(
  capture : @client_row_source_host.RowSourceCapture,
) -> @execution.SuppliedRelationRead? {
  @client_row_source_host.row_capture_original_read(capture)
}

///|
#export_name("clientProgramKeyedFileLocatorAdvance")
pub fn client_program_keyed_file_locator_advance(
  locator : @publication_host.ClientKeyedFileLocator,
) -> Result[String?, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.advance_client_keyed_file_locator(locator)
}

///|
#export_name("clientProgramKeyedFileLocatorCancel")
pub fn client_program_keyed_file_locator_cancel(
  locator : @publication_host.ClientKeyedFileLocator,
) -> Unit {
  @publication_host.cancel_client_keyed_file_locator(locator)
}

///|
#export_name("clientProgramKeyedRequestStart")
pub fn client_program_keyed_request_start(
  left : @publication_host.ClientKeyedLeftRead,
  row : Int,
  max_work : Int,
  max_text_bytes : Int,
) -> Result[
  @publication_host.ClientKeyedRequestPreparation,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.start_client_keyed_row_request(left, row, {
    max_work,
    max_pairs: 100,
    values: { max_nodes: 10000, max_depth: 100, max_text_bytes, },
  })
}

///|
#export_name("clientProgramKeyedLeftMatchesAcquisition")
pub fn client_program_keyed_left_matches_acquisition(
  left : @publication_host.ClientKeyedLeftRead,
  acquisition : @publication_host.ClientKeyedAcquisition,
) -> Bool {
  @publication_host.client_keyed_left_matches_acquisition(left, acquisition)
}

///|
#export_name("clientProgramKeyedRequestAdvance")
pub fn client_program_keyed_request_advance(
  preparation : @publication_host.ClientKeyedRequestPreparation,
) -> (
  Int,
  Int,
  @publication_host.ClientKeyedRequest?,
  @publication_host.ClientKeyedRequestIssue?,
) {
  match @publication_host.advance_client_keyed_row_request(preparation) {
    ClientKeyedRequestContinue(work~) => (0, work, None, None)
    ClientKeyedRequestComplete(request, work~) => (1, work, Some(request), None)
    ClientKeyedRequestFailed(issue, work~) => (2, work, None, Some(issue))
  }
}

///|
#export_name("clientProgramKeyedRequestCancel")
pub fn client_program_keyed_request_cancel(
  preparation : @publication_host.ClientKeyedRequestPreparation,
) -> Unit {
  @publication_host.cancel_client_keyed_row_request(preparation)
}

///|
#export_name("clientProgramKeyedRequestWork")
pub fn client_program_keyed_request_work(
  preparation : @publication_host.ClientKeyedRequestPreparation,
) -> Int {
  @publication_host.client_keyed_request_preparation_work(preparation)
}

///|
#export_name("clientProgramKeyedRequestWire")
pub fn client_program_keyed_request_wire(
  request : @publication_host.ClientKeyedRequest,
  max_bytes : Int,
) -> Result[String, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.client_keyed_request_wire(request, max_bytes, 10000, 100)
}

///|
#export_name("clientProgramKeyedRequestObserveAttempt")
pub fn client_program_keyed_request_observe_attempt(
  request : @publication_host.ClientKeyedRequest,
  bytes : Int64,
  now_ms : Int64,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.observe_client_keyed_request_attempt(request, bytes, now_ms)
}

///|
#export_name("clientProgramKeyedResponseObserve")
pub fn client_program_keyed_response_observe(
  request : @publication_host.ClientKeyedRequest,
  wire_bytes : Int64,
  decoded_bytes : Int64,
  now_ms : Int64,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.observe_client_keyed_response(
    request, wire_bytes, decoded_bytes, now_ms,
  )
}

///|
#export_name("clientProgramKeyedRequestFinishIO")
pub fn client_program_keyed_request_finish_io(
  request : @publication_host.ClientKeyedRequest,
  now_ms : Int64,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.finish_client_keyed_request_io(request, now_ms)
}

///|
#export_name("clientProgramKeyedLookupUsage")
pub fn client_program_keyed_lookup_usage(
  left : @publication_host.ClientKeyedLeftRead,
) -> Array[Int64] {
  let (requests, attempts, request_bytes, response_bytes, decoded_bytes, elapsed
  ) = @publication_host.client_keyed_lookup_usage(left)
  [requests, attempts, request_bytes, response_bytes, decoded_bytes, elapsed]
}

///|
#export_name("clientProgramKeyedRequestFailIO")
pub fn client_program_keyed_request_fail_io(
  request : @publication_host.ClientKeyedRequest,
) -> Unit {
  @publication_host.fail_client_keyed_request_io(request)
}

///|
#export_name("clientProgramKeyedRequestRemainingMs")
pub fn client_program_keyed_request_remaining_ms(
  request : @publication_host.ClientKeyedRequest,
  now_ms : Int64,
) -> Result[Int64, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.client_keyed_request_remaining_ms(request, now_ms)
}

///|
#export_name("clientProgramSelectSingleKeyedAcquisition")
pub fn client_program_select_single_keyed_acquisition(
  prepared : @publication_host.PreparedClientProgram,
) -> Result[
  @publication_host.ClientKeyedAcquisition?,
  @publication_host.ClientKeyedAcquisitionIssue,
] {
  @publication_host.select_client_single_keyed_acquisition(prepared)
}

///|
#export_name("clientProgramKeyedDirectAcquisitionCoordinates")
pub fn client_program_keyed_direct_acquisition_coordinates(
  acquisition : @publication_host.ClientKeyedAcquisition,
) -> (Int, Int, Int)? {
  @publication_host.client_keyed_direct_acquisition_coordinates(acquisition)
}

///|
#export_name("clientProgramKeyedLookupCapacity")
pub fn client_program_keyed_lookup_capacity(
  acquisition : @publication_host.ClientKeyedAcquisition,
  max_bytes : Int,
  max_work : Int,
) -> (Int64?, Int64?, Int64, Int64)? {
  @publication_host.client_keyed_lookup_capacity(
    acquisition, max_bytes, max_work,
  )
}

///|
#export_name("clientProgramKeyedAcquisitionInputCoordinates")
pub fn client_program_keyed_acquisition_input_coordinates(
  acquisition : @publication_host.ClientKeyedAcquisition,
) -> Array[Int]? {
  @publication_host.client_keyed_acquisition_coordinates(acquisition).map(coordinates => {
    let subject = @program_check.source_execution_subject(
      @publication_host.client_keyed_acquisition_check(acquisition),
    )
    [coordinates.0, subject.input, coordinates.1, coordinates.2]
  })
}

///|
#export_name("clientProgramKeyedRowCapacityTarget")
pub fn client_program_keyed_row_capacity_target(
  capacity : @client_row_source_host.RowKeyedCapacity,
  declaration : @client_row_source_host.RowDeclaration,
) -> Result[Array[String], @client_row_source_host.RowHostIssue] {
  @client_row_source_host.keyed_row_capacity_target(capacity, declaration).map(target => {
    let result = [target.0]
    result.append(target.1)
    result
  })
}

///|
#export_name("clientProgramPrepareKeyedCapturedLocalInstalledLedger")
pub fn client_program_prepare_keyed_captured_local_installed_ledger(
  prepared : @publication_host.PreparedClientProgram,
  direct : @client_local_host.ClientInstalledCaptureCapacity,
  keyed : @publication_host.ClientKeyedAcquisition,
  keyed_capacity : @client_row_source_host.RowKeyedCapacity,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  max_bytes : Int,
  max_work : Int,
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  captured_content : Bool?,
) -> @resources.Ledger? {
  @client_local_host.prepare_keyed_captured_local_installed_ledger(
    prepared,
    direct,
    keyed,
    keyed_capacity,
    transport_bytes,
    transport_execution_bytes,
    max_bytes,
    max_work,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    captured_content=captured_content.unwrap_or(false),
  )
}

///|
#export_name("clientProgramPrepareKeyedSerializationCapturedLedger")
pub fn client_program_prepare_keyed_serialization_captured_ledger(
  prepared : @publication_host.PreparedClientProgram,
  direct : @client_local_host.ClientInstalledCaptureCapacity,
  keyed : @publication_host.ClientKeyedAcquisition,
  keyed_capacity : @client_row_source_host.RowKeyedCapacity,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  max_bytes : Int,
  max_work : Int,
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  task : Int,
  step : Int,
  prefix_retained_bytes : Int64,
  prefix_execution_bytes : Int64,
  captured_content : Bool?,
) -> @resources.Ledger? {
  @client_local_host.prepare_keyed_captured_local_installed_ledger(
    prepared,
    direct,
    keyed,
    keyed_capacity,
    transport_bytes,
    transport_execution_bytes,
    max_bytes,
    max_work,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    serialization=Some(
      (task, step, prefix_retained_bytes, prefix_execution_bytes),
    ),
    captured_content=captured_content.unwrap_or(false),
  )
}

///|
/// Reserve the same declaration-derived acquisition Ledger for a checked
/// single keyed Model root. All Model/input/suffix capacity is derived by its
/// existing common owner, never accepted as a caller-authored byte estimate.
#export_name("clientProgramPrepareKeyedInferCapturedLedger")
pub fn client_program_prepare_keyed_infer_captured_ledger(
  prepared : @publication_host.PreparedClientProgram,
  occurrence : @publication_host.ClientInferOccurrence,
  direct : @client_local_host.ClientInstalledCaptureCapacity,
  keyed : @publication_host.ClientKeyedAcquisition,
  keyed_capacity : @client_row_source_host.RowKeyedCapacity,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  max_bytes : Int,
  max_work : Int,
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  captured_content : Bool?,
) -> @resources.Ledger? {
  guard @client_local_host.prepare_client_composed_infer_prefix(
      prepared,
      occurrence,
      installed_contracts,
      values_body,
      fragment_body~,
      ordered_body~,
    )
    is Some(prefix) else {
    return None
  }
  let suffix = if @publication_host.client_infer_occurrence_terminal(occurrence) {
    None
  } else {
    let prepared_suffix = @client_local_host.prepare_client_composed_infer_suffix(
      prepared,
      occurrence,
      installed_contracts,
      values_body,
      fragment_body~,
      ordered_body~,
    )
    guard prepared_suffix is Some(_) else { return None }
    prepared_suffix
  }
  guard @infer_host.keyed_root_capacity(
      occurrence,
      prefix,
      suffix,
      @infer_host.standard_limits(),
    )
    is Some(capacity) else {
    return None
  }
  let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
    occurrence,
  )
  @client_local_host.prepare_keyed_captured_local_installed_ledger(
    prepared,
    direct,
    keyed,
    keyed_capacity,
    transport_bytes,
    transport_execution_bytes,
    max_bytes,
    max_work,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    infer=Some(
      (
        task,
        step,
        @execution.execution_capacity_retained_bytes(capacity),
        @execution.execution_capacity_execution_bytes(capacity),
      ),
    ),
    captured_content=captured_content.unwrap_or(false),
  )
}

///|
#export_name("clientProgramKeyedRowPrepareCapacity")
pub fn client_program_keyed_row_prepare_capacity(
  acquisition : @publication_host.ClientKeyedAcquisition,
  declaration : @client_row_source_host.RowDeclaration,
  max_page_bytes : Int,
  max_text_bytes : Int,
  max_work : Int,
) -> Result[
  @client_row_source_host.RowKeyedCapacity,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.prepare_keyed_row_capacity(
    @publication_host.client_keyed_acquisition_owner(acquisition),
    @publication_host.client_keyed_acquisition_facts(acquisition),
    declaration,
    @client_local_host.installed_keyed_row_limits(
      max_page_bytes, max_text_bytes, max_work,
    ),
  )
}

///|
#export_name("clientProgramKeyedRowCapacityBytes")
pub fn client_program_keyed_row_capacity_bytes(
  capacity : @client_row_source_host.RowKeyedCapacity,
) -> (Int64, Int64) {
  @client_row_source_host.keyed_row_capacity_bytes(capacity)
}

///|
#export_name("clientProgramKeyedRowPrepareAcquisition")
pub fn client_program_keyed_row_prepare_acquisition(
  acquisition : @publication_host.ClientKeyedAcquisition,
  request : @publication_host.ClientKeyedRequest,
  declaration : @client_row_source_host.RowDeclaration,
  max_page_bytes : Int,
  max_text_bytes : Int,
  max_work : Int,
) -> Result[
  @client_row_source_host.RowKeyedAcquisition,
  @client_row_source_host.RowHostIssue,
] {
  guard @publication_host.client_keyed_request_value(request, acquisition)
    is Some(value) else {
    return Err(InvalidState)
  }
  @client_row_source_host.prepare_keyed_row_acquisition(
    @publication_host.client_keyed_acquisition_owner(acquisition),
    @publication_host.client_keyed_acquisition_facts(acquisition),
    value,
    declaration,
    @client_local_host.installed_keyed_row_limits(
      max_page_bytes, max_text_bytes, max_work,
    ),
    input_available=Some(() => {
      @publication_host.client_keyed_request_matches_acquisition(
        request, acquisition,
      )
    }),
  )
}

///|
#export_name("clientProgramKeyedRowStartAccounted")
pub fn client_program_keyed_row_start_accounted(
  acquisition : @client_row_source_host.RowKeyedAcquisition,
  nonce : String,
  verify : (@client_row_source_host.RowAttempt) -> Bool,
  ledger : @resources.Ledger,
  transfer_bytes : Int64,
  execution_scratch : Int64,
  cleanup_confirmed : (@client_row_source_host.RowAttempt) -> Bool,
) -> Result[
  @client_row_source_host.RowRun,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.start_accounted_keyed_row_acquisition(
    acquisition, nonce, verify, ledger, transfer_bytes, execution_scratch, cleanup_confirmed,
  )
}

///|
#export_name("clientProgramKeyedRowTarget")
pub fn client_program_keyed_row_target(
  acquisition : @client_row_source_host.RowKeyedAcquisition,
) -> Result[Array[String], @client_row_source_host.RowHostIssue] {
  @client_row_source_host.keyed_row_acquisition_target(acquisition).map(target => {
    [target.0, ..target.1]
  })
}

///|
#export_name("clientProgramKeyedRowBegin")
pub fn client_program_keyed_row_begin(
  run : @client_row_source_host.RowRun,
  issuer : @admitted.ReferenceIssuer?,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.begin_keyed_row_run(run, reference_issuer=issuer)
}

///|
#export_name("clientProgramKeyedRowBeginPage")
pub fn client_program_keyed_row_begin_page(
  run : @client_row_source_host.RowRun,
  body : Bytes,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.begin_row_run_keyed_page(run, body)
}

///|
#export_name("clientProgramKeyedRowBeginChargedPage")
pub fn client_program_keyed_row_begin_charged_page(
  run : @client_row_source_host.RowRun,
  charge : @client_row_source_host.RowPageCharge,
  body : Bytes,
) -> Result[Unit, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.begin_charged_row_run_keyed_page(run, charge, body)
}

///|
#export_name("clientProgramKeyedRowAdvancePage")
pub fn client_program_keyed_row_advance_page(
  run : @client_row_source_host.RowRun,
  quantum : Int,
) -> Result[Array[Int], @client_row_source_host.RowHostIssue] {
  @client_row_source_host.advance_row_run_keyed_page(run, quantum).map(poll => {
    match poll {
      KeyedPageContinue(work~) => [0, 0, work]
      KeyedPageComplete(rows~, work~) => [1, rows, work]
    }
  })
}

///|
#export_name("clientProgramKeyedRowRetain")
pub fn client_program_keyed_row_retain(
  run : @client_row_source_host.RowRun,
) -> Result[
  @client_row_source_host.RowKeyedSourceCapture,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.retain_keyed_row_run(run)
}

///|
#export_name("clientProgramKeyedRowCaptureRead")
pub fn client_program_keyed_row_capture_read(
  capture : @client_row_source_host.RowKeyedSourceCapture,
) -> Result[
  @execution.SuppliedRelationRead,
  @client_row_source_host.RowHostIssue,
] {
  @client_row_source_host.keyed_row_capture_read(capture)
}

///|
#export_name("clientProgramKeyedRowCaptureIdentity")
pub fn client_program_keyed_row_capture_identity(
  capture : @client_row_source_host.RowKeyedSourceCapture,
) -> Result[String, @client_row_source_host.RowHostIssue] {
  @client_row_source_host.keyed_row_capture_identity(capture).map(identity => {
    @execution.row_wire_cid(identity)
  })
}

///|
#export_name("clientProgramKeyedLookupStart")
pub fn client_program_keyed_lookup_start(
  left : @publication_host.ClientKeyedLeftRead,
  ledger : @resources.Ledger,
  max_bytes : Int,
  max_work : Int,
) -> Result[
  @publication_host.ClientKeyedLookupInput,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.start_client_keyed_lookup_input(
    left, ledger, max_bytes, max_work,
  )
}

///|
#export_name("clientProgramKeyedLookupFind")
pub fn client_program_keyed_lookup_find(
  lookup : @publication_host.ClientKeyedLookupInput,
  request : @publication_host.ClientKeyedRequest,
) -> Result[Int, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.find_client_keyed_lookup_response(lookup, request)
}

///|
/// Prepare the original complete request inventory before any physical send.
/// These ports retain the existing lookup owner, work and reservation.
#export_name("clientProgramKeyedLookupRequestPlanStart")
pub fn client_program_keyed_lookup_request_plan_start(
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.start_client_keyed_lookup_request_plan(lookup)
}

///|
#export_name("clientProgramKeyedLookupRequestPlanRetain")
pub fn client_program_keyed_lookup_request_plan_retain(
  lookup : @publication_host.ClientKeyedLookupInput,
  request : @publication_host.ClientKeyedRequest,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.retain_client_keyed_lookup_planned_request(lookup, request)
}

///|
#export_name("clientProgramKeyedLookupRequestPlanFinish")
pub fn client_program_keyed_lookup_request_plan_finish(
  lookup : @publication_host.ClientKeyedLookupInput,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.finish_client_keyed_capture_request_plan(
    lookup, max_bytes, max_nodes, max_depth,
  )
}

///|
/// Borrow the original row already selected by the SAME frozen schedule.
/// This projects control DATA only; Source permission still precedes IO.
#export_name("clientProgramKeyedLookupNextPlannedRow")
pub fn client_program_keyed_lookup_next_planned_row(
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Result[Int, @publication_host.ClientKeyedRequestIssue] {
  match @publication_host.client_keyed_lookup_next_planned_row(lookup) {
    Some(row) => Ok(row)
    None => Err(@publication_host.Assembly("unavailable_planned_request"))
  }
}

///|
/// Borrow the same prepared occurrence, without another request cursor.
#export_name("clientProgramKeyedLookupPlannedRequest")
pub fn client_program_keyed_lookup_planned_request(
  lookup : @publication_host.ClientKeyedLookupInput,
  row : Int,
) -> Result[
  @publication_host.ClientKeyedRequest,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.client_keyed_lookup_planned_request(lookup, row)
}

///|
#export_name("clientProgramKeyedLookupRequestStart")
pub fn client_program_keyed_lookup_request_start(
  lookup : @publication_host.ClientKeyedLookupInput,
  row : Int,
) -> Result[
  @publication_host.ClientKeyedRequestPreparation,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.start_client_keyed_lookup_request(lookup, row)
}

///|
#export_name("clientProgramKeyedLookupChargeVerification")
pub fn client_program_keyed_lookup_charge_verification(
  lookup : @publication_host.ClientKeyedLookupInput,
  request : @publication_host.ClientKeyedRequest,
  bytes : Int,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.charge_client_keyed_lookup_verification(
    lookup, request, bytes,
  )
}

///|
#export_name("clientProgramKeyedLookupRequestAdvance")
pub fn client_program_keyed_lookup_request_advance(
  lookup : @publication_host.ClientKeyedLookupInput,
  preparation : @publication_host.ClientKeyedRequestPreparation,
) -> (
  Int,
  Int,
  @publication_host.ClientKeyedRequest?,
  @publication_host.ClientKeyedRequestIssue?,
) {
  match
    @publication_host.advance_client_keyed_lookup_request(lookup, preparation) {
    ClientKeyedRequestContinue(work~) => (0, work, None, None)
    ClientKeyedRequestComplete(request, work~) => (1, work, Some(request), None)
    ClientKeyedRequestFailed(issue, work~) => (2, work, None, Some(issue))
  }
}

///|
#export_name("clientProgramKeyedLookupReuse")
pub fn client_program_keyed_lookup_reuse(
  lookup : @publication_host.ClientKeyedLookupInput,
  request : @publication_host.ClientKeyedRequest,
  index : Int,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.reuse_client_keyed_lookup_response(lookup, request, index)
}

///|
/// A structurally compatible right port is insufficient: the physical RowRun
/// must have retained the exact original opaque Request being assembled.
#export_name("clientProgramKeyedLookupAcceptCapture")
pub fn client_program_keyed_lookup_accept_capture(
  lookup : @publication_host.ClientKeyedLookupInput,
  acquisition : @publication_host.ClientKeyedAcquisition,
  request : @publication_host.ClientKeyedRequest,
  capture : @client_row_source_host.RowKeyedSourceCapture,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  guard @publication_host.client_keyed_request_value(request, acquisition)
    is Some(value) &&
    @client_row_source_host.keyed_row_capture_matches_request(capture, value) else {
    return Err(Assembly("foreign_capture"))
  }
  let read = match @client_row_source_host.keyed_row_capture_read(capture) {
    Ok(value) => value
    Err(_) => return Err(Assembly("closed_capture"))
  }
  @publication_host.begin_client_keyed_lookup_response(
    lookup,
    request,
    read,
    capture=Some(capture),
  )
}

///|
#export_name("clientProgramKeyedLookupAdvance")
pub fn client_program_keyed_lookup_advance(
  lookup : @publication_host.ClientKeyedLookupInput,
  quantum : Int,
) -> Result[Bool, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.advance_client_keyed_lookup_input(lookup, quantum)
}

///|
#export_name("clientProgramKeyedLookupRead")
pub fn client_program_keyed_lookup_read(
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Result[
  @execution.SuppliedRelationRead,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.finish_client_keyed_lookup_input(lookup)
}

///|
/// Retain the original right identity/body before its first Model read.
/// This is not a completed attempt receipt or permission to publish.
#export_name("clientProgramKeyedLookupPublicationInput")
pub fn client_program_keyed_lookup_publication_input(
  lookup : @publication_host.ClientKeyedLookupInput,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @execution.SuppliedRelationRead,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.finish_client_keyed_lookup_publication_input(
    lookup,
    max_bytes,
    max_nodes,
    max_depth,
    retain_body=true,
  )
}

///|
#export_name("clientProgramKeyedLookupIdentity")
pub fn client_program_keyed_lookup_identity(
  lookup : @publication_host.ClientKeyedLookupInput,
) -> String? {
  @publication_host.client_keyed_lookup_input_identity(lookup)
}

///|
#export_name("clientProgramKeyedLookupWork")
pub fn client_program_keyed_lookup_work(
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Int64 {
  @publication_host.client_keyed_lookup_input_work(lookup)
}

///|
#export_name("clientProgramKeyedLookupIssueObservation")
pub fn client_program_keyed_lookup_issue_observation(
  lookup : @publication_host.ClientKeyedLookupInput,
  authority_scope_cid : String,
  observed_at : String,
) -> Result[
  @publication_host.ClientKeyedLookupObservation,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.issue_client_keyed_lookup_observation(
    lookup, authority_scope_cid, observed_at,
  )
}

///|
#export_name("clientProgramKeyedLookupObservationWires")
pub fn client_program_keyed_lookup_observation_wires(
  value : @publication_host.ClientKeyedLookupObservation,
) -> (String, String)? {
  @publication_host.client_keyed_lookup_observation_wires(value)
}

///|
#export_name("clientProgramKeyedLookupCleanup")
pub fn client_program_keyed_lookup_cleanup(
  lookup : @publication_host.ClientKeyedLookupInput,
  quantum : Int,
) -> Result[Bool, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.cleanup_client_keyed_lookup_input(lookup, quantum)
}

///|
#export_name("clientProgramIssueCompiledKeyedTaskInvocation")
pub fn client_program_issue_compiled_keyed_task_invocation(
  run : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  capture : @query.CapturedInputSource,
  identity : @query.CapturedSourceRelationIdentity,
  requirement : @planning.QueryRequirement,
  source_evidence_wire : String,
  input_logical_wire : String,
  keyed : @publication_host.ClientKeyedLookupObservation,
  authority_scope_cid : String,
  data_policy_cid : String,
  capture_started_at : String,
  capture_completed_at : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (@publication.RunEvidenceValue, @publication.PublicationContract),
  @publication.RunEvidenceValueIssue,
] {
  @publication_host.issue_client_compiled_keyed_task_invocation(
    run, definition, capture, identity, requirement, source_evidence_wire, input_logical_wire,
    keyed, authority_scope_cid, data_policy_cid, capture_started_at, capture_completed_at,
    max_wire_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramKeyedLookupStop")
pub fn client_program_keyed_lookup_stop(
  lookup : @publication_host.ClientKeyedLookupInput,
) -> Unit {
  @publication_host.stop_client_keyed_lookup_input(lookup)
}

///|
#export_name("clientProgramKeyedLookupJoinPrepare")
pub fn client_program_keyed_lookup_join_prepare(
  prepared : @publication_host.PreparedClientProgram,
  lookup : @publication_host.ClientKeyedLookupInput,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
) -> @client_local_host.ClientKeyedJoinPreparation? {
  @client_local_host.prepare_client_keyed_local_join(
    prepared, lookup, sequence_contracts, values, fragment, ordered,
  )
}

///|
/// The normal checked task graph borrows the original acquisitions. This
/// opens no physical task, issues no Source receipt and grants no publication.
#export_name("clientProgramKeyedLookupOpenDag")
pub fn client_program_keyed_lookup_open_dag(
  prepared : @publication_host.PreparedClientProgram,
  lookup : @publication_host.ClientKeyedLookupInput,
  ledger : @resources.Ledger,
) -> Result[@strategy.CapturedDAG, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.open_client_keyed_lookup_dag(prepared, lookup, ledger)
}

///|
#export_name("clientProgramKeyedLookupOpenLocalHost")
pub fn client_program_keyed_lookup_open_local_host(
  prepared : @publication_host.PreparedClientProgram,
  lookup : @publication_host.ClientKeyedLookupInput,
  ledger : @resources.Ledger,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  retained_output : Bool,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  @client_local_host.open_client_keyed_local_host(
    prepared,
    lookup,
    ledger,
    sequence_contracts,
    values,
    fragment,
    ordered,
    retained_output~,
    provider_factory=installed_client_family_providers,
  )
}

///|
#export_name("clientProgramKeyedLookupTaskLayout")
pub fn client_program_keyed_lookup_task_layout(
  prepared : @publication_host.PreparedClientProgram,
) -> Array[(Int, Int?, Int?, Int?)] {
  let graph = @publication_host.prepared_client_graph(prepared)
  Array::makei(@strategy.graph_task_count(graph), task => {
    (
      task,
      @strategy.graph_task_selected_step(graph, task),
      @strategy.graph_task_prefix_end(graph, task),
      @strategy.graph_task_input_count(graph, task),
    )
  })
}

///|
#export_name("clientProgramKeyedLookupDagInputs")
pub fn client_program_keyed_lookup_dag_inputs(
  run : @strategy.CapturedDAG,
  task : Int,
) -> Result[
  (@execution.ProducerRead, @execution.SuppliedRelationRead),
  @strategy.RunIssue,
] {
  let left = match @strategy.captured_task_input(run, task, 100, 10000) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  @strategy.captured_supplied_task_input(run, task, input_index=1).map(right => {
    (left, right)
  })
}

///|
#export_name("clientProgramKeyedLookupDagStop")
pub fn client_program_keyed_lookup_dag_stop(
  run : @strategy.CapturedDAG,
) -> Unit {
  @strategy.stop_captured_dag(run)
}

///|
#export_name("clientProgramEffectKeyedLookupJoinPrepare")
pub fn client_program_effect_keyed_lookup_join_prepare(
  prepared : @publication_host.PreparedClientEffectComputation,
  lookup : @publication_host.ClientKeyedLookupInput,
  sequence_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
) -> @client_local_host.ClientKeyedJoinPreparation? {
  @client_local_host.prepare_client_effect_keyed_local_join(
    prepared, lookup, sequence_contracts, values, fragment, ordered,
  )
}

///|
#export_name("clientProgramKeyedLookupJoinCapacity")
pub fn client_program_keyed_lookup_join_capacity(
  prepared : @client_local_host.ClientKeyedJoinPreparation,
) -> Array[Int64] {
  let capacity = @client_local_host.client_keyed_local_join_capacity(prepared)
  [
    @execution.execution_capacity_retained_bytes(capacity),
    @execution.execution_capacity_execution_bytes(capacity),
  ]
}

///|
/// Private installed Host handoff. The normal dispatcher reserves the above
/// capacity and retains upstream captures; this is not public Run admission.
#export_name("clientProgramKeyedLookupJoinStart")
pub fn client_program_keyed_lookup_join_start(
  prepared : @client_local_host.ClientKeyedJoinPreparation,
) -> Result[
  @local.ManagedProviderExecution,
  @client_local_host.ClientQueryResidualIssue,
] {
  @client_local_host.start_client_keyed_local_join(prepared)
}

///|
#export_name("clientProgramKeyedLookupDagJoinStart")
pub fn client_program_keyed_lookup_dag_join_start(
  prepared : @client_local_host.ClientKeyedJoinPreparation,
  run : @strategy.CapturedDAG,
) -> Result[
  @local.ManagedProviderExecution,
  @client_local_host.ClientQueryResidualIssue,
] {
  @client_local_host.start_client_keyed_local_join(prepared, run=Some(run))
}

///|
#export_name("clientProgramKeyedLookupJoinAdvance")
pub fn client_program_keyed_lookup_join_advance(
  execution : @local.ManagedProviderExecution,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  @local.advance_managed_provider(execution, quantum)
}

///|
#export_name("clientProgramKeyedLookupJoinCancel")
pub fn client_program_keyed_lookup_join_cancel(
  execution : @local.ManagedProviderExecution,
) -> Bool {
  @local.cancel_managed_provider(execution)
}

///|
#export_name("clientProgramKeyedLookupJoinCleanup")
pub fn client_program_keyed_lookup_join_cleanup(
  execution : @local.ManagedProviderExecution,
) -> Result[Bool, @connector.FixedComputeIssue] {
  @local.cleanup_managed_provider(execution)
}

///|
#export_name("clientProgramKeyedLookupJoinWork")
pub fn client_program_keyed_lookup_join_work(
  execution : @local.ManagedProviderExecution,
) -> Result[Int64, @local.ManagedProviderWorkIssue] {
  @local.managed_provider_cumulative_work(execution)
}

///|
/// Common ordered Relation export of a real provider completion. This is
/// private input material, not a fabricated Named Result or Source receipt.
#export_name("clientProgramKeyedJoinOutputExportBegin")
pub fn client_program_keyed_join_output_export_begin(
  output : @execution.CompletedOutput,
) -> Result[@execution.CompletedOutputExport, @execution.CompletedExportIssue] {
  let values : @execution.ValueLimits = {
    max_nodes: 20000,
    max_text_bytes: 500000,
    max_depth: 100,
    max_work: 20000000,
  }
  let wire : @execution.RowWireLimits = {
    max_columns: 100,
    max_order_work: 1000000,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 64,
  }
  @execution.prepare_completed_relation_export(
    output,
    100,
    values,
    wire,
    wire,
    { max_fields: 100, max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    65536,
  )
}

///|
#export_name("clientProgramKeyedJoinOutputExportNext")
pub fn client_program_keyed_join_output_export_next(
  stream : @execution.CompletedOutputExport,
) -> Result[String?, @execution.CompletedExportIssue] {
  @execution.next_completed_output_export_canonical_row(
    stream, 100000, 100, 1000000,
  ).map(row => row.map(value => value.1))
}

///|
#export_name("clientProgramKeyedJoinOutputExportFinish")
pub fn client_program_keyed_join_output_export_finish(
  stream : @execution.CompletedOutputExport,
) -> Result[(Array[String], String, String), @execution.CompletedExportIssue] {
  @execution.finish_completed_relation_export(stream).map(value => {
    let receipt = value.0
    (
      @execution.completed_relation_export_field_names(receipt),
      @execution.logical_relation_cid(
        @execution.completed_relation_export_identity(receipt),
      ),
      @execution.relation_schema_cid(
        @execution.completed_relation_export_schema_identity(receipt),
      ),
    )
  })
}

///|
#export_name("clientProgramKeyedJoinOutputExportClose")
pub fn client_program_keyed_join_output_export_close(
  stream : @execution.CompletedOutputExport,
) -> Unit {
  @execution.cancel_completed_output_export(stream)
}
