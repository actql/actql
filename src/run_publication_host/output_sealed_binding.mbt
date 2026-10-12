///|
/// Bind an original filesystem Sealed record through the existing completed
/// Result content/schema Owner. This neither opens a file nor authorizes a
/// publisher or Store commit. The Host must observe the same physical generation
/// and its calling Run Owner must revalidate the original context.
pub fn PublicationOutputExport::issue_sealed_durable_binding(
  self : PublicationOutputExport,
  run_definition : @publication.PublicationContract,
  invocation : @publication.PublicationContract,
  retention : @publication.PublicationContract,
  record : @payload.PublicationPayloadRecord,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract, PublicationOutputPayloadIssue] {
  guard @payload.publication_payload_record_state(record) is @payload.Sealed &&
    @payload.publication_payload_record_generation(record) is Some(generation) &&
    generation.size >= 0L &&
    generation.size <= 2147483647L else {
    return Err(InvalidState)
  }
  let request = @payload.publication_payload_record_request(record)
  let expected = match
    self.prepare_payload_request(
      @payload.publication_payload_request_attempt(request),
      @payload.publication_payload_request_store_authority(request),
      @payload.publication_payload_material_identity(request),
      @payload.publication_payload_request_max_bytes(request),
    ) {
    Ok(value) => value
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
  let digest = @payload.publication_payload_record_digest(record)
  if !digest.has_prefix("sha256:") {
    return Err(RequestMismatch)
  }
  // The existing binding Owner checks these physical bytes/digest against the
  // original live content identity and supplies all schema/ordering fields.
  self
  .issue_durable_binding(
    run_definition,
    invocation,
    retention,
    @payload.publication_payload_material_identity(request),
    @payload.publication_payload_request_store_authority(request),
    generation.size.to_int(),
    digest[7:].to_owned(),
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
  .map_err(issue => Binding(issue))
}
