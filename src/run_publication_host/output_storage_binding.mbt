///|
/// Bind the canonical bytes of this exact live export to observed Store facts.
/// Semantic fields come from its original receipt/evidence/artifact, never from
/// an adapter's reconstructed JSON. This does not acknowledge a Store commit or
/// authorize publication; the calling Run owner must bind the original context.
pub fn PublicationOutputExport::issue_durable_binding(
  self : PublicationOutputExport,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  material_generation_cid : String,
  store_authority_cid : String,
  observed_byte_count : Int,
  physical_sha256 : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract, PublicationOutputExportIssue] {
  guard self.receipt is Some(receipt) &&
    @execution.completed_relation_export_receipt_live(receipt) else {
    return Err(InvalidState)
  }
  guard self.definition is Some(definition) &&
    self.evidence is Some(evidence) &&
    self.artifact is Some(artifact) else {
    return Err(InvalidState)
  }
  let (content_cid, byte_count, _, row_count) = self.content_identity().unwrap()
  if byte_count != observed_byte_count ||
    content_cid != "sha256:" + physical_sha256 {
    return Err(Output(ForeignMaterial))
  }
  let fields = match self.result_fields() {
    Ok(fields) => fields
    Err(issue) => return Err(issue)
  }
  @publication.issue_durable_result_binding(
    run_definition,
    definition,
    invocation,
    artifact,
    @publication.result_ordering_evidence_contract(evidence),
    retention,
    self.codec_contract_cid().unwrap(),
    fields,
    self.result_schema_wire().unwrap(),
    material_generation_cid,
    store_authority_cid,
    row_count,
    byte_count,
    physical_sha256,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map_err(issue => DurableBinding(issue))
}
