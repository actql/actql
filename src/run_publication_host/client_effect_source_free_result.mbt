///|
let source_free_effect_result_scope_body : String =
  #|{"sources":[],"version":"actql-acquisition-scope/0.1"}

///|
let source_free_effect_result_scope_cid : String = "sha256:" +
  @sha.hex(@utf8.encode(source_free_effect_result_scope_body))

///|
fn source_free_effect_result_scope_matches(
  scope : @publication.PublicationContract,
) -> Bool {
  @publication.publication_contract_name(scope) == "acquisition_scope" &&
  @publication.publication_contract_identity(scope) ==
  source_free_effect_result_scope_cid
}

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
    source_free_effect_result_scope_matches(scope) else {
    return None
  }
  Some(scope)
}
