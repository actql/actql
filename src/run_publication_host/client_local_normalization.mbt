///|
pub(all) enum ClientLocalNormalizationIssue {
  Inventory(@checked.CompletionFreeInventoryIssue)
  ForeignPreparation
  ForeignCatalog
  SubstitutedJournal
  Evidence(@publication.RunEvidenceValueIssue)
}

///|
/// Original preparation owns the completion inventory and its issued bytes.
/// The normative journal preimage has no additional Program binding fields;
/// this opaque projection and the original materials chain own those links.
struct ClientLocalNormalization {
  preparation : PreparedClientProgram
  audit : @checked.LocalCompletionFreeInventory
  evidence : @publication.RunEvidenceValue
}

///|
pub fn client_local_completion_free_catalog_cid() -> String {
  "sha256:690a1e3eea6e0ce89e54937db070a578ec66c2c456061c28a29c7c4dba1b6587"
}

///|
fn local_normalization_catalog_cid(
  inventory : @checked.LocalCompletionFreeInventory,
) -> String {
  if @checked.local_completion_free_inventory_uses_groups(inventory) {
    return "sha256:b63098d9379e482326c612be898d13d86c0c849d6c77afb7f2574b33cb2a78d5"
  }
  if @checked.local_completion_free_inventory_uses_checked_expressions(
      inventory,
    ) {
    return "sha256:e51161c71f8cb1565fd562ce325a78d2cec3b5c55a5aca54e70953fd6d92db74"
  }
  let supplied = @checked.local_completion_free_inventory_parameters_supplied(
    inventory,
  )
  if @checked.local_completion_free_inventory_uses_explicit_cast(inventory) {
    if supplied {
      "sha256:0eebf603b459361c55386c3863c0fc6e3928cdae2def8aeca899272b3ecade47"
    } else {
      "sha256:538424f689566bf75ba8e9e20241aad4bea6acdeccf301216bcd3dc64036ad49"
    }
  } else if supplied {
    "sha256:105e716b0494553cf970393a550ece0553787fb1967ee01f245ea607b03d0fe1"
  } else {
    client_local_completion_free_catalog_cid()
  }
}

///|
/// Issue only from the inventory retained by the original checked preparation.
/// No parse, compile, Source acquisition or physical Effect operation occurs.
pub fn issue_prepared_client_local_normalization(
  owner : PreparedClientProgram,
) -> Result[ClientLocalNormalization, ClientLocalNormalizationIssue] {
  if owner.local_normalization is Some(original) {
    match prepared_client_local_normalization_evidence(owner, original) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    return Ok(original)
  }
  let inventory = match
    @checked.local_program_completion_free_inventory(
      @strategy.graph_program(owner.graph),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Inventory(issue))
  }
  let wire = "{\"entries\":[],\"rule_catalog_cid\":\"" +
    local_normalization_catalog_cid(inventory) +
    "\",\"version\":\"actql-normalization-journal/0.1\"}"
  let journal = match
    @publication.seal_run_evidence_value(
      "normalization_journal", wire, 1024, 32, 8,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let issued : ClientLocalNormalization = {
    preparation: owner,
    audit: inventory,
    evidence: journal,
  }
  owner.local_normalization = Some(issued)
  Ok(issued)
}

///|
/// A copied or foreign preparation cannot take another original journal.
/// Definition, semantics and check-environment identity are inherited from
/// this exact preparation owner, rather than inferred from equal source bytes.
pub fn prepared_client_local_normalization_evidence(
  owner : PreparedClientProgram,
  value : ClientLocalNormalization,
) -> Result[@publication.RunEvidenceValue, ClientLocalNormalizationIssue] {
  if !physical_equal(owner, value.preparation) ||
    !(owner.local_normalization is Some(original) &&
    physical_equal(original, value)) ||
    !@checked.local_completion_free_inventory_matches(
      value.audit,
      @strategy.graph_program(owner.graph),
    ) {
    return Err(ForeignPreparation)
  }
  Ok(value.evidence)
}

///|
/// Re-admit saved bytes against the original projection without issuing a new
/// journal or repeating preparation. Cross-process materials restoration is a
/// separate connection; an arbitrary journal alone is not an inventory proof.
pub fn restore_prepared_client_local_normalization(
  owner : PreparedClientProgram,
  original : ClientLocalNormalization,
  wire : String,
  catalog_cid : String,
) -> Result[@publication.RunEvidenceValue, ClientLocalNormalizationIssue] {
  let expected = match
    prepared_client_local_normalization_evidence(owner, original) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if catalog_cid != local_normalization_catalog_cid(original.audit) {
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
