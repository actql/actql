///|
/// Provider before DATA for the same complete unique-key lookup. This is not
/// a Mapping, sealed Preview, absence grant, current permission or claim.
pub struct RecordKeyUpsertBefore {
  priv mut self : RecordKeyUpsertBefore?
  priv original : RecordDeclaration
  priv lookup : @catalog.RecordLookupObservation
  priv checked : @catalog.CheckedRecordPage
  priv target : @catalog.OriginalRecordTarget?
  priv before_wire : String?
  priv version_cid : String?
}

///|
pub fn prepare_record_key_upsert_before(
  original : RecordDeclaration,
  lookup : @catalog.RecordLookupObservation,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[RecordKeyUpsertBefore, RecordReadIssue] {
  if !record_target_before_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  let page = @catalog.record_key_lookup_page(lookup)
  let names = @catalog.record_page_columns(page)
  if !@catalog.record_page_uses_catalog(page, original.catalog) ||
    names.length() != original.names.length() {
    return Err(ForeignDeclaration)
  }
  // Complete original selection, independently of escaped mutable View fields.
  // Preserve observed field order; do not impose another ordering on a lookup.
  let mut work = limits.max_comparison_work
  for name in names {
    let mut matched = false
    for expected in original.names {
      for text in [name, expected] {
        if text.length() > work {
          return Err(Catalog(@catalog.BudgetExceeded))
        }
        work -= text.length()
      }
      if name == expected {
        matched = true
        break
      }
    }
    if !matched {
      return Err(ForeignDeclaration)
    }
  }
  let mut identity_bytes = limits.max_identity_bytes
  for
    text in [
      page.app_id,
      @catalog.record_key_lookup_key(lookup),
      @catalog.record_key_lookup_identity(lookup),
    ] {
    if text.length() > identity_bytes {
      return Err(Catalog(@catalog.BudgetExceeded))
    }
    let bytes = @utf8.encode(text).length()
    if bytes > identity_bytes {
      return Err(Catalog(@catalog.BudgetExceeded))
    }
    identity_bytes -= bytes
  }
  let records = @catalog.record_page_records(page)
  guard records.length() <= 1 else { return Err(InvalidRequest) }
  let (checked, target, before_wire, version_cid) = if records.is_empty() {
    let checked = match
      @catalog.project_checked_record_page(page, original.settings, values) {
      Ok(value) => value
      Err(issue) => return Err(Catalog(issue))
    }
    (checked, None, None, None)
  } else {
    let target = match
      @catalog.prepare_original_record_target(
        page,
        0,
        limits.max_identity_bytes,
      ) {
      Ok(value) => value
      Err(_) => return Err(InvalidRequest)
    }
    let (checked, before, version) = match
      prepare_record_target_before(original, target, values, {
        ..limits,
        max_comparison_work: work,
      }) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    (checked, Some(target), Some(before), Some(version))
  }
  let result : RecordKeyUpsertBefore = {
    self: None,
    original,
    lookup,
    checked,
    target,
    before_wire,
    version_cid,
  }
  result.self = Some(result)
  Ok(result)
}

///|
pub fn record_key_upsert_before_key(value : RecordKeyUpsertBefore) -> String {
  @catalog.record_key_lookup_key(value.lookup)
}

///|
pub fn record_key_upsert_before_identity(
  value : RecordKeyUpsertBefore,
) -> String {
  @catalog.record_key_lookup_identity(value.lookup)
}

///|
pub fn record_key_upsert_before_target(
  value : RecordKeyUpsertBefore,
) -> @catalog.OriginalRecordTarget? {
  value.target
}

///|
pub fn record_key_upsert_before_wire(value : RecordKeyUpsertBefore) -> String? {
  value.before_wire
}

///|
pub fn record_key_upsert_before_version_cid(
  value : RecordKeyUpsertBefore,
) -> String? {
  value.version_cid
}

///|
pub fn record_key_upsert_before_matches(
  value : RecordKeyUpsertBefore,
  original : RecordDeclaration,
  lookup : @catalog.RecordLookupObservation,
) -> Bool {
  value.self is Some(issued) &&
  physical_equal(issued, value) &&
  physical_equal(value.original, original) &&
  physical_equal(value.lookup, lookup) &&
  physical_equal(
    @catalog.checked_record_original(value.checked),
    @catalog.record_key_lookup_page(lookup),
  )
}
