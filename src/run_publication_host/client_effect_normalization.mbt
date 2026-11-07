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
enum ClientEffectNormalizationInventory {
  MappedCreate(@checked.CompletionFreeInventory)
  LocalUpdate(@checked.LocalUpdateCompletionFreeInventory)
  CommonUpdate(@checked.LocalCommonUpdateCompletionFreeInventory)
}

///|
struct ClientEffectNormalization {
  owner : PreparedClientEffectComputation
  inventory : ClientEffectNormalizationInventory
  journal : @publication.RunEvidenceValue
}

///|
pub fn client_effect_completion_free_catalog_cid() -> String {
  "sha256:ea21a2a2ab522cbf960c5e97120648e351db7c127768101502210ed7d8fcfb38"
}

///|
pub fn client_effect_local_update_completion_free_catalog_cid() -> String {
  "sha256:9ba6d5dff43cd54b0d61d6923fd4cb3143e1a5e238bad20b297133393d783468"
}

///|
fn client_effect_common_update_completion_free_catalog_cid() -> String {
  "sha256:1263116a02d125a0c66f2445a175075d4ec333e56f3d003d35e9d51065fecf8f"
}

///|
/// Catalog selection follows the nominal inventory owned by the original
/// preparation. A transported catalog field is not a profile selection.
pub fn client_effect_normalization_catalog_cid(
  value : ClientEffectNormalization,
) -> String {
  client_effect_normalization_inventory_profile(value.inventory).1
}

///|
fn client_effect_normalization_inventory_profile(
  inventory : ClientEffectNormalizationInventory,
) -> (String, String) {
  match inventory {
    MappedCreate(_) =>
      (
        "actql-resident-effect-completion-free/0.1",
        client_effect_completion_free_catalog_cid(),
      )
    LocalUpdate(_) =>
      (
        "actql-local-update-completion-free/0.1",
        client_effect_local_update_completion_free_catalog_cid(),
      )
    CommonUpdate(_) =>
      (
        "actql-local-common-update-completion-free/0.1",
        client_effect_common_update_completion_free_catalog_cid(),
      )
  }
}

///|
fn client_effect_normalization_inventory_journal_cid(
  inventory : ClientEffectNormalizationInventory,
) -> String {
  match inventory {
    MappedCreate(_) =>
      "sha256:849788c9eede8ad674223eb06775c2dba2cf0ed1d02ceb0a5de6ccfeec2cb087"
    LocalUpdate(_) =>
      "sha256:e9f69915b6368e0c8e1669b010e57e65f633bd5a8d589d3b3575c2b043f4b44d"
    CommonUpdate(_) =>
      "sha256:8b5172ca35db5cd4f35b8e6bbde52243d92b9e9027c2fc4568b8d66a5334ffb1"
  }
}

///|
fn same_client_effect_normalization_profile(
  left : ClientEffectNormalizationInventory?,
  right : ClientEffectNormalizationInventory?,
) -> Bool {
  // Profile equality is not inventory custody. Physical Owner checks are
  // required separately before compilation, issuance and material readback.
  match (left, right) {
    (None, None)
    | (Some(MappedCreate(_)), Some(MappedCreate(_)))
    | (Some(LocalUpdate(_)), Some(LocalUpdate(_)))
    | (Some(CommonUpdate(_)), Some(CommonUpdate(_))) => true
    _ => false
  }
}

///|
fn checked_client_effect_normalization_inventory(
  owner : PreparedClientEffectComputation,
) -> Result[ClientEffectNormalizationInventory, ClientEffectNormalizationIssue] {
  if owner.normalization is Some(original) &&
    physical_equal(original.owner, owner) &&
    client_effect_normalization_inventory_matches(original.inventory, owner) {
    return Ok(original.inventory)
  }
  let headers = @checked.effect_program_static_headers(owner.candidate)
  guard @syntax.effect_header_count(headers) == 1 else {
    return Err(Inventory(ProfileNotInstalled))
  }
  match
    @syntax.effect_header_kind(@syntax.effect_header_at(headers, 0).unwrap()) {
    "create" =>
      @checked.effect_program_completion_free_inventory(owner.candidate)
      .map(fn(value) { MappedCreate(value) })
      .map_err(fn(issue) { Inventory(issue) })
    "update" =>
      match
        @checked.effect_program_local_update_completion_free_inventory(
          owner.candidate,
        ) {
        Ok(value) => Ok(LocalUpdate(value))
        Err(ProfileNotInstalled) =>
          @checked.effect_program_common_update_completion_free_inventory(
            owner.candidate,
          )
          .map(value => CommonUpdate(value))
          .map_err(issue => Inventory(issue))
        Err(issue) => Err(Inventory(issue))
      }
    _ => Err(Inventory(ProfileNotInstalled))
  }
}

///|
fn client_effect_normalization_inventory_matches(
  inventory : ClientEffectNormalizationInventory,
  owner : PreparedClientEffectComputation,
) -> Bool {
  match inventory {
    MappedCreate(inventory) =>
      @checked.completion_free_inventory_matches(inventory, owner.candidate)
    LocalUpdate(inventory) =>
      @checked.local_update_completion_free_inventory_matches(
        inventory,
        owner.candidate,
      )
    CommonUpdate(inventory) =>
      @checked.local_common_update_completion_free_inventory_matches(
        inventory,
        owner.candidate,
      )
  }
}

///|
/// Issue only from the inventory retained by the original checked preparation.
/// No parse, compile, Source acquisition or physical Effect operation occurs.
pub fn issue_prepared_client_effect_normalization(
  owner : PreparedClientEffectComputation,
) -> Result[ClientEffectNormalization, ClientEffectNormalizationIssue] {
  if owner.normalization is Some(original) {
    return match original.inventory {
      MappedCreate(_) => Ok(original)
      LocalUpdate(_) | CommonUpdate(_) => Err(Inventory(ProfileNotInstalled))
    }
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
  let issued = { owner, inventory: MappedCreate(inventory), journal, }
  owner.normalization = Some(issued)
  Ok(issued)
}

///|
/// Extend the same preparation-owned normalization issuer for the installed
/// Local update slice. Checking, audit and current write authority are distinct
/// obligations. This projection never starts an observation or physical write.
pub fn issue_prepared_client_effect_local_update_normalization(
  owner : PreparedClientEffectComputation,
) -> Result[ClientEffectNormalization, ClientEffectNormalizationIssue] {
  if owner.normalization is Some(original) {
    return match original.inventory {
      LocalUpdate(_) => Ok(original)
      MappedCreate(_) | CommonUpdate(_) => Err(Inventory(ProfileNotInstalled))
    }
  }
  let inventory = match
    @checked.effect_program_local_update_completion_free_inventory(
      owner.candidate,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Inventory(issue))
  }
  let wire = "{\"entries\":[],\"rule_catalog_cid\":\"" +
    client_effect_local_update_completion_free_catalog_cid() +
    "\",\"version\":\"actql-normalization-journal/0.1\"}"
  let journal = match
    @publication.seal_run_evidence_value(
      "normalization_journal", wire, 1024, 32, 8,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let issued = { owner, inventory: LocalUpdate(inventory), journal, }
  owner.normalization = Some(issued)
  Ok(issued)
}

///|
/// Select only the inventory retained by the original checked Effect kind.
/// Both paths reuse their existing issuer and exact preparation-owned proof;
/// neither a caller profile nor a failed alternate issuer selects this kind.
pub fn issue_prepared_client_effect_selected_normalization(
  owner : PreparedClientEffectComputation,
) -> Result[ClientEffectNormalization, ClientEffectNormalizationIssue] {
  let selected = match checked_client_effect_normalization_inventory(owner) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let original = match selected {
    MappedCreate(_) => issue_prepared_client_effect_normalization(owner)
    LocalUpdate(_) =>
      issue_prepared_client_effect_local_update_normalization(owner)
    CommonUpdate(_) => issue_common_update_normalization(owner, selected)
  }
  match original {
    Err(issue) => Err(issue)
    Ok(proof) =>
      prepared_client_effect_normalization_evidence(owner, proof).map(fn(_) {
        proof
      })
  }
}

///|
/// A copied or foreign preparation cannot take another original journal.
/// Definition, semantics and check-environment identity are inherited from
/// this exact preparation owner, rather than inferred from equal source bytes.
pub fn prepared_client_effect_normalization_evidence(
  owner : PreparedClientEffectComputation,
  value : ClientEffectNormalization,
) -> Result[@publication.RunEvidenceValue, ClientEffectNormalizationIssue] {
  let matches = client_effect_normalization_inventory_matches(
    value.inventory,
    owner,
  )
  if !physical_equal(owner, value.owner) ||
    !(owner.normalization is Some(original) && physical_equal(original, value)) ||
    !matches {
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
  if catalog_cid != client_effect_normalization_catalog_cid(original) {
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

///|
fn issue_common_update_normalization(
  owner : PreparedClientEffectComputation,
  inventory : ClientEffectNormalizationInventory,
) -> Result[ClientEffectNormalization, ClientEffectNormalizationIssue] {
  guard inventory is CommonUpdate(_) &&
    client_effect_normalization_inventory_matches(inventory, owner) else {
    return Err(ForeignPreparation)
  }
  if owner.normalization is Some(original) {
    guard original.inventory is CommonUpdate(_) else {
      return Err(Inventory(ProfileNotInstalled))
    }
    return Ok(original)
  }
  let wire = "{\"entries\":[],\"rule_catalog_cid\":\"" +
    client_effect_common_update_completion_free_catalog_cid() +
    "\",\"version\":\"actql-normalization-journal/0.1\"}"
  let journal = match
    @publication.seal_run_evidence_value(
      "normalization_journal", wire, 1024, 32, 8,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  let original = { owner, inventory, journal, }
  owner.normalization = Some(original)
  Ok(original)
}
