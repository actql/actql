///|
/// Admitted computation and application evidence for the original Run.
/// Nothing is published until its separate authorized Store owner commits.
pub struct ClientEffectSavedFileCompletion {
  application : ClientEffectSavedApplication
  members : Array[@publication.PublicationContract]
  final_receipt : @publication.PublicationContract
  evidence : @publication.EffectfulFinalRunEvidence
}

///|
pub fn ClientEffectSavedApplication::complete_file_evidence(
  self : ClientEffectSavedApplication,
  terminals : Array[ClientEffectSavedFileTerminal],
  limits : @checkpoint.WireLimits,
  fund : (Int, Int, Int) -> Bool,
  fund_exact : (Int64) -> Bool,
  work : (Int) -> Bool,
) -> Result[
  ClientEffectSavedFileCompletion,
  ClientEffectResolutionOriginalIssue,
] {
  let (member_count, row_count) = self.ordered_count()
  guard member_count > 0 &&
    row_count == terminals.length() &&
    fund(0, 64 + 32 * member_count + 48 * row_count, limits.max_depth) else {
    return Err(InvalidOriginal)
  }
  let computation = self.computation
  let preview = computation.preview.preview
  let members = Array(capacity=member_count)
  let mut index = 0
  for member_index in 0..<member_count {
    let count = self.keys[member_index].length()
    let scopes = Array(capacity=count)
    let locators = Array(capacity=count)
    let keys = Array(capacity=count)
    let bases = Array(capacity=count)
    let heads = Array(capacity=count)
    let active = Array(capacity=count)
    let receipts = Array(capacity=count)
    let mut bytes = 1536
    let mut nodes = 48
    for ordinal in 0..<count {
      guard terminals.get(index) is Some(original) else {
        return Err(InvalidOriginal)
      }
      let dispatch = original.response.dispatch
      let row = dispatch.row
      guard dispatch.index == index &&
        row.member_index == member_index &&
        row.ordinal == ordinal &&
        physical_equal(row.application, self) &&
        @effect.effect_ledger_entry_state_code(original.terminal) == 2 &&
        @publication.publication_contract_wire_usage(original.receipt)
        is Some((receipt_bytes, receipt_nodes, _)) &&
        receipt_bytes <= limits.max_wire_bytes - bytes &&
        receipt_nodes <= limits.max_nodes - nodes &&
        work(1 + receipt_bytes) else {
        return Err(InvalidOriginal)
      }
      bytes += receipt_bytes
      nodes += receipt_nodes
      scopes.push(self.scoped_request)
      locators.push(row.locator)
      keys.push(row.key)
      bases.push(row.basis)
      heads.push(Some(original.terminal))
      active.push(false)
      receipts.push(Some(original.receipt))
      index += 1
    }
    guard fund(bytes, nodes, limits.max_depth) &&
      @effect.issue_effect_member_receipt_from_row_partition(
        preview,
        member_index,
        scopes,
        locators,
        keys,
        bases,
        heads,
        active,
        receipts,
        count,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      is Ok(member_receipt) else {
      return Err(InvalidOriginal)
    }
    members.push(member_receipt)
  }
  let member_wires = members.map(@publication.publication_contract_json)
  let mut member_bytes = 2048
  for member_wire in member_wires {
    guard @scalar.admit_utf8_length(
        member_wire,
        limits.max_wire_bytes - member_bytes,
      )
      is Ok(bytes) &&
      work(bytes) else {
      return Err(InvalidOriginal)
    }
    member_bytes += bytes
  }
  guard fund(member_bytes, 80 + 32 * member_count, limits.max_depth) &&
    @publication.issue_effect_set_apply_receipt_from_members(
      preview,
      members,
      Array::make(member_count, false),
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Ok(effect_set) else {
    return Err(InvalidOriginal)
  }
  let set_wire = @publication.publication_contract_json(effect_set)
  guard @publication.retained_effectful_final_issuance_inventory(
      computation.retained,
      set_wire,
      member_wires,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(inventory) &&
    fund_saved_effect_completion(inventory, fund_exact) &&
    @publication.issue_retained_effectful_final_run_evidence(
      computation.retained,
      computation.derivations,
      computation.orderings,
      computation.retentions,
      set_wire,
      member_wires,
      limits.max_wire_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    is Ok(evidence) else {
    return Err(InvalidOriginal)
  }
  let final_receipt = @publication.effectful_final_run_evidence_receipt(
    evidence,
  )
  Ok({ application: self, members, final_receipt, evidence, })
}

///|
fn fund_saved_effect_completion(
  inventory : @publication.EffectPreviewIdentityConstructionInventory,
  fund : (Int64) -> Bool,
) -> Bool {
  guard @execution.preparation_representation_cost({
      record_headers: inventory.record_headers,
      reference_slots: inventory.reference_slots,
      scalar_words: inventory.scalar_words,
      owned_utf16_units: inventory.owned_utf16_units,
      owned_wire_bytes: inventory.owned_wire_bytes,
    })
    is Some(total) else {
    return false
  }
  fund(total)
}

///|
pub fn ClientEffectSavedFileCompletion::result_count(
  self : ClientEffectSavedFileCompletion,
) -> Int {
  @publication.retained_effectful_computation_result_count(
    self.application.computation.retained,
  )
}

///|
pub fn ClientEffectSavedFileCompletion::final_receipt_cid(
  self : ClientEffectSavedFileCompletion,
) -> String {
  @publication.publication_contract_identity(self.final_receipt)
}
