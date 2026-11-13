///|
/// Policy provenance for standard Local initialization, not adoption or a grant.
pub fn local_standard_profile_body() -> String {
  (
    #|{"control":{"operations":["cancel","publish","read","resolve","submit"],"resource":"run"},"effect":{"operations":["effect"],"outcome":"delegate"},"infer":{"operations":["infer","model_raw_capture"],"scope":"registered-model-tasks"},"profile_id":"actql-local-standard","profile_version":"0.1","read":{"operations":["read"],"scope":"configured-connections"},"request":{"operations":["write"],"resource":"original-host-realization"},"result":{"operations":["read"],"scope":"same-run-original-results"},"scope":"standard-local-installation","sign":{"operations":["sign"],"resource":"original-local-purpose-key"}}
  )
}

///|
pub fn local_standard_profile_identity() -> BootstrapProfile {
  let body = @json.parse(local_standard_profile_body()) catch {
    _ => abort("invalid standard Local profile original")
  }
  {
    profile_id: "actql-local-standard",
    profile_version: "0.1",
    profile_cid: document_cid(body).unwrap(),
  }
}

///|
/// Concrete installed subjects, supplied by the existing initialization Owner.
/// Configured connections and registered Tasks remain independently current;
/// names, profile bytes and this materializer do not establish their authority.
pub(all) struct LocalStandardAccountSubjects {
  account_id : String
  principal : String
  control_connection : String
  configured_connections : Array[String]
  model_tasks : Array[(String, String)]
  request_target : (String, String)?
  signing_key_resource : String?
}

///|
pub(all) enum LocalStandardProfileIssue {
  InvalidSubjects
  Configuration(ConfigurationIssue)
} derive(Eq, Debug)

///|
// Both Local materializers emit one finite Account configuration. Check its
// actual entry inventory before allocating entries or duplicate indexes, using
// the SAME admission Owner's bound rather than separate Source/Task ceilings.
fn local_profile_entry_inventory(
  sources : Int,
  tasks : Int,
  fixed : Int,
) -> Result[Unit, ConfigurationIssue] {
  let count = sources.to_int64() + tasks.to_int64() + fixed.to_int64()
  if count > 2147483647L {
    return Err(CanonicalDocumentTooLarge)
  }
  if count > MAX_ENTRIES.to_int64() {
    return Err(TooManyEntries(count.to_int()))
  }
  Ok(())
}

///|
fn local_standard_entry(
  name : String,
  subjects : LocalStandardAccountSubjects,
  connection : Selector,
  resource : Selector,
  operations : Array[String],
  outcome : ConfiguredOutcome,
) -> RawAccountEntry {
  {
    entry_id: name,
    outcome,
    scope: {
      principal: AnyOf([subjects.principal]),
      connection,
      resource,
      operation: AnyOf(operations),
    },
    exclusions: [],
  }
}

///|
/// Materialize the specified standard policy for initial durable adoption only.
/// Never merge with authored configuration or regenerate missing saved state.
/// Same-Run Result/control, Credential, egress, resource and approval checks
/// remain with their existing Owners; delegation is not an Effect permit.
pub fn local_standard_account_configuration(
  subjects : LocalStandardAccountSubjects,
) -> Result[String, LocalStandardProfileIssue] {
  if !valid_name(subjects.account_id) ||
    !valid_name(subjects.principal) ||
    !valid_name(subjects.control_connection) {
    return Err(InvalidSubjects)
  }
  // run, Result and Effect, plus the exact optional request/sign entries.
  let fixed = 3 +
    (if subjects.request_target is Some(_) { 1 } else { 0 }) +
    (if subjects.signing_key_resource is Some(_) { 1 } else { 0 })
  match
    local_profile_entry_inventory(
      subjects.configured_connections.length(), subjects.model_tasks.length(), fixed,
    ) {
    Err(issue) => return Err(Configuration(issue))
    Ok(_) => ()
  }
  let entries = [
    local_standard_entry(
      "local-run",
      subjects,
      AnyOf([subjects.control_connection]),
      AnyOf(["run"]),
      ["cancel", "publish", "read", "resolve", "submit"],
      Allow,
    ),
    // The public Result Owner supplies the original name and same-Run binding.
    // This standard (not limited Mock) policy permits that local read domain.
    local_standard_entry(
      "local-result-read",
      subjects,
      AnyOf([subjects.control_connection]),
      All,
      ["read"],
      Allow,
    ),
    local_standard_entry(
      "local-effect",
      subjects,
      All,
      All,
      ["effect"],
      Delegate,
    ),
  ]
  let seen_connections : Map[String, Bool] = Map([])
  for index, connection in subjects.configured_connections {
    if !valid_name(connection) || seen_connections.contains(connection) {
      return Err(InvalidSubjects)
    }
    seen_connections[connection] = true
    entries.push(
      local_standard_entry(
        "local-read-" + index.to_string(),
        subjects,
        AnyOf([connection]),
        All,
        ["read"],
        Allow,
      ),
    )
  }
  let seen_tasks : Map[(String, String), Bool] = Map([])
  for index, task in subjects.model_tasks {
    if !valid_name(task.0) || !valid_cid(task.1) || seen_tasks.contains(task) {
      return Err(InvalidSubjects)
    }
    seen_tasks[task] = true
    entries.push(
      local_standard_entry(
        "local-infer-" + index.to_string(),
        subjects,
        AnyOf([task.0]),
        AnyOf([task.1]),
        ["infer", "model_raw_capture"],
        Allow,
      ),
    )
  }
  if subjects.request_target is Some(target) {
    if !valid_name(target.0) || !valid_name(target.1) {
      return Err(InvalidSubjects)
    }
    entries.push(
      local_standard_entry(
        "local-request",
        subjects,
        AnyOf([target.0]),
        AnyOf([target.1]),
        ["write"],
        Allow,
      ),
    )
  }
  if subjects.signing_key_resource is Some(resource) {
    if !valid_name(resource) {
      return Err(InvalidSubjects)
    }
    entries.push(
      local_standard_entry(
        "local-sign",
        subjects,
        AnyOf([subjects.control_connection]),
        AnyOf([resource]),
        ["sign"],
        Allow,
      ),
    )
  }
  let raw : RawAccountConfiguration = {
    account_id: subjects.account_id,
    bootstrap: Some(local_standard_profile_identity()),
    entries,
  }
  match admit_account_configuration(raw) {
    Err(issue) => return Err(Configuration(issue))
    Ok(_) => ()
  }
  entries.sort_by((left, right) => {
    code_unit_compare(left.entry_id, right.entry_id)
  })
  let document = canonical_document(
    raw.account_id,
    raw.bootstrap,
    entries.map(entry => {
      entry_id: entry.entry_id,
      outcome: entry.outcome,
      scope: entry.scope,
      exclusions: [],
    }),
  )
  guard canonical_value_of(document) is Some(value) else {
    return Err(Configuration(CanonicalDocumentTooLarge))
  }
  Ok(
    @canonical_json.stringify_value(
      value,
      MAX_CONFIG_INPUT_BYTES,
      CANONICAL_MAX_NODES,
      CANONICAL_MAX_DEPTH,
    ),
  ) catch {
    _ => Err(Configuration(CanonicalDocumentTooLarge))
  }
}
