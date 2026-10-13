///|
// Explicit operation identity is durable metadata, not current permission.
// The real adopted Host performs the Account/custody/transaction checks. No
// settings file, old Policy, grant or Run is replaced by this CLI command.
fn local_run_policy_upgrade_operation(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  operation : String,
  child : @argparse.Matches,
) -> String raise ClientStop {
  let operation_id = required(child, "operation-id")
  let receipt = if operation == "lookup-policy-upgrade" {
    local_policy_upgrade_result(
      operation_id,
      host.lookup_run_policy_upgrade(
        crypto,
        settings.principal,
        settings.connection,
        operation_id,
      ),
    )
  } else {
    // A finite first-install profile already has its own selected original.
    // This explicit append is reserved for the unchanged legacy adoption.
    if settings.run_policy_profile_file is Some(_) {
      stop("LocalPolicyUpgradeChangedIntent")
    }
    Some(
      local_policy_upgrade_result(
        operation_id,
        host.upgrade_run_policy(
          crypto,
          settings.principal,
          settings.connection,
          operation_id,
          settings.read_file.unwrap_or_else(() => {
            stop("LocalReadPolicyOriginalNotSelected")
          }),
          settings.run_file.unwrap_or_else(() => {
            stop("LocalRunOriginalNotSelected")
          }),
          required(child, "retention-file"),
          required(child, "store-file"),
        ),
      ),
    )
  }
  let value = match receipt {
    Some(value) =>
      Json::object(
        Map([
          ("kind", Json::string("local_run_policy_upgrade")),
          ("operationId", Json::string(value.operation_id)),
          ("adoptionCid", Json::string(value.adoption_cid)),
          ("authorityScopeCid", Json::string(value.authority_scope_cid)),
          ("originalCid", Json::string(value.original_cid)),
          ("profileCid", Json::string(value.profile_cid)),
        ]),
      )
    None =>
      Json::object(
        Map([
          ("kind", Json::string("local_run_policy_upgrade_not_committed")),
          ("operationId", Json::string(operation_id)),
        ]),
      )
  }
  if child.flags.get("json").unwrap_or(false) {
    encode_request_json(value, 4096)
  } else {
    match receipt {
      Some(value) =>
        "Original Local policy upgrade: " +
        value.operation_id +
        "\nAdoption: " +
        value.adoption_cid +
        "\nOriginal: " +
        value.original_cid
      None =>
        "No committed Local policy upgrade for this operation. This does not authorize retry."
    }
  }
}

///|
// Keep the original operation ID on unknown outcomes. This formatter neither
// infers an absent commit nor authorizes retry, renewal or a second append.
fn[T] local_policy_upgrade_result(
  operation_id : String,
  result : Result[T, @local_host.NativeClientRunJournalIssue],
) -> T raise ClientStop {
  match result {
    Ok(value) => value
    Err(issue) => {
      let code = match issue {
        TransactionUnknown | Fenced => "LocalPolicyUpgradeUnknown"
        AuthorizationDenied => "LocalPolicyUpgradeAuthorizationDenied"
        ChangedIntent | ForeignRun => "LocalPolicyUpgradeChangedIntent"
        CapacityExceeded => "LocalPolicyUpgradeCapacityRefused"
        CustodyLost => "LocalPolicyUpgradeOriginalUnavailable"
        _ => "LocalPolicyUpgradeStorageFailure"
      }
      let identity = encode_request_json(
        Json::object(
          Map([
            ("operationId", Json::string(operation_id)),
            ("lookup", Json::string("lookup-policy-upgrade")),
          ]),
        ),
        4096,
      )
      stop(code + " " + identity)
    }
  }
}
