///|
// Borrow the actual current whole-package observation. This is neither an
// authority nor another adoption Owner; the Host retains its original files.
priv struct NativeLocalRuntimeBinding {
  current : NativeLocalPackagedRuntime
  installed_assets : (
    @host.ClientLocalProductAssets,
    @local.ClientInstalledSequenceContracts,
  )
  files : Array[NativeLocalSelectedFile]
  pair : @host.ClientNativeLocalScalarRuntimePair?
  principal : String
  connection : String
  scope : String
}

///|
fn local_runtime_original_assets(
  environment : Bytes,
  run : Bytes,
) -> Result[@host.ClientLocalProductAssets, NativeClientRunJournalIssue] {
  let source = match
    @source.parse_json_bytes_preserving(run, {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: 8192,
      max_depth: 64,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  try {
    let root = read_policy_decoded(
      @decode.closed_object(cursor, ["native", "version"]),
    )
    if read_policy_text(root, "version", 32) != "actql-config/0.1" {
      return Err(CustodyLost)
    }
    let native = read_policy_decoded(
      @decode.closed_object(read_policy_field(root, "native"), ["run"]),
    )
    let fields = read_policy_decoded(
      @decode.closed_object(read_policy_field(native, "run"), [
        "namespace_id", "store_name", "store_authority_cid", "store_capacity_bytes",
        "store_objects", "store_record_bytes", "result_payload_bytes", "retention_policy_wire",
        "source_free",
      ]),
    )
    let values = read_policy_decoded(
      @decode.closed_object(read_policy_field(fields, "source_free"), [
        "registry", "values", "fragment", "ordered", "result_policy_cid", "result_policy_wire",
      ]),
    )
    let environment = @utf8.decode(environment) catch {
      _ => return Err(CustodyLost)
    }
    Ok({
      environment,
      registry: read_policy_text(values, "registry", 65536),
      values: read_policy_text(values, "values", 65536),
      fragment: read_policy_text(values, "fragment", 65536),
      ordered: Some(read_policy_text(values, "ordered", 65536)),
      result_policy: read_policy_text(values, "result_policy_wire", 8192),
    })
  } catch {
    LocalReadPolicyStop(_) => Err(CustodyLost)
  }
}

///|
// Operator-selected Host capacity is checking DATA, not a different runtime.
// Every other Environment member and policy stays identical to the installed
// cohort. The existing capacity Owner validates finite quantities and version;
// this comparison issues no Account/current/Run or physical permission.
fn local_runtime_capacity_environment_context(wire : String) -> String? {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => return None
  }
  try {
    let value = @canonical.from_source(source, 8192, 64, 65536)
    guard @canonical.object_field(value, "evidence_bundle_cid")
      is Some(@canonical.String(identity)) &&
      @canonical.object_without_field(value, "evidence_bundle_cid")
      is Some(body) &&
      @canonical.cid_value(body, 65536, 8192, 64) == identity &&
      @canonical.object_field(body, "host_policy_profile") is Some(profile) &&
      @canonical.object_field(profile, "capacity") is Some(capacity) &&
      @canonical.object_without_field(profile, "capacity") is Some(other_policy) else {
      return None
    }
    let capacity_wire = @canonical.stringify_value(capacity, 65536, 8192, 64)
    let capacity_cid = @canonical.cid_value(capacity, 65536, 8192, 64)
    guard @capacity_policy.admit(@utf8.encode(capacity_wire), capacity_cid, {
        max_bytes: 65536,
        max_nodes: 8192,
        max_depth: 64,
      })
      is Ok(_) &&
      @canonical.object_with_replaced_fields(body, [
        ("host_policy_profile", other_policy),
      ])
      is Some(context) else {
      return None
    }
    Some(@canonical.stringify_value(context, 65536, 8192, 64))
  } catch {
    _ => None
  }
}

///|
fn local_runtime_capacity_environment_compatible(
  original : String,
  installed : String,
) -> Bool {
  match
    (
      local_runtime_capacity_environment_context(original),
      local_runtime_capacity_environment_context(installed),
    ) {
    (Some(original), Some(installed)) => original == installed
    _ => false
  }
}

///|
// Private synchronous access preserves the original current/Account/selected
// file operations while an acquired Journal routes each SQL call through its
// own SQLite phase. It is never stored in the binding or accepted publicly.
priv struct NativeLocalRuntimeBindingAccess {
  runtime_current : (NativeLocalPackagedRuntime) -> Bool
  scope : (String, String) -> Result[String, NativeLocalAdoptionIssue]
  read_allowed : (String, String) -> Bool
  selected : (String) -> Result[
    NativeLocalSelectedFile,
    NativeClientRunJournalIssue,
  ]
}

///|
// Only the three closed Runtime binding callers use this synchronous frame.
// Retain one exact principal/connection projection and at most the three
// constructor selections, not an Allow shared with another operation. Every
// getter still observes original lifetime; the caller owns its full entry and
// return fences. Cutting these references is not a physical cleanup ACK.
fn[T] with_local_runtime_binding_frame(
  source : NativeLocalRuntimeBindingAccess,
  current : () -> Bool,
  operation : (NativeLocalRuntimeBindingAccess) -> T,
) -> T {
  let active = Ref(true)
  let scope : Ref[(String, String, Result[String, NativeLocalAdoptionIssue])?] = Ref(
    None,
  )
  // The existing port has the fixed resource=run, operation=read purpose.
  let read : Ref[(String, String, Bool)?] = Ref(None)
  let selected : Array[
    (String, Result[NativeLocalSelectedFile, NativeClientRunJournalIssue]),
  ] = []
  let clear = () => {
    scope.val = None
    read.val = None
    selected.clear()
  }
  let live = () => {
    if active.val && current() {
      true
    } else {
      active.val = false
      clear()
      false
    }
  }
  let access : NativeLocalRuntimeBindingAccess = {
    runtime_current: runtime => live() && (source.runtime_current)(runtime),
    scope: (principal, connection) => {
      if !live() {
        return Err(CustodyLost)
      }
      if scope.val is Some((original_principal, original_connection, value)) &&
        principal == original_principal &&
        connection == original_connection {
        return value
      }
      let value = (source.scope)(principal, connection)
      scope.val = Some((principal, connection, value))
      value
    },
    read_allowed: (principal, connection) => {
      if !live() {
        return false
      }
      if read.val is Some((original_principal, original_connection, value)) &&
        principal == original_principal &&
        connection == original_connection {
        return value
      }
      let value = (source.read_allowed)(principal, connection)
      read.val = Some((principal, connection, value))
      value
    },
    selected: name => {
      if !live() {
        return Err(CustodyLost)
      }
      for (original_name, value) in selected {
        if name == original_name {
          return value
        }
      }
      let value = (source.selected)(name)
      // The actual Runtime constructor names exactly three files. Do not
      // impose a new name restriction if a future caller asks for another;
      // simply avoid retaining additional selections in this frame.
      if selected.length() < 3 {
        selected.push((name, value))
      }
      value
    },
  }
  let result = operation(access)
  active.val = false
  clear()
  result
}

///|
fn native_local_runtime_binding_access(
  host : NativeLocalHostConnection,
) -> NativeLocalRuntimeBindingAccess {
  {
    runtime_current: runtime => runtime.check_current() is Ok(_),
    scope: (principal, connection) => {
      host.authority_scope_cid(principal, connection, host.epoch.crypto)
    },
    read_allowed: (principal, connection) => {
      host.authorize({
        principal,
        connection,
        resource: "run",
        operation: "read",
      })
      is Ok(@authorization.Allow(_))
    },
    selected: name => local_run_policy_selected(host, name),
  }
}

///|
// Binding installation metadata does not read a Run or Result. Their actual
// consumers retain the independent Account authorization at the operation.
fn local_runtime_binding_current_with_access(
  binding : NativeLocalRuntimeBinding,
  access : NativeLocalRuntimeBindingAccess,
) -> Bool {
  if !(access.runtime_current)(binding.current) ||
    !((access.scope)(binding.principal, binding.connection) is Ok(scope) &&
    scope == binding.scope) {
    return false
  }
  for file in binding.files {
    if !((access.selected)(file.name) is Ok(current) &&
      current.body == file.body) {
      return false
    }
  }
  (access.runtime_current)(binding.current)
}

///|
fn local_runtime_binding_current(
  host : NativeLocalHostConnection,
  binding : NativeLocalRuntimeBinding,
) -> Bool {
  local_runtime_binding_current_with_access(
    binding,
    native_local_runtime_binding_access(host),
  )
}

///|
// The frozen pair is descriptor metadata. This implementation has no admitted
// historical operational witness; a caller cannot enable it with DATA or a CID.
fn require_local_historical_runtime_implementation() -> Result[
  Unit,
  NativeClientRunJournalIssue,
] {
  Err(UnsupportedPreparation)
}

///|
/// Original files come only from this authenticated adoption. The predecessor
/// expectation is the retained installed-109 receipt, not the candidate's SHA.
/// Binding observes compatibility inputs; only explicit upgrade can append.
pub fn NativeLocalHostConnection::bind_packaged_runtime(
  self : NativeLocalHostConnection,
  current : NativeLocalPackagedRuntime,
  principal : String,
  connection : String,
  environment_file : String,
  run_file : String,
  runtime_file : String,
) -> Result[Unit, NativeClientRunJournalIssue] {
  self.bind_packaged_runtime_with_access(
    current,
    principal,
    connection,
    environment_file,
    run_file,
    runtime_file,
    native_local_runtime_binding_access(self),
  )
}

///|
fn NativeLocalHostConnection::bind_packaged_runtime_with_access(
  self : NativeLocalHostConnection,
  current : NativeLocalPackagedRuntime,
  principal : String,
  connection : String,
  environment_file : String,
  run_file : String,
  runtime_file : String,
  access : NativeLocalRuntimeBindingAccess,
) -> Result[Unit, NativeClientRunJournalIssue] {
  native_timing_begin(16)
  defer native_timing_end(16)
  let scope = match (access.scope)(principal, connection) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if !((access.scope)(principal, connection) is Ok(current_scope) &&
    current_scope == scope) {
    return Err(AuthorizationDenied)
  }
  let files : Array[NativeLocalSelectedFile] = []
  for name in [environment_file, run_file, runtime_file] {
    if files.any(file => file.name == name) {
      return Err(CustodyLost)
    }
    match (access.selected)(name) {
      Ok(file) => files.push(file)
      Err(issue) => return Err(issue)
    }
  }
  let original_wire = @utf8.decode(files[2].body) catch {
    _ => return Err(CustodyLost)
  }
  let original_assets = match
    local_runtime_original_assets(files[0].body, files[1].body) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let manifest = match current.manifest() {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let installed_assets = match current.installed_assets() {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let (assets, _) = installed_assets
  let pair = if original_wire ==
    @host.client_native_local_runtime_original(manifest) {
    // The unchanged cohort is not a migration; preserve its original path.
    if (
        original_assets.environment != assets.environment &&
        !local_runtime_capacity_environment_compatible(
          original_assets.environment,
          assets.environment,
        )
      ) ||
      original_assets.registry != assets.registry ||
      original_assets.values != assets.values ||
      original_assets.fragment != assets.fragment ||
      original_assets.ordered != assets.ordered ||
      original_assets.result_policy != assets.result_policy {
      return Err(CustodyLost)
    }
    None
  } else {
    match require_local_historical_runtime_implementation() {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    // Original adoption custody and the fixed receipt are independent inputs.
    let original = match
      @host.admit_client_native_local_runtime(
        original_wire, "109564ef9a4f8241096292843b875d4c81fbb6f3", "darwin-arm64",
        "80731853b15f4d600ef391b3778c734bc40bfb6caed246c0c145916b419e49bd",
      ) {
      Ok(value) => value
      Err(_) => return Err(CustodyLost)
    }
    match
      @host.inspect_client_native_local_scalar_runtime_pair(
        original, manifest, original_assets, assets,
      ) {
      Ok(value) => Some(value)
      Err(_) => return Err(CustodyLost)
    }
  }
  let binding = {
    current,
    installed_assets,
    files,
    pair,
    principal,
    connection,
    scope,
  }
  if !local_runtime_binding_current_with_access(binding, access) {
    return Err(AuthorizationDenied)
  }
  // Rebinding cannot replace another physical observation or original role set.
  if self.packaged_runtime is Some(previous) {
    if !physical_equal(previous.current, current) ||
      previous.files.map(file => (file.name, file.content_cid)) !=
      files.map(file => (file.name, file.content_cid)) ||
      previous.scope != scope {
      return Err(ChangedIntent)
    }
  } else {
    self.packaged_runtime = Some(binding)
  }
  Ok(())
}

///|
fn NativeLocalHostConnection::runtime_policy_pair(
  self : NativeLocalHostConnection,
  scope : String,
) -> Result[
  @host.ClientNativeLocalScalarRuntimePair?,
  NativeClientRunJournalIssue,
] {
  match self.packaged_runtime {
    None => Ok(None)
    Some(binding) =>
      if binding.scope == scope && local_runtime_binding_current(self, binding) {
        Ok(binding.pair)
      } else {
        Err(CustodyLost)
      }
  }
}
