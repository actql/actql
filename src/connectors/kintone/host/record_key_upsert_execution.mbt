///|
pub(all) enum RecordKeyUpsertExecutionIssue {
  MappingMismatch
  Values(@catalog.RecordWriteJsonIssue)
  Lookup(@catalog.RecordLookupIssue)
  Before(RecordReadIssue)
  Request(@catalog.RecordKeyUpsertIssue)
}

///|
/// The selected Mapping, intended cells and exact original lookup request
/// constitute the proposal. They carry no permission to read or write.
pub struct RecordKeyUpsertProposal {
  priv mut self : RecordKeyUpsertProposal?
  priv mapping : RecordKeyUpsertMapping
  priv values : @catalog.RecordWriteValues
  priv lookup : @catalog.RecordLookupRequest
}

///|
fn check_record_key_upsert_written_fields(
  fields : Array[@rows.RowMappingSource],
  values : @catalog.RecordWriteValues,
  max_work : Int,
) -> Result[Unit, RecordKeyUpsertExecutionIssue] {
  if max_work <= 0 {
    return Err(Lookup(InvalidLimits))
  }
  if fields.length() > max_work {
    return Err(Lookup(BudgetExceeded))
  }
  let mut work = max_work - fields.length()
  let mut required = 0
  for field in fields {
    if field.null_behavior != "omit" {
      required += 1
    }
  }
  for index in 0..<=fields.length() {
    guard @catalog.record_write_values_field_at(values, index)
      is Some((name, is_null)) else {
      break
    }
    if index == fields.length() {
      return Err(MappingMismatch)
    }
    let mut matched = false
    for field in fields {
      if name.length() >= work || field.target.length() >= work - name.length() {
        return Err(Lookup(BudgetExceeded))
      }
      work -= 1 + name.length() + field.target.length()
      if field.target == name {
        if is_null && field.null_behavior != "write_null" {
          return Err(MappingMismatch)
        }
        if field.null_behavior != "omit" {
          required -= 1
        }
        matched = true
        break
      }
    }
    if !matched {
      return Err(MappingMismatch)
    }
  }
  if required == 0 {
    Ok(())
  } else {
    Err(MappingMismatch)
  }
}

///|
/// Validate the intended cells before constructing the original lookup. A
/// write outside the selected Mapping or an omitted mandatory cell refuses.
pub fn prepare_record_key_upsert_proposal(
  mapping : RecordKeyUpsertMapping,
  identity : String,
  bytes : Bytes,
  max_input_bytes : Int,
  write_limits : @catalog.RecordWriteLimits,
  lookup_limits : @catalog.RecordLookupLimits,
) -> Result[RecordKeyUpsertProposal, RecordKeyUpsertExecutionIssue] {
  guard mapping.self is Some(original) && physical_equal(mapping, original) else {
    return Err(MappingMismatch)
  }
  let catalog = mapping.original.catalog
  let values = match
    @catalog.prepare_record_write_values_json(
      catalog, bytes, max_input_bytes, write_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Values(issue))
  }
  match
    check_record_key_upsert_written_fields(
      mapping.fields,
      values,
      lookup_limits.max_comparison_work,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let lookup = match
    @catalog.prepare_record_text_key_lookup(
      catalog,
      mapping.key,
      identity,
      mapping.original.names,
      lookup_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Lookup(issue))
  }
  let proposal : RecordKeyUpsertProposal = {
    self: None,
    mapping,
    values,
    lookup,
  }
  proposal.self = Some(proposal)
  Ok(proposal)
}

///|
pub fn record_key_upsert_proposal_lookup(
  value : RecordKeyUpsertProposal,
) -> @catalog.RecordLookupRequest {
  value.lookup
}

///|
/// The same proposal must own the exact lookup whose observed result selects
/// CREATE or revision-checked UPDATE. The caller owns physical response custody.
pub fn prepare_record_key_upsert_observed_request(
  proposal : RecordKeyUpsertProposal,
  observed : @catalog.RecordLookupObservation,
  values : @catalog.RecordValueLimits,
  write_limits : @catalog.RecordWriteLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[
  (RecordKeyUpsertBefore, @catalog.RecordKeyUpsertRequest),
  RecordKeyUpsertExecutionIssue,
] {
  guard proposal.self is Some(original) && physical_equal(proposal, original) else {
    return Err(MappingMismatch)
  }
  if !@catalog.record_key_lookup_uses_request(observed, proposal.lookup) {
    return Err(Lookup(ForeignRequest))
  }
  let before = match
    prepare_record_key_upsert_before(
      proposal.mapping.original,
      observed,
      values,
      limits,
    ) {
    Ok(before) => before
    Err(issue) => return Err(Before(issue))
  }
  match
    @catalog.prepare_record_key_upsert_request(
      observed,
      proposal.values,
      write_limits,
      limits,
      target=record_key_upsert_before_target(before),
    ) {
    Ok(request) => Ok((before, request))
    Err(issue) => Err(Request(issue))
  }
}
