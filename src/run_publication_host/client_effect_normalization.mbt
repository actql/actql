///|
pub(all) enum ClientEffectNormalizationIssue {
  Inventory(@checked.CompletionFreeInventoryIssue)
  ForeignPreparation
  ForeignMaterials
  MissingOriginalJournal
  UnverifiedOriginalMaterials
  ForeignCatalog
  SubstitutedJournal
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
/// Original preparation owns the completion inventory and its issued bytes.
/// The normative journal preimage has no additional Program binding fields;
/// this opaque projection and the original materials chain own those links.
struct ClientEffectNormalization {
  owner : PreparedClientEffectComputation
  inventory : @checked.CompletionFreeInventory
  journal : @publication.RunEvidenceValue
}

///|
pub fn client_effect_completion_free_catalog_cid() -> String {
  "sha256:ea21a2a2ab522cbf960c5e97120648e351db7c127768101502210ed7d8fcfb38"
}

///|
/// Issue only from the inventory retained by the original checked preparation.
/// No parse, compile, Source acquisition or physical Effect operation occurs.
pub fn issue_prepared_client_effect_normalization(
  owner : PreparedClientEffectComputation,
) -> Result[ClientEffectNormalization, ClientEffectNormalizationIssue] {
  if owner.normalization is Some(original) {
    return Ok(original)
  }
  let inventory = match
    @checked.effect_program_completion_free_inventory(owner.candidate) {
    Ok(value) => value
    Err(issue) => return Err(Inventory(issue))
  }
  let wire = "{\"entries\":[],\"rule_catalog_cid\":\"" +
    client_effect_completion_free_catalog_cid() +
    "\",\"version\":\"actql-normalization-journal/0.1\"}"
  let journal = match
    @publication.seal_run_evidence_value(
      "normalization_journal", wire, 1024, 32, 8,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let issued = { owner, inventory, journal, }
  owner.normalization = Some(issued)
  Ok(issued)
}

///|
/// A copied or foreign preparation cannot take another original journal.
/// Definition, semantics and check-environment identity are inherited from
/// this exact preparation owner, rather than inferred from equal source bytes.
pub fn prepared_client_effect_normalization_evidence(
  owner : PreparedClientEffectComputation,
  value : ClientEffectNormalization,
) -> Result[@publication.RunEvidenceValue, ClientEffectNormalizationIssue] {
  if !physical_equal(owner, value.owner) ||
    !(owner.normalization is Some(original) && physical_equal(original, value)) ||
    !@checked.completion_free_inventory_matches(
      value.inventory,
      owner.candidate,
    ) {
    return Err(ForeignPreparation)
  }
  Ok(value.journal)
}

///|
/// Re-admit saved bytes against the original projection without issuing a new
/// journal or repeating preparation. Cross-process materials restoration is a
/// separate connection; an arbitrary journal alone is not an inventory proof.
pub fn restore_prepared_client_effect_normalization(
  owner : PreparedClientEffectComputation,
  original : ClientEffectNormalization,
  wire : String,
  catalog_cid : String,
) -> Result[@publication.RunEvidenceValue, ClientEffectNormalizationIssue] {
  let expected = match
    prepared_client_effect_normalization_evidence(owner, original) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if catalog_cid != client_effect_completion_free_catalog_cid() {
    return Err(ForeignCatalog)
  }
  if wire != @publication.run_evidence_value_json(expected) {
    return Err(SubstitutedJournal)
  }
  match
    @publication.admit_run_evidence_value(
      "normalization_journal", wire, 1024, 32, 8,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Evidence(issue))
  }
}
