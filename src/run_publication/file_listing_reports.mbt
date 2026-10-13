///|
// Semantic DATA validation after the existing closed shape/limits admission.
// This proves no Source completion, Resource association or physical custody;
// the original Row/capture issuer must bind the same actual captured input.
fn completed_file_listing_reports_consistent(
  value : @json.CanonicalValue,
  max_wire_bytes : Int,
) -> Bool {
  guard @json.object_field(value, "file_listing_reports") is Some(reports) else {
    return true
  }
  guard @json.object_field(reports, "row_count") is Some(@json.Number(count)) &&
    @json.object_field(reports, "rows") is Some(@json.Array(rows)) &&
    count == @json.array_count(rows).to_double() else {
    return false
  }
  for index in 0..<@json.array_count(rows) {
    guard @json.array_at(rows, index) is Some(row) &&
      @json.object_field(row, "row_ordinal") is Some(@json.Number(ordinal)) &&
      ordinal == index.to_double() &&
      @json.object_field(row, "resource_ref_cid")
      is Some(@json.String(resource)) &&
      valid_contract_cid(resource) else {
      return false
    }
    match
      (
        @json.object_field(row, "reported_media_type"),
        @json.object_field(row, "media_type"),
      ) {
      (Some(@json.Null), Some(@json.Null)) => ()
      (Some(@json.String(reported)), Some(@json.String(projected))) =>
        if @contract.normalize_content_media_type_case(reported, max_wire_bytes) !=
          Ok(projected) {
          return false
        }
      _ => return false
    }
  }
  true
}
