///|
/// Stable physical custody key for one admitted private Preview in one Store.
/// The encrypted allocation remains separately addressed by its byte digest.
/// Equal semantic Previews in different Run occurrences cannot share this
/// holding, and the key alone grants no read or apply authority.
pub fn effect_preview_private_holding_cid(
  preview : EffectPreviewIdentity,
  store_authority_cid : String,
) -> String? {
  if !valid_contract_cid(store_authority_cid) {
    return None
  }
  let writer = @encode.hashing_writer(1024, 32, 2) catch { _ => return None }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "authoring_context_cid")
    @encode.string_value(writer, preview.authoring_context_cid)
    @encode.key(writer, "effect_preview_cid")
    @encode.string_value(writer, preview.semantic_cid)
    @encode.key(writer, "run_identity_cid")
    @encode.string_value(writer, preview.run_identity_cid)
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, store_authority_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-private-holding/0.1")
    @encode.end_object(writer)
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    Some("sha256:" + digest)
  } catch {
    _ => None
  }
}
