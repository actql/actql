///|
/// Fixed physical request branch DATA, selected from one complete original
/// unique Text-key lookup. It is not approval, current authority or an ACK.
pub(all) enum RecordKeyUpsertOperation {
  Insert
  Update
} derive(Eq, Debug)

///|
pub(all) enum RecordKeyUpsertIssue {
  InvalidLimits
  BudgetExceeded
  ForeignCatalog
  InvalidLookup
  ChangedKey
  MissingRequiredField(String)
  Write(RecordWriteIssue)
  Request(RecordMutationIssue)
} derive(Eq, Debug)

///|
/// Retain the same original lookup and intended values beside the existing
/// typed CREATE or revision-checked UPDATE. No failed branch can choose the
/// other branch, acquire another observation or repeat a physical request.
pub struct RecordKeyUpsertRequest {
  priv mut self : RecordKeyUpsertRequest?
  priv lookup : RecordLookupObservation
  priv intended : RecordWriteValues
  priv operation : RecordKeyUpsertOperation
  priv create : RecordCreateRequest?
  priv update : RecordUpdateRequest?
}

///|
pub fn prepare_record_key_upsert_request(
  lookup : RecordLookupObservation,
  intended : RecordWriteValues,
  write_limits : RecordWriteLimits,
  request_limits : RecordMutationLimits,
  target? : OriginalRecordTarget? = None,
) -> Result[RecordKeyUpsertRequest, RecordKeyUpsertIssue] {
  if !write_json_limits_valid(write_limits) ||
    !mutation_limits_valid(request_limits) {
    return Err(InvalidLimits)
  }
  let original = lookup.request
  let catalog = original.catalog
  if !physical_equal(intended.catalog, catalog) ||
    !physical_equal(lookup.page.catalog, catalog) {
    return Err(ForeignCatalog)
  }
  if original.key.length() > request_limits.max_identity_bytes ||
    original.value.length() >
    request_limits.max_identity_bytes - original.key.length() {
    return Err(BudgetExceeded)
  }
  guard require_form_unique_key(catalog, original.key) is Ok(metadata) &&
    metadata.native_type == "SINGLE_LINE_TEXT" &&
    !original.value.is_empty() &&
    record_write_field_contract(catalog, original.key) is Some(contract) &&
    @admitted.checked_text_value(original.value, contract) is Some(key_value) else {
    return Err(InvalidLookup)
  }
  let mut key_present = false
  let mut work = request_limits.max_comparison_work
  for (name, checked) in intended.originals {
    for text in [name, original.key] {
      if text.length() > work {
        return Err(BudgetExceeded)
      }
      work -= text.length()
    }
    if name == original.key {
      guard checked.value is @admitted.Text(value) else {
        return Err(ChangedKey)
      }
      for text in [value, original.value] {
        if text.length() > work {
          return Err(BudgetExceeded)
        }
        work -= text.length()
      }
      if value != original.value {
        return Err(ChangedKey)
      }
      key_present = true
    }
  }
  let count = lookup.page.records.length()
  guard count <= 1 &&
    lookup.page.total_count is Some(total) &&
    record_lookup_count_is(total, count) else {
    return Err(InvalidLookup)
  }
  if count == 0 && target is Some(_) {
    return Err(InvalidLookup)
  }
  let (operation, create, update) = if count == 1 {
    let target = match target {
      Some(original) => {
        if !physical_equal(original.page, lookup.page) ||
          !physical_equal(original.record, lookup.page.records[0]) {
          return Err(InvalidLookup)
        }
        original
      }
      None =>
        match
          prepare_original_record_target(
            lookup.page,
            0,
            request_limits.max_identity_bytes,
          ) {
          Ok(value) => value
          Err(issue) => return Err(Request(issue))
        }
    }
    let request = match
      prepare_record_update_request([(target, intended)], request_limits) {
      Ok(value) => value
      Err(issue) => return Err(Request(issue))
    }
    (Update, None, Some(request))
  } else {
    let cells = intended.originals.copy()
    if !key_present {
      cells.push((original.key, key_value))
    }
    let required = match
      record_create_required_fields(
        catalog,
        write_limits.max_fields,
        request_limits.max_comparison_work,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Write(issue))
    }
    for name in required {
      if !cells.any(cell => cell.0 == name) {
        return Err(MissingRequiredField(name))
      }
    }
    let values = match
      prepare_record_write_values(catalog, cells, write_limits) {
      Ok(value) => value
      Err(issue) => return Err(Write(issue))
    }
    let request = match
      prepare_record_create_request(catalog, [values], request_limits) {
      Ok(value) => value
      Err(issue) => return Err(Request(issue))
    }
    (Insert, Some(request), None)
  }
  let result : RecordKeyUpsertRequest = {
    self: None,
    lookup,
    intended,
    operation,
    create,
    update,
  }
  result.self = Some(result)
  Ok(result)
}

///|
pub fn record_key_upsert_request_is_original(
  value : RecordKeyUpsertRequest,
) -> Bool {
  value.self is Some(original) && physical_equal(original, value)
}

///|
pub fn record_key_upsert_request_matches_lookup(
  value : RecordKeyUpsertRequest,
  lookup : RecordLookupObservation,
) -> Bool {
  record_key_upsert_request_is_original(value) &&
  physical_equal(value.lookup, lookup)
}

///|
pub fn record_key_upsert_request_operation(
  value : RecordKeyUpsertRequest,
) -> RecordKeyUpsertOperation {
  value.operation
}

///|
pub fn record_key_upsert_request_values(
  value : RecordKeyUpsertRequest,
) -> RecordWriteValues {
  value.intended
}

///|
pub fn record_key_upsert_create_request(
  value : RecordKeyUpsertRequest,
) -> RecordCreateRequest? {
  if record_key_upsert_request_is_original(value) {
    value.create
  } else {
    None
  }
}

///|
pub fn record_key_upsert_update_request(
  value : RecordKeyUpsertRequest,
) -> RecordUpdateRequest? {
  if record_key_upsert_request_is_original(value) {
    value.update
  } else {
    None
  }
}
