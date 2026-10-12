///|
pub(all) enum PublicationOutputPayloadIssue {
  InvalidState
  PayloadLimit
  RequestMismatch
  Payload(@payload.PublicationPayloadIssue)
  Replay(PublicationOutputExportIssue)
  Binding(PublicationOutputExportIssue)
}

///|
/// Replay only the already identified live Result behind this exact payload
/// intent. This returns bounded physical bytes, not publisher authority or a
/// Store transition. Cancelling the child does not cancel the original export.
pub fn PublicationOutputExport::replay_payload_request(
  self : PublicationOutputExport,
  request : @payload.PublicationPayloadRequest,
) -> Result[PublicationOutputReplay, PublicationOutputPayloadIssue] {
  let expected = match
    self.prepare_payload_request(
      @payload.publication_payload_request_attempt(request),
      @payload.publication_payload_request_store_authority(request),
      @payload.publication_payload_material_identity(request),
      @payload.publication_payload_request_max_bytes(request),
    ) {
    Ok(expected) => expected
    Err(issue) => return Err(issue)
  }
  let original_body = match @payload.publication_payload_request_json(request) {
    Ok(body) => body
    Err(issue) => return Err(Payload(issue))
  }
  let expected_body = match
    @payload.publication_payload_request_json(expected) {
    Ok(body) => body
    Err(issue) => return Err(Payload(issue))
  }
  if @payload.publication_payload_request_identity(request) !=
    @payload.publication_payload_request_identity(expected) ||
    original_body != expected_body {
    return Err(RequestMismatch)
  }
  self.replay().map_err(issue => Replay(issue))
}

///|
/// Issue physical payload intent from the original live export. Its value and
/// schema interpretation remain under this Owner; no Store write or publisher
/// authorization is implied. The caller binds the original publication attempt.
pub fn PublicationOutputExport::prepare_payload_request(
  self : PublicationOutputExport,
  publication_attempt_cid : String,
  store_authority_cid : String,
  material_generation_cid : String,
  max_payload_bytes : Int64,
) -> Result[@payload.PublicationPayloadRequest, PublicationOutputPayloadIssue] {
  guard self.receipt is Some(receipt) &&
    @execution.completed_relation_export_receipt_live(receipt) &&
    self.definition is Some(definition) &&
    self.evidence is Some(evidence) &&
    self.artifact is Some(_) else {
    return Err(InvalidState)
  }
  let (_, bytes, _, rows) = self.content_identity().unwrap()
  if bytes < 1 || max_payload_bytes < bytes.to_int64() {
    return Err(PayloadLimit)
  }
  @payload.prepare_publication_payload_request(
    store_authority_cid,
    publication_attempt_cid,
    material_generation_cid,
    @publication.publication_contract_identity(definition),
    self.logical_relation_cid().unwrap(),
    self.result_schema_cid().unwrap(),
    @publication.publication_contract_identity(
      @publication.result_ordering_evidence_contract(evidence),
    ),
    self.codec_contract_cid().unwrap(),
    bytes.to_int64(),
    rows.to_int64(),
  ).map_err(issue => Payload(issue))
}
