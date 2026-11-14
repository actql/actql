///|
// One checked immutable context on the existing prepared capture, not another
// Resource Owner or cached approval. It borrows the already-funded tree and
// original nominal contracts; it never reconstructs a Read or a send grant.
priv struct PreparedCapturedEffectSourceContext {
  preview : EffectPreviewIdentity
  invocation : PublicationContract
  context : @json.CanonicalValue
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
// The complete chain has validated this SAME context once. Project every
// actual Source binding once, retaining the old duplicate/coverage/body/Store
// checks. The returned vector replaces the legacy seen + repeated admissions;
// its transient index and existing typed Source handles remain on the SAME
// decoded Read's pre-funded typed-body/index inventory, never a fresh budget.
pub fn prepared_captured_effect_run_sources(
  captured : PublicationContract,
  prepared : PreparedCapturedEffectRun,
  preview : EffectPreviewIdentity,
  invocation : PublicationContract,
  member_indices : Array[Int],
  artifacts : Array[PublicationContract],
  store_authority_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Array[CapturedEffectSourceArtifact], CapturedRunIssuanceIssue] {
  guard physical_equal(captured, prepared.captured) &&
    prepared.source_context is Some(original) &&
    physical_equal(preview, original.preview) &&
    physical_equal(invocation, original.invocation) &&
    max_bytes == original.max_bytes &&
    max_nodes == original.max_nodes &&
    max_depth == original.max_depth else {
    return Err(
      CaptureIssuanceReferenceMismatch("effect_source_prepared_context"),
    )
  }
  let count = effect_preview_member_count(preview)
  if count == 0 ||
    member_indices.length() != artifacts.length() ||
    member_indices.length() > count {
    return Err(CaptureIssuanceReferenceMismatch("effect_source_inventory"))
  }
  let seen = Array::make(count, false)
  let sources = []
  for index in 0..<member_indices.length() {
    let member_index = member_indices[index]
    if member_index < 0 || member_index >= count || seen[member_index] {
      return Err(CaptureIssuanceReferenceMismatch("effect_source_inventory"))
    }
    let source = match
      captured_effect_source_from_checked_context(
        preview,
        member_index,
        invocation,
        artifacts[index],
        original.context,
        store_authority_cid,
        max_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    seen[member_index] = true
    sources.push(source)
  }
  for index in 0..<count {
    if (effect_preview_member_relation_source(preview, index) is Some(_)) !=
      seen[index] {
      return Err(CaptureIssuanceReferenceMismatch("effect_source_inventory"))
    }
  }
  Ok(sources)
}
