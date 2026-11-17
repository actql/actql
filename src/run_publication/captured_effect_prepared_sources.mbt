///|
// Validate the complete chain once, then project every Source in this SAME
// synchronous call. Returned Source handles retain an exact immutable context
// association for subsequent row projections. Its borrowed originals and the
// transient index vector use the SAME decoded Read's typed-body/member
// inventory. No permission, Store custody or current decision is cached.
pub fn prepared_captured_effect_run_sources(
  run_definition : PublicationContract,
  invocation : PublicationContract,
  definitions : Array[PublicationContract],
  result_artifacts : Array[PublicationContract],
  manifest : PublicationContract,
  receipt : PublicationContract,
  captured : PublicationContract,
  prepared : PreparedCapturedEffectRun,
  preview : EffectPreviewIdentity,
  member_indices : Array[Int],
  artifacts : Array[PublicationContract],
  store_authority_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[CapturedEffectSourceArtifact], RunEvidenceChainIssue] {
  match
    validate_prepared_effectful_computation_evidence_chain(
      run_definition, invocation, definitions, result_artifacts, manifest, receipt,
      captured, prepared, preview, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @json.object_field(captured.value, "effect_context") is Some(context) else {
    return Err(EvidenceInventoryMismatch("effect_source_prepared_context"))
  }
  let count = effect_preview_member_count(preview)
  if count == 0 ||
    member_indices.length() != artifacts.length() ||
    member_indices.length() > count {
    return Err(EvidenceInventoryMismatch("effect_source_inventory"))
  }
  let seen = Array::make(count, false)
  let sources = []
  for index in 0..<member_indices.length() {
    let member_index = member_indices[index]
    if member_index < 0 || member_index >= count || seen[member_index] {
      return Err(EvidenceInventoryMismatch("effect_source_inventory"))
    }
    let source = match
      captured_effect_source_from_checked_context(
        preview,
        member_index,
        invocation,
        artifacts[index],
        captured,
        context,
        store_authority_cid,
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(_) => return Err(EvidenceInventoryMismatch("effect_source_capture"))
    }
    seen[member_index] = true
    sources.push(source)
  }
  for index in 0..<count {
    if (effect_preview_member_relation_source(preview, index) is Some(_)) !=
      seen[index] {
      return Err(EvidenceInventoryMismatch("effect_source_inventory"))
    }
  }
  Ok(sources)
}
