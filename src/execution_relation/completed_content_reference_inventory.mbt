///|
/// The original export's reference inventory can outlive its transient row
/// stream only through an explicit custody move. No rows or references copy.
priv struct CompletedContentReferencesOriginal {
  mut view : CompletedContentReferences?
  mut references : CompletedExportReferences?
  mut schema : @schema.Schema?
  mut fields : Array[String]?
}

///|
struct CompletedContentReferences {
  mut original : CompletedContentReferencesOriginal?
}

///|
/// Must run while the exact finished export is still current, before its
/// normal finally retires that receipt. The caller retains its original pin
/// and owns bounded retirement of this same inventory, not a second export.
pub fn take_completed_relation_content_references(
  receipt : CompletedRelationExportReceipt,
) -> Result[CompletedContentReferences, CompletedExportIssue] {
  guard !receipt.rows.binding &&
    receipt.rows.source is Some(source) &&
    receipt.rows.references is Some(references) &&
    references.complete &&
    !references.revoked &&
    completed_output_available(source) else {
    return Err(Unavailable)
  }
  // The source liveness callback may itself retire this receipt.
  guard receipt.rows.source is Some(current) &&
    physical_equal(current, source) &&
    receipt.rows.references is Some(current_references) &&
    physical_equal(current_references, references) &&
    references.complete &&
    !references.revoked else {
    return Err(Unavailable)
  }
  // Consume the transient owner's right to bind or reissue this export.
  // Immutable row/schema/CID facts stay on the original receipt as DATA.
  receipt.rows.source = None
  receipt.rows.references = None
  let original : CompletedContentReferencesOriginal = {
    view: None,
    references: Some(references),
    schema: Some(receipt.rows.content.schema),
    fields: Some(receipt.fields),
  }
  let view : CompletedContentReferences = { original: Some(original), }
  original.view = Some(view)
  Ok(view)
}

///|
fn completed_content_reference_at(
  value : CompletedContentReferences,
  row : Int,
  column : Int,
) -> @admitted.ReferenceValue? {
  guard value.original is Some(original) &&
    original.view.map(issued => physical_equal(issued, value)) == Some(true) &&
    original.references is Some(references) &&
    original.schema is Some(schema) &&
    @schema.field_at(schema, column) is Some(field) &&
    field.contract.shape is @contract.ContentRef(..) &&
    original_export_content_reference(references, row, column)
    is Some(reference) else {
    return None
  }
  guard value.original is Some(current) &&
    physical_equal(current, original) &&
    original.references.map(current => physical_equal(current, references)) ==
    Some(true) else {
    return None
  }
  Some(reference)
}

///|
pub fn completed_content_reference_field(
  value : CompletedContentReferences,
  row : Int,
  field : @schema.Field,
  max_fields : Int,
  max_work : Int,
) -> Result[@admitted.ReferenceValue, CompletedExportIssue] {
  guard value.original is Some(original) && original.fields is Some(fields) else {
    return Err(Unavailable)
  }
  original_export_content_field(fields, row, field, max_fields, max_work, column => {
    completed_content_reference_at(value, row, column)
  })
}

///|
/// Logical revocation is immediate; actual array scrubbing consumes bounded
/// work. False retains the same inventory and its original parent's custody.
pub fn advance_release_completed_content_references(
  value : CompletedContentReferences,
  quantum : Int,
) -> Bool {
  guard value.original is Some(original) else { return true }
  if original.view.map(issued => physical_equal(issued, value)) != Some(true) {
    return false
  }
  guard original.references is Some(references) else { return false }
  references.revoked = true
  if !advance_completed_export_reference_reclamation(references, quantum) {
    return false
  }
  original.references = None
  original.schema = None
  original.fields = None
  original.view = None
  value.original = None
  true
}
