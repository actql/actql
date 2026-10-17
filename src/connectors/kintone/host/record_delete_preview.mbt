///|
/// Checked before DATA under the same original Mapping/Form and target. This
/// is neither an authenticated observation, current permission nor an Effect
/// outcome; the original Site/capture must establish and retain those facts.
pub struct RecordDeletePreview {
  priv mapping : RecordDeleteMapping
  priv target : @catalog.OriginalRecordTarget
  priv checked : @catalog.CheckedRecordPage
  priv before_wire : String
  priv version_cid : String
}

///|
pub fn prepare_record_delete_preview(
  mapping : RecordDeleteMapping,
  target : @catalog.OriginalRecordTarget,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[RecordDeletePreview, RecordReadIssue] {
  if limits.max_records <= 0 || limits.max_records > 100 ||
    limits.max_identity_bytes <= 0 || limits.max_comparison_work <= 0 ||
    limits.max_output_bytes <= 0 || limits.max_output_nodes <= 0 ||
    limits.max_output_depth <= 0 {
    return Err(InvalidLimits)
  }
  let page = @catalog.original_record_target_page(target)
  if !record_delete_mapping_page_matches(mapping, page) {
    return Err(ForeignDeclaration)
  }
  let identity = @catalog.original_record_target_id(target)
  let revision = @catalog.original_record_target_revision(target)
  let mut remaining = limits.max_identity_bytes
  for text in [page.app_id, identity, revision] {
    if text.length() > remaining {
      return Err(Catalog(@catalog.BudgetExceeded))
    }
    remaining -= text.length()
  }
  let records = @catalog.record_page_records(page)
  let mut work = limits.max_comparison_work
  let mut selected = None
  for index, record in records {
    for text in [identity, record.record_id] {
      if text.length() > work {
        return Err(Catalog(@catalog.BudgetExceeded))
      }
      work -= text.length()
    }
    if identity == record.record_id {
      selected = Some(index)
      break
    }
  }
  guard selected is Some(index) else { return Err(InvalidRequest) }
  let checked = match
    @catalog.project_checked_record_page(page, mapping.original.settings, values) {
    Ok(value) => value
    Err(issue) => return Err(Catalog(issue))
  }
  let columns = @catalog.checked_record_columns(checked)
  let rows = @catalog.checked_record_rows(checked)
  guard rows.get(index) is Some(row) && row.length() == columns.length() else {
    return Err(InvalidRequest)
  }
  let writer = @encode.writer(
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  ) catch {
    issue => return Err(RequestEncoding(issue))
  }
  let before = try {
    // The existing writer orders original keys, while CheckedValue preserves
    // Decimal/date/array meaning without JSON/Double reconstruction.
    @encode.begin_object(writer)
    for column, name in columns {
      @encode.key(writer, name)
      @admitted.emit_checked_wire_value(row[column], writer)
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    issue => {
      @encode.cancel_writer(writer)
      return Err(RequestEncoding(issue))
    }
  }
  let hash = @encode.hashing_writer(
    limits.max_output_bytes,
    limits.max_output_nodes,
    limits.max_output_depth,
  ) catch {
    issue => return Err(RequestEncoding(issue))
  }
  let version = try {
    // A deterministic version-guard fingerprint of exact original strings,
    // not a new identity issuer or proof of a provider action/current state.
    @encode.begin_array(hash)
    for text in [page.app_id, identity, revision] {
      @encode.string_value(hash, text)
    }
    @encode.end_array(hash)
    "sha256:" + @encode.finish_hash(hash)
  } catch {
    issue => {
      @encode.cancel_writer(hash)
      return Err(RequestEncoding(issue))
    }
  }
  Ok({ mapping, target, checked, before_wire: before, version_cid: version })
}

///|
pub fn record_delete_preview_identity(view : RecordDeletePreview) -> String {
  @catalog.original_record_target_id(view.target)
}

///|
pub fn record_delete_preview_version_cid(view : RecordDeletePreview) -> String {
  view.version_cid
}

///|
pub fn record_delete_preview_before_wire(view : RecordDeletePreview) -> String {
  view.before_wire
}

///|
/// Correspondence only: the same original Mapping and target must remain held.
pub fn record_delete_preview_matches(
  view : RecordDeletePreview,
  mapping : RecordDeleteMapping,
  target : @catalog.OriginalRecordTarget,
) -> Bool {
  physical_equal(view.mapping, mapping) && physical_equal(view.target, target) &&
  physical_equal(@catalog.checked_record_original(view.checked),
    @catalog.original_record_target_page(target))
}
