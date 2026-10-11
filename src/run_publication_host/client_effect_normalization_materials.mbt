///|
/// Exact journal custody retained by the existing original Run material
/// admission. It grants neither execution, approval nor current authority.
struct ClientEffectNormalizationMaterialCustody {
  compilation : ClientEffectCompilation
  run_cid : String
  request : ClientRequestIdentity?
  journal_wire : String
  materials_cid : String
}

///|
/// Restore only saved journal bytes through the original admitted material
/// Owner. This operation does not prepare, compile, issue a journal, refresh
/// lifetime/authority, acquire Source input or perform Provider I/O.
pub fn restore_client_effect_run_normalization(
  materials : ClientEffectRunMaterials,
) -> Result[@publication.RunEvidenceValue, ClientEffectNormalizationIssue] {
  let prepared = materials.prepared
  if !physical_equal(materials.compilation.owner, prepared) ||
    !physical_equal(materials.compilation, materials.allowed.compilation) ||
    bind_client_effect_compiled_run(
      prepared,
      materials.allowed,
      materials.run_definition,
    )
    is Err(_) {
    return Err(ForeignMaterials)
  }
  guard materials.normalization is Some(custody) else {
    return Err(MissingOriginalJournal)
  }
  guard prepared.normalization_custody is Some(original) &&
    physical_equal(custody, original) &&
    physical_equal(custody.compilation, materials.compilation) &&
    custody.run_cid ==
    @publication.publication_contract_identity(materials.run_definition) &&
    custody.request == materials.request else {
    return Err(ForeignMaterials)
  }
  // The retained original checker inventory, not wire shape or execution
  // success, supplies the applicability proof. Missing/unsupported proof
  // remains a refusal even if the supplied journal has the fixed empty CID.
  match @checked.effect_program_completion_free_inventory(prepared.candidate) {
    Ok(inventory) =>
      if !@checked.completion_free_inventory_matches(
          inventory,
          prepared.candidate,
        ) {
        return Err(ForeignPreparation)
      }
    Err(issue) => return Err(Inventory(issue))
  }
  let journal = match
    @publication.admit_run_evidence_value(
      "normalization_journal",
      custody.journal_wire,
      1024,
      32,
      8,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  // Independently frozen catalog/journal preimages are published alongside
  // the issuer. Never construct a replacement journal during restoration.
  if @publication.run_evidence_value_identity(journal) !=
    "sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087" {
    return Err(SubstitutedJournal)
  }
  Ok(journal)
}

///|
/// Retained material digest for custody correlation; no transport signature
/// or current authorization is inferred from this content identity.
pub fn client_effect_normalization_materials_cid(
  materials : ClientEffectRunMaterials,
) -> String? {
  guard restore_client_effect_run_normalization(materials) is Ok(_) &&
    materials.normalization is Some(custody) else {
    return None
  }
  Some(custody.materials_cid)
}
