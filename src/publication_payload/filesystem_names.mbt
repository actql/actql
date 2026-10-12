///|
/// Private Host layout projection. This is not a durable record, a new identity
/// preimage, a physical name acquisition or permission to publish or reclaim.
pub fn publication_payload_filesystem_names_json(
  record : PublicationPayloadRecord,
) -> Result[String, PublicationPayloadIssue] {
  if (record.state != Writing && record.state != Sealed) ||
    record.ownership is None ||
    record.opaque_ownership_cid is Some(_) {
    return Err(InvalidTransition)
  }
  let request = record.request
  let writer = @encode.writer(1024, 16, 2) catch {
    _ => return Err(InvalidRecord)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "material_generation_cid")
    @encode.string_value(writer, request.material_generation_cid)
    @encode.key(writer, "object_name")
    @encode.string_value(writer, publication_payload_object_name(request))
    @encode.key(writer, "record_revision")
    @encode.string_value(writer, record.revision.to_string())
    @encode.key(writer, "request_cid")
    @encode.string_value(writer, request.request_cid)
    @encode.key(writer, "staging_name")
    @encode.string_value(writer, publication_payload_staging_name(request))
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, request.store_authority_cid)
    @encode.end_object(writer)
  } catch {
    _ => return Err(InvalidRecord)
  }
  Ok(@encode.finish(writer) catch { _ => return Err(InvalidRecord) })
}
