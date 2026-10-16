///|
// Compare all six asset metadata entries against the already complete,
// source-bound build-time body proof. This does not open or reconstruct them.
fn historical_scalar_pair_asset_metadata(
  runtime : ClientNativeLocalRuntime,
  original : Bool,
) -> Bool {
  let mut count = 0
  for entry in runtime.members {
    if !entry.path.has_prefix("data/") {
      continue
    }
    let hash = if original {
      native_local_scalar_pair_original_asset_hash(entry.role)
    } else {
      native_local_scalar_pair_current_asset_hash(entry.role)
    }
    let bytes = if original {
      native_local_scalar_historical_original_asset_bytes(entry.role)
    } else {
      native_local_scalar_historical_current_asset_bytes(entry.role)
    }
    if hash != Some(entry.sha256) || bytes != Some(entry.bytes) {
      return false
    }
    count += 1
  }
  count == 6
}

///|
/// Restore only the logical metadata of the single retained old109/a3b pair.
/// Its fixed generated input revalidates the existing complete body proof.
/// The ordinary inspect/restore APIs still require their actual six bodies.
///
/// Native must separately authenticate the saved packet, adoption and scope,
/// observe the complete current package, select the formal corrective cohort,
/// and retain the same transaction/HMAC/current/cleanup responsibilities. This
/// does not restore missing Run/Prepared/data originals or issue compatibility,
/// physical custody, current authority, signing permission or a new CID domain.
pub fn restore_client_native_local_historical_scalar_runtime_pair_metadata(
  saved_body : Bytes,
  original : ClientNativeLocalRuntime,
  historical : ClientNativeLocalRuntime,
) -> Result[
  ClientNativeLocalScalarRuntimePair,
  ClientNativeLocalScalarRuntimePairIssue,
] {
  let evidence = @utf8.encode(native_local_scalar_pair_evidence_wire())
  if evidence.length() > 8192 ||
    "sha256:" + @sha.hex(evidence) != native_local_scalar_pair_evidence_cid() ||
    native_local_scalar_pair_evidence_cid() !=
    native_local_scalar_historical_evidence_cid() {
    return Err(InvalidOriginal)
  }
  if original.source_sha != "109564ef9a4f8241096292843b875d4c81fbb6f3" ||
    @sha.hex(@utf8.encode(original.wire)) !=
    "80731853b15f4d600ef391b3778c734bc40bfb6caed246c0c145916b419e49bd" {
    return Err(UnknownPredecessor)
  }
  if historical.source_sha != native_local_scalar_historical_source() ||
    @sha.hex(@utf8.encode(historical.wire)) !=
    native_local_scalar_historical_manifest_hash() {
    return Err(InvalidOriginal)
  }
  if original.platform != "darwin-arm64" ||
    historical.platform != original.platform {
    return Err(UnsupportedPlatform)
  }
  if validate_client_native_local_runtime_library_components(
      original, historical,
    )
    is Err(_) {
    return Err(LibraryChanged)
  }
  if !historical_scalar_pair_asset_metadata(original, true) ||
    !historical_scalar_pair_asset_metadata(historical, false) {
    return Err(AssetChanged)
  }
  // No caller proof, parsed JSON, source label or current default is selected.
  // The exact saved preimage remains the final equality, never a repaired body.
  scalar_pair_metadata(original, historical).bind(pair => {
    if saved_body == pair.body {
      Ok(pair)
    } else {
      Err(InvalidOriginal)
    }
  })
}
