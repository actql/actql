///|
/// Validate the same original Sealed payload responsibility against a binding
/// borrowed from the original Done commit view. This reads no physical Store,
/// issues no publication/output, and never acknowledges or starts an operation.
pub fn validate_publication_commit_payload_binding(
  nonce : Int64,
  publication : Int,
  payload_record : Int,
  current_configuration : Int,
  result : Int,
  binding_index : Int,
) -> Int {
  validate_original_publication_payload_binding(
    nonce, publication, payload_record, current_configuration, result, binding_index,
  )
}

///|
/// Validate binding and snapshot on the same selected Saved reader.
/// The observation is a separate sealed input, not a binding coordinate.
pub fn validate_saved_result_reader_facts(
  nonce : Int64,
  publication : Int,
  payload_record : Int,
  current_configuration : Int,
  result : Int,
  binding_index : Int,
  observation : Int,
) -> Int {
  guard result >= 0 &&
    result < 8 &&
    binding_index >= 0 &&
    binding_index < 8 &&
    selected(nonce) is Some(value) &&
    value.payload_records.get(payload_record) is Some(payload) &&
    payload.source is SavedResult(_, saved) else {
    return -2
  }
  let binding = validate_original_publication_payload_binding(
    nonce, publication, payload_record, current_configuration, result, binding_index,
  )
  if binding != 0 {
    return binding
  }
  let same_reader_census = saved_result_export_parent(value, publication)
    is Some((parent, original)) &&
    physical_equal(saved, original) &&
    parent.kind == INCREMENTAL_SAVED_RESULT_KIND
  let snapshot = validate_original_payload_record_snapshot(
    nonce,
    payload_record,
    observation,
    current_configuration,
    same_reader_census~,
  )
  // Keep the binding, snapshot and first physical refusal distinguishable.
  if snapshot == 0 || snapshot == -41 {
    snapshot
  } else {
    snapshot - 1024
  }
}

///|
fn validate_original_publication_payload_binding(
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
  let selected_view = match parent.file {
    Some(file) =>
      checked_publication_commit_view(value, parent, () => {
        sdk_file_observed_payload_current(
          value, publication, parent, file, current,
        )
      })
    None => publication_commit_export_view(value, parent, current.account)
  }
  let (commit, view) = match selected_view {
    Ok(original) => original
    Err(code) => return code
  }
  if result < 0 ||
    result >= publication_result_count(parent) ||
    binding_index < 0 {
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
    value.publication_preflights.get(parent.preflight)
    is Some({ closing: false, .. } as preflight) else {
    return -32
  }
  match observed_live_payload_current(value, payload, current_configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  let binding = match commit.view_binding(view, binding_index) {
    Ok(binding) => binding
    Err(_) => return -32
  }
  match preflight.origin {
    ComputePublicationPreflight({ prepared: Some(prepared), .. }) =>
      if @local_run.validate_local_preflight_commit_binding(
          prepared,
          result,
          parent.publications[result],
          original,
          current.account,
          binding,
          65536,
          4096,
          64,
        )
        is Ok(_) {
        0
      } else {
        -32
      }
    FilePublicationPreflight(file) => {
      let recheck = () => {
        observed_live_payload_current(value, payload, current_configuration).map_err(code => {
            @local_run.LocalCapturedTaskPublicationPreflightIssue::Binding(
              @local_run.LocalRunPublicationBindingIssue::Current(
                @host.ClientLocalAdoptedCurrentIssue::Physical(code),
              ),
            )
          },
        )
      }
      let expected = with_sdk_file_payload_result_current(
        parent,
        file,
        result,
        recheck,
        (prepared, row, recheck) => {
          @local_run.issue_local_captured_task_sealed_result_binding(
            prepared,
            result,
            row,
            original,
            {
              max_results: value.workspace_slots,
              max_wire_bytes: 65536,
              max_nodes: 4096,
              max_depth: 64,
            },
            recheck,
          )
        },
      )
      match expected {
        Ok(value) => if same_sdk_file_binding(value, binding) { 0 } else { -35 }
        Err(code) => code
      }
    }
    SavedEffectPublicationPreflight({ prepared: Some(prepared), .. }) =>
      match prepared.bind_sealed_payload(result, original) {
        Ok(expected) if same_sdk_file_binding(expected, binding) =>
          if payload_record_current(value, payload, current_configuration) {
            0
          } else {
            -32
          }
        _ => -35
      }
    _ => -32
  }
}
