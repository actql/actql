///|
// Pure product configuration assembly. These originals must still pass the
// existing exclusive adoption, current Account, Policy and physical Owners.
// Calling this function is neither adoption nor an execution/read permission.
pub(all) struct ClientLocalProductAssets {
  environment : String
  registry : String
  values : String
  fragment : String
  ordered : String?
  result_policy : String
}

///|
/// Common original bodies only, not a Native profile or authority token.
/// Persist these at explicit adoption; restore the authenticated originals
/// instead of invoking the assembler again to replace custody or expiry.
pub(all) struct ClientLocalProductCommonOriginals {
  account : Bytes
  retention_dependencies : Bytes
  retention_policy : Bytes
  store : Bytes
  result_policy : Bytes
}

///|
priv struct ProductCommonAssembly {
  account : String
  retention_dependencies : String
  retention_policy : String
  store : String
  result_policy : String
  evidence : String
  expires : String
}

///|
pub(all) enum ClientLocalProductConfigurationIssue {
  InvalidLocation
  InvalidObservationTime
  InvalidEnvironment
  UnsupportedAsset
  InvalidResultPolicy
  ConfigurationLimit
} derive(Eq, Debug)

///|
fn product_absolute_location(path : String) -> Bool {
  if !path.has_prefix("/") ||
    path.length() > 4096 ||
    path.length() < 2 ||
    path.has_suffix("/") ||
    path.contains("\u{0000}") {
    return false
  }
  let parts = path.split("/").to_array()
  for index in 1..<parts.length() {
    if parts[index].is_empty() || parts[index] == "." || parts[index] == ".." {
      return false
    }
  }
  true
}

///|
fn product_wire(
  value : Json,
) -> Result[String, ClientLocalProductConfigurationIssue] {
  try {
    let canonical = @canonical.from_json(value, 8192, 64, 65536)
    Ok(@canonical.stringify_value(canonical, 65536, 8192, 64))
  } catch {
    _ => Err(ConfigurationLimit)
  }
}

///|
fn product_asset_value(
  wire : String,
) -> Result[@canonical.CanonicalValue, ClientLocalProductConfigurationIssue] {
  let original = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => return Err(UnsupportedAsset)
  }
  Ok(@canonical.from_source(original, 8192, 64, 65536)) catch {
    _ => Err(UnsupportedAsset)
  }
}

///|
fn product_object(fields : Array[(String, Json)]) -> Json {
  Json::object(Map::from_array(fields))
}

///|
fn product_texts(values : Array[String]) -> Json {
  Json::array(values.map(Json::string))
}

///|
fn product_selector(value : String) -> Json {
  product_object([("any_of", product_texts([value]))])
}

///|
fn product_cid(wire : String) -> String {
  "sha256:" + @sha.hex(@utf8.encode(wire))
}

///|
/// Assemble the source-free baseline once using the actual selected paths,
/// clock and packaged bodies. Restoration must use the retained originals;
/// it must not call this function to refresh expiry or replace lost custody.
fn product_assemble_common(
  configuration_root : String,
  observed_at : String,
  assets : ClientLocalProductAssets,
  mock? : @authorization.LocalMockAccountSubjects? = None,
) -> Result[ProductCommonAssembly, ClientLocalProductConfigurationIssue] raise ProductConfigurationFailure {
  if !product_absolute_location(configuration_root) {
    return Err(InvalidLocation)
  }
  guard @values.timestamp_epoch_milliseconds(observed_at) is Some(now) else {
    return Err(InvalidObservationTime)
  }
  guard @values.epoch_milliseconds_timestamp(now + 86400000L) is Some(expires) &&
    @values.epoch_milliseconds_timestamp(now + 172800000L) is Some(delete_by) &&
    @values.epoch_milliseconds_timestamp(now + 604800000L)
    is Some(metadata_delete_by) else {
    return Err(InvalidObservationTime)
  }
  let environment_value = match product_asset_value(assets.environment) {
    Ok(value) => value
    Err(_) => return Err(InvalidEnvironment)
  }
  guard @canonical.object_field(environment_value, "evidence_bundle_cid")
    is Some(@canonical.String(evidence)) else {
    return Err(InvalidEnvironment)
  }
  // Retained installations keep their original environment; only an exact
  // installed text-time policy selects the capability, never a refreshed CID.
  let text_time = match
    @canonical.object_field(environment_value, "host_policy_profile") {
    Some(profile) =>
      @canonical.object_field(profile, "text_time_evaluation") is Some(_)
    None => false
  }
  if admit_client_check_environment(
      assets.environment,
      evidence,
      { text_time, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    )
    is None {
    return Err(InvalidEnvironment)
  }
  // The initial bundled profile installs no Source, Model, Effect or credential.
  for
    section in [
      "source_views", "model_task_contracts", "command_contracts", "connector_capabilities",
      "connector_catalogs", "mapping_contracts", "schema_snapshots", "contract_registry",
    ] {
    guard @canonical.object_field(environment_value, section)
      is Some(@canonical.Array(values)) &&
      @canonical.array_count(values) == 0 else {
      return Err(InvalidEnvironment)
    }
  }
  let registry = product_require(product_asset_value(assets.registry))
  let values = product_require(product_asset_value(assets.values))
  let limits : @execution.RegistryLimits = {
    max_body_bytes: 65536,
    max_body_nodes: 8192,
    max_body_depth: 64,
  }
  let installed = match
    @execution.admit_relation_registry(registry, values, limits) {
    Ok(value) => value
    Err(_) => return Err(UnsupportedAsset)
  }
  if @execution.admit_fragment_contract(
      installed,
      product_require(product_asset_value(assets.fragment)),
      limits,
    )
    is Err(_) {
    return Err(UnsupportedAsset)
  }
  if assets.ordered is Some(wire) &&
    @execution.admit_ordered_contract(
      installed,
      product_require(product_asset_value(wire)),
      limits,
    )
    is Err(_) {
    return Err(UnsupportedAsset)
  }
  let policy = product_cid(assets.result_policy)
  if admit_source_free_result_policy_body(
      policy,
      assets.result_policy,
      8192,
      512,
      8,
    )
    is Err(_) {
    return Err(InvalidResultPolicy)
  }
  let principal = "local-cli"
  let connection = "local"
  let account = match mock {
    Some(subjects) => {
      // This installer has one fixed principal/control connection. A Project
      // supplies exact source/task subjects, never replacement Host identity.
      if subjects.account_id != principal ||
        subjects.principal != principal ||
        subjects.control_connection != connection {
        return Err(UnsupportedAsset)
      }
      match @authorization.local_mock_account_configuration(subjects) {
        Ok(original) => original
        Err(_) => return Err(UnsupportedAsset)
      }
    }
    None => {
      let account = product_require(
        product_wire(
          product_object([
            ("version", Json::string("actql-execution-account-config/0.1")),
            ("account_id", Json::string(principal)),
            (
              "entries",
              Json::array([
                product_object([
                  ("entry_id", Json::string("local-result-read")),
                  ("principal", product_selector(principal)),
                  ("connection", product_selector(connection)),
                  ("resource", product_selector("result/answer")),
                  ("operation", product_selector("read")),
                  ("outcome", Json::string("allow")),
                  ("exclusions", Json::array([])),
                ]),
                product_object([
                  ("entry_id", Json::string("local-run-control")),
                  ("principal", product_selector(principal)),
                  ("connection", product_selector(connection)),
                  ("resource", product_selector("run")),
                  (
                    "operation",
                    product_object([
                      (
                        "any_of",
                        product_texts(["cancel", "publish", "read", "submit"]),
                      ),
                    ]),
                  ),
                  ("outcome", Json::string("allow")),
                  ("exclusions", Json::array([])),
                ]),
              ]),
            ),
          ]),
        ),
      )
      if @authorization.admit_account_configuration_json(account) is Err(_) {
        return Err(ConfigurationLimit)
      }
      account
    }
  }
  // Reuse the installed Local policy leaf contract and retain actual preimages.
  let dependencies : Array[Json] = []
  for
    (kind, name) in [
      ("retention_contract", "local-result-retention"),
      ("metadata_retention_policy", "local-result-metadata"),
      ("clock_contract", "local-clock"),
    ] {
    let wire = product_require(
      product_wire(
        product_object([
          ("name", Json::string(name)),
          ("version", Json::string("actql-installed-local-policy/0.1")),
        ]),
      ),
    )
    let cid = product_cid(wire)
    if @publication.admit_captured_effect_dependency_body(
        kind,
        Some(cid),
        wire,
        8192,
        512,
        8,
      )
      is Err(_) {
      return Err(ConfigurationLimit)
    }
    dependencies.push(
      product_object([
        ("kind", Json::string(kind)),
        ("cid", Json::string(cid)),
        ("wire", Json::string(wire)),
      ]),
    )
  }
  let dependency_cid = fn(index) {
    match dependencies[index] {
      Object(fields) =>
        match fields.get("cid") {
          Some(String(value)) => value
          _ => ""
        }
      _ => ""
    }
  }
  let retention_body = product_require(
    product_wire(
      product_object([
        ("version", Json::string("actql-result-retention-policy/0.1")),
        ("retention_contract_cid", Json::string(dependency_cid(0))),
        ("effective_data_policy_cid", Json::string(policy)),
        ("available_until", Json::string(expires)),
        ("delete_by", Json::string(delete_by)),
        ("extension_ceiling_at", Json::string(delete_by)),
        ("metadata_retention_policy_cid", Json::string(dependency_cid(1))),
        ("metadata_delete_by", Json::string(metadata_delete_by)),
        ("clock_contract_cid", Json::string(dependency_cid(2))),
      ]),
    ),
  )
  let retention = match
    @publication.seal_publication_contract(
      "result_retention_policy", retention_body, 8192, 512, 8,
    ) {
    Ok(value) => value
    Err(_) => return Err(ConfigurationLimit)
  }
  // Preserve the existing Local Store-owner preimage order, not a fabricated CID.
  let writer = @encode.writer(8192, 16, 4) catch {
    _ => return Err(ConfigurationLimit)
  }
  let store_original = try {
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-local-store-owner/0.1")
    @encode.key(writer, "root")
    @encode.string_value(writer, configuration_root + "/results")
    @encode.key(writer, "principalId")
    @encode.string_value(writer, principal)
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(ConfigurationLimit)
  }
  Ok({
    account,
    retention_dependencies: product_require(
      product_wire(Json::array(dependencies)),
    ),
    retention_policy: @publication.publication_contract_json(retention),
    store: store_original,
    result_policy: assets.result_policy,
    evidence,
    expires,
  })
}

///|
fn product_assemble_originals(
  configuration_root : String,
  sqlite_library : String,
  signature_library : String,
  observed_at : String,
  assets : ClientLocalProductAssets,
  finite_run_profile? : Bool = false,
  mock? : @authorization.LocalMockAccountSubjects? = None,
) -> Result[Array[(String, Bytes)], ClientLocalProductConfigurationIssue] raise ProductConfigurationFailure {
  if !product_absolute_location(configuration_root) ||
    !product_absolute_location(sqlite_library) ||
    !product_absolute_location(signature_library) ||
    sqlite_library == signature_library {
    return Err(InvalidLocation)
  }
  let common = product_require(
    product_assemble_common(configuration_root, observed_at, assets, mock~),
  )
  let profile = if finite_run_profile {
    match
      client_local_run_policy_profile({
        account: @utf8.encode(common.account),
        retention_dependencies: @utf8.encode(common.retention_dependencies),
        retention_policy: @utf8.encode(common.retention_policy),
        store: @utf8.encode(common.store),
        result_policy: @utf8.encode(common.result_policy),
      }) {
      Ok(value) => Some(value)
      Err(_) => return Err(UnsupportedAsset)
    }
  } else {
    None
  }
  let principal = "local-cli"
  let connection = "local"
  let policy = product_cid(common.result_policy)
  let source_free = product_object([
    ("registry", Json::string(assets.registry)),
    ("values", Json::string(assets.values)),
    ("fragment", Json::string(assets.fragment)),
    ("result_policy_cid", Json::string(policy)),
    ("result_policy_wire", Json::string(assets.result_policy)),
  ])
  if assets.ordered is Some(wire) && source_free is Object(fields) {
    fields["ordered"] = Json::string(wire)
  }
  let run = product_require(
    product_wire(
      product_object([
        ("version", Json::string("actql-config/0.1")),
        (
          "native",
          product_object([
            (
              "run",
              product_object([
                ("namespace_id", Json::string("local")),
                ("store_name", Json::string("results")),
                ("store_authority_cid", Json::string(product_cid(common.store))),
                ("store_capacity_bytes", Json::number(1048576)),
                ("store_objects", Json::number(8)),
                ("store_record_bytes", Json::number(1048576)),
                ("result_payload_bytes", Json::number(65536)),
                ("retention_policy_wire", Json::string(common.retention_policy)),
                ("source_free", source_free),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  )
  let read = product_require(
    product_wire(
      product_object([
        ("version", Json::string("actql-config/0.1")),
        (
          "native",
          product_object([
            (
              "result_read",
              product_object([
                ("enabled", Json::boolean(true)),
                ("principal", Json::string(principal)),
                ("connection", Json::string(connection)),
                (
                  "result_names",
                  product_texts(
                    if mock is Some(subjects) {
                      if subjects.update_target is Some(_) {
                        ["answer", "main", "updates"]
                      } else {
                        ["answer", "main"]
                      }
                    } else {
                      ["answer"]
                    },
                  ),
                ),
                ("formats", product_texts(["csv", "json", "jsonl"])),
                ("purpose", Json::string("cli-read")),
                ("sink", Json::string("stdout")),
                ("data_policy_cids", product_texts([policy])),
                ("max_bytes", Json::number(65536)),
                ("max_uses", Json::number(1)),
                ("expires_at", Json::string(common.expires)),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  )
  let configuration = product_require(
    product_wire(
      product_object([
        ("version", Json::string("actql-config/0.1")),
        ("account_config", Json::string("account.json")),
        ("state_dir", Json::string(configuration_root + "/host")),
        (
          "native",
          product_object([
            (
              "check_environment",
              product_object([
                ("file", Json::string("environment.json")),
                ("evidence_bundle_cid", Json::string(common.evidence)),
              ]),
            ),
            (
              "local",
              product_object([
                ("account_id", Json::string(principal)),
                ("principal", Json::string(principal)),
                ("connection", Json::string(connection)),
                ("state_parent", Json::string(configuration_root)),
                ("state_name", Json::string("host")),
                ("managed_root", Json::string(configuration_root)),
                ("sqlite_library", Json::string(sqlite_library)),
                ("signature_library", Json::string(signature_library)),
                ("submission_ttl_ms", Json::number(86400000)),
                ("journal_record_limit", Json::number(8)),
                ("journal_snapshot_bytes", Json::number(8388608)),
                (
                  "installation_files",
                  product_texts([
                    "read.json", "run.json", "retention.json", "store.json",
                  ]),
                ),
                ("run_file", Json::string("run.json")),
                ("read_file", Json::string("read.json")),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  )
  let originals = [
    ("account.json", @utf8.encode(common.account)),
    ("config.json", @utf8.encode(configuration)),
    ("environment.json", @utf8.encode(assets.environment)),
    ("run.json", @utf8.encode(run)),
    ("read.json", @utf8.encode(read)),
    ("retention.json", @utf8.encode(common.retention_dependencies)),
    ("store.json", @utf8.encode(common.store)),
  ]
  if profile is Some(profile) {
    // First explicit finite adoption only. The old factory and restored
    // absolute originals never enter this branch and remain byte-identical.
    for index, (name, bytes) in originals {
      if name == "config.json" || name == "read.json" {
        let text = @utf8.decode(bytes) catch {
          _ => return Err(ConfigurationLimit)
        }
        let value = @json.parse(text) catch {
          _ => return Err(ConfigurationLimit)
        }
        guard value is Object(root) &&
          root.get("native") is Some(Object(native)) else {
          return Err(ConfigurationLimit)
        }
        if name == "config.json" {
          guard native.get("local") is Some(Object(settings)) else {
            return Err(ConfigurationLimit)
          }
          settings["run_policy_profile_file"] = Json::string("profile.json")
          settings["installation_files"] = product_texts([
            "read.json", "run.json", "retention.json", "store.json", "profile.json",
            "material-read.json", "file-read.json",
          ])
        } else {
          guard native.get("result_read") is Some(Object(read)) else {
            return Err(ConfigurationLimit)
          }
          read.remove("expires_at") |> ignore
          read["run_policy_profile_cid"] = Json::string(
            client_local_run_policy_profile_cid(profile),
          )
          read["run_file"] = Json::string("run.json")
          read["retention_file"] = Json::string("retention.json")
          read["store_file"] = Json::string("store.json")
        }
        originals[index] = (
          name,
          @utf8.encode(product_require(product_wire(value))),
        )
      }
    }
    originals.push(
      (
        "profile.json",
        @utf8.encode(client_local_run_policy_profile_wire(profile)),
      ),
    )
    // Independent initial Material selection. Preserve the stdout original's
    // bytes/CID and its existing saved Run-policy identity unchanged.
    guard originals.iter().find_first(entry => entry.0 == "read.json")
      is Some((_, read_bytes)) else {
      return Err(ConfigurationLimit)
    }
    let material_text = @utf8.decode(read_bytes) catch {
      _ => return Err(ConfigurationLimit)
    }
    let material = @json.parse(material_text) catch {
      _ => return Err(ConfigurationLimit)
    }
    guard material is Object(root) &&
      root.get("native") is Some(Object(native)) &&
      native.get("result_read") is Some(Object(read)) else {
      return Err(ConfigurationLimit)
    }
    read["sink"] = Json::string("material")
    read["purpose"] = Json::string("cli-table")
    read["formats"] = product_texts(["json"])
    originals.push(
      (
        "material-read.json",
        @utf8.encode(product_require(product_wire(material))),
      ),
    )
    // Independent first-initialization File selection. Neither a later CLI
    // destination nor a restored stdout original manufactures this policy.
    // The original stdout and Material bodies remain byte-identical.
    let file = @json.parse(material_text) catch {
      _ => return Err(ConfigurationLimit)
    }
    guard file is Object(root) &&
      root.get("native") is Some(Object(native)) &&
      native.get("result_read") is Some(Object(read)) else {
      return Err(ConfigurationLimit)
    }
    read["sink"] = Json::string("file")
    read["purpose"] = Json::string("cli-file")
    originals.push(
      ("file-read.json", @utf8.encode(product_require(product_wire(file)))),
    )
  }
  Ok(originals)
}

///|
priv suberror ProductConfigurationFailure {
  ProductConfigurationFailure(ClientLocalProductConfigurationIssue)
}

///|
fn[T] product_require(
  value : Result[T, ClientLocalProductConfigurationIssue],
) -> T raise ProductConfigurationFailure {
  match value {
    Ok(value) => value
    Err(issue) => raise ProductConfigurationFailure(issue)
  }
}

///|
/// Create bounded originals for the first explicit adoption only. This pure
/// assembler does not inspect files, issue authority or repair lost originals.
pub fn client_local_product_originals(
  configuration_root : String,
  sqlite_library : String,
  signature_library : String,
  observed_at : String,
  assets : ClientLocalProductAssets,
) -> Result[Array[(String, Bytes)], ClientLocalProductConfigurationIssue] {
  product_assemble_originals(
    configuration_root, sqlite_library, signature_library, observed_at, assets,
  ) catch {
    ProductConfigurationFailure(issue) => Err(issue)
  }
}

///|
/// Distinct first-install metadata for an explicitly selected finite profile.
/// It does not adopt, renew old installations, accept work or authorize read.
pub fn client_local_product_finite_originals(
  configuration_root : String,
  sqlite_library : String,
  signature_library : String,
  observed_at : String,
  assets : ClientLocalProductAssets,
  mock? : @authorization.LocalMockAccountSubjects? = None,
) -> Result[Array[(String, Bytes)], ClientLocalProductConfigurationIssue] {
  product_assemble_originals(
    configuration_root,
    sqlite_library,
    signature_library,
    observed_at,
    assets,
    finite_run_profile=true,
    mock~,
  ) catch {
    ProductConfigurationFailure(issue) => Err(issue)
  }
}

///|
/// Assemble the shared bounded originals without requiring Native library
/// paths, Native configuration or a CLI read purpose. This is first-adoption
/// metadata only; each Host must still enforce current Account, Policy, Store
/// and custody checks through the existing Owners.
pub fn client_local_product_common_originals(
  configuration_root : String,
  observed_at : String,
  assets : ClientLocalProductAssets,
) -> Result[
  ClientLocalProductCommonOriginals,
  ClientLocalProductConfigurationIssue,
] {
  try {
    let common = product_require(
      product_assemble_common(configuration_root, observed_at, assets),
    )
    Ok({
      account: @utf8.encode(common.account),
      retention_dependencies: @utf8.encode(common.retention_dependencies),
      retention_policy: @utf8.encode(common.retention_policy),
      store: @utf8.encode(common.store),
      result_policy: @utf8.encode(common.result_policy),
    })
  } catch {
    ProductConfigurationFailure(issue) => Err(issue)
  }
}
