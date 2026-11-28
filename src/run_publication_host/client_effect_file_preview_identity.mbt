///|
/// Exact installed file target and selected Mapping facts already admitted by
/// the local Host. The encoder projects these facts into evidence identities.
pub(all) struct ClientEffectFilePreviewInstallation {
  connector_registration : String
  connector_revision : String
  runtime_bundle_cid : String
  binding_cid : String
  connection : String
  resource : String
  mapping_cid : String
  primary_identity : String
}

///|
pub(all) struct ClientEffectFilePreviewIdentity {
  capability_cid : String
  resource_identity_cid : String
}

///|
/// Preview evidence for one selected file Effect and its ordered requests.
/// Approval and dispatch remain with the original Effect owner.
pub fn client_effect_file_preview_identity(
  original : ClientEffectFilePreviewInstallation,
  operation : String,
  request_count : Int,
  request_at : (Int) -> String?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientEffectFilePreviewIdentity, Unit] {
  guard (operation == "update" || operation == "delete") &&
    request_count >= 0 &&
    request_count <= max_nodes else {
    return Err(())
  }
  try {
    let capability = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(capability)
    @encode.key(capability, "binding_cid")
    @encode.string_value(capability, original.binding_cid)
    @encode.key(capability, "connection")
    @encode.string_value(capability, original.connection)
    @encode.key(capability, "connector_registration")
    @encode.string_value(capability, original.connector_registration)
    @encode.key(capability, "connector_revision")
    @encode.string_value(capability, original.connector_revision)
    @encode.key(capability, "idempotency")
    @encode.string_value(capability, "unavailable")
    @encode.key(capability, "mapping_cid")
    @encode.string_value(capability, original.mapping_cid)
    @encode.key(capability, "operation")
    @encode.string_value(capability, operation)
    @encode.key(capability, "request_cids")
    @encode.begin_array(capability)
    for index in 0..<request_count {
      guard request_at(index) is Some(cid) else { return Err(()) }
      @encode.string_value(capability, cid)
    }
    @encode.end_array(capability)
    @encode.key(capability, "resource")
    @encode.string_value(capability, original.resource)
    @encode.key(capability, "route")
    @encode.string_value(capability, "single_serial")
    @encode.key(capability, "runtime_bundle_cid")
    @encode.string_value(capability, original.runtime_bundle_cid)
    @encode.key(capability, "version")
    @encode.string_value(
      capability, "actql-installed-row-effect-capability/0.1",
    )
    @encode.end_object(capability)
    let capability_cid = "sha256:" + @encode.finish_hash(capability)
    let scheme = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
    @encode.begin_object(scheme)
    @encode.key(scheme, "connector_registration")
    @encode.string_value(scheme, original.connector_registration)
    @encode.key(scheme, "mapping_cid")
    @encode.string_value(scheme, original.mapping_cid)
    @encode.key(scheme, "primary_identity")
    @encode.string_value(scheme, original.primary_identity)
    @encode.key(scheme, "resource")
    @encode.string_value(scheme, original.resource)
    @encode.key(scheme, "version")
    @encode.string_value(
      scheme, "actql-installed-row-effect-identity-scheme/0.1",
    )
    @encode.end_object(scheme)
    Ok({
      capability_cid,
      resource_identity_cid: "sha256:" + @encode.finish_hash(scheme),
    })
  } catch {
    _ => Err(())
  }
}
