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
    #|{"control":{"operations":["read","resolve"],"resource":"run"},"effect":{"operations":["effect"],"outcome":"delegate"},"infer":{"connection":"mock","operations":["infer","model_raw_capture"]},"profile_id":"actql-local-mock","profile_version":"0.1","read":{"operations":["read"]},"request":{"operations":["write"],"resource":"original-host-mock-realization"},"scope":"selected-mock-project-installation","sign":{"operations":["sign"],"resource":"original-local-purpose-key"}}
  )
}

///|
pub fn local_mock_profile_identity() -> BootstrapProfile {
  let body = @json.parse(local_mock_profile_body()) catch {
    _ => abort("invalid local Mock profile original")
  }
  {
    profile_id: LOCAL_MOCK_PROFILE_ID,
    profile_version: LOCAL_MOCK_PROFILE_VERSION,
    profile_cid: document_cid(body).unwrap(),
  }
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
    !valid_name(subjects.control_connection) ||
    subjects.sources.length() > 128 ||
    subjects.model_tasks.length() > 64 {
    return Err(InvalidSubjects)
  }
  let entries = [
    local_mock_entry(
      "local-run",
      subjects,
      subjects.control_connection,
      "run",
      ["read", "resolve"],
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
