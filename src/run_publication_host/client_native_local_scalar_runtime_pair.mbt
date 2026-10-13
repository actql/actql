///|
/// Finite descriptor/body evidence only. No file observation, original adoption
/// custody, current authority or permission to resume an old Run is issued.
struct ClientNativeLocalScalarRuntimePair {
  original : ClientNativeLocalRuntime
  current : ClientNativeLocalRuntime
  body : Bytes
}

///|
pub(all) enum ClientNativeLocalScalarRuntimePairIssue {
  UnknownPredecessor
  UnsupportedPlatform
  LibraryChanged
  AssetChanged
  InvalidOriginal
  ForeignPreparation
  Encoding
} derive(Eq, Debug)

///|
fn scalar_pair_asset(
  assets : ClientLocalProductAssets,
  role : String,
) -> String? {
  match role {
    "environment" => Some(assets.environment)
    "registry" => Some(assets.registry)
    "values" => Some(assets.values)
    "fragment" => Some(assets.fragment)
    "ordered" => assets.ordered
    "result-policy" => Some(assets.result_policy)
    _ => None
  }
}

///|
fn scalar_pair_assets(
  runtime : ClientNativeLocalRuntime,
  assets : ClientLocalProductAssets,
  original : Bool,
) -> Result[Unit, ClientNativeLocalScalarRuntimePairIssue] {
  let mut count = 0
  for entry in runtime.members {
    if !entry.path.has_prefix("data/") {
      continue
    }
    guard scalar_pair_asset(assets, entry.role) is Some(wire) else {
      return Err(AssetChanged)
    }
    let expected = if original {
      native_local_scalar_pair_original_asset_hash(entry.role)
    } else {
      native_local_scalar_pair_current_asset_hash(entry.role)
    }
    let bytes = @utf8.encode(wire)
    if expected != Some(entry.sha256) ||
      bytes.length().to_int64() != entry.bytes ||
      @sha.hex(bytes) != entry.sha256 {
      return Err(AssetChanged)
    }
    count += 1
  }
  if count != 6 || assets.ordered is None {
    return Err(AssetChanged)
  }
  Ok(())
}

///|
/// Inspect the single retained predecessor and source-bound asset pair.
/// Native must obtain the predecessor from authentic adoption, verify the
/// entire current physical package and commit this metadata in its original
/// transaction. Publicly copied bytes cannot supply any of those facts.
pub fn inspect_client_native_local_scalar_runtime_pair(
  original : ClientNativeLocalRuntime,
  current : ClientNativeLocalRuntime,
  original_assets : ClientLocalProductAssets,
  current_assets : ClientLocalProductAssets,
) -> Result[
  ClientNativeLocalScalarRuntimePair,
  ClientNativeLocalScalarRuntimePairIssue,
] {
  let evidence = @utf8.encode(native_local_scalar_pair_evidence_wire())
  if evidence.length() > 8192 ||
    "sha256:" + @sha.hex(evidence) != native_local_scalar_pair_evidence_cid() {
    return Err(InvalidOriginal)
  }
  if original.source_sha != "109564ef9a4f8241096292843b875d4c81fbb6f3" ||
    @sha.hex(@utf8.encode(original.wire)) !=
    "80731853b15f4d600ef391b3778c734bc40bfb6caed246c0c145916b419e49bd" {
    return Err(UnknownPredecessor)
  }
  if original.platform != "darwin-arm64" ||
    current.platform != original.platform {
    return Err(UnsupportedPlatform)
  }
  if validate_client_native_local_runtime_library_components(original, current)
    is Err(_) {
    return Err(LibraryChanged)
  }
  match scalar_pair_assets(original, original_assets, true) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match scalar_pair_assets(current, current_assets, false) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let body = match
    client_local_original_record_body([
      ("current_manifest_sha256", @sha.hex(@utf8.encode(current.wire))),
      ("current_source_sha", current.source_sha),
      ("evidence_cid", native_local_scalar_pair_evidence_cid()),
      ("original_manifest_sha256", @sha.hex(@utf8.encode(original.wire))),
      ("original_source_sha", original.source_sha),
      ("platform", original.platform),
      ("profile", "primitive-scalar-values"),
      ("version", "actql-native-local-scalar-runtime-pair/0.1"),
    ]) {
    Ok(value) => value
    Err(_) => return Err(Encoding)
  }
  Ok({ original, current, body, })
}

///|
/// Reconstruct exact metadata from the same independently obtained inputs.
/// This reader never admits caller-supplied evidence, restores missing custody,
/// changes a source identity or repairs a saved body.
pub fn restore_client_native_local_scalar_runtime_pair(
  body : Bytes,
  original : ClientNativeLocalRuntime,
  current : ClientNativeLocalRuntime,
  original_assets : ClientLocalProductAssets,
  current_assets : ClientLocalProductAssets,
) -> Result[
  ClientNativeLocalScalarRuntimePair,
  ClientNativeLocalScalarRuntimePairIssue,
] {
  inspect_client_native_local_scalar_runtime_pair(
    original, current, original_assets, current_assets,
  ).bind(pair => if body == pair.body { Ok(pair) } else { Err(InvalidOriginal) })
}

///|
pub fn client_native_local_scalar_runtime_pair_body(
  pair : ClientNativeLocalScalarRuntimePair,
) -> Bytes {
  pair.body
}

///|
/// Retain the nominal original preparation; this is not re-compilation against
/// current contracts. Missing original material has no alternative here.
pub fn validate_client_native_local_scalar_runtime_pair_preparation(
  pair : ClientNativeLocalScalarRuntimePair,
  profile : ClientNativeLocalScalarValuesProfile,
  prepared : PreparedClientProgram,
) -> Result[Unit, ClientNativeLocalScalarRuntimePairIssue] {
  if pair.original.platform != pair.current.platform ||
    validate_client_native_local_scalar_values_preparation(profile, prepared)
    is Err(_) {
    return Err(ForeignPreparation)
  }
  for
    index in 0..<client_native_local_scalar_values_profile_operation_count(
      profile,
    ) {
    if client_native_local_scalar_values_profile_operation_at(profile, index)
      is Some(operation) &&
      ["REL.values", "REL.derive", "REL.where", "REL.select"].contains(
        operation,
      ) {
      continue
    }
    return Err(ForeignPreparation)
  }
  Ok(())
}
