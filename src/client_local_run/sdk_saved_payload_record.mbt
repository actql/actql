///|
/// Admit the saved payload through its existing Owner, then match every
/// retained request/content field against this exact observed commit. This is
/// read-only restoration: it issues no Result, write transition or physical
/// generation/Store acknowledgement. Actual FD/generation checks stay separate.
pub fn restore_local_sdk_saved_payload_record(
  source : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  body : Bytes,
) -> Result[
  (@payload.PublicationPayloadRecord, @publication.PublicationContract),
  LocalSDKReadOriginalsIssue,
] {
  let durable = match @payload.admit_durable_publication_payload_record(body) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  let record = match
    @payload.restore_durable_publication_payload_record(durable) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  validate_local_sdk_saved_payload_record(
    source, account, owner, view, result_name, record,
  ).map(binding => (record, binding))
}

///|
/// The returned binding is the original committed body, never a newly issued
/// binding. A copied ordinal, current policy or equal-looking physical digest
/// cannot substitute a foreign view/request or a non-Sealed/opaque record.
pub fn validate_local_sdk_saved_payload_record(
  source : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  record : @payload.PublicationPayloadRecord,
) -> Result[@publication.PublicationContract, LocalSDKReadOriginalsIssue] {
  guard source.origin is Saved(_) else { return Err(InvalidOriginal) }
  match source.validate_view(owner, view) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match source.validate_current(account, result_name) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let material = match
    owner.observed_result_read_materials(view, result_name, 16) {
    Ok(value) => value
    Err(issue) => return Err(StoredChain(issue))
  }
  let attempt = match owner.view_contract(view, 6) {
    Ok(value) => value
    Err(issue) => return Err(StoredChain(Commit(issue)))
  }
  let read = material.read
  let request = @payload.publication_payload_record_request(record)
  guard @payload.publication_payload_record_state(record) is Sealed &&
    @payload.publication_payload_record_generation(record) is Some(generation) &&
    @payload.publication_payload_record_ownership(record) is Some(_) &&
    @payload.publication_payload_record_opaque_generation(record) is None &&
    @payload.publication_payload_record_opaque_ownership(record) is None &&
    generation.size == read.byte_count &&
    @payload.publication_payload_record_actual_bytes(record) == read.byte_count &&
    @payload.publication_payload_record_digest(record) ==
    "sha256:" + read.physical_sha256 &&
    @payload.publication_payload_request_attempt(request) ==
    @publication.publication_contract_identity(attempt) &&
    @payload.publication_payload_request_result_definition(request) ==
    read.result_definition_cid &&
    @payload.publication_payload_request_logical_relation(request) ==
    read.logical_result_cid &&
    @payload.publication_payload_request_schema(request) ==
    read.result_schema_cid &&
    @payload.publication_payload_request_ordering_evidence(request) ==
    read.ordering_evidence_cid &&
    @payload.publication_payload_request_codec(request) ==
    read.codec_contract_cid &&
    @payload.publication_payload_request_row_count(request) == read.row_count &&
    @payload.publication_payload_request_max_bytes(request) == read.byte_count &&
    @payload.publication_payload_request_store_authority(request) ==
    read.store_authority_cid &&
    @payload.publication_payload_material_identity(request) ==
    read.material_generation_cid else {
    return Err(InvalidOriginal)
  }
  for i = 0; i < 16; i = i + 1 {
    match owner.view_binding(view, i) {
      Ok(binding) if @publication.publication_contract_identity(binding) ==
        read.durable_result_binding_cid => return Ok(binding)
      Ok(_) => ()
      Err(_) => break
    }
  }
  Err(InvalidOriginal)
}
