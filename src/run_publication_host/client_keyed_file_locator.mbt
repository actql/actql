///|
/// This continuation borrows the original listing under its original lookup
/// reservation. Its fixed control fields fit the lookup's 4096-byte control
/// allowance; it never allocates a per-file map or another row representation.
struct ClientKeyedFileLocator {
  lookup : ClientKeyedLookupInput
  request : ClientKeyedRequest
  cursor : @query.CapturedFileLocator
}

///|
fn client_keyed_file_locator_available(
  lookup : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
) -> Bool {
  !lookup.closed &&
  lookup.completed is None &&
  lookup.copying is None &&
  lookup.preparation is None &&
  lookup.selected_request is Some(selected) &&
  physical_equal(selected, request) &&
  physical_equal(request.left, lookup.left) &&
  lookup.selected_index == Some(-1) &&
  request.attempts == 0L &&
  !request.io_complete &&
  lookup.left.lookup_issue is None &&
  client_keyed_request_matches_acquisition(request, lookup.left.acquisition)
}

///|
pub fn start_client_keyed_file_locator(
  lookup : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
  source : @query.CapturedInputSource,
  read : @execution.SuppliedRelationRead,
) -> Result[ClientKeyedFileLocator, ClientKeyedRequestIssue] {
  if !client_keyed_file_locator_available(lookup, request) ||
    !client_keyed_left_source_matches(lookup.left, source) {
    return Err(Assembly("invalid_file_locator_request"))
  }
  if !charge_keyed_lookup_input_work(lookup, 1) {
    return Err(LookupLimit("work"))
  }
  guard @acquisition.keyed_row_request_field(request.request, "resource")
    is Some(resource) &&
    resource.value is @values.Reference(reference) &&
    @acquisition.keyed_row_request_field(request.request, "version")
    is Some(version) &&
    version.value is @values.Text(version) &&
    @query.start_captured_file_locator(
      source,
      read,
      reference,
      version,
      lookup.max_bytes,
    )
    is Some(cursor) else {
    return Err(Assembly("file_locator_unavailable"))
  }
  Ok({ lookup, request, cursor, })
}

///|
pub fn start_client_composed_keyed_file_locator(
  lookup : ClientKeyedLookupInput,
  request : ClientKeyedRequest,
  sources : Array[@query.CapturedInputSource],
  reads : Array[@execution.SuppliedRelationRead?],
) -> Result[ClientKeyedFileLocator, ClientKeyedRequestIssue] {
  guard lookup.left.composed is Some(original) &&
    client_keyed_file_locator_available(lookup, request) &&
    sources.length() == original.sources.length() && reads.length() == sources.length() &&
    client_composed_keyed_original_current(original) else {
    return Err(Assembly("invalid_file_locator_request"))
  }
  let mut selected = None
  for index, source in sources {
    if !physical_equal(source, original.sources[index]) { return Err(ForeignLeft) }
    guard reads[index] is Some(read) else { continue }
    match start_client_keyed_file_locator(lookup, request, source, read) {
      Ok(locator) => {
        if selected is Some(previous) {
          cancel_client_keyed_file_locator(previous)
          cancel_client_keyed_file_locator(locator)
          return Err(Assembly("ambiguous_file_locator"))
        }
        selected = Some(locator)
      }
      Err(Assembly("file_locator_unavailable")) => ()
      Err(issue) => return Err(issue)
    }
  }
  match selected {
    Some(value) => Ok(value)
    None => Err(Assembly("file_locator_unavailable"))
  }
}

///|
pub fn cancel_client_keyed_file_locator(
  cursor : ClientKeyedFileLocator,
) -> Unit {
  @query.cancel_captured_file_locator(cursor.cursor)
}

///|
/// Charge the same original allowance before every bounded metadata step.
/// Cleanup/cancellation neither sends nor renews that allowance.
pub fn advance_client_keyed_file_locator(
  cursor : ClientKeyedFileLocator,
) -> Result[String?, ClientKeyedRequestIssue] {
  if !client_keyed_file_locator_available(cursor.lookup, cursor.request) {
    cancel_client_keyed_file_locator(cursor)
    return Err(Assembly("invalid_file_locator_request"))
  }
  if !charge_keyed_lookup_input_work(cursor.lookup, 1) {
    cancel_client_keyed_file_locator(cursor)
    return Err(LookupLimit("work"))
  }
  match @query.advance_captured_file_locator(cursor.cursor) {
    CapturedFileLocatorContinue => Ok(None)
    CapturedFileLocatorComplete(path) => Ok(Some(path))
    CapturedFileLocatorFailed => {
      keyed_lookup_fail(
        cursor.lookup.left,
        Assembly("file_locator_unavailable"),
      )
      |> ignore
      Err(Assembly("file_locator_unavailable"))
    }
  }
}
