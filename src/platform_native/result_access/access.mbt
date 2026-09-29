///|
pub(all) enum NativeResultAccessIssue {
  InvalidRequest
  InvalidProgress
  AccessDenied
  ResultUnavailable
  Store(@store.NativePublicationStoreIssue)
  Publication(@publication.DeliveryIssuanceIssue)
}

///|
pub(all) struct NativeResultAccessRequest {
  namespace_id : String
  authority_scope_cid : String
  run_definition_cid : String
  principal_id : String
  purpose : String
  result_name : String
  format : String
  attempt_id : String
}

///|
pub(all) struct NativeResultReadFacts {
  request : NativeResultAccessRequest
  public_index_entry_cid : String
  result_manifest_cid : String
  result_artifact_cid : String
  result_definition_cid : String
  material_generation_cid : String
  observed_at : String
}

///|
pub(all) struct NativeResultReadAdmission {
  authorization_context_cid : String
  data_ceiling_cid : String
  egress_admission_cid : String
  expires_at : String
  max_bytes : Int
  max_uses : Int
}

///|
pub(all) struct NativeResultDeliveryAuthorization {
  request : NativeResultAccessRequest
  public_index_entry_cid : String
  result_manifest_cid : String
  result_read_grant_cid : String
  stage : String
  observed_at : String
}

///|
struct NativeResultAccessAuthority {
  authorize_request : (NativeResultAccessRequest) -> Bool
  admit_read : (NativeResultReadFacts) -> NativeResultReadAdmission?
  authorize_delivery : (NativeResultDeliveryAuthorization) -> Bool
}

///|
struct NativeResultAccessService {
  store : @store.Store
  authority : NativeResultAccessAuthority
  now : () -> String
  max_wire_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_row_bytes : Int
  input_chunk_bytes : Int
}

///|
struct NativeResultAccessSession {
  service : NativeResultAccessService
  request : NativeResultAccessRequest
  resolved : @store.NativeCommittedResult
  grant : @publication.PublicationContract
  clock_contract_cid : String
  delivery : @store.ResultDelivery
  mut closed : Bool
}

///|
fn valid_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn valid_request(request : NativeResultAccessRequest) -> Bool {
  !request.namespace_id.is_empty() &&
  valid_cid(request.authority_scope_cid) &&
  valid_cid(request.run_definition_cid) &&
  !request.principal_id.is_empty() &&
  !request.purpose.is_empty() &&
  !request.result_name.is_empty() &&
  (
    request.format == "json" ||
    request.format == "jsonl" ||
    request.format == "csv"
  ) &&
  !request.attempt_id.is_empty()
}

///|
fn[T] store_result(
  result : Result[T, @store.NativePublicationStoreIssue],
) -> Result[T, NativeResultAccessIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Store(issue))
  }
}

///|
fn[T] publication_result(
  result : Result[T, @publication.DeliveryIssuanceIssue],
) -> Result[T, NativeResultAccessIssue] {
  match result {
    Ok(value) => Ok(value)
    Err(issue) => Err(Publication(issue))
  }
}

///|
fn progress_result(
  result : Result[Unit, @publication.ResultAccessProgressIssue],
) -> Result[Unit, NativeResultAccessIssue] {
  match result {
    Ok(_) => Ok(())
    Err(_) => Err(InvalidProgress)
  }
}

///|
pub fn install_native_result_access_authority(
  authorize_request : (NativeResultAccessRequest) -> Bool,
  admit_read : (NativeResultReadFacts) -> NativeResultReadAdmission?,
  authorize_delivery : (NativeResultDeliveryAuthorization) -> Bool,
) -> NativeResultAccessAuthority {
  { authorize_request, admit_read, authorize_delivery, }
}

///|
pub fn install_native_result_access_service(
  store : @store.Store,
  authority : NativeResultAccessAuthority,
  now : () -> String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_row_bytes : Int,
  input_chunk_bytes : Int,
) -> Result[NativeResultAccessService, NativeResultAccessIssue] {
  if max_wire_bytes < 1 ||
    max_nodes < 1 ||
    max_depth < 1 ||
    max_row_bytes < 1 ||
    input_chunk_bytes < 1 {
    return Err(InvalidRequest)
  }
  Ok({
    store,
    authority,
    now,
    max_wire_bytes,
    max_nodes,
    max_depth,
    max_row_bytes,
    input_chunk_bytes,
  })
}

///|
fn observed_at(
  service : NativeResultAccessService,
) -> Result[String, NativeResultAccessIssue] {
  let value = (service.now)()
  if value.is_empty() {
    Err(InvalidRequest)
  } else {
    Ok(value)
  }
}

///|
pub fn open_native_result_access(
  service : NativeResultAccessService,
  request : NativeResultAccessRequest,
) -> Result[NativeResultAccessSession, NativeResultAccessIssue] {
  if !valid_request(request) {
    return Err(InvalidRequest)
  }
  let progress = @publication.begin_result_access_progress()
  if @publication.result_access_progress_action(progress) !=
    @publication.ResultAccessAuthorizeRequest {
    return Err(InvalidProgress)
  }
  let authorized = (service.authority.authorize_request)(request)
  match
    progress_result(
      @publication.record_result_access_request_authorization(
        progress, authorized,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !authorized {
    return Err(AccessDenied)
  }
  if @publication.result_access_progress_action(progress) !=
    @publication.ResultAccessResolveCommittedResult {
    return Err(InvalidProgress)
  }
  let resolved = match
    store_result(
      service.store.resolve_committed_result(
        request.namespace_id,
        request.authority_scope_cid,
        request.run_definition_cid,
        request.result_name,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
      ),
    ) {
    Ok(Some(value)) => value
    Ok(None) => {
      ignore(@publication.record_result_access_resolution(progress, false))
      return Err(AccessDenied)
    }
    Err(issue) => {
      ignore(@publication.record_result_access_resolution(progress, false))
      return Err(issue)
    }
  }
  match
    progress_result(
      @publication.record_result_access_resolution(progress, true),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if @publication.result_access_progress_action(progress) !=
    @publication.ResultAccessCheckInitialAvailability {
    return Err(InvalidProgress)
  }
  let initial_time = match observed_at(service) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let clock_contract_cid = match
    publication_result(
      @publication.result_retention_clock_contract_cid(resolved.retention),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    store_result(
      service.store.observe_trusted_clock(clock_contract_cid, initial_time),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let availability = match
    publication_result(
      @publication.result_read_availability(
        resolved.result_manifest,
        request.result_name,
        resolved.retention,
        initial_time,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let available = availability == "available"
  match
    progress_result(
      @publication.record_result_access_initial_availability(
        progress, available,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if !available {
    return Err(ResultUnavailable)
  }
  if @publication.result_access_progress_action(progress) !=
    @publication.ResultAccessAdmitRead {
    return Err(InvalidProgress)
  }
  let facts : NativeResultReadFacts = {
    request,
    public_index_entry_cid: @publication.publication_contract_identity(
      resolved.public_index_entry,
    ),
    result_manifest_cid: @publication.publication_contract_identity(
      resolved.result_manifest,
    ),
    result_artifact_cid: resolved.read.result_artifact_cid,
    result_definition_cid: resolved.read.result_definition_cid,
    material_generation_cid: resolved.read.material_generation_cid,
    observed_at: initial_time,
  }
  let admission = (service.authority.admit_read)(facts)
  match
    progress_result(
      @publication.record_result_access_read_admission(
        progress,
        admission is Some(_),
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard admission is Some(admission) else { return Err(AccessDenied) }
  if @publication.result_access_progress_action(progress) !=
    @publication.ResultAccessIssueGrant {
    return Err(InvalidProgress)
  }
  let grant = match
    publication_result(
      @publication.issue_result_read_grant(
        resolved.public_index_entry,
        resolved.result_manifest,
        [request.result_name],
        [request.format],
        request.principal_id,
        request.purpose,
        admission.data_ceiling_cid,
        admission.max_bytes,
        admission.max_uses,
        admission.expires_at,
        admission.authorization_context_cid,
        admission.egress_admission_cid,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
      ),
    ) {
    Ok(value) => value
    Err(issue) => {
      ignore(@publication.record_result_access_grant(progress, false))
      return Err(issue)
    }
  }
  match
    progress_result(@publication.record_result_access_grant(progress, true)) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if @publication.result_access_progress_action(progress) !=
    @publication.ResultAccessStartDelivery {
    return Err(InvalidProgress)
  }
  let schema_wire = match
    store_result(
      service.store.read_result_schema(resolved.read.result_schema_cid),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let delivery = match
    store_result(
      service.store.begin_result_delivery(
        resolved.public_index_entry,
        resolved.result_manifest,
        grant,
        resolved.retention,
        resolved.binding,
        resolved.read.material_generation_cid,
        request.result_name,
        request.format,
        request.attempt_id,
        initial_time,
        schema_wire,
        resolved.read.result_fields,
        service.input_chunk_bytes,
        service.max_row_bytes,
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
        admission.max_bytes.to_int64(),
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    service,
    request,
    resolved,
    grant,
    clock_contract_cid,
    delivery,
    closed: false,
  })
}

///|
fn NativeResultAccessSession::authorize_stage(
  self : NativeResultAccessSession,
  stage : String,
) -> Result[String, NativeResultAccessIssue] {
  if self.closed {
    return Err(InvalidProgress)
  }
  let first = match observed_at(self.service) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    store_result(
      self.service.store.observe_trusted_clock(self.clock_contract_cid, first),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let availability = match
    publication_result(
      @publication.result_read_availability(
        self.resolved.result_manifest,
        self.request.result_name,
        self.resolved.retention,
        first,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if availability != "available" {
    return Err(ResultUnavailable)
  }
  let authorization : NativeResultDeliveryAuthorization = {
    request: self.request,
    public_index_entry_cid: @publication.publication_contract_identity(
      self.resolved.public_index_entry,
    ),
    result_manifest_cid: @publication.publication_contract_identity(
      self.resolved.result_manifest,
    ),
    result_read_grant_cid: @publication.publication_contract_identity(
      self.grant,
    ),
    stage,
    observed_at: first,
  }
  if !(self.service.authority.authorize_delivery)(authorization) {
    return Err(AccessDenied)
  }
  let final_time = match observed_at(self.service) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    store_result(
      self.service.store.observe_trusted_clock(
        self.clock_contract_cid,
        final_time,
      ),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let final_availability = match
    publication_result(
      @publication.result_read_availability(
        self.resolved.result_manifest,
        self.request.result_name,
        self.resolved.retention,
        final_time,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if final_availability != "available" ||
    !@publication.result_read_grant_valid_at(self.grant, final_time) {
    return Err(ResultUnavailable)
  }
  Ok(final_time)
}

///|
pub fn NativeResultAccessSession::attempt_cid(
  self : NativeResultAccessSession,
) -> String {
  self.delivery.attempt_cid()
}

///|
pub fn NativeResultAccessSession::next(
  self : NativeResultAccessSession,
  max_bytes : Int,
) -> Result[@store.NativePublicationDeliveryChunk, NativeResultAccessIssue] {
  let observed = match self.authorize_stage("read") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  store_result(self.delivery.next(max_bytes, observed))
}

///|
pub fn NativeResultAccessSession::confirm_chunk(
  self : NativeResultAccessSession,
) -> Result[Int64, NativeResultAccessIssue] {
  if self.closed {
    return Err(InvalidProgress)
  }
  store_result(self.delivery.confirm_chunk())
}

///|
pub fn NativeResultAccessSession::confirm_sink_finished(
  self : NativeResultAccessSession,
) -> Result[@store.NativeResultDeliverySuccess, NativeResultAccessIssue] {
  let observed = match self.authorize_stage("receipt") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result = match
    store_result(self.delivery.confirm_sink_finished(observed)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.closed = true
  Ok(result)
}

///|
pub fn NativeResultAccessSession::terminate(
  self : NativeResultAccessSession,
  confirmed_prefix_bytes : Int?,
  cancellation_observed : Bool,
  exposure : String,
  possible_unconfirmed_max_bytes : Int?,
  failure_cid : String?,
) -> Result[@store.NativeResultDeliveryFailure, NativeResultAccessIssue] {
  let observed = match observed_at(self.service) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let result = match
    store_result(
      self.delivery.terminate(
        confirmed_prefix_bytes, cancellation_observed, exposure, possible_unconfirmed_max_bytes,
        failure_cid, observed,
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.closed = true
  Ok(result)
}

///|
pub fn NativeResultAccessSession::close(
  self : NativeResultAccessSession,
) -> Result[Unit, NativeResultAccessIssue] {
  if self.closed {
    return Ok(())
  }
  match store_result(self.delivery.close()) {
    Ok(_) => {
      self.closed = true
      Ok(())
    }
    Err(issue) => Err(issue)
  }
}
