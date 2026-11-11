///|
#export_name("clientProgramCapturedContentCandidate")
pub fn client_program_captured_content_candidate(
  acquisition : @publication_host.ClientKeyedAcquisition,
  request : @publication_host.ClientKeyedRequest,
  binding_wire : String,
  media_type : String,
  content_cid : String,
  size_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
) -> Result[
  @publication_host.ClientCapturedContent,
  @publication.GeneratedContentReferenceIssue,
] {
  @publication_host.prepare_client_captured_content(
    acquisition,
    request,
    binding_wire,
    media_type,
    content_cid,
    size_bytes,
    { max_bytes, max_nodes, max_depth, max_text_units, },
  )
}

///|
#export_name("clientProgramReserveCapturedContentWorkspace")
pub fn client_program_reserve_captured_content_workspace(
  ledger : @resources.Ledger,
  max_bytes : Int,
  inventory_count : Int,
) -> Result[@resources.Reservation, @resources.LedgerIssue] {
  guard @publication_host.client_captured_content_workspace_capacity(
      max_bytes,
      inventory_count~,
    )
    is Some((retained, execution)) else {
    return Err(@resources.InvalidLimits)
  }
  @resources.reserve_attempt(ledger, 0L, retained, execution)
}

///|
#export_name("clientProgramGrowCapturedContentWorkspace")
pub fn client_program_grow_captured_content_workspace(
  ledger : @resources.Ledger,
  reservation : @resources.Reservation,
  max_bytes : Int,
  inventory_count : Int,
) -> Result[Unit, @resources.LedgerIssue] {
  guard @publication_host.client_captured_content_workspace_capacity(
      max_bytes,
      inventory_count~,
    )
    is Some((retained, execution)) else {
    return Err(@resources.InvalidLimits)
  }
  @resources.grow_execution_reservation_capacity(
    ledger, reservation, retained, execution,
  )
}

///|
#export_name("clientProgramReleaseCapturedContentWorkspace")
pub fn client_program_release_captured_content_workspace(
  ledger : @resources.Ledger,
  reservation : @resources.Reservation,
) -> Result[Unit, @resources.LedgerIssue] {
  @resources.settle_reservation(ledger, reservation)
}

///|
#export_name("clientProgramRunCapturedContentCandidate")
pub fn client_program_run_captured_content_candidate(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  acquisition : @publication_host.ClientKeyedAcquisition,
  request : @publication_host.ClientKeyedRequest,
  binding_wire : String,
  media_type : String,
  content_cid : String,
  size_bytes : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
) -> Result[
  @publication_host.ClientCapturedContent,
  @publication.GeneratedContentReferenceIssue,
] {
  @publication_host.prepare_client_run_captured_content(
    compiled,
    definition,
    acquisition,
    request,
    binding_wire,
    media_type,
    content_cid,
    size_bytes,
    { max_bytes, max_nodes, max_depth, max_text_units, },
  )
}

///|
#export_name("clientProgramCapturedContentHoldingCid")
pub fn client_program_captured_content_holding_cid(
  value : @publication_host.ClientCapturedContent,
) -> String? {
  @publication_host.client_captured_content_holding_cid(value)
}

///|
#export_name("clientProgramStoredRunCapturedContentCandidate")
pub fn client_program_stored_run_captured_content_candidate(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  acquisition : @publication_host.ClientKeyedAcquisition,
  original_wire : String,
  binding_wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
) -> Result[
  @publication_host.ClientCapturedContent,
  @publication.GeneratedContentReferenceIssue,
] {
  @publication_host.prepare_client_stored_run_captured_content(
    compiled,
    definition,
    acquisition,
    original_wire,
    binding_wire,
    { max_bytes, max_nodes, max_depth, max_text_units, },
  )
}

///|
#export_name("clientProgramCapturedContentReissuer")
pub fn client_program_captured_content_reissuer(
  resolve : (String?, String) -> @admitted.CheckedValue?,
) -> @admitted.ReferenceIssuer {
  @admitted.bind_reference_reissuer((contract, wire) => {
    guard contract.shape is @parameter_contract.ContentRef(media_type~) &&
      resolve(media_type, wire) is Some(checked) &&
      checked.value is @admitted.Reference(original) else {
      return None
    }
    Some(original)
  })
}

///|
#export_name("clientProgramCapturedContentWire")
pub fn client_program_captured_content_wire(
  value : @publication_host.ClientCapturedContent,
) -> String {
  @publication_host.client_captured_content_wire(value)
}

///|
#export_name("clientProgramCapturedContentCid")
pub fn client_program_captured_content_cid(
  value : @publication_host.ClientCapturedContent,
) -> String {
  @publication_host.client_captured_content_identity(value)
}

///|
#export_name("clientProgramCapturedContentStorage")
pub fn client_program_captured_content_storage(
  value : @publication_host.ClientCapturedContent,
) -> (String, String, String, Int) {
  @publication_host.client_captured_content_storage(value)
}

///|
#export_name("clientProgramIssueCapturedContent")
pub fn client_program_issue_captured_content(
  value : @publication_host.ClientCapturedContent,
  issuer : @admitted.ReferenceIssuer,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
) -> Result[@admitted.CheckedValue, @publication.GeneratedContentReferenceIssue] {
  @publication_host.issue_client_captured_content(value, issuer, {
    max_bytes,
    max_nodes,
    max_depth,
    max_text_units,
  })
}
