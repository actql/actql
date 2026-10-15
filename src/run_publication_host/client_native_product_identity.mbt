///|
/// Closed private packaging metadata used by the adopted finite successor.
/// It identifies bytes only: no custody, release trust, compatibility, current
/// permission, claim or new CID domain is issued by this pure codec.
struct ClientNativeProductIdentity {
  wire : String
}

///|
fn product_identity_keys() -> Array[String] {
  [
    "launcher_inventory_sha256", "native_binary_sha256", "platform", "platform_inventory_sha256",
    "runtime_manifest_sha256", "source_sha",
  ]
}

///|
/// Preserve the exact six-field identity from the adopted successor proposal.
/// Expected digests are metadata here; Native must obtain them from the same
/// real complete-product observation and separately check the trusted cohort.
pub fn client_native_product_identity(
  launcher_inventory_sha256 : String,
  native_binary_sha256 : String,
  platform : String,
  platform_inventory_sha256 : String,
  runtime_manifest_sha256 : String,
  source_sha : String,
) -> Result[ClientNativeProductIdentity, ClientNativeLocalRuntimeIssue] {
  if ![
      launcher_inventory_sha256, native_binary_sha256, platform_inventory_sha256,
      runtime_manifest_sha256,
    ].all(value => runtime_hex(value, 64)) ||
    !runtime_hex(source_sha, 40) ||
    !(platform == "darwin-arm64" || platform == "linux-x64-gnu") {
    return Err(InvalidIdentity)
  }
  let fields = [
    launcher_inventory_sha256, native_binary_sha256, platform, platform_inventory_sha256,
    runtime_manifest_sha256, source_sha,
  ]
  let body = match
    client_local_original_record_body(
      product_identity_keys().mapi((i, key) => (key, fields[i])),
    ) {
    Ok(value) => value
    Err(_) => return Err(CapacityExceeded)
  }
  let wire = @utf8.decode(body) catch { _ => return Err(InvalidManifest) }
  Ok({ wire, })
}

///|
/// Decode literal original metadata only. Noncanonical or repaired copies do
/// not become a new original, and this reader cannot reconstruct physical ACK.
pub fn read_client_native_product_identity(
  wire : String,
) -> Result[ClientNativeProductIdentity, ClientNativeLocalRuntimeIssue] {
  let body = @utf8.encode(wire)
  // The successor's existing per-field intake, not memory admission.
  if body.length() > 4096 {
    return Err(CapacityExceeded)
  }
  let fields = match
    client_local_original_record_fields(body, product_identity_keys()) {
    Ok(value) => value
    Err(_) => return Err(InvalidManifest)
  }
  client_native_product_identity(
    fields[0],
    fields[1],
    fields[2],
    fields[3],
    fields[4],
    fields[5],
  )
}

///|
pub fn client_native_product_identity_wire(
  value : ClientNativeProductIdentity,
) -> String {
  value.wire
}
