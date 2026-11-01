///|
// Shared original-page projection for UPDATE and DELETE. Callers first check
// their selected Mapping, complete columns and the same explicit limits.
fn record_target_before_limits_valid(
  limits : @catalog.RecordMutationLimits,
) -> Bool {
  limits.max_records > 0 &&
  limits.max_records <= 100 &&
  limits.max_identity_bytes > 0 &&
  limits.max_comparison_work > 0 &&
  limits.max_output_bytes > 0 &&
  limits.max_output_nodes > 0 &&
  limits.max_output_depth > 0
}

///|
fn prepare_record_target_before(
  original : RecordDeclaration,
  target : @catalog.OriginalRecordTarget,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[(@catalog.CheckedRecordPage, String, String), RecordReadIssue] {
  let page = @catalog.original_record_target_page(target)
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
    @catalog.project_checked_record_page(page, original.settings, values) {
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
    // Preserve the admitted column order. The ordinary object writer checks
    // keys; it does not invent canonical field order. CheckedValue preserves
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
  Ok((checked, before, version))
}
