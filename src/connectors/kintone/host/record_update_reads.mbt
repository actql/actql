///|
/// Reuse the existing complete native Form comparison. This is a DATA fence,
/// not a current Account decision, credential use or physical read.
pub fn record_update_mapping_recheck_form(
  mapping : RecordUpdateMapping,
  bytes : Bytes,
  limits : @catalog.FormFieldLimits,
) -> Result[Unit, RecordUpdateExecutionIssue] {
  if !record_update_mapping_is_original(mapping) {
    return Err(MappingMismatch)
  }
  match
    @catalog.recheck_original_record_form(
      mapping.original.catalog,
      bytes,
      limits,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Request(issue))
  }
}

///|
pub fn record_update_proposal_app_id(proposal : RecordUpdateProposal) -> String {
  proposal.mapping.original.catalog.app_id
}

///|
/// One exact API-id lookup with the complete original before-field inventory.
/// A Record Number, guessed revision or caller query never supplies this body.
pub fn record_update_target_read_body(
  proposal : RecordUpdateProposal,
  max_fields : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RecordUpdateExecutionIssue] {
  if !record_update_proposal_matches_mapping(proposal, proposal.mapping) {
    return Err(MappingMismatch)
  }
  if max_fields <= 0 || max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let names = proposal.mapping.before_fields
  if names.length() > max_fields || names.length() > 998 {
    return Err(Request(@catalog.BudgetExceeded))
  }
  // Ids are already bounded digit Strings. Check the query size before its
  // concatenation; Encoder still bounds the complete request and UTF8 names.
  let prefix = "$id in ("
  let suffix = ") order by $id asc limit 1"
  if prefix.length() + suffix.length() > max_bytes ||
    proposal.identity.length() > max_bytes - prefix.length() - suffix.length() {
    return Err(Request(@catalog.BudgetExceeded))
  }
  let query = prefix + proposal.identity + suffix
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(Request(@catalog.BudgetExceeded))
  }
  try {
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "app")
    @encode.string_value(writer, proposal.mapping.original.catalog.app_id)
    @encode.ordered_key(writer, "fields")
    @encode.begin_array(writer)
    @encode.string_value(writer, "$id")
    @encode.string_value(writer, "$revision")
    for name in names {
      @encode.string_value(writer, name)
    }
    @encode.end_array(writer)
    @encode.ordered_key(writer, "query")
    @encode.string_value(writer, query)
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(Request(@catalog.BudgetExceeded))
    }
  }
}
