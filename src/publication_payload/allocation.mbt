///|
/// The existing Native Store's allocation body, independent of physical I/O.
/// Decoding is not proof that a directory was created, that its identity was
/// persisted, or that the caller may publish, reclaim, or reopen it.
struct PublicationPayloadAllocation {
  name : String
  ownership : PublicationPayloadOwnership?
}

///|
pub const PUBLICATION_PAYLOAD_ALLOCATION_FILE : String = "payload"

///|
pub fn publication_payload_allocation_namespace() -> String {
  "publication_payload_allocation"
}

///|
pub fn prepare_publication_payload_allocation_name(
  request : PublicationPayloadRequest,
  ordinal : Int64,
) -> String {
  "alloc-" +
  publication_payload_material_identity(request)[7:].to_owned() +
  "-" +
  ordinal.to_string()
}

///|
/// Preserve the existing stored allocation decoder's accepted decimal range.
/// This is a physical codec limit, not a change to UInt64 payload ownership or
/// a language restriction. No later name can supply missing acquisition proof.
fn allocation_decimal(text : String) -> Int64? {
  if text.is_empty() {
    return None
  }
  let mut value = 0L
  for character in text {
    let code = character.to_int()
    if code < 48 || code > 57 || value > 100000000000000L {
      return None
    }
    value = value * 10L + (code - 48).to_int64()
  }
  Some(value)
}

///|
pub fn encode_publication_payload_allocation(
  name : String,
  ownership : PublicationPayloadOwnership?,
) -> Bytes {
  @utf8.encode(
    match ownership {
      Some(identity) =>
        name +
        "|" +
        identity.device.to_string() +
        "|" +
        identity.inode.to_string()
      None => name
    },
  )
}

///|
pub fn admit_publication_payload_allocation(
  request : PublicationPayloadRequest,
  body : Bytes,
) -> Result[PublicationPayloadAllocation, PublicationPayloadIssue] {
  let prefix = "alloc-" +
    publication_payload_material_identity(request)[7:].to_owned() +
    "-"
  let parts = @utf8.decode_lossy(body).split("|").collect()
  guard parts.length() == 1 || parts.length() == 3 else {
    return Err(StateCollision)
  }
  let name = parts[0].to_owned()
  guard name.has_prefix(prefix) &&
    allocation_decimal(
      name.unsafe_substring(start=prefix.length(), end=name.length()),
    )
    is Some(_) else {
    return Err(StateCollision)
  }
  if parts.length() == 1 {
    return Ok({ name, ownership: None, })
  }
  match
    (
      allocation_decimal(parts[1].to_owned()),
      allocation_decimal(parts[2].to_owned()),
    ) {
    (Some(device), Some(inode)) =>
      Ok({
        name,
        ownership: Some({
          device: device.reinterpret_as_uint64(),
          inode: inode.reinterpret_as_uint64(),
        }),
      })
    _ => Err(StateCollision)
  }
}

///|
pub fn publication_payload_allocation_name(
  allocation : PublicationPayloadAllocation,
) -> String {
  allocation.name
}

///|
pub fn publication_payload_allocation_ownership(
  allocation : PublicationPayloadAllocation,
) -> PublicationPayloadOwnership? {
  allocation.ownership
}

///|
pub fn next_publication_payload_allocation_ordinal(
  request : PublicationPayloadRequest,
  name : String,
) -> Result[Int64, PublicationPayloadIssue] {
  let prefix = "alloc-" +
    publication_payload_material_identity(request)[7:].to_owned() +
    "-"
  guard name.has_prefix(prefix) else { return Err(StateCollision) }
  match
    allocation_decimal(
      name.unsafe_substring(start=prefix.length(), end=name.length()),
    ) {
    Some(ordinal) => Ok(ordinal + 1L)
    None => Err(StateCollision)
  }
}
