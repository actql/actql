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
    #|{"control":{"operations":["cancel","publish","read","resolve","submit"],"resource":"run"},"effect":{"operations":["effect"],"outcome":"delegate"},"infer":{"connection":"mock","operations":["infer","model_raw_capture"]},"profile_id":"actql-local-mock","profile_version":"0.1","read":{"operations":["read"]},"request":{"operations":["write"],"resource":"original-host-mock-realization"},"result":{"operations":["read"],"scope":"same-run-original-results"},"scope":"selected-mock-project-installation","sign":{"operations":["sign"],"resource":"original-local-purpose-key"}}
  )
}

///|
/// Exact previously issued finite Result policy; recovery never broadens it.
fn local_mock_updates_profile_body() -> String {
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
  profile == local_mock_profile_body_identity(local_mock_updates_profile_body()) ||
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
  DuplicateUpdateTarget
  Configuration(ConfigurationIssue)
} derive(Eq, Debug)

///|
fn local_mock_entry(
  name : String,
  subjects : LocalMockAccountSubjects,
  connection : String,
  resource : Selector,
  operations : Array[String],
  outcome : ConfiguredOutcome,
) -> RawAccountEntry {
  {
    entry_id: name,
    outcome,
    scope: {
      principal: AnyOf([subjects.principal]),
      connection: AnyOf([connection]),
      resource,
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
  let targets = match subjects.update_target {
    Some(target) => [target]
    None => []
  }
  local_mock_account_configuration_original(subjects, targets, false)
}

///|
/// Build the complete selected target policy once. The original installing
/// Host must fund this constructor before it allocates entries or serializes
/// the Account. This is configuration DATA, not adoption or an Effect permit.
pub fn local_mock_account_configuration_prepared(
  subjects : LocalMockAccountSubjects,
  update_targets : Array[(String, String)],
  prepare : (AccountConfigurationConstruction) -> Bool,
  original_result_read? : Bool = false,
) -> Result[String, LocalMockProfileIssue]? {
  guard local_mock_account_construction(subjects, update_targets)
    is Some(request) &&
    prepare(request) else {
    return None
  }
  Some(
    local_mock_account_configuration_original(
      subjects, update_targets, original_result_read,
    ),
  )
}

///|
/// Choose DATA for a fresh Host control domain, disjoint from every actual
/// Source/target connection and the Mock Model provider. The SAME Read admits
/// the borrowed-key index and bounded String workspace before allocation.
/// Reopen must compare this result with its retained original, never retarget.
pub fn local_mock_control_connection_prepared(
  preferred : String,
  saved_profile : BootstrapProfile?,
  original_control : String?,
  sources : Array[(String, String)],
  update_targets : Array[(String, String)],
  prepare : (AccountConfigurationConstruction) -> Bool,
) -> Result[String, LocalMockProfileIssue]? {
  guard local_mock_control_construction(preferred, sources, update_targets)
    is Some(request) &&
    prepare(request) else {
    return None
  }
  if !valid_name(preferred) || !normalized_text(preferred) {
    return Some(Err(InvalidSubjects))
  }
  if saved_profile is Some(profile) {
    if profile.profile_id != LOCAL_MOCK_PROFILE_ID ||
      profile.profile_version != LOCAL_MOCK_PROFILE_VERSION {
      return Some(Err(InvalidSubjects))
    }
    // These are independently pinned complete profile-body identities, not
    // another interpretation of policy JSON or a replacement adoption record.
    match profile.profile_cid {
      "sha256:c910a820bfc2428234bcb73701593a3aafe7f457fb586eb000d4587c1e600a5e" => {
        guard original_control is Some(control) &&
          control == preferred &&
          local_mock_control_disjoint(control, sources, update_targets) else {
          return Some(Err(InvalidSubjects))
        }
        return Some(Ok(control))
      }
      "sha256:0423a05cccb8d7329cc130247130f2081bb8f54e42ae579e99166da30c21de52"
      | "sha256:8d3a8a44d338852bdef34d4547dc8a9c22d91e9831dac20ee42f144de8793e01"
      | "sha256:5d1edcd4312874f4621a96fa5d6a73b4015952cab8db0f6950a1622dcf0ab36f"
      | "sha256:fe8f88f3465a18456678bf9bf32943dcc4e4a8654b6d449f0c6af174fffd7e3a" => {
        if original_control is Some(_) {
          return Some(Err(InvalidSubjects))
        }
        return Some(Ok(preferred))
      }
      _ => return Some(Err(InvalidSubjects))
    }
  }
  if original_control is Some(_) {
    return Some(Err(InvalidSubjects))
  }
  let occupied : Map[String, Bool] = { "mock": true }
  for source in sources {
    occupied[source.0] = true
  }
  for target in update_targets {
    occupied[target.0] = true
  }
  if !occupied.contains(preferred) {
    return Some(Ok(preferred))
  }
  // At most N distinct occupied labels, hence one of these N+1 candidates is
  // free. Int bounds were checked before the index or decimal String existed.
  let count = sources.length() + update_targets.length() + 1
  for index in 0..<=count {
    let candidate = "actql-local-control-" + index.to_string()
    if !occupied.contains(candidate) {
      return Some(Ok(candidate))
    }
  }
  Some(Err(InvalidSubjects))
}

///|
fn local_mock_control_disjoint(
  control : String,
  sources : Array[(String, String)],
  targets : Array[(String, String)],
) -> Bool {
  control != "mock" &&
  !sources.any(source => source.0 == control) &&
  !targets.any(target => target.0 == control)
}

///|
/// Validate the complete selected inventory before the installing Host creates
/// keys or a configuration identity. The SAME Account Read funds all duplicate
/// indexes and normalization; this result is DATA, never an Allow or adoption.
pub fn validate_local_mock_inventory_prepared(
  control_connection : String,
  sources : Array[(String, String)],
  model_tasks : Array[String],
  request_target : (String, String)?,
  update_targets : Array[(String, String)],
  prepare : (AccountConfigurationConstruction) -> Bool,
) -> Result[Unit, LocalMockProfileIssue]? {
  guard local_mock_inventory_construction(
      control_connection, sources, model_tasks, request_target, update_targets,
    )
    is Some(request) &&
    prepare(request) else {
    return None
  }
  if !valid_name(control_connection) || !normalized_text(control_connection) {
    return Some(Err(InvalidSubjects))
  }
  let seen_sources : Map[(String, String), Bool] = Default::default()
  for source in sources {
    if !valid_name(source.0) ||
      !valid_name(source.1) ||
      !normalized_text(source.0) ||
      !normalized_text(source.1) ||
      seen_sources.contains(source) {
      return Some(Err(InvalidSubjects))
    }
    seen_sources[source] = true
  }
  let seen_tasks : Map[String, Bool] = Default::default()
  for task in model_tasks {
    if !valid_cid(task) || seen_tasks.contains(task) {
      return Some(Err(InvalidSubjects))
    }
    seen_tasks[task] = true
  }
  let seen_targets : Map[(String, String), Bool] = Default::default()
  for target in update_targets {
    if !seen_sources.contains(target) {
      return Some(Err(InvalidSubjects))
    }
    if seen_targets.contains(target) {
      return Some(Err(DuplicateUpdateTarget))
    }
    seen_targets[target] = true
  }
  if request_target is Some(target) {
    if !valid_name(target.0) ||
      !valid_name(target.1) ||
      !normalized_text(target.0) ||
      !normalized_text(target.1) ||
      seen_sources.contains(target) ||
      (target.0 == "mock" && seen_tasks.contains(target.1)) {
      return Some(Err(InvalidSubjects))
    }
  }
  Some(Ok(()))
}

///|
fn local_mock_account_configuration_original(
  subjects : LocalMockAccountSubjects,
  update_targets : Array[(String, String)],
  original_result_read : Bool,
) -> Result[String, LocalMockProfileIssue] {
  if !valid_name(subjects.account_id) ||
    !valid_name(subjects.principal) ||
    !valid_name(subjects.control_connection) ||
    !local_mock_control_disjoint(
      subjects.control_connection,
      subjects.sources,
      update_targets,
    ) {
    return Err(InvalidSubjects)
  }
  // One own-domain Result read; every target retains its exact delegate.
  let fixed = 2L +
    update_targets.length().to_int64() +
    (if subjects.request_target is Some(_) { 1L } else { 0L }) +
    (if subjects.signing_key_resource is Some(_) { 1L } else { 0L })
  if fixed > 2147483647L {
    return Err(Configuration(CanonicalDocumentTooLarge))
  }
  match
    local_profile_entry_inventory(
      subjects.sources.length(),
      subjects.model_tasks.length(),
      fixed.to_int(),
    ) {
    Err(issue) => return Err(Configuration(issue))
    Ok(_) => ()
  }
  if subjects.update_target is Some(legacy) &&
    (update_targets.length() != 1 || update_targets[0] != legacy) {
    return Err(InvalidSubjects)
  }
  let targets = update_targets.copy()
  targets.sort_by((left, right) => {
    let connection = code_unit_compare(left.0, right.0)
    if connection == 0 {
      code_unit_compare(left.1, right.1)
    } else {
      connection
    }
  })
  let entries = [
    local_mock_entry(
      "local-run",
      subjects,
      subjects.control_connection,
      AnyOf(["run"]),
      ["cancel", "publish", "read", "resolve", "submit"],
      Allow,
    ),
    // The SDK uses the exact installed Result role after checking the
    // requested name and current committed Run. Other Mock Hosts select
    // the named resource in this disjoint control domain themselves.
    local_mock_entry(
      if original_result_read {
        local_original_result_read_entry_id
      } else {
        "local-result-read"
      },
      subjects,
      subjects.control_connection,
      if original_result_read {
        AnyOf([local_original_result_read_resource])
      } else {
        All
      },
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
        AnyOf([source.1]),
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
        AnyOf([task]),
        ["infer", "model_raw_capture"],
        Allow,
      ),
    )
  }
  for index, target in targets {
    // Disjoint logical targets may share one physical JSON document. This
    // policy binds connection/resource, never pathname or file-owner count.
    if !seen_sources.contains(target) {
      return Err(InvalidSubjects)
    }
    if index > 0 && targets[index - 1] == target {
      return Err(DuplicateUpdateTarget)
    }
    entries.push(
      local_mock_entry(
        if targets.length() == 1 {
          "mock-update"
        } else {
          "mock-update-" + index.to_string()
        },
        subjects,
        target.0,
        AnyOf([target.1]),
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
        AnyOf([resource]),
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
        AnyOf([target.1]),
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
  let geometry : Ref[AccountCanonicalBounds?] = Ref(None)
  match
    admit_with_overlap_budget(
      raw,
      MAX_OVERLAP_WORK,
      geometry_out=Some(geometry),
    ) {
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
  guard geometry.val is Some(bounds) &&
    canonical_value_of(document, bounds=Some(bounds)) is Some(value) else {
    return Err(Configuration(CanonicalDocumentTooLarge))
  }
  Ok(
    @canonical_json.stringify_value(
      value,
      bounds.encoded_bytes,
      bounds.nodes,
      CANONICAL_MAX_DEPTH,
    ),
  ) catch {
    _ => Err(Configuration(CanonicalDocumentTooLarge))
  }
}
