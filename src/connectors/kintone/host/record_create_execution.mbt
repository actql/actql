///|
pub(all) enum RecordCreateExecutionIssue {
  Catalog(@catalog.RecordCreateJsonIssue)
  MappingMismatch
} derive(Eq, Debug)

///|
/// The original mapped rows and same Form are checked before exposing a raw
/// request. This is not an insertion decision, Preview, credential or claim.
pub fn prepare_record_create_execution_request(
  mapping : RecordCreateMapping,
  bytes : Bytes,
  max_input_bytes : Int,
  write_limits : @catalog.RecordWriteLimits,
  request_limits : @catalog.RecordMutationLimits,
) -> Result[@catalog.RecordCreateRequest, RecordCreateExecutionIssue] {
  if !record_create_mapping_is_original(mapping) {
    return Err(MappingMismatch)
  }
  let request = match
    @catalog.prepare_record_create_request_json(
      mapping.original.catalog,
      bytes,
      max_input_bytes,
      write_limits,
      request_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Catalog(issue))
  }
  if !record_create_mapping_matches_request(mapping, request) {
    return Err(MappingMismatch)
  }
  Ok(request)
}

///|
/// Restore under the same original Mapping with complete saved body equality.
/// This retains protocol DATA only; saved custody/current/claim remain outside.
pub fn restore_record_create_execution_request(
  mapping : RecordCreateMapping,
  bytes : Bytes,
  original_body : String,
  max_input_bytes : Int,
  write_limits : @catalog.RecordWriteLimits,
  request_limits : @catalog.RecordMutationLimits,
) -> Result[@catalog.RecordCreateRequest, RecordCreateExecutionIssue] {
  if !record_create_mapping_is_original(mapping) {
    return Err(MappingMismatch)
  }
  let request = match
    @catalog.restore_record_create_request_json(
      mapping.original.catalog,
      bytes,
      original_body,
      max_input_bytes,
      write_limits,
      request_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Catalog(issue))
  }
  if !record_create_mapping_matches_request(mapping, request) {
    return Err(MappingMismatch)
  }
  Ok(request)
}
