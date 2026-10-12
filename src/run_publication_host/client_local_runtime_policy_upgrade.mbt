///|
/// A closed alternative of the existing installation upgrade metadata.
/// Native must authenticate and commit it in the original journal transaction;
/// this projection does not issue custody, physical compatibility or authority.
struct ClientLocalRuntimePolicyUpgrade {
  policy : ClientLocalRunPolicyUpgrade
  runtime : ClientNativeLocalScalarRuntimePair
  body : Bytes
}

///|
fn local_runtime_policy_upgrade_keys() -> Array[String] {
  [
    "adoption_cid", "authority_scope_cid", "legacy_admissions_wire", "operation_id",
    "profile_wire", "read_configuration_name", "read_original_cid", "read_selection_wire",
    "retention_configuration_cid", "retention_configuration_name", "run_configuration_cid",
    "run_configuration_name", "runtime_pair_wire", "store_configuration_cid", "store_configuration_name",
    "version",
  ]
}

///|
/// Preserve the entire old fifteen-key original. Only the explicitly different
/// alternative contains a runtime pair; an old append cannot be backfilled.
pub fn bind_client_local_runtime_policy_upgrade(
  policy : ClientLocalRunPolicyUpgrade,
  runtime : ClientNativeLocalScalarRuntimePair,
) -> Result[ClientLocalRuntimePolicyUpgrade, ClientLocalRunPolicyProfileIssue] {
  let prior = match
    client_local_original_record_fields(
      policy.body,
      local_policy_upgrade_keys(),
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  let runtime_wire = @utf8.decode(runtime.body) catch {
    _ => return Err(InvalidOriginal)
  }
  let fields : Array[(String, String)] = []
  for index, key in local_policy_upgrade_keys() {
    if key == "store_configuration_cid" {
      fields.push(("runtime_pair_wire", runtime_wire))
    }
    fields.push(
      (
        key,
        if key == "version" {
          "actql-local-runtime-policy-upgrade/0.1"
        } else {
          prior[index]
        },
      ),
    )
  }
  match client_local_original_record_body(fields) {
    Ok(body) => Ok({ policy, runtime, body, })
    Err(_) => Err(Encoding)
  }
}

///|
/// Revalidate the saved policy through the existing original-policy reader and
/// compare the runtime pair with its independently reconstructed opaque value.
/// No legacy acceptance list is recaptured and no missing input is repaired.
pub fn admit_client_local_runtime_policy_upgrade(
  body : Bytes,
  profile : ClientLocalRunPolicyProfile,
  original_read_wire : String,
  adoption_cid : String,
  authority_scope_cid : String,
  operation_id : String,
  selected : Array[(String, String)],
  runtime : ClientNativeLocalScalarRuntimePair,
) -> Result[ClientLocalRuntimePolicyUpgrade, ClientLocalRunPolicyProfileIssue] {
  let fields = match
    client_local_original_record_fields(
      body,
      local_runtime_policy_upgrade_keys(),
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  if fields[15] != "actql-local-runtime-policy-upgrade/0.1" ||
    @utf8.encode(fields[12]) != runtime.body {
    return Err(InvalidOriginal)
  }
  let original_fields : Array[(String, String)] = []
  for index, key in local_runtime_policy_upgrade_keys() {
    if key == "runtime_pair_wire" {
      continue
    }
    original_fields.push(
      (
        key,
        if key == "version" {
          "actql-local-run-policy-upgrade/0.1"
        } else {
          fields[index]
        },
      ),
    )
  }
  let prior = match client_local_original_record_body(original_fields) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  let policy = match
    admit_client_local_run_policy_upgrade(
      prior, profile, original_read_wire, adoption_cid, authority_scope_cid, operation_id,
      selected,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  bind_client_local_runtime_policy_upgrade(policy, runtime).bind(original => {
    if original.body == body {
      Ok(original)
    } else {
      Err(InvalidOriginal)
    }
  })
}

///|
pub fn client_local_runtime_policy_upgrade_body(
  original : ClientLocalRuntimePolicyUpgrade,
) -> Bytes {
  original.body
}

///|
pub fn client_local_runtime_policy_upgrade_policy(
  original : ClientLocalRuntimePolicyUpgrade,
) -> ClientLocalRunPolicyUpgrade {
  original.policy
}

///|
pub fn client_local_runtime_policy_upgrade_runtime(
  original : ClientLocalRuntimePolicyUpgrade,
) -> ClientNativeLocalScalarRuntimePair {
  original.runtime
}
