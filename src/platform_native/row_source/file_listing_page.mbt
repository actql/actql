///|
/// Physical field names retained from the original declared file binding.
/// These are DATA; neither names nor a file row can issue a ResourceRef.
pub(all) struct NativeRelationFileListingFields {
  name : String
  version : String
  media_type : String
  path : String?
}

///|
fn file_listing_fields_valid(
  provider : NativeRelationFilePreparedProvider,
  selected : NativeRelationFileListingFields,
) -> Bool {
  let contract = @rows.relation_document_prepared_contract(
    provider.prepared_contract,
  )
  guard contract.shape is @contract.Object(fields) else { return false }
  let text = (name, nullable) => {
    if !file_capture_text(name, 64) {
      return false
    }
    for index = 0; index < @contract.field_count(fields); index = index + 1 {
      let field = @contract.field_at(fields, index).unwrap()
      if field.name == name {
        return field.contract.shape is @contract.Text(_) &&
          (nullable || !field.contract.nullable)
      }
    }
    false
  }
  text(selected.name, false) &&
  text(selected.version, false) &&
  text(selected.media_type, false) &&
  selected.path.map(path => text(path, true)).unwrap_or(true)
}

///|
// Keep the same opaque version as the existing declared-file supplier: an
// authored version label alone cannot hide changes to the admitted row.
fn file_listing_row_version(
  row : @rows.RelationTargetRow,
  field : String,
  limits : @rows.RowPageLimits,
) -> String? {
  guard @rows.relation_target_text(row, field) is Some(declared) &&
    !declared.is_empty() &&
    @rows.relation_target_version(row) is Some(original) else {
    return None
  }
  try {
    // Stream the closed two-field canonical preimage; do not parse or copy
    // the complete physical row to construct its exposed version.
    // The raw document bounds the encoded declared Text. The derived closed
    // preimage additionally contains two field names and the original 71-byte
    // CID. Fund that fixed expansion; do not apply the raw-body ceiling to a
    // different serialization or narrow otherwise admitted version labels.
    guard @execution.checked_preparation_add_product(
        limits.max_bytes.to_int64(),
        113L,
        1L,
      )
      is Some(bytes) &&
      bytes <= 2147483647L else {
      return None
    }
    let writer = @encode.hashing_writer(bytes.to_int(), 5, 1)
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "declared_version")
    @encode.string_value(writer, declared)
    @encode.ordered_key(writer, "row_version_cid")
    @encode.string_value(writer, original)
    @encode.end_object(writer)
    Some("sha256:" + @encode.finish_hash(writer))
  } catch {
    _ => None
  }
}

///|
priv suberror FileListingPageStop {
  FileListingPageStop(NativeRelationFileIssue)
}

///|
fn file_listing_text(
  row : @rows.RelationTargetRow,
  field : String,
) -> String raise FileListingPageStop {
  @rows.relation_target_text(row, field).unwrap_or_else(() => {
    raise FileListingPageStop(InvalidInput)
  })
}

///|
/// Project a bounded listing envelope from the SAME admitted physical document.
/// The original Source supplies its ResourceRef issuer for each observed row
/// identity. This function supplies no reference authority, Account decision,
/// physical read, response charge or listing completion receipt. The caller
/// funds the construction inventory before entry and consumes the result with
/// its existing original charged listing-page protocol.
pub fn project_native_relation_file_listing_page(
  provider : NativeRelationFilePreparedProvider,
  document : @rows.RelationDocument,
  fields : NativeRelationFileListingFields,
  issue_resource : (String) -> Result[
    @admitted.CheckedValue,
    NativeRelationFileIssue,
  ],
) -> Result[Bytes, NativeRelationFileIssue] {
  let selected = provider.selection
  let limits = provider.limits.page
  if !file_listing_fields_valid(provider, fields) {
    return Err(InvalidInput)
  }
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
  let mut current_row : @rows.RelationTargetRow? = None
  let result = try {
    let count = @rows.relation_target_row_count(target).unwrap_or_else(() => {
      raise FileListingPageStop(ForeignOriginal)
    })
    if count > limits.max_rows {
      raise FileListingPageStop(FileLimit)
    }
    let writer = @encode.writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.begin_object(writer)
    @encode.key(writer, "items")
    @encode.begin_array(writer)
    for index = 0; index < count; index = index + 1 {
      let identity = @rows.relation_target_row_identity(target, index).unwrap_or_else(() => {
          raise FileListingPageStop(ForeignOriginal)
        },
      )
      let row = match
        @rows.observe_relation_target(target, provider.declaration, identity) {
        Ok(value) => value
        Err(issue) => raise FileListingPageStop(Document(issue))
      }
      current_row = Some(row)
      // The original Source may reenter. Recheck the physical originals after
      // its callback, before emitting any returned nominal reference or field.
      let resource = match issue_resource(identity) {
        Ok(value) => value
        Err(issue) => raise FileListingPageStop(issue)
      }
      guard resource.value is @admitted.Reference(reference) &&
        resource.contract.shape is @contract.ResourceRef(resource_kind="file") &&
        @admitted.reference_available(reference) &&
        @rows.relation_target_row_identity(target, index) == Some(identity) else {
        raise FileListingPageStop(ForeignOriginal)
      }
      let version = file_listing_row_version(row, fields.version, limits).unwrap_or_else(() => {
          raise FileListingPageStop(InvalidInput)
        },
      )
      @encode.begin_object(writer)
      @encode.key(writer, "resource")
      @identity.emit_value(reference.envelope, writer)
      @encode.key(writer, "version")
      @encode.string_value(writer, version)
      @encode.key(writer, "name")
      @encode.string_value(writer, file_listing_text(row, fields.name))
      @encode.key(writer, "path")
      match fields.path.bind(path => @rows.relation_target_text(row, path)) {
        Some(path) => @encode.string_value(writer, path)
        None => @encode.null_value(writer)
      }
      @encode.key(writer, "media_type")
      @encode.string_value(writer, file_listing_text(row, fields.media_type))
      @encode.key(writer, "size_bytes")
      @encode.null_value(writer)
      @encode.key(writer, "modified_at")
      @encode.null_value(writer)
      @encode.end_object(writer)
      if !@rows.discard_relation_target_row_original(row) {
        raise FileListingPageStop(ForeignOriginal)
      }
      current_row = None
    }
    @encode.end_array(writer)
    @encode.key(writer, "request_token")
    @encode.null_value(writer)
    @encode.key(writer, "next_token")
    @encode.null_value(writer)
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    FileListingPageStop(issue) => Err(issue)
    _ => Err(FileLimit)
  }
  if current_row is Some(row) {
    @rows.discard_relation_target_row_original(row) |> ignore
    current_row = None
  }
  // Only the temporary typed projection belongs here. The caller retains its
  // original document, charge and physical children on either outcome.
  if !@rows.discard_relation_target_document_original(target) {
    return Err(ForeignOriginal)
  }
  result
}

///|
/// Additional complete construction peak for this closed physical-to-listing
/// projection. The raw document, original provider metadata and Source's
/// reference-issuance callback have separate retained owners. Compose this
/// with those SAME parent allowances before calling the projection; it issues
/// neither backing nor permission. No row/page/GC phase credit is assumed.
pub fn native_relation_file_listing_construction_inventory(
  provider : NativeRelationFilePreparedProvider,
) -> @execution.PreparationRepresentationUnits? {
  let limits = provider.limits.page
  guard file_provider_projection_inventory(provider) is Some(projected) &&
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
  // Page writer and observe_relation_target's before-wire writer coexist.
  // Two hashes cover that row's original version and the exposed version.
  // One live row (H1/R4/W1 + Some H1/R1/W1), fixed field-validation closure,
  // call/error/Option frontier (H16/R20/W14), two CID strings (H4/142 UTF16),
  // and returned UTF8 page (H1/B). The closed flat ResourceRef envelope uses
  // the synchronous canonical emitter: one container cursor, parent stack,
  // scalar/key cursors and pop/refusal carriers add H10/R14/W8. Its original
  // canonical fields/strings are borrowed, never copied as another JSON tree.
  @execution.compose_preparation_representation([
    projected,
    {
      record_headers: 2L * text.record_headers + 2L * hash.record_headers + 24L,
      reference_slots: 2L * text.reference_slots +
      2L * hash.reference_slots +
      40L,
      scalar_words: 2L * text.scalar_words + 2L * hash.scalar_words + 24L,
      owned_utf16_units: 2L * text.owned_utf16_units +
      2L * hash.owned_utf16_units +
      142L,
      owned_wire_bytes: 2L * hash.owned_wire_bytes + limits.max_bytes.to_int64(),
    },
  ])
}
