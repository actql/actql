///|
// Row-level dependency for the finite successor, not an alternative public
// operation lookup. Its caller must still validate all installation rows and
// commit/restore the successor in the existing journal transaction. In
// particular, this does not change the ordinary current-pair reader.
//
// The installer selects runtime_file from this adoption. historical is only
// manifest metadata: Common accepts exactly the retained old109/a3b proof,
// never this caller's source label, a replacement asset body or permission.
// This is exercised by fresh row-reader WBs. Keep it private until the
// successor's complete transaction/selection supplier is installed; exporting
// an ordinary history bypass merely to silence a warning would be incorrect.
#warnings("-unused_value")
fn read_local_historical_runtime_upgrade_original(
  host : NativeLocalHostConnection,
  row : @sqlite.NativeJournalValue,
  principal : String,
  connection : String,
  runtime_file : String,
  historical : @host.ClientNativeLocalRuntime,
) -> Result[NativeLocalPolicyUpgradeOriginal, NativeClientRunJournalIssue] {
  let scope = match
    host.authority_scope_cid(principal, connection, host.epoch.crypto) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let current = () => {
    local_policy_upgrade_current(
      host,
      host.epoch.crypto,
      principal,
      connection,
      scope,
      false,
    )
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  let selected = match local_run_policy_selected(host, runtime_file) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let wire = @utf8.decode(selected.body) catch { _ => return Err(CustodyLost) }
  let original_runtime = match
    @host.admit_client_native_local_runtime(
      wire, "109564ef9a4f8241096292843b875d4c81fbb6f3", "darwin-arm64", "80731853b15f4d600ef391b3778c734bc40bfb6caed246c0c145916b419e49bd",
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let resolved = Ref(false)
  let original = match
    read_local_policy_upgrade_original_with_runtime_dependency(host, row, (
      _,
      authenticated_body,
    ) => {
      // The shared reader has already checked revision, HMAC, closed shape,
      // selected originals/profile and their actual logical authority scope.
      // Common below still checks this pair against field 12 of that same
      // body and admits the complete original policy without repairing it.
      let fields = match
        @host.client_local_original_record_fields(authenticated_body, [
          "adoption_cid", "authority_scope_cid", "legacy_admissions_wire", "operation_id",
          "profile_wire", "read_configuration_name", "read_original_cid", "read_selection_wire",
          "retention_configuration_cid", "retention_configuration_name", "run_configuration_cid",
          "run_configuration_name", "runtime_pair_wire", "store_configuration_cid",
          "store_configuration_name", "version",
        ]) {
        Ok(value) => value
        Err(_) => return Err(CustodyLost)
      }
      match
        @host.restore_client_native_local_historical_scalar_runtime_pair_metadata(
          @utf8.encode(fields[12]),
          original_runtime,
          historical,
        ) {
        Ok(value) => {
          resolved.val = true
          Ok(value)
        }
        Err(_) => Err(CustodyLost)
      }
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // An ordinary fifteen-key append has no historical pair. Never backfill it
  // from the fixed proof or reinterpret it as a committed runtime transition.
  if !resolved.val {
    return Err(UnsupportedPreparation)
  }
  if original.principal != principal ||
    original.connection != connection ||
    original.scope != scope {
    return Err(ChangedIntent)
  }
  if !current() {
    return Err(AuthorizationDenied)
  }
  if !(host.selected_configuration(selected.name) is Ok(body) &&
    body == selected.body) {
    return Err(CustodyLost)
  }
  // Selected-file verification itself can perform physical callbacks. Retain
  // the existing current check after it as well, never a saved Allow decision.
  if !current() {
    return Err(AuthorizationDenied)
  }
  Ok(original)
}
