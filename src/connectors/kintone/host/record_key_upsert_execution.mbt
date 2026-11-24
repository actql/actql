///|
pub(all) enum RecordKeyUpsertExecutionIssue {
  MappingMismatch
  SavedRequestMismatch
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
  priv value_wire : String
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
  let value_wire = match
    @catalog.record_write_values_json(
      values,
      Int::min(max_input_bytes, write_limits.max_output_bytes),
      write_limits.max_nodes,
      write_limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Values(issue))
  }
  let proposal : RecordKeyUpsertProposal = {
    self: None,
    mapping,
    values,
    value_wire,
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
pub fn record_key_upsert_proposal_value_wire(
  value : RecordKeyUpsertProposal,
) -> String {
  value.value_wire
}

///|
/// Keep the before state under the original lookup response operation. The
/// caller retains this output when its parser and credential child return.
pub fn prepare_record_key_upsert_proposal_before(
  proposal : RecordKeyUpsertProposal,
  observed : @catalog.RecordLookupObservation,
  values : @catalog.RecordValueLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[RecordKeyUpsertBefore, RecordKeyUpsertExecutionIssue] {
  guard proposal.self is Some(original) && physical_equal(proposal, original) else {
    return Err(MappingMismatch)
  }
  if !@catalog.record_key_lookup_uses_request(observed, proposal.lookup) {
    return Err(Lookup(ForeignRequest))
  }
  match
    prepare_record_key_upsert_before(
      proposal.mapping.original,
      observed,
      values,
      limits,
    ) {
    Ok(before) => Ok(before)
    Err(issue) => Err(Before(issue))
  }
}

///|
fn record_key_upsert_has_original_before(
  proposal : RecordKeyUpsertProposal,
  before : RecordKeyUpsertBefore,
) -> Bool {
  proposal.self is Some(original) &&
  physical_equal(proposal, original) &&
  record_key_upsert_before_matches(
    before,
    proposal.mapping.original,
    before.lookup,
  ) &&
  @catalog.record_key_lookup_uses_request(before.lookup, proposal.lookup)
}

///|
/// Construct the selected mutation from the same retained before observation.
/// The caller checks currentness and owns request finalization and dispatch.
pub fn prepare_record_key_upsert_request_from_before(
  proposal : RecordKeyUpsertProposal,
  before : RecordKeyUpsertBefore,
  write_limits : @catalog.RecordWriteLimits,
  limits : @catalog.RecordMutationLimits,
) -> Result[@catalog.RecordKeyUpsertRequest, RecordKeyUpsertExecutionIssue] {
  guard proposal.self is Some(original) && physical_equal(proposal, original) else {
    return Err(MappingMismatch)
  }
  if !record_key_upsert_has_original_before(proposal, before) {
    return Err(Lookup(ForeignRequest))
  }
  match
    @catalog.prepare_record_key_upsert_request(
      before.lookup,
      proposal.values,
      write_limits,
      limits,
      target=record_key_upsert_before_target(before),
    ) {
    Ok(request) => Ok(request)
    Err(issue) => Err(Request(issue))
  }
}

///|
/// Correlate the exact proposal, lookup and before target with its one native
/// mutation. Equal values or another target from the same page cannot stand
/// in for the originals held by this request.
pub fn record_key_upsert_execution_matches(
  proposal : RecordKeyUpsertProposal,
  before : RecordKeyUpsertBefore,
  request : @catalog.RecordKeyUpsertRequest,
) -> Bool {
  if !record_key_upsert_has_original_before(proposal, before) ||
    !@catalog.record_key_upsert_request_matches_lookup(request, before.lookup) ||
    !physical_equal(
      @catalog.record_key_upsert_request_values(request),
      proposal.values,
    ) {
    return false
  }
  match (before.target, @catalog.record_key_upsert_request_operation(request)) {
    (None, Insert) =>
      @catalog.record_key_upsert_create_request(request) is Some(_)
    (Some(target), Update) => {
      guard @catalog.record_key_upsert_update_request(request) is Some(update) else {
        return false
      }
      let records = @catalog.record_update_request_values(update)
      records.length() == 1 &&
      physical_equal(records[0].0, target) &&
      physical_equal(records[0].1, proposal.values)
    }
    _ => false
  }
}

///|
/// Restore the saved material through the same native constructors. The
/// surrounding owner verifies the saved digests and binds the returned DATA
/// to its original Preview and claim. This path performs no physical lookup
/// or write and cannot change the already selected branch.
pub fn restore_record_key_upsert_execution(
  mapping : RecordKeyUpsertMapping,
  identity : String,
  value_bytes : Bytes,
  target_bytes : Bytes,
  operation : @catalog.RecordKeyUpsertOperation,
  original_body : String,
  max_input_bytes : Int,
  lookup_limits : @catalog.RecordLookupLimits,
  pages : @catalog.RecordPageLimits,
  values : @catalog.RecordValueLimits,
  write_limits : @catalog.RecordWriteLimits,
  request_limits : @catalog.RecordMutationLimits,
  before_limits : @catalog.RecordMutationLimits,
) -> Result[
  (
    RecordKeyUpsertProposal,
    RecordKeyUpsertBefore,
    @catalog.RecordKeyUpsertRequest,
  ),
  RecordKeyUpsertExecutionIssue,
] {
  guard @scalar.admit_utf8_length(
      original_body,
      request_limits.max_output_bytes,
    )
    is Ok(_) else {
    return Err(Request(Request(BudgetExceeded)))
  }
  let proposal = match
    prepare_record_key_upsert_proposal(
      mapping, identity, value_bytes, max_input_bytes, write_limits, lookup_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let observed = match
    @catalog.project_record_key_lookup(
      proposal.lookup,
      200,
      target_bytes,
      pages,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Lookup(issue))
  }
  let before = match
    prepare_record_key_upsert_proposal_before(
      proposal, observed, values, before_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if (before.target is None) != (operation is Insert) {
    return Err(SavedRequestMismatch)
  }
  let request = match
    prepare_record_key_upsert_request_from_before(
      proposal, before, write_limits, request_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let body = match operation {
    Insert => {
      guard @catalog.record_key_upsert_create_request(request) is Some(create) else {
        return Err(SavedRequestMismatch)
      }
      @catalog.record_create_request_body(create)
    }
    Update => {
      guard @catalog.record_key_upsert_update_request(request) is Some(update) else {
        return Err(SavedRequestMismatch)
      }
      @catalog.record_update_request_body(update)
    }
  }
  if body != original_body {
    return Err(SavedRequestMismatch)
  }
  Ok((proposal, before, request))
}
