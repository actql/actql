///|
/// Codec DATA from the SAME selected predispatch execution original. This
/// neither observes Allow nor constructs a Request, capture or completion.
pub fn client_keyed_source_response_encoding(
  request : ClientKeyedRequest,
) -> String? {
  guard request.assembly_accounting is Some(state) &&
    !state.closed &&
    !state.growing &&
    !state.identifying &&
    !request.io_complete &&
    request.attempts == 1L &&
    state.selected_request is Some(same) &&
    physical_equal(same, request) &&
    state.native_read_profile is Some(profile) &&
    @publication.publication_contract_name(profile) ==
    "installed_row_source_read" else {
    return None
  }
  Some("typed_json_row_array")
}
