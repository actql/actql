///|
/// Published policy provenance, not an Account grant or installation proof.
pub const LOCAL_MOCK_PROFILE_ID : String = "actql-local-mock"

///|
pub const LOCAL_MOCK_PROFILE_VERSION : String = "0.1"

///|
/// The finite profile is instantiated only by a trusted explicit Mock
/// initializer. Its installation, Project, actual backend and durable adoption
/// remain Host originals; these policy bytes cannot authenticate any of them.
pub fn local_mock_profile_body() -> String {
  (
    #|{"control":{"operations":["cancel","publish","read","resolve","submit"],"resource":"run"},"effect":{"operations":["effect"],"outcome":"delegate"},"infer":{"connection":"mock","operations":["infer","model_raw_capture"]},"profile_id":"actql-local-mock","profile_version":"0.1","read":{"operations":["read"]},"request":{"operations":["write"],"resource":"original-host-mock-realization"},"result":{"operations":["read"],"resources":["result/answer","result/main","result/updates"]},"scope":"selected-mock-project-installation","sign":{"operations":["sign"],"resource":"original-local-purpose-key"}}
  )
}

///|
/// Exact prior primary policy. Recognition never adds grants to saved state.
fn local_mock_primary_profile_body() -> String {
  (
    #|{"control":{"operations":["cancel","publish","read","resolve","submit"],"resource":"run"},"effect":{"operations":["effect"],"outcome":"delegate"},"infer":{"connection":"mock","operations":["infer","model_raw_capture"]},"profile_id":"actql-local-mock","profile_version":"0.1","read":{"operations":["read"]},"request":{"operations":["write"],"resource":"original-host-mock-realization"},"result":{"operations":["read"],"resources":["result/answer","result/main"]},"scope":"selected-mock-project-installation","sign":{"operations":["sign"],"resource":"original-local-purpose-key"}}
  )
}

///|
/// The previously issued answer-only body remains an exact original. It is
/// recognized for recovery, never materialized as an upgrade on reopen.
fn local_mock_answer_profile_body() -> String {
  (
    #|{"control":{"operations":["cancel","publish","read","resolve","submit"],"resource":"run"},"effect":{"operations":["effect"],"outcome":"delegate"},"infer":{"connection":"mock","operations":["infer","model_raw_capture"]},"profile_id":"actql-local-mock","profile_version":"0.1","read":{"operations":["read"]},"request":{"operations":["write"],"resource":"original-host-mock-realization"},"result":{"operations":["read"],"resource":"result/answer"},"scope":"selected-mock-project-installation","sign":{"operations":["sign"],"resource":"original-local-purpose-key"}}
  )
}

///|
/// Exact predecessor policy bytes remain evidence for already adopted
/// installations. Recognizing them never upgrades their saved configuration.
pub fn local_mock_profile_predecessor_body() -> String {
  (
    #|{"control":{"operations":["read","resolve"],"resource":"run"},"effect":{"operations":["effect"],"outcome":"delegate"},"infer":{"connection":"mock","operations":["infer","model_raw_capture"]},"profile_id":"actql-local-mock","profile_version":"0.1","read":{"operations":["read"]},"request":{"operations":["write"],"resource":"original-host-mock-realization"},"scope":"selected-mock-project-installation","sign":{"operations":["sign"],"resource":"original-local-purpose-key"}}
  )
}

///|
pub fn local_mock_profile_identity() -> BootstrapProfile {
  local_mock_profile_body_identity(local_mock_profile_body())
}

///|
fn local_mock_profile_body_identity(wire : String) -> BootstrapProfile {
  let body = @json.parse(wire) catch {
    _ => abort("invalid local Mock profile original")
  }
  {
    profile_id: LOCAL_MOCK_PROFILE_ID,
    profile_version: LOCAL_MOCK_PROFILE_VERSION,
    profile_cid: document_cid(body).unwrap(),
  }
}

///|
/// Closed historical identity check only. The actual Host must still retain
/// its saved intent/configuration, same installation and current authority.
/// This does not issue adoption, a Run, a Result or replacement permissions.
pub fn is_known_local_mock_profile(profile : BootstrapProfile) -> Bool {
  profile == local_mock_profile_identity() ||
  profile == local_mock_profile_body_identity(local_mock_primary_profile_body()) ||
  profile == local_mock_profile_body_identity(local_mock_answer_profile_body()) ||
  profile ==
  local_mock_profile_body_identity(local_mock_profile_predecessor_body())
}

///|
/// Concrete subjects retained by the installing Host. This is DATA, not a
/// constructor for a Mock backend, Reviewer, key or current authorization.
/// All sources and Tasks must belong to that same selected Project/Mock
/// installation; a matching connection name cannot substitute a live backend.
pub(all) struct LocalMockAccountSubjects {
  account_id : String
  principal : String
  control_connection : String
  sources : Array[(String, String)]
  model_tasks : Array[String]
  request_target : (String, String)?
  update_target : (String, String)?
  signing_key_resource : String?
}

///|
pub(all) enum LocalMockProfileIssue {
  InvalidSubjects
  Configuration(ConfigurationIssue)
} derive(Eq, Debug)

///|
fn local_mock_entry(
  name : String,
  subjects : LocalMockAccountSubjects,
  connection : String,
  resource : String,
  operations : Array[String],
  outcome : ConfiguredOutcome,
) -> RawAccountEntry {
  {
    entry_id: name,
    outcome,
    scope: {
      principal: AnyOf([subjects.principal]),
      connection: AnyOf([connection]),
      resource: AnyOf([resource]),
      operation: AnyOf(operations),
    },
    exclusions: [],
  }
}

///|
/// Generate one bounded concrete configuration, never merge it with operator
/// entries or install it on absence. The existing initializer must persist its
/// intent before exclusive creation, confirm this exact configuration and bind
/// bootstrap adoption before dispatch. Reopen uses current saved configuration,
/// not this function as a recovery or missing-state regrant mechanism.
pub fn local_mock_account_configuration(
  subjects : LocalMockAccountSubjects,
) -> Result[String, LocalMockProfileIssue] {
  if !valid_name(subjects.account_id) ||
    !valid_name(subjects.principal) ||
    !valid_name(subjects.control_connection) {
    return Err(InvalidSubjects)
  }
  // run and the two ordinary Results; UPDATE adds both its delegate and
  // updates Result. Request/sign entries remain independently selected.
  let fixed = 3 +
    (if subjects.update_target is Some(_) { 2 } else { 0 }) +
    (if subjects.request_target is Some(_) { 1 } else { 0 }) +
    (if subjects.signing_key_resource is Some(_) { 1 } else { 0 })
  match
    local_profile_entry_inventory(
      subjects.sources.length(),
      subjects.model_tasks.length(),
      fixed,
    ) {
    Err(issue) => return Err(Configuration(issue))
    Ok(_) => ()
  }
  let entries = [
    local_mock_entry(
      "local-run",
      subjects,
      subjects.control_connection,
      "run",
      ["cancel", "publish", "read", "resolve", "submit"],
      Allow,
    ),
    // Both exact supported defaults are finite subjects: legacy/explicit
    // answer and the new public read-only Source primary main. Neither entry
    // grants another name or substitutes for the same-Run manifest/current gate.
    local_mock_entry(
      "local-result-read",
      subjects,
      subjects.control_connection,
      "result/answer",
      ["read"],
      Allow,
    ),
    local_mock_entry(
      "local-primary-result-read",
      subjects,
      subjects.control_connection,
      "result/main",
      ["read"],
      Allow,
    ),
  ]
  let seen_sources : Map[(String, String), Bool] = Map([])
  for index, source in subjects.sources {
    if !valid_name(source.0) ||
      !valid_name(source.1) ||
      seen_sources.contains(source) {
      return Err(InvalidSubjects)
    }
    seen_sources[source] = true
    entries.push(
      local_mock_entry(
        "mock-read-" + index.to_string(),
        subjects,
        source.0,
        source.1,
        ["read"],
        Allow,
      ),
    )
  }
  let seen_tasks : Map[String, Bool] = Map([])
  for index, task in subjects.model_tasks {
    if !valid_cid(task) || seen_tasks.contains(task) {
      return Err(InvalidSubjects)
    }
    seen_tasks[task] = true
    entries.push(
      local_mock_entry(
        "mock-infer-" + index.to_string(),
        subjects,
        "mock",
        task,
        ["infer", "model_raw_capture"],
        Allow,
      ),
    )
  }
  if subjects.update_target is Some(target) {
    // UPDATE can only name a selected readable Mock subject. Delegate is
    // unresolved until the existing exact Preview/Checkpoint decision; this
    // profile never supplies a permit, signature or physical write grant.
    if !seen_sources.contains(target) {
      return Err(InvalidSubjects)
    }
    entries.push(
      local_mock_entry(
        "mock-update",
        subjects,
        target.0,
        target.1,
        ["effect"],
        Delegate,
      ),
    )
    // Only the selected UPDATE recipe's exact Named Result. This does not
    // approve the Effect, issue a Result or replace its same-Run/current gate.
    entries.push(
      local_mock_entry(
        "local-update-result-read",
        subjects,
        subjects.control_connection,
        "result/updates",
        ["read"],
        Allow,
      ),
    )
  }
  if subjects.signing_key_resource is Some(resource) {
    if !valid_name(resource) {
      return Err(InvalidSubjects)
    }
    entries.push(
      local_mock_entry(
        "local-sign",
        subjects,
        subjects.control_connection,
        resource,
        ["sign"],
        Allow,
      ),
    )
  }
  if subjects.request_target is Some(target) {
    if !valid_name(target.0) ||
      !valid_name(target.1) ||
      seen_sources.contains(target) ||
      (target.0 == "mock" && seen_tasks.contains(target.1)) {
      return Err(InvalidSubjects)
    }
    entries.push(
      local_mock_entry(
        "local-request",
        subjects,
        target.0,
        target.1,
        ["write"],
        Allow,
      ),
    )
  }
  let raw : RawAccountConfiguration = {
    account_id: subjects.account_id,
    bootstrap: Some(local_mock_profile_identity()),
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
