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
priv enum ClientLocalNormalizationInventory {
  CompletionFree(@checked.LocalCompletionFreeInventory)
  SortCompletion(@checked.LocalSortNormalizationInventory)
}

///|
struct ClientLocalNormalization {
  preparation : PreparedClientProgram
  audit : ClientLocalNormalizationInventory
  evidence : @publication.RunEvidenceValue
}

///|
pub fn client_local_completion_free_catalog_cid() -> String {
  "sha256:690a1e3eea6e0ce89e54937db070a578ec66c2c456061c28a29c7c4dba1b6587"
}

///|
fn local_completion_free_catalog_cid(
  inventory : @checked.LocalCompletionFreeInventory,
) -> String {
  if @checked.local_completion_free_inventory_uses_set(inventory) {
    return "sha256:0f0003ec6a1ec4520a7b9615b916d903dafc138e94145e5a57d45a1bf7937f33"
  }
  if @checked.local_completion_free_inventory_uses_distinct(inventory) {
    return "sha256:4cbc2466af84dc925b7e79c91c0a7a19a2a16873bb6e7975e8f6855a954831d8"
  }
  if @checked.local_completion_free_inventory_uses_sort(inventory) {
    return "sha256:aa08e331a77f389359583e74ce6d7c801ad76a21d13520e55571f71a237ff24e"
  }
  if @checked.local_completion_free_inventory_uses_take(inventory) {
    return "sha256:2e87dfc12f59f5755bc3a41b61fc0a9b5b5cc0c0f7861128924c852c13ce7d03"
  }
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
fn local_normalization_catalog_cid(
  inventory : ClientLocalNormalizationInventory,
) -> String {
  match inventory {
    CompletionFree(value) => local_completion_free_catalog_cid(value)
    SortCompletion(value) =>
      if @checked.local_sort_normalization_inventory_uses_projection(value) {
        "sha256:2ca357988216b4271b9b7ba73afdfc841b73cb9992947254c659bf7ab80eb56b"
      } else if @checked.local_sort_normalization_inventory_uses_set(value) {
        "sha256:0f0003ec6a1ec4520a7b9615b916d903dafc138e94145e5a57d45a1bf7937f33"
      } else if @checked.local_sort_normalization_inventory_uses_distinct(value) {
        "sha256:4cbc2466af84dc925b7e79c91c0a7a19a2a16873bb6e7975e8f6855a954831d8"
      } else {
        "sha256:43da977432e59fa094193c21ef4a11ba10de94f54400ef2576d6293b12500a57"
      }
  }
}

///|
fn local_normalization_inventory_matches(
  inventory : ClientLocalNormalizationInventory,
  owner : @checked.CheckedProgram,
) -> Bool {
  match inventory {
    CompletionFree(value) =>
      @checked.local_completion_free_inventory_matches(value, owner)
    SortCompletion(value) =>
      @checked.local_sort_normalization_inventory_matches(value, owner)
  }
}

///|
fn local_sort_normalization_journal_body(
  inventory : @checked.LocalSortNormalizationInventory,
  catalog_cid : String,
) -> Result[String, ClientLocalNormalizationIssue] {
  try {
    let writer = @encode.writer(1024, 32, 8)
    @encode.begin_object(writer)
    @encode.key(writer, "entries")
    @encode.begin_array(writer)
    for index in 0..<@checked.local_sort_normalization_entry_count(inventory) {
      guard @checked.local_sort_normalization_entry_at(inventory, index)
        is Some((path, authored, canonical)) else {
        return Err(ForeignPreparation)
      }
      @encode.begin_object(writer)
      @encode.key(writer, "authored")
      @encode.string_value(writer, authored)
      @encode.key(writer, "canonical")
      @encode.string_value(writer, canonical)
      @encode.key(writer, "path")
      @encode.string_value(writer, path)
      @encode.key(writer, "rule")
      guard @checked.local_sort_normalization_entry_rule_at(inventory, index)
        is Some(rule) else {
        return Err(ForeignPreparation)
      }
      @encode.string_value(writer, rule)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "rule_catalog_cid")
    @encode.string_value(writer, catalog_cid)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-normalization-journal/0.1")
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(Evidence(@publication.RunEvidenceEncoding))
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
  let program = @strategy.graph_program(owner.graph)
  let inventory : ClientLocalNormalizationInventory = match
    @checked.local_program_sort_normalization_inventory(program) {
    Ok(Some(value)) => SortCompletion(value)
    Ok(None) =>
      match @checked.local_program_completion_free_inventory(program) {
        Ok(value) => CompletionFree(value)
        Err(issue) => return Err(Inventory(issue))
      }
    Err(issue) => return Err(Inventory(issue))
  }
  let catalog_cid = local_normalization_catalog_cid(inventory)
  let wire = match inventory {
    CompletionFree(_) =>
      "{\"entries\":[],\"rule_catalog_cid\":\"" +
      catalog_cid +
      "\",\"version\":\"actql-normalization-journal/0.1\"}"
    SortCompletion(value) =>
      match local_sort_normalization_journal_body(value, catalog_cid) {
        Ok(wire) => wire
        Err(issue) => return Err(issue)
      }
  }
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
    !local_normalization_inventory_matches(
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
