///|
/// Borrow the acquisition scope sealed by the actual source-free Artifact.
/// The original Run Invocation and checked compilation must both agree.
pub fn client_effect_source_free_result_original_scope(
  artifact : ClientEffectLocalResultArtifact,
  publication : ClientEffectSourceFreeInvocationOriginal,
) -> @publication.PublicationContract? {
  guard artifact.run_invocation is Some(invocation) &&
    physical_equal(invocation, publication.invocation) &&
    physical_equal(artifact.invocation.owner, publication.compilation.owner) &&
    artifact.invocation.unit == 0 &&
    artifact.scope is Some(scope) &&
    @publication.publication_contract_name(scope) == "acquisition_scope" else {
    return None
  }
  let wire = @publication.publication_contract_json(scope)
  if wire.length() > 256 {
    return None
  }
  // Check the admitted scope's actual Source list. The generated scope CID
  // remains part of the original sealed object.
  let value = @json.parse(wire) catch { _ => return None }
  guard value is Object(fields) &&
    fields.get("sources") is Some(Array(sources)) &&
    sources.is_empty() else {
    return None
  }
  Some(scope)
}
