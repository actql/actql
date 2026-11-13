///|
// Presentation accepts only the private saved-plan holder. Its view was read
// from the authenticated original row, never supplied as a raw-wire argument.
fn native_saved_plan_reply(
  saved : NativeClientSavedRunPlan,
  authority_scope : String,
  reserve : (Int64, Int64, Int64) -> Result[Unit, NativeClientRunJournalIssue],
) -> Result[String, NativeClientRunJournalIssue] {
  if authority_scope != saved.original.scope {
    return Err(ForeignRun)
  }
  guard @publication.publication_contract_run_definition_scope(
      saved.original.definition,
    )
    is Some(run_namespace) else {
    return Err(ForeignRun)
  }
  if run_namespace.is_empty() || run_namespace.length() > 256 {
    return Err(Encoding)
  }
  for character in run_namespace {
    if character.to_int() < 32 || character.to_int() == 127 {
      return Err(Encoding)
    }
  }
  let definition = @publication.publication_contract_identity(
    saved.original.definition,
  )
  if !native_saved_plan_cid(authority_scope) ||
    !native_saved_plan_cid(definition) {
    return Err(ForeignRun)
  }
  guard @encode.quoted_string_construction_extent(run_namespace)
    is Some((namespace_bytes, _)) else {
    return Err(Encoding)
  }
  // The two CIDs are already checked ASCII. Namespace is quoted by the same
  // canonical writer used elsewhere; no builtin JSON tree is constructed.
  let reference_bytes = "{\"authorityScopeCid\":,\"namespaceId\":,\"runDefinitionCid\":}"
    .length()
    .to_int64() +
    73L +
    namespace_bytes +
    73L
  let mut view_bytes = 0L
  for character in saved.view {
    let scalar = character.to_int()
    view_bytes += if scalar < 128 {
      1L
    } else if scalar < 2048 {
      2L
    } else if scalar < 65536 {
      3L
    } else {
      4L
    }
  }
  let prefix = "{\"plan_view\":"
  let middle = ",\"run_ref\":"
  let suffix = ",\"version\":\"actql-run-plan-view/0.1\"}"
  let bytes = prefix.length().to_int64() +
    view_bytes +
    middle.length().to_int64() +
    reference_bytes +
    suffix.length().to_int64()
  if bytes <= 0L || bytes >= 2147483519L {
    return Err(CapacityExceeded)
  }
  guard @encode.text_writer_construction_inventory(
      reference_bytes.to_int(),
      4,
      1,
    )
    is Some(reference_owner) &&
    @encode.text_writer_construction_inventory(bytes.to_int(), 1, 0)
    is Some(envelope_owner) &&
    @execution.preparation_representation_cost({
      record_headers: reference_owner.record_headers +
      envelope_owner.record_headers,
      reference_slots: reference_owner.reference_slots +
      envelope_owner.reference_slots,
      scalar_words: reference_owner.scalar_words + envelope_owner.scalar_words,
      owned_utf16_units: reference_owner.owned_utf16_units +
      envelope_owner.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(execution) &&
    @execution.preparation_representation_cost({
      // Both output Strings plus the returned Result carrier.
      record_headers: 3L,
      reference_slots: 1L,
      scalar_words: 0L,
      owned_utf16_units: reference_bytes + bytes,
      owned_wire_bytes: 0L,
    })
    is Some(retained) else {
    return Err(CapacityExceeded)
  }
  // Envelope assembly is the SAME pinned StringBuilder family covered by the
  // text writer owner above. The reference output remains live beside it.
  let (header, unit, terminator, _, _) = @bootstrap.native_managed_value_layout()
  if header <= 0L || unit != 2L || terminator != unit {
    return Err(CapacityExceeded)
  }
  let mut capacity = 1L
  while capacity < bytes {
    capacity *= 2L
  }
  match reserve(retained, execution, header + (capacity + 1L) * unit) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  try {
    let reference = @encode.writer(reference_bytes.to_int(), 4, 1)
    @encode.begin_object(reference)
    @encode.key(reference, "authorityScopeCid")
    @encode.string_value(reference, authority_scope)
    @encode.key(reference, "namespaceId")
    @encode.string_value(reference, run_namespace)
    @encode.key(reference, "runDefinitionCid")
    @encode.string_value(reference, definition)
    @encode.end_object(reference)
    let reference = @encode.finish(reference)
    let output = StringBuilder()
    output.write_string(prefix)
    output.write_string(saved.view)
    output.write_string(middle)
    output.write_string(reference)
    output.write_string(suffix)
    Ok(output.to_string())
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(Encoding)
  }
}

///|
fn native_saved_plan_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for i in 7..<value.length() {
    let unit = value.code_unit_at(i).to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
// This wrapper retains the original Read's accumulated metadata backing. It
// does not authorize a read: the CLI keeps its selection/current/access fences.
pub fn NativeLocalJournalCapture::saved_run_plan_reply_in_original_read(
  self : NativeLocalJournalCapture,
  saved : NativeClientSavedRunPlan,
  authority_scope : String,
) -> Result[String, NativeLocalAdoptionIssue] {
  self.with_current_adoption_material_in_original_read((
    host,
    _material,
    operations,
  ) => {
    guard run_metadata_construction(host.database, Some(operations.reads))
      is Some(reserve) else {
      return Err(OriginalResourceScopePending)
    }
    native_saved_plan_reply(saved, authority_scope, reserve).map_err(issue => {
      Journal(issue)
    })
  })
}
