///|
/// Encode the existing Native Store association for an original Run and Source.
/// The caller supplies the already-serialized PublicationPayload request and
/// retains all binding checks, physical custody and cleanup responsibility.
/// These bytes are not an admitted contract, storage proof or execution permit.
pub fn native_effect_source_custody_record_json(
  run : PublicationContract,
  source : CapturedEffectSourceArtifact,
  request_wire : String,
  store_authority_cid : String,
  physical_digest : String,
  physical_bytes : Int64,
  cleanup_complete : Bool,
  max_record_bytes : Int,
) -> Result[String, PublicationContractIssue] {
  let writer = @encode.writer(max_record_bytes, 128, 4) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "cleanup_complete")
    @encode.bool_value(writer, cleanup_complete)
    @encode.key(writer, "holding_cid")
    @encode.string_value(writer, captured_effect_source_holding_cid(source))
    @encode.key(writer, "payload_request")
    @encode.string_value(writer, request_wire)
    @encode.key(writer, "physical_bytes")
    @encode.string_value(writer, physical_bytes.to_string())
    @encode.key(writer, "physical_digest")
    @encode.string_value(writer, physical_digest)
    @encode.key(writer, "run_definition")
    @encode.string_value(writer, publication_contract_json(run))
    @encode.key(writer, "source_artifact")
    @encode.string_value(writer, captured_effect_source_artifact_json(source))
    @encode.key(writer, "store_authority_cid")
    @encode.string_value(writer, store_authority_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-effect-source-custody/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok(wire)
}
