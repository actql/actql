///|
// Borrow the actual current whole-package observation. This is neither an
// authority nor another adoption Owner; the Host retains its original files.
priv struct NativeLocalRuntimeBinding {
  current : NativeLocalPackagedRuntime
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
fn local_runtime_binding_current(
  host : NativeLocalHostConnection,
  binding : NativeLocalRuntimeBinding,
) -> Bool {
  if binding.current.check_current() is Err(_) ||
    !local_policy_upgrade_current(
      host,
      host.epoch.crypto,
      binding.principal,
      binding.connection,
      binding.scope,
      false,
    ) {
    return false
  }
  for file in binding.files {
    if !(host.selected_configuration(file.name) is Ok(body) && body == file.body) {
      return false
    }
  }
  binding.current.check_current() is Ok(_)
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
  let scope = match
    self.authority_scope_cid(principal, connection, self.epoch.crypto) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if !local_policy_upgrade_current(
      self,
      self.epoch.crypto,
      principal,
      connection,
      scope,
      false,
    ) {
    return Err(AuthorizationDenied)
  }
  let files : Array[NativeLocalSelectedFile] = []
  for name in [environment_file, run_file, runtime_file] {
    if files.any(file => file.name == name) {
      return Err(CustodyLost)
    }
    match local_run_policy_selected(self, name) {
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
  let assets = match current.assets() {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let pair = if original_wire ==
    @host.client_native_local_runtime_original(manifest) {
    // The unchanged cohort is not a migration; preserve its original path.
    if original_assets.environment != assets.environment ||
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
  let binding = { current, files, pair, principal, connection, scope, }
  if !local_runtime_binding_current(self, binding) {
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
