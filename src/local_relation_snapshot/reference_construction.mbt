///|
/// Metadata field/scalar visit bound for this SAME immutable Member. No text
/// scan, typed Reference validation, normalization or body read is performed.
/// Caller backs the bound/borrowed frame before entry, then the quotation and
/// observation frames before the observer. This is not Resource work credit.
pub fn member_reference_construction_inspection_bound(
  original : @environment.Member,
) -> Int64 {
  if @environment.member_section(original) != @environment.SchemaSnapshots {
    return 1L
  }
  4L +
  2L *
  @decode.object_length(@environment.member_body(original))
  .unwrap_or(0)
  .to_int64()
}

///|
/// Observe the actual source_ref text's UTF16 length by original indexed field
/// access, without constructing an ObjectView or copying its String. Return
/// actual metadata visits even when unavailable. None is never zero demand or
/// a known semantic refusal; only the original reader admits a Reference.
/// The caller owns/backed all returned inventory and quotation controls.
pub fn observe_member_reference_read_construction(
  original : @environment.Member,
) -> (@reference.ReferenceReadConstructionInventory?, Int64) {
  let mut work = 1L
  if @environment.member_section(original) != @environment.SchemaSnapshots {
    return (None, work)
  }
  let body = @environment.member_body(original)
  work += 1L
  if @decode.object_length(body) is Some(count) {
    for i in 0..<count {
      work += 2L
      let (name, value) = @decode.field_at(body, i).unwrap()
      if name == snapshot_reference_field {
        work += 1L
        return match @decode.text(value) {
          Ok(text) =>
            (
              @reference.reference_read_construction_inventory(text.length()),
              work,
            )
          Err(_) => (None, work)
        }
      }
    }
  }
  (None, work)
}
