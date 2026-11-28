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
// actual entry inventory before allocating entries or duplicate indexes.
// Keep the array representation bound, not a separate Source/Task allowance.
fn local_profile_entry_inventory(
  sources : Int,
  tasks : Int,
  fixed : Int,
) -> Result[Unit, ConfigurationIssue] {
  let count = sources.to_int64() + tasks.to_int64() + fixed.to_int64()
  if count > 2147483647L {
    return Err(CanonicalDocumentTooLarge)
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
  local_standard_account_configuration_original(subjects)
}

///|
/// Same policy builder/admission, with its complete constructor envelope
/// admitted before entry arrays, duplicate indexes or canonical text exist.
pub fn local_standard_account_configuration_prepared(
  subjects : LocalStandardAccountSubjects,
  prepare : (AccountConfigurationConstruction) -> Bool,
) -> Result[String, LocalStandardProfileIssue]? {
  guard local_standard_account_construction(subjects) is Some(request) &&
    prepare(request) else {
    return None
  }
  Some(local_standard_account_configuration_original(subjects))
}

///|
/// Construct the installed SDK read-only form of the standard Local Account.
/// Sources are exact declared connection/resource tuples collected by the
/// original Catalog caller before entering this already funded constructor.
/// The control namespace uses the existing bounded disjoint-name selector.
pub fn local_standard_file_account_configuration_prepared(
  sources : Array[(String, String)],
  prepare : (AccountConfigurationConstruction) -> Bool,
) -> Result[(String, String), LocalStandardProfileIssue]? {
  guard !sources.is_empty() else { return Some(Err(InvalidSubjects)) }
  let control = match
    local_mock_control_connection_prepared(
      "local",
      None,
      None,
      sources,
      [],
      prepare,
    ) {
    Some(Ok(value)) => value
    Some(Err(_)) => return Some(Err(InvalidSubjects))
    None => return None
  }
  let subjects : LocalStandardAccountSubjects = {
    account_id: "local-cli",
    principal: "local-cli",
    control_connection: control,
    configured_connections: [],
    model_tasks: [],
    request_target: None,
    signing_key_resource: None,
  }
  guard local_standard_account_construction(subjects, file_sources=sources)
    is Some(quote) &&
    prepare(quote) else {
    return None
  }
  Some(
    local_standard_account_configuration_original(
      subjects,
      file_sources=Some(sources),
    ).map(wire => (control, wire)),
  )
}

///|
fn local_standard_account_configuration_original(
  subjects : LocalStandardAccountSubjects,
  file_sources? : Array[(String, String)]? = None,
) -> Result[String, LocalStandardProfileIssue] {
  if !valid_name(subjects.account_id) ||
    !valid_name(subjects.principal) ||
    !valid_name(subjects.control_connection) {
    return Err(InvalidSubjects)
  }
  let declared = file_sources.unwrap_or([])
  guard declared.length() <=
    2147483647 - subjects.configured_connections.length() else {
    return Err(Configuration(CanonicalDocumentTooLarge))
  }
  // Run, Result and Effect, plus the exact optional request/sign entries.
  let fixed = 3 +
    (if subjects.request_target is Some(_) { 1 } else { 0 }) +
    (if subjects.signing_key_resource is Some(_) { 1 } else { 0 })
  match
    local_profile_entry_inventory(
      subjects.configured_connections.length() + declared.length(),
      subjects.model_tasks.length(),
      fixed,
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
  if file_sources is Some(_) {
    entries[1] = local_standard_entry(
      local_original_result_read_entry_id,
      subjects,
      AnyOf([subjects.control_connection]),
      AnyOf([local_original_result_read_resource]),
      ["read"],
      Allow,
    )
    let seen : Map[(String, String), Bool] = Map([])
    for index, source in declared {
      let (connection, resource) = source
      guard connection != subjects.control_connection &&
        valid_name(connection) &&
        valid_name(resource) &&
        !seen.contains(source) else {
        return Err(InvalidSubjects)
      }
      seen[source] = true
      entries.push(
        local_standard_entry(
          "local-read-" + index.to_string(),
          subjects,
          AnyOf([connection]),
          AnyOf([resource]),
          ["read"],
          Allow,
        ),
      )
    }
  }
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

///|
fn local_standard_account_construction(
  subjects : LocalStandardAccountSubjects,
  file_sources? : Array[(String, String)] = [],
) -> AccountConfigurationConstruction? {
  let entries = subjects.configured_connections.length().to_int64() +
    subjects.model_tasks.length().to_int64() +
    file_sources.length().to_int64() +
    5L
  if entries > 2147483647L {
    return None
  }
  // Closed standard entries own four selector positions and fixed operation
  // tokens. Count each borrowed name occurrence before building any array.
  guard @counts.checked_nonnegative_add_product(
      subjects.account_id.length().to_int64(),
      entries,
      subjects.principal.length().to_int64() +
      subjects.control_connection.length().to_int64() +
      256L,
    )
    is Some(initial_text) else {
    return None
  }
  let mut text = initial_text
  let mut longest = Int::max(
    subjects.account_id.length(),
    Int::max(subjects.principal.length(), subjects.control_connection.length()),
  )
  for value in subjects.configured_connections {
    guard @counts.checked_nonnegative_add_product(
        text,
        value.length().to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    text = next
    longest = Int::max(longest, value.length())
  }
  for (connection, resource) in file_sources {
    guard @counts.checked_nonnegative_add_product(
        text,
        connection.length().to_int64() + resource.length().to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    text = next
    longest = Int::max(
      longest,
      Int::max(connection.length(), resource.length()),
    )
  }
  for task in subjects.model_tasks {
    guard @counts.checked_nonnegative_add_product(
        text,
        task.0.length().to_int64() + task.1.length().to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    text = next
    longest = Int::max(longest, Int::max(task.0.length(), task.1.length()))
  }
  if subjects.request_target is Some(value) {
    guard @counts.checked_nonnegative_add_product(
        text,
        value.0.length().to_int64() + value.1.length().to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    text = next
    longest = Int::max(longest, Int::max(value.0.length(), value.1.length()))
  }
  if subjects.signing_key_resource is Some(value) {
    guard @counts.checked_nonnegative_add_product(
        text,
        value.length().to_int64(),
        1L,
      )
      is Some(next) else {
      return None
    }
    text = next
    longest = Int::max(longest, value.length())
  }
  guard @canonical.nfc_lf_retained_output_units(text) is Some(normalized) &&
    @canonical.nfc_lf_construction_scratch_extent(Int::max(longest, 128))
    is Some(nfc) &&
    @shape.collection_construction_extent({
      records: 96L * entries + 64L,
      record_references: 256L * entries + 128L,
      record_words: 128L * entries + 64L,
      reference_arrays: 80L * entries + 32L,
      reference_items: 256L * entries + 128L,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 16L * entries + 4L,
      map_entries: 64L * entries + 16L,
    })
    is Some(forest) else {
    return None
  }
  // Native Json + canonical frozen forests, compiled selectors, keyed/sorted
  // entries and the returned canonical String coexist. The fixed standard
  // policy uses no exclusions, so overlap has one pair region, not an n² forest.
  guard @counts.checked_nonnegative_add_product(512L * entries, normalized, 6L)
    is Some(output_bound) else {
    return None
  }
  let output = account_representation_limit(output_bound)
  guard @encode.text_writer_construction_inventory(
      output,
      account_representation_limit(64L * entries + 16L),
      CANONICAL_MAX_DEPTH,
    )
    is Some(writer) else {
    return None
  }
  let retained = account_construction_units(1L, 0L, 0L, output.to_int64())
  Some({
    retained,
    execution: account_construction_units(
      forest.record_headers + nfc.record_headers + writer.record_headers + 32L,
      forest.reference_slots +
      nfc.reference_slots +
      writer.reference_slots +
      64L,
      forest.scalar_words + nfc.scalar_words + writer.scalar_words + 128L,
      4L * normalized + nfc.owned_utf16_units + writer.owned_utf16_units,
      wire=256L,
    ),
  })
}
