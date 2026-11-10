///|
/// A bounded installation descriptor, never an adoption or execution permit.
/// Its fields use the existing formal Native Local runtime recipe.
pub struct ClientNativeLocalRuntime {
  wire : String
  source_sha : String
  platform : String
  members : Array[ClientNativeLocalRuntimeMember]
}

///|
pub(all) struct ClientNativeLocalRuntimeMember {
  role : String
  path : String
  bytes : Int64
  sha256 : String
}

///|
pub(all) enum ClientNativeLocalRuntimeIssue {
  InvalidIdentity
  InvalidManifest
  InvalidMember
  InvalidClosure
  CapacityExceeded
} derive(Eq, Debug)

///|
priv suberror ProductRuntimeFailure {
  ProductRuntimeFailure(ClientNativeLocalRuntimeIssue)
}

///|
fn[T] runtime_refuse(
  issue : ClientNativeLocalRuntimeIssue,
) -> T raise ProductRuntimeFailure {
  raise ProductRuntimeFailure(issue)
}

///|
fn runtime_hex(value : String, length : Int) -> Bool {
  value.length() == length &&
  value.iter().all(c => (c >= 'a' && c <= 'f') || (c >= '0' && c <= '9'))
}

///|
fn runtime_filename(value : String) -> Bool {
  if value.is_empty() || value.length() > 128 {
    return false
  }
  let chars = value.iter().to_array()
  let alnum = fn(c) {
    (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
  }
  alnum(chars[0]) &&
  chars.all(c => alnum(c) || c == '_' || c == '.' || c == '-')
}

///|
fn runtime_object(
  cursor : @decode.Cursor,
  keys : Array[String],
) -> @decode.ObjectView raise ProductRuntimeFailure {
  let object = @decode.closed_object(cursor, keys).unwrap_or_else(() => {
    runtime_refuse(InvalidManifest)
  })
  for key in keys {
    if @decode.lookup(object, key) is None {
      runtime_refuse(InvalidManifest)
    }
  }
  object
}

///|
fn runtime_text(
  object : @decode.ObjectView,
  key : String,
) -> String raise ProductRuntimeFailure {
  let value = @decode.lookup(object, key).unwrap_or_else(() => {
    runtime_refuse(InvalidManifest)
  })
  @decode.text(value).unwrap_or_else(() => runtime_refuse(InvalidManifest))
}

///|
fn runtime_elements(
  object : @decode.ObjectView,
  key : String,
  min : Int,
  max : Int,
) -> Array[@decode.Cursor] raise ProductRuntimeFailure {
  let value = @decode.lookup(object, key).unwrap_or_else(() => {
    runtime_refuse(InvalidManifest)
  })
  let values = @decode.elements(value).unwrap_or_else(() => {
    runtime_refuse(InvalidManifest)
  })
  if values.length() < min || values.length() > max {
    runtime_refuse(InvalidManifest)
  }
  values
}

///|
fn runtime_member(
  object : @decode.ObjectView,
  role : String,
  prefix : String,
  limit : Int64,
) -> ClientNativeLocalRuntimeMember raise ProductRuntimeFailure {
  let path = runtime_text(object, "path")
  let parts = path.split("/").to_array()
  let hash = runtime_text(object, "sha256")
  let bytes = @decode.lookup(object, "bytes")
    .bind(value => @decode.safe_integer(value).to_option())
    .unwrap_or_else(() => runtime_refuse(InvalidMember))
  if parts.length() != 2 ||
    parts[0] != prefix ||
    !runtime_filename(parts[1].to_owned()) ||
    !runtime_hex(hash, 64) ||
    bytes < 1L ||
    bytes > limit {
    runtime_refuse(InvalidMember)
  }
  { role, path, bytes, sha256: hash, }
}

///|
fn runtime_assemble(
  wire : String,
  source_sha : String,
  platform : String,
  manifest_sha256 : String,
) -> ClientNativeLocalRuntime raise ProductRuntimeFailure {
  if !runtime_hex(source_sha, 40) ||
    !runtime_hex(manifest_sha256, 64) ||
    (platform != "darwin-arm64" && platform != "linux-x64-gnu") {
    runtime_refuse(InvalidIdentity)
  }
  let bytes = @utf8.encode(wire)
  if bytes.length() > 65536 {
    runtime_refuse(CapacityExceeded)
  }
  if @sha.hex(bytes) != manifest_sha256 {
    runtime_refuse(InvalidIdentity)
  }
  let source = @source.parse_json_bytes_preserving(bytes, {
    max_input_bytes: 65536,
    max_nodes: 8192,
    max_depth: 64,
  }).unwrap_or_else(() => runtime_refuse(InvalidManifest))
  let cursor = @decode.admit(source, {
    max_nodes: 8192,
    max_depth: 64,
    max_string_bytes: 65536,
    max_total_string_bytes: 65536,
  }).unwrap_or_else(() => runtime_refuse(InvalidManifest))
  let root = runtime_object(cursor, [
    "sourceSha", "platform", "libraries", "assets", "licenses",
  ])
  if runtime_text(root, "sourceSha") != source_sha ||
    runtime_text(root, "platform") != platform {
    runtime_refuse(InvalidIdentity)
  }
  let members : Array[ClientNativeLocalRuntimeMember] = []
  let paths : Array[String] = []
  let mut total = 0L
  let append = fn(
    entry : ClientNativeLocalRuntimeMember,
  ) -> Unit raise ProductRuntimeFailure {
    if paths.contains(entry.path) {
      runtime_refuse(InvalidMember)
    }
    total += entry.bytes
    if total > 67108864L {
      runtime_refuse(CapacityExceeded)
    }
    paths.push(entry.path)
    members.push(entry)
  }
  let licenses : Array[String] = []
  for item in runtime_elements(root, "licenses", 1, 8) {
    let object = runtime_object(item, ["path", "bytes", "sha256"])
    let entry = runtime_member(object, "license", "licenses", 1048576L)
    licenses.push(entry.path)
    append(entry)
  }
  let library_names : Array[String] = []
  let library_roles : Array[String] = []
  let used_licenses : Array[String] = []
  let dependencies : Array[String] = []
  for item in runtime_elements(root, "libraries", 2, 8) {
    let object = runtime_object(item, [
      "role", "path", "bytes", "sha256", "license", "dependencies", "abi",
    ])
    let role = runtime_text(object, "role")
    if role != "sqlite" && role != "crypto" && role != "dependency" {
      runtime_refuse(InvalidMember)
    }
    if role != "dependency" {
      if library_roles.contains(role) {
        runtime_refuse(InvalidMember)
      }
      library_roles.push(role)
    }
    let entry = runtime_member(object, role, "lib", 67108864L)
    library_names.push(entry.path.split("/").to_array()[1].to_owned())
    let license = runtime_text(object, "license")
    if !licenses.contains(license) {
      runtime_refuse(InvalidClosure)
    }
    used_licenses.push(license)
    let declared : Array[String] = []
    for value in runtime_elements(object, "dependencies", 0, 8) {
      let name = @decode.text(value).unwrap_or_else(() => {
        runtime_refuse(InvalidClosure)
      })
      if declared.contains(name) {
        runtime_refuse(InvalidClosure)
      }
      declared.push(name)
      dependencies.push(name)
    }
    let key = if platform == "darwin-arm64" {
      "minimumMacOS"
    } else {
      "minimumGlibc"
    }
    let abi = runtime_object(@decode.lookup(object, "abi").unwrap(), [key])
    let version = runtime_text(abi, key).split(".").to_array()
    if (version.length() != 2 && version.length() != 3) ||
      !version.all(part => {
        !part.is_empty() && part.iter().all(c => c >= '0' && c <= '9')
      }) {
      runtime_refuse(InvalidManifest)
    }
    append(entry)
  }
  if !library_roles.contains("sqlite") ||
    !library_roles.contains("crypto") ||
    !licenses.all(path => used_licenses.contains(path)) {
    runtime_refuse(InvalidClosure)
  }
  let systems = if platform == "darwin-arm64" {
    ["/usr/lib/libSystem.B.dylib", "/usr/lib/libz.1.dylib"]
  } else {
    [
      "libc.so.6", "libm.so.6", "libdl.so.2", "libpthread.so.0", "librt.so.1", "ld-linux-x86-64.so.2",
    ]
  }
  if !dependencies.all(name => {
      library_names.contains(name) || systems.contains(name)
    }) {
    runtime_refuse(InvalidClosure)
  }
  let asset_roles : Array[String] = []
  for item in runtime_elements(root, "assets", 5, 6) {
    let object = runtime_object(item, ["role", "path", "bytes", "sha256"])
    let role = runtime_text(object, "role")
    if ![
        "environment", "registry", "values", "fragment", "ordered", "result-policy",
      ].contains(role) ||
      asset_roles.contains(role) {
      runtime_refuse(InvalidMember)
    }
    let entry = runtime_member(object, role, "data", 65536L)
    if entry.path != "data/" + role + ".json" {
      runtime_refuse(InvalidMember)
    }
    asset_roles.push(role)
    append(entry)
  }
  if !["environment", "registry", "values", "fragment", "result-policy"].all(role => {
      asset_roles.contains(role)
    }) {
    runtime_refuse(InvalidClosure)
  }
  { wire, source_sha, platform, members, }
}

///|
/// Admit installation data under the existing recipe bounds. This does not
/// prove the files, loader ABI, adoption, current policy or execution authority.
pub fn admit_client_native_local_runtime(
  wire : String,
  source_sha : String,
  platform : String,
  manifest_sha256 : String,
) -> Result[ClientNativeLocalRuntime, ClientNativeLocalRuntimeIssue] {
  Ok(runtime_assemble(wire, source_sha, platform, manifest_sha256)) catch {
    ProductRuntimeFailure(issue) => Err(issue)
  }
}

///|
pub fn client_native_local_runtime_members(
  value : ClientNativeLocalRuntime,
) -> Array[ClientNativeLocalRuntimeMember] {
  value.members.copy()
}

///|
pub fn client_native_local_runtime_original(
  value : ClientNativeLocalRuntime,
) -> String {
  value.wire
}

///|
/// Keep the exact runtime manifest among the existing selected originals.
/// This is still first-adoption input, not a restoration or permission issuer.
fn assemble_client_native_local_product_originals(
  configuration_root : String,
  sqlite_library : String,
  signature_library : String,
  observed_at : String,
  assets : ClientLocalProductAssets,
  runtime : ClientNativeLocalRuntime,
  finite_run_profile? : Bool = false,
  mock? : @authorization.LocalMockAccountSubjects? = None,
  host_configuration? : String? = None,
) -> Result[Array[(String, Bytes)], ClientLocalProductConfigurationIssue] {
  try {
    // Packaged asset bytes must match this exact original manifest, not merely
    // another accepted registry or a freshly generated replacement body.
    for entry in runtime.members {
      let body = match entry.role {
        "environment" => Some(assets.environment)
        "registry" => Some(assets.registry)
        "values" => Some(assets.values)
        "fragment" => Some(assets.fragment)
        "ordered" => assets.ordered
        "result-policy" => Some(assets.result_policy)
        _ => None
      }
      if entry.path.has_prefix("data/") {
        guard body is Some(wire) else { return Err(UnsupportedAsset) }
        let bytes = @utf8.encode(wire)
        if bytes.length().to_int64() != entry.bytes ||
          @sha.hex(bytes) != entry.sha256 {
          return Err(UnsupportedAsset)
        }
      }
    }
    if assets.ordered is Some(_) &&
      !runtime.members.any(entry => entry.role == "ordered") {
      return Err(UnsupportedAsset)
    }
    let originals = product_require(
      if finite_run_profile {
        client_local_product_finite_originals(
          configuration_root,
          sqlite_library,
          signature_library,
          observed_at,
          assets,
          mock~,
        )
      } else {
        client_local_product_originals(
          configuration_root, sqlite_library, signature_library, observed_at, assets,
        )
      },
    )
    // Trusted first-install Mock selection only. The Account already contains
    // this explicit Sign tuple; retaining it grants no key use or permission.
    let initial_host_signing = match (mock, host_configuration) {
      (Some(subjects), Some(wire)) if finite_run_profile &&
        subjects.signing_key_resource is Some(resource) => {
        let configuration = match
          admit_client_host_signer_configuration(wire, {
            max_wire_bytes: 65536,
            max_nodes: 1024,
            max_depth: 16,
            max_signers: 64,
          }) {
          Ok(value) if !value.has_explicit_signers() => value
          _ => return Err(UnsupportedAsset)
        }
        ignore(configuration)
        Some((subjects.principal, subjects.control_connection, resource))
      }
      (_, Some(_)) => return Err(UnsupportedAsset)
      _ => None
    }
    for index, (name, bytes) in originals {
      if name == "config.json" {
        let wire = @utf8.decode(bytes) catch {
          _ => return Err(ConfigurationLimit)
        }
        let config = @json.parse(wire) catch {
          _ => return Err(ConfigurationLimit)
        }
        guard config is Object(root) &&
          root.get("native") is Some(Object(native)) &&
          native.get("local") is Some(Object(settings)) else {
          return Err(ConfigurationLimit)
        }
        let selected = [
          "read.json", "run.json", "retention.json", "store.json", "runtime.json",
        ]
        if finite_run_profile {
          selected.push("profile.json")
          selected.push("material-read.json")
          selected.push("file-read.json")
        }
        if initial_host_signing is Some((principal, connection, resource)) {
          settings["initial_host_signing"] = product_object([
            ("principal", Json::string(principal)),
            ("connection", Json::string(connection)),
            ("resource", Json::string(resource)),
          ])
        }
        settings["installation_files"] = product_texts(selected)
        originals[index] = (
          name,
          @utf8.encode(product_require(product_wire(config))),
        )
      }
    }
    if initial_host_signing is Some(_) {
      // Preserve the supplied operator original, including its exact bytes.
      // Pure assembly proves no path/custody/current or absent-file witness.
      // The physical initializer must retain the actual selected Host input.
      originals.push(("host.json", @utf8.encode(host_configuration.unwrap())))
    }
    originals.push(("runtime.json", @utf8.encode(runtime.wire)))
    Ok(originals)
  } catch {
    ProductConfigurationFailure(issue) => Err(issue)
  }
}

///|
/// Existing absolute first-adoption profile. Restored installations retain
/// these bytes and are never silently converted to finite Run issuance.
pub fn client_native_local_product_originals(
  configuration_root : String,
  sqlite_library : String,
  signature_library : String,
  observed_at : String,
  assets : ClientLocalProductAssets,
  runtime : ClientNativeLocalRuntime,
) -> Result[Array[(String, Bytes)], ClientLocalProductConfigurationIssue] {
  assemble_client_native_local_product_originals(
    configuration_root, sqlite_library, signature_library, observed_at, assets, runtime,
  )
}

///|
/// Explicit first-adoption finite metadata using the same verified runtime
/// cohort. Physical adoption/current authority and per-Run acceptance remain
/// required. The original library/asset manifest and selected limits persist.
pub fn client_native_local_finite_product_originals(
  configuration_root : String,
  sqlite_library : String,
  signature_library : String,
  observed_at : String,
  assets : ClientLocalProductAssets,
  runtime : ClientNativeLocalRuntime,
  mock? : @authorization.LocalMockAccountSubjects? = None,
  host_configuration? : String? = None,
) -> Result[Array[(String, Bytes)], ClientLocalProductConfigurationIssue] {
  assemble_client_native_local_product_originals(
    configuration_root,
    sqlite_library,
    signature_library,
    observed_at,
    assets,
    runtime,
    finite_run_profile=true,
    mock~,
    host_configuration~,
  )
}
