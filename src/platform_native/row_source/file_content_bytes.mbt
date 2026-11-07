///|
priv suberror FileContentProjectionStop {
  FileContentProjectionStop(NativeRelationFileIssue)
}

///|
/// Extract the SAME observed file version as exact UTF-8 DATA. The original
/// Source resolves its nominal ResourceRef to identity before this call and
/// charges/retains the physical response and this constructor's overlap.
/// This projection does not issue ContentRef, store bytes, complete a keyed
/// request or acknowledge any Source/Store cleanup.
pub fn project_native_relation_file_content_bytes(
  provider : NativeRelationFilePreparedProvider,
  document : @rows.RelationDocument,
  fields : NativeRelationFileListingFields,
  content_utf8 : String,
  identity : String,
  expected_version : String,
  max_content_bytes : Int,
) -> Result[(String, Bytes), NativeRelationFileIssue] {
  if max_content_bytes < 0 ||
    max_content_bytes > provider.limits.page.max_bytes ||
    !file_listing_fields_valid(provider, fields) ||
    !file_capture_text(content_utf8, 64) ||
    !file_capture_text(identity, provider.limits.page.max_bytes) ||
    expected_version.length() != 71 {
    return Err(InvalidInput)
  }
  let selected = provider.selection
  let target = match
    @rows.project_relation_target_document(
      document,
      provider.declaration,
      selected.resource,
      selected.items_path,
      selected.key_path,
      selected.primary_identity,
      [],
      prepared_contract=Some(provider.prepared_contract),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Document(issue))
  }
  let mut observed : @rows.RelationTargetRow? = None
  let result = try {
    let row = match
      @rows.observe_relation_target(target, provider.declaration, identity) {
      Ok(value) => value
      Err(issue) => raise FileContentProjectionStop(Document(issue))
    }
    observed = Some(row)
    // An unchanged authored label cannot conceal replacement of body or any
    // other admitted row field. Reuse the listing's one version definition.
    if file_listing_row_version(row, fields.version, provider.limits.page) !=
      Some(expected_version) {
      raise FileContentProjectionStop(ForeignOriginal)
    }
    guard @rows.relation_target_text(row, content_utf8) is Some(text) &&
      @rows.relation_target_text(row, fields.media_type) is Some(media_type) else {
      raise FileContentProjectionStop(InvalidInput)
    }
    // Measure before the UTF-8 getter allocates. Preserve decomposed Unicode,
    // line endings and empty content; a size refusal never creates the buffer.
    if @scalar.admit_utf8_length(text, max_content_bytes) is Err(_) {
      raise FileContentProjectionStop(FileLimit)
    }
    guard @rows.relation_target_text_bytes(row, content_utf8) is Some(bytes) else {
      raise FileContentProjectionStop(InvalidInput)
    }
    Ok((media_type, bytes))
  } catch {
    FileContentProjectionStop(issue) => Err(issue)
  }
  // Only this temporary typed projection retires here. The caller's original
  // response and returned bytes remain with their existing Source/Store owner.
  let row_retired = match observed {
    Some(row) => @rows.discard_relation_target_row_original(row)
    None => true
  }
  let target_retired = @rows.discard_relation_target_document_original(target)
  if !row_retired || !target_retired {
    return Err(ForeignOriginal)
  }
  result
}

///|
/// Complete simultaneous constructor DATA, to compose under the SAME parent
/// before projection. Raw input, provider metadata, physical Reader and Store
/// writer have separate original lifetimes and are not paid by this quote.
pub fn native_relation_file_content_construction_inventory(
  provider : NativeRelationFilePreparedProvider,
  max_content_bytes : Int,
) -> @execution.PreparationRepresentationUnits? {
  file_content_construction_inventory(provider, max_content_bytes, None)
}

///|
fn file_content_construction_inventory(
  provider : NativeRelationFilePreparedProvider,
  max_content_bytes : Int,
  response_bytes : Int?,
) -> @execution.PreparationRepresentationUnits? {
  if max_content_bytes < 0 || max_content_bytes > provider.limits.page.max_bytes {
    return None
  }
  let limits = provider.limits.page
  guard file_provider_projection_inventory(provider, response_bytes~)
    is Some(projected) &&
    @encode.text_writer_construction_inventory(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(text) &&
    @encode.hash_writer_construction_inventory(
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(hash) else {
    return None
  }
  // observe_relation_target: retained before-wire writer plus original row
  // hash; exposed version: second hash and two CID strings (H4/142 UTF16).
  // Row and original Some H2/R5/W2; borrowed field/version/UTF8-length Options
  // H5/R3/W5; returned UTF8 Bytes + tuple + Result H3/R3/W1; prelude, two
  // projection Results, refusal/stop and two cleanup Results H8/R8/W6.
  // Charge success and refusal peaks together, with no GC/phase credit.
  @execution.compose_preparation_representation([
    projected,
    {
      record_headers: text.record_headers + 2L * hash.record_headers + 22L,
      reference_slots: text.reference_slots + 2L * hash.reference_slots + 19L,
      scalar_words: text.scalar_words + 2L * hash.scalar_words + 14L,
      owned_utf16_units: text.owned_utf16_units +
      2L * hash.owned_utf16_units +
      142L,
      owned_wire_bytes: 2L * hash.owned_wire_bytes +
      max_content_bytes.to_int64(),
    },
  ])
}
