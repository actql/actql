///|
// Only the adopted Mock Project may derive the captured File selector from
// the original fixed read metadata. The actual File Plan or the saved Task
// and finite Run originals are checked by the respective caller.
fn sdk_mock_file_read_selection_needed(
  configuration : StoredRunConfiguration,
  sdk : StoredSDKRunConfiguration,
) -> Bool {
  let (_, connection, _, _, _, _, _) = @publication.local_sdk_result_read_selection_parameters(
    sdk.read,
  )
  configuration.mock_project is Some(_) &&
  configuration.local_project is None &&
  connection == "local" &&
  @publication.local_sdk_result_read_selection_uses_installed_result_authority(
    sdk.read,
  ) &&
  !@publication.local_sdk_result_read_selection_uses_accepted_run_policy(
    sdk.read,
  )
}

///|
// A composed Local Model can derive the accepted-Run selector only from the
// adopted Local Project and its exact installed Model configuration.
fn sdk_local_model_file_read_selection_needed(
  configuration : StoredRunConfiguration,
  sdk : StoredSDKRunConfiguration,
) -> Bool {
  let (_, connection, _, _, _, _, _) = @publication.local_sdk_result_read_selection_parameters(
    sdk.read,
  )
  configuration.local_project is Some(_) &&
  configuration.mock_project is None &&
  sdk.portable_model is Some(_) &&
  connection == configuration.tuple.connection &&
  @publication.local_sdk_result_read_selection_uses_installed_result_authority(
    sdk.read,
  ) &&
  !@publication.local_sdk_result_read_selection_uses_accepted_run_policy(
    sdk.read,
  )
}

///|
fn sdk_accepted_file_read_selection_capacity(
  sdk : StoredSDKRunConfiguration,
) -> (Int64, Int64)? {
  // Both canonical wires have the same bounded literals and adopted profile.
  // The accepted-policy flag replaces the singleton fixed SHA-256 CID array.
  let (_, connection, _, _, _, _, _) = @publication.local_sdk_result_read_selection_parameters(
    sdk.read,
  )
  let units = @publication.local_sdk_result_read_selection_wire(sdk.read).length()
  // A non-ASCII control connection can take three octets per UTF-16 unit.
  let bytes = if connection == "local" { units } else { 3 * units }
  guard @encode.text_writer_construction_inventory(bytes, 32, 4) is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  guard @execution.preparation_representation_cost({
      record_headers: 5L,
      reference_slots: 10L,
      scalar_words: 4L,
      owned_utf16_units: bytes.to_int64() + 71L,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + hash.record_headers + 12L,
      reference_slots: writer.reference_slots + hash.reference_slots + 20L,
      scalar_words: writer.scalar_words + hash.scalar_words + 16L,
      owned_utf16_units: writer.owned_utf16_units +
      hash.owned_utf16_units +
      135L,
      owned_wire_bytes: hash.owned_wire_bytes + 4L * bytes.to_int64(),
    })
    is Some(scratch) else {
    return None
  }
  Some((retained, scratch))
}

///|
fn issue_sdk_accepted_file_read_selection(
  configuration : StoredRunConfiguration,
  sdk : StoredSDKRunConfiguration,
) -> Result[@publication.LocalSDKResultReadSelection, Int] {
  guard sdk_mock_file_read_selection_needed(configuration, sdk) ||
    sdk_local_model_file_read_selection_needed(configuration, sdk) else {
    return Err(-32)
  }
  let (_, connection, _, _, _, _, _) = @publication.local_sdk_result_read_selection_parameters(
    sdk.read,
  )
  @publication.issue_local_sdk_result_read_selection(
    @host.client_local_run_policy_profile_cid(sdk.profile),
    @publication.local_sdk_result_read_selection_data_policy_cid(sdk.read),
    connection~,
    accepted_run_policy=true,
  ).map_err(_ => -32)
}
