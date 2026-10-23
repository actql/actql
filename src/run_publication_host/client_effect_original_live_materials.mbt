///|
/// Bind already-issued original material bytes to their live checked Owner.
/// This does not prepare or compile again, issue a journal, refresh the Run,
/// claim work, grant approval or authorize any Provider operation. Durable
/// retention and current cancellation/authorization remain with their Owners.
pub fn bind_prepared_client_effect_original_materials(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  issued : ClientEffectIssuedNormalizationMaterials,
  request? : ClientRequestIdentity? = None,
) -> Result[ClientEffectRunMaterials, ClientEffectRunMaterialsIssue] {
  let prepared = client_effect_compilation_owner(allowed.compilation)
  let run_cid = @publication.publication_contract_identity(definition)
  if !original_effect_materials_match(issued, issued.wire, run_cid) {
    return Err(Normalization(UnverifiedOriginalMaterials))
  }
  if !physical_equal(issued.compilation.owner, prepared) {
    return Err(Normalization(ForeignPreparation))
  }
  if !physical_equal(issued.compilation, allowed.compilation) {
    return Err(Normalization(ForeignMaterials))
  }
  // The issuer already validated these immutable invocation/authorization
  // artifacts and Run/request tuple. This is not a current policy evaluation.
  // Equal canonical Definitions and equivalent admitted evidence may reuse it;
  // a different tuple still takes the original validation and error path.
  let exact = if issued.request == request &&
    issued.prepared_cid ==
    @publication.run_evidence_value_identity(allowed.prepared) &&
    issued.authorization_cid ==
    @publication.run_evidence_value_identity(allowed.authorization) {
    issued.wire
  } else {
    match
      issue_prepared_client_effect_run_materials(
        allowed,
        definition,
        request~,
        normalization=Some(issued.original),
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  }
  if exact != issued.wire ||
    !same_client_effect_normalization_profile(
      issued.normalization_profile,
      allowed.compilation.normalization_profile,
    ) {
    return Err(Normalization(ForeignMaterials))
  }
  // A preparation can have only its existing exact live material binding.
  // Another Run/request/compiler cannot displace a retained custody handle,
  // even if its Program or proposed journal has equal public identity.
  if prepared.normalization_custody is Some(custody) {
    if !physical_equal(custody.compilation, allowed.compilation) ||
      custody.run_cid != run_cid ||
      custody.request != request ||
      custody.materials_cid != original_effect_materials_cid(issued) {
      return Err(Normalization(ForeignMaterials))
    }
    let materials : ClientEffectRunMaterials = {
      normalization: Some(custody),
      prepared,
      compilation: allowed.compilation,
      allowed,
      run_definition: definition,
      request,
    }
    return restore_client_effect_run_normalization(materials)
      .map(_ => materials)
      .map_err(issue => Normalization(issue))
  }
  let custody : ClientEffectNormalizationMaterialCustody = {
    issued: Some(issued),
    compilation: allowed.compilation,
    run_cid,
    prepared_cid: @publication.run_evidence_value_identity(allowed.prepared),
    authorization_cid: @publication.run_evidence_value_identity(
      allowed.authorization,
    ),
    request,
    journal_wire: @publication.run_evidence_value_json(issued.original.journal),
    journal: issued.original.journal,
    inventory: issued.original.inventory,
    materials_cid: original_effect_materials_cid(issued),
  }
  prepared.normalization_custody = Some(custody)
  Ok({
    normalization: Some(custody),
    prepared,
    compilation: allowed.compilation,
    allowed,
    run_definition: definition,
    request,
  })
}
