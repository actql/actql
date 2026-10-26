///|
/// Fresh trusted physical facts do not advance the original Sealed record.
/// The Host retains the original reader/reservation and fences them again
/// before Store commit; this bridge provides no publisher or durable ACK.
pub fn validate_payload_record_snapshot(
  nonce : Int64,
  handle : Int,
  input : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.payload_records.get(handle) is Some(record) &&
    record.confirmed &&
    record.record is Some(original) &&
    value.copies.get(input) is Some((slot, _)) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.closing {
    return -5
  }
  if !payload_record_current(value, record, current_configuration) {
    return -32
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "store_authority_cid", "material_generation_cid", "device", "inode", "size",
      "physical_digest",
    ])
    is Ok(object) &&
    required_text(object, "store_authority_cid") is Some(store) &&
    required_text(object, "material_generation_cid") is Some(material) &&
    required_text(object, "device") is Some(device_wire) &&
    required_text(object, "inode") is Some(inode_wire) &&
    required_text(object, "size") is Some(size_wire) &&
    required_text(object, "physical_digest") is Some(digest) &&
    payload_physical_uint64(device_wire) is Some(device) &&
    payload_physical_uint64(inode_wire) is Some(inode) &&
    payload_physical_size(size_wire) is Some(size) else {
    return -31
  }
  let request = @payload.publication_payload_record_request(original)
  if store != @payload.publication_payload_request_store_authority(request) ||
    material != @payload.publication_payload_material_identity(request) {
    return -32
  }
  match
    @payload.validate_publication_payload_sealed_generation(
      original,
      { device, inode, size, },
      digest,
    ) {
    Ok(_) => 0
    Err(_) => -32
  }
}
