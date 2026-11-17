///|
/// Exact issued DATA retained before the managed DAG exists. This does not own
/// resources or grant publication. Its fixed borrowed shape is included in the
/// original Request Effect Plan quote; it preserves the existing issuer tuple.
struct ClientEffectSourceFreeInvocationOriginal {
  compilation : ClientEffectCompilation
  observation : @publication.RunEvidenceValue
  invocation : @publication.PublicationContract
}

///|
pub fn issue_client_effect_source_free_invocation_original(
  compilation : ClientEffectCompilation,
  policy : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientEffectSourceFreeInvocationOriginal,
  @publication.RunEvidenceValueIssue,
] {
  match
    issue_client_effect_source_free_invocation(
      compilation, policy, max_bytes, max_nodes, max_depth,
    ) {
    Err(issue) => Err(issue)
    Ok((observation, invocation)) =>
      Ok({ compilation, observation, invocation, })
  }
}

///|
pub fn client_effect_source_free_invocation_original_observation(
  value : ClientEffectSourceFreeInvocationOriginal,
) -> @publication.RunEvidenceValue {
  value.observation
}

///|
pub fn client_effect_source_free_invocation_original_invocation(
  value : ClientEffectSourceFreeInvocationOriginal,
) -> @publication.PublicationContract {
  value.invocation
}

///|
pub fn client_effect_source_free_invocation_original_matches(
  value : ClientEffectSourceFreeInvocationOriginal,
  compilation : ClientEffectCompilation,
) -> Bool {
  physical_equal(value.compilation, compilation)
}

///|
/// The actual bound Run retains these original admission/Definition objects.
/// Equal CID/bytes, another compiler, or a fresh bind cannot replace them.
pub fn client_effect_publication_originals_match(
  bound : PreparedClientEffectRun,
  prepared : PreparedClientEffectComputation,
  compilation : ClientEffectCompilation,
  admission : @publication.RunPublicationAdmission,
  definition : @publication.PublicationContract,
) -> Bool {
  let original = @strategy.checked_effect_run_owner(bound.checked)
  physical_equal(bound.computation, prepared) &&
  physical_equal(compilation.owner, prepared) &&
  physical_equal(
    @effect_binding.effect_program_run_admission(original),
    admission,
  ) &&
  physical_equal(
    @effect_binding.effect_program_run_definition(original),
    definition,
  )
}

///|
pub fn client_effect_source_free_invocation_original_compilation(
  value : ClientEffectSourceFreeInvocationOriginal,
) -> ClientEffectCompilation {
  value.compilation
}
