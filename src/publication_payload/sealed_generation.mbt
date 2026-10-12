///|
/// Compare fresh trusted filesystem facts with this original Sealed record.
/// This read-only check grants no read/publication authority and changes no
/// durable state. The Host retains the original descriptor and reservation and
/// rechecks its name/generation before the physical commit.
pub fn validate_publication_payload_sealed_generation(
  record : PublicationPayloadRecord,
  generation : PublicationPayloadGeneration,
  physical_digest : String,
) -> Result[Unit, PublicationPayloadIssue] {
  guard record.state is Sealed &&
    record.generation is Some(original) &&
    record.ownership is Some(ownership) &&
    record.opaque_ownership_cid is None &&
    record.opaque_generation_cid is None else {
    return Err(InvalidRecord)
  }
  if generation.size < 0L ||
    !valid_sha256_cid(physical_digest) ||
    generation != original ||
    generation.device != ownership.device ||
    generation.inode != ownership.inode ||
    generation.size != record.actual_bytes ||
    physical_digest != record.physical_digest {
    return Err(IdentityMismatch)
  }
  Ok(())
}
