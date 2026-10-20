///|
/// Validate the same original Sealed payload responsibility against a binding
/// borrowed from the original Done commit view. This reads no physical Store,
/// issues no publication/output, and never acknowledges or starts an operation.
#export_name("actql_publication_commit_export_validate_payload_binding")
pub fn validate_publication_commit_payload_binding(
  nonce : Int64,
  publication : Int,
  payload_record : Int,
  current_configuration : Int,
  result : Int,
  binding_index : Int,
) -> Int {
  if selected(nonce) is Some(value) &&
    value.payload_records.get(payload_record) is Some(payload) &&
    payload.source is SavedResult(parent, saved) {
    guard saved_result_export_parent(value, publication)
      is Some((actual, original)) &&
      physical_equal(parent, actual) &&
      physical_equal(saved, original) &&
      saved.source is Some(source) &&
      saved.owner is Some(owner) &&
      saved.view is Some(view) &&
      value.run_configurations.get(current_configuration) is Some(current) else {
      return -2
    }
    match saved_payload_binding(value, payload, current_configuration) {
      Ok(_) => ()
      Err(code) => return code
    }
    match
      @local_run.local_sdk_saved_result_coordinates(
        source,
        current.account,
        owner,
        view,
        saved.result_name,
      ) {
      Ok(ordinals) if ordinals == (result, binding_index) => return 0
      _ => return -32
    }
  }
  guard selected(nonce) is Some(value) &&
    value.publications.get(publication) is Some(parent) &&
    value.payload_records.get(payload_record) is Some(payload) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if payload.closing {
    return -5
  }
  let (commit, view) = match
    publication_commit_export_view(value, parent, current.account) {
    Ok(original) => original
    Err(code) => return code
  }
  if result < 0 || result >= parent.publications.length() || binding_index < 0 {
    return -3
  }
  guard payload.confirmed &&
    payload.record is Some(original) &&
    @payload.publication_payload_record_state(original) is Sealed &&
    @payload.publication_payload_record_generation(original) is Some(_) &&
    @payload.publication_payload_record_ownership(original) is Some(_) &&
    @payload.publication_payload_record_opaque_ownership(original) is None &&
    value.payload_requests.get(payload.request)
    is Some(
      {
        publication: original_parent,
        index: original_result,
        closing: false,
        ..
      }
    ) &&
    original_parent == publication &&
    original_result == result &&
    payload_record_current(value, payload, current_configuration) &&
    value.publication_preflights.get(parent.preflight)
    is Some({ closing: false, preflight: Some(preflight), .. }) else {
    return -32
  }
  let binding = match commit.view_binding(view, binding_index) {
    Ok(binding) => binding
    Err(_) => return -32
  }
  match
    @local_run.validate_local_preflight_commit_binding(
      preflight,
      result,
      parent.publications[result],
      original,
      current.account,
      binding,
      65536,
      4096,
      64,
    ) {
    Ok(_) => 0
    Err(_) => -32
  }
}
