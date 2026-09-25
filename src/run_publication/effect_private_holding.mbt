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

///|
/// One Store custody key for the completed computation of a Run. The
/// holding's manifest is the exact Captured Run CID; retrying this Run with
/// different computation evidence conflicts rather than replacing bytes.
pub fn effect_computation_capture_holding_cid(
  run_definition : PublicationContract,
  store_authority_cid : String,
) -> String? {
  if run_definition.name != "run_definition" ||
    !valid_contract_cid(store_authority_cid) {
    return None
  }
  let writer = @encode.hashing_writer(1024, 32, 2) catch { _ => return None }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, run_definition.identity)
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, store_authority_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-computation-holding/0.1")
    @encode.end_object(writer)
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    Some("sha256:" + digest)
  } catch {
    _ => None
  }
}

///|
/// The encrypted capture inventory has independent custody from its physical
/// Result payloads. Both keys are scoped to the same exact Run and Store.
pub fn effect_computation_record_holding_cid(
  run_definition : PublicationContract,
  store_authority_cid : String,
) -> String? {
  if run_definition.name != "run_definition" ||
    !valid_contract_cid(store_authority_cid) {
    return None
  }
  let writer = @encode.hashing_writer(1024, 32, 2) catch { _ => return None }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(writer, run_definition.identity)
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, store_authority_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-computation-record/0.1")
    @encode.end_object(writer)
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    Some("sha256:" + digest)
  } catch {
    _ => None
  }
}

///|
/// Independent Effect-source custody for one member and Run occurrence.
/// A public Result and this private input may share immutable bytes, never
/// the same holding or release responsibility.
pub fn effect_source_artifact_holding_cid(
  artifact : PublicationContract,
  effect_id : String,
  run_identity_cid : String,
  store_authority_cid : String,
) -> String? {
  if artifact.name != "effect_source_artifact" {
    return None
  }
  effect_source_holding_identity(
    artifact.identity,
    effect_id,
    run_identity_cid,
    store_authority_cid,
  )
}

///|
fn effect_source_holding_identity(
  artifact_cid : String,
  effect_id : String,
  run_identity_cid : String,
  store_authority_cid : String,
) -> String? {
  if !valid_contract_cid(artifact_cid) ||
    effect_id.is_empty() ||
    !valid_contract_cid(run_identity_cid) ||
    !valid_contract_cid(store_authority_cid) {
    return None
  }
  let writer = @encode.hashing_writer(1024, 32, 2) catch { _ => return None }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "effect_id")
    @encode.string_value(writer, effect_id)
    @encode.key(writer, "result_artifact_cid")
    @encode.string_value(writer, artifact_cid)
    @encode.key(writer, "run_identity_cid")
    @encode.string_value(writer, run_identity_cid)
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, store_authority_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-source-holding/0.1")
    @encode.end_object(writer)
    let (digest, _, _) = @encode.finish_hash_usage(writer)
    Some("sha256:" + digest)
  } catch {
    _ => None
  }
}
