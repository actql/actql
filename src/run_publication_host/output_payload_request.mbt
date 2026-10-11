///|
pub(all) enum PublicationOutputPayloadIssue {
  InvalidState
  PayloadLimit
  Payload(@payload.PublicationPayloadIssue)
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
