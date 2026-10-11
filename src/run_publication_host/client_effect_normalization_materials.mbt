///|
/// Private nominal issuer identity. It retains no material, Run or preparation.
/// Proofs refer to this constant; the issuer never refers back to a proof.
let original_effect_materials_issuer : Ref[Unit] = Ref(())

///|
/// Exact bytes issued under the original preparation's normalization Owner.
/// This process-local projection is not a serializable transport credential.
struct ClientEffectIssuedNormalizationMaterials {
  issuer : Ref[Unit]
  original : ClientEffectNormalization
  compilation : ClientEffectCompilation
  run_cid : String
  wire : String
  normalization_profile : Bool
}

///|
/// Issue caller-owned original bytes before dispatch. Caller-supplied wire
/// cannot create this projection. Approval and current authority stay separate.
pub fn issue_prepared_client_effect_normalization_materials(
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  original : ClientEffectNormalization,
  request? : ClientRequestIdentity? = None,
) -> Result[
  ClientEffectIssuedNormalizationMaterials,
  ClientEffectRunMaterialsIssue,
] {
  let wire = match
    issue_prepared_client_effect_run_materials(
      allowed,
      definition,
      request~,
      normalization=Some(original),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let run_cid = @publication.publication_contract_identity(definition)
  // No reverse index on the preparation: each Run's bytes are retained only
  // by its caller/admitted custody. The opaque type has no public constructor.
  Ok({
    issuer: original_effect_materials_issuer,
    original,
    compilation: allowed.compilation,
    run_cid,
    wire,
    normalization_profile: allowed.compilation.normalization_profile,
  })
}

///|
pub fn client_effect_issued_normalization_materials_wire(
  issued : ClientEffectIssuedNormalizationMaterials,
) -> String {
  issued.wire
}

///|
fn original_effect_materials_match(
  issued : ClientEffectIssuedNormalizationMaterials,
  wire : String,
  run_cid : String,
) -> Bool {
  issued.wire == wire &&
  issued.run_cid == run_cid &&
  physical_equal(issued.compilation.owner, issued.original.owner) &&
  issued.normalization_profile == issued.compilation.normalization_profile &&
  physical_equal(issued.issuer, original_effect_materials_issuer) &&
  prepared_client_effect_normalization_evidence(
    issued.original.owner,
    issued.original,
  )
  is Ok(_)
}

///|
/// Exact journal custody retained by the existing original Run material
/// admission. It grants neither execution, approval nor current authority.
struct ClientEffectNormalizationMaterialCustody {
  issued : ClientEffectIssuedNormalizationMaterials?
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
  match custody.issued {
    Some(issued) =>
      if !original_effect_materials_match(issued, issued.wire, custody.run_cid) ||
        custody.materials_cid != "sha256:" + @sha.hex(@utf8.encode(issued.wire)) ||
        custody.journal_wire !=
        @publication.run_evidence_value_json(issued.original.journal) {
        return Err(UnverifiedOriginalMaterials)
      }
    None =>
      // Generic wire cannot select the legacy path. The private compilation
      // profile was admitted through the saved invocation and exact Run CID.
      if !materials.compilation.normalization_profile {
        return Err(UnverifiedOriginalMaterials)
      }
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

///|
/// Decode the published finite journal without invoking its original issuer.
/// Applicability and provenance are separate: inventory plus the original
/// Run's bound compiler profile are required before returning review custody.
fn admit_completion_free_material_journal(
  wire : String,
) -> Result[@publication.RunEvidenceValue, ClientEffectNormalizationIssue] {
  let journal = match
    @publication.admit_run_evidence_value(
      "normalization_journal", wire, 1024, 32, 8,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  if @publication.run_evidence_value_identity(journal) !=
    "sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087" ||
    wire != @publication.run_evidence_value_json(journal) {
    return Err(SubstitutedJournal)
  }
  Ok(journal)
}
