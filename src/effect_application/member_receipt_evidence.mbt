///|
pub(all) enum EffectMemberReceiptEvidenceIssue {
  InvalidInventory
  ActivePhysicalOwner(Int)
  ForeignLedgerHead(Int)
  MissingTerminalReceipt(Int)
  ForeignTerminalReceipt(Int)
  RowPartitionMismatch(Int)
  MemberReceipt(@publication.EffectApplyReceiptBindingIssue)
  Receipt(@publication.PublicationContractIssue)
  Encoding
} derive(Debug)

///|
/// Issue one member Receipt from the exact durable row partition. The caller
/// must re-admit terminal receipts from saved response bytes before calling.
/// Physical custody and evidence-view authority remain Host obligations.
pub fn issue_effect_member_receipt_from_row_partition(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  scopes : Array[LogicalRequestScope],
  locators : Array[LogicalItemLocator],
  keys : Array[EffectDispatchKey],
  bases : Array[EffectLedgerBasis],
  heads : Array[EffectLedgerEntry?],
  active_owners : Array[Bool],
  terminal_receipts : Array[@publication.PublicationContract?],
  max_rows : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[@publication.PublicationContract, EffectMemberReceiptEvidenceIssue] {
  guard @publication.effect_preview_row_count(preview, member_index)
    is Some(row_count) &&
    row_count <= max_rows &&
    heads.length() == row_count &&
    terminal_receipts.length() == row_count else {
    return Err(InvalidInventory)
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  let mut success = false
  let mut accepted = false
  let mut unknown = false
  let mut failure = false
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "effect_member_preview_cid")
    @encode.string_value(
      writer,
      @publication.effect_preview_member_identity(preview, member_index).unwrap(),
    )
    @encode.key(writer, "effect_preview_cid")
    @encode.string_value(
      writer,
      @publication.effect_preview_semantic_identity(preview),
    )
    @encode.key(writer, "rows")
    @encode.begin_array(writer)
    for index in 0..<row_count {
      let row_cid = @publication.effect_preview_ordered_row_identity(
        preview, member_index, index,
      ).unwrap()
      let head = heads[index]
      let state = match head {
        None => "unattempted"
        Some(entry) =>
          match entry.state {
            Prepared => "unattempted"
            Dispatching | Unknown => "unknown"
            Applied => "applied"
            Accepted => "accepted"
            Failed => "failed"
          }
      }
      match state {
        "applied" => success = true
        "accepted" => {
          success = true
          accepted = true
        }
        "unknown" => unknown = true
        _ => failure = true
      }
      @encode.begin_object(writer)
      @encode.key(writer, "row_index")
      @encode.number_value(writer, index.to_double())
      @encode.key(writer, "row_preview_cid")
      @encode.string_value(writer, row_cid)
      @encode.key(writer, "state")
      @encode.string_value(writer, state)
      if state != "unattempted" {
        let entry = head.unwrap()
        let dispatch_cid = if state == "unknown" {
          if entry.state == Dispatching {
            entry.cid
          } else {
            entry.prior_entry_cid.unwrap_or("")
          }
        } else {
          match terminal_receipts[index] {
            Some(receipt) =>
              @publication.effect_row_outcome_receipt_dispatch_identity(receipt).unwrap_or(
                "",
              )
            None => return Err(MissingTerminalReceipt(index))
          }
        }
        @encode.key(writer, "dispatch_entry_cid")
        @encode.string_value(writer, dispatch_cid)
        @encode.key(writer, "attempt_sequence")
        @encode.number_value(writer, entry.attempt_sequence.to_double())
        if state == "unknown" {
          @encode.key(writer, "ledger_head_cid")
          @encode.string_value(writer, entry.cid)
        } else {
          guard terminal_receipts[index] is Some(receipt) else {
            return Err(MissingTerminalReceipt(index))
          }
          @encode.key(writer, "outcome_receipt_cid")
          @encode.string_value(
            writer,
            @publication.publication_contract_identity(receipt),
          )
        }
      }
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "run_identity_cid")
    @encode.string_value(
      writer,
      @publication.effect_preview_run_identity(preview),
    )
    @encode.key(writer, "status")
    let status = if unknown {
      "unknown_outcome"
    } else if failure {
      if success {
        "partial_failure"
      } else {
        "failed"
      }
    } else if accepted {
      "accepted"
    } else {
      "applied"
    }
    @encode.string_value(writer, status)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-effect-apply-receipt/0.1")
    @encode.end_object(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let body = @encode.finish(writer) catch { _ => return Err(Encoding) }
  let issued = match
    @publication.seal_publication_contract(
      "effect_apply_receipt", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Receipt(issue))
  }
  match
    check_effect_member_receipt_row_partition_evidence(
      preview,
      member_index,
      scopes,
      locators,
      keys,
      bases,
      heads,
      active_owners,
      terminal_receipts,
      @publication.publication_contract_json(issued),
      max_rows,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(_) => Ok(issued)
    Err(issue) => Err(issue)
  }
}

///|
/// Check a member receipt's row partition against exact durable Ledger heads and
/// physically re-admitted terminal row receipts. The adapter must read each
/// head from the Store and re-admit each terminal receipt against its saved
/// response before passing it here. This does not prove the member's aggregate
/// typed outcome, grant evidence viewing, or establish current apply authority.
pub fn check_effect_member_receipt_row_partition_evidence(
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  scopes : Array[LogicalRequestScope],
  locators : Array[LogicalItemLocator],
  keys : Array[EffectDispatchKey],
  bases : Array[EffectLedgerBasis],
  heads : Array[EffectLedgerEntry?],
  active_owners : Array[Bool],
  terminal_receipts : Array[@publication.PublicationContract?],
  member_receipt_wire : String,
  max_rows : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, EffectMemberReceiptEvidenceIssue] {
  let row_count = match
    @publication.effect_preview_row_count(preview, member_index) {
    Some(value) => value
    None => return Err(InvalidInventory)
  }
  if max_rows < 0 ||
    row_count > max_rows ||
    scopes.length() != row_count ||
    locators.length() != row_count ||
    keys.length() != row_count ||
    bases.length() != row_count ||
    heads.length() != row_count ||
    active_owners.length() != row_count ||
    terminal_receipts.length() != row_count {
    return Err(InvalidInventory)
  }
  let receipt = match
    @publication.admit_effect_apply_receipt_for_member(
      preview, member_index, member_receipt_wire, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(MemberReceipt(issue))
  }
  let preview_cid = @publication.effect_preview_semantic_identity(preview)
  let effect_kind = match
    @publication.effect_preview_member_kind(preview, member_index) {
    Some(value) => value
    None => return Err(InvalidInventory)
  }
  for row_index in 0..<row_count {
    if active_owners[row_index] {
      return Err(ActivePhysicalOwner(row_index))
    }
    let row_cid = @publication.effect_preview_ordered_row_identity(
      preview, member_index, row_index,
    ).unwrap()
    if bases[row_index].logical_request_scope_cid !=
      logical_request_scope_cid(scopes[row_index]) ||
      bases[row_index].logical_item_locator_cid != locators[row_index].cid ||
      bases[row_index].dispatch_key_cid != keys[row_index].cid ||
      admit_effect_single_row(
        preview,
        member_index,
        row_index,
        effect_kind,
        scopes[row_index],
        row_cid,
        locators[row_index],
        keys[row_index],
      )
      is Err(_) {
      return Err(ForeignLedgerHead(row_index))
    }
    let expected_partition = match heads[row_index] {
      None => "unattempted"
      Some(head) => {
        if bases[row_index].effect_preview_cid != preview_cid ||
          !effect_ledger_entry_matches_basis(head, bases[row_index]) {
          return Err(ForeignLedgerHead(row_index))
        }
        match head.state {
          Prepared => "unattempted"
          Dispatching | Unknown => "unknown"
          Applied => "applied"
          Accepted => "accepted"
          Failed => "failed"
        }
      }
    }
    let claimed = @publication.effect_apply_receipt_row_state(receipt, row_cid)
    if claimed != Some(expected_partition) &&
      !(claimed == Some("rolled_back") && expected_partition == "failed") {
      return Err(RowPartitionMismatch(row_index))
    }
    if expected_partition == "unknown" {
      guard heads[row_index] is Some(head) else {
        return Err(ForeignLedgerHead(row_index))
      }
      let dispatch_cid = if head.state == Dispatching {
        Some(head.cid)
      } else {
        head.prior_entry_cid
      }
      if @publication.effect_apply_receipt_row_field(
          receipt, row_cid, "ledger_head_cid",
        ) !=
        Some(head.cid) ||
        @publication.effect_apply_receipt_row_field(
          receipt, row_cid, "dispatch_entry_cid",
        ) !=
        dispatch_cid ||
        @publication.effect_apply_receipt_row_attempt_sequence(receipt, row_cid) !=
        Some(head.attempt_sequence) {
        return Err(ForeignLedgerHead(row_index))
      }
    }
    match expected_partition {
      "applied" | "accepted" | "failed" => {
        guard heads[row_index] is Some(head) &&
          terminal_receipts[row_index] is Some(row_receipt) else {
          return Err(MissingTerminalReceipt(row_index))
        }
        if head.outcome_receipt_cid !=
          Some(@publication.publication_contract_identity(row_receipt)) ||
          @publication.effect_apply_receipt_row_field(
            receipt, row_cid, "outcome_receipt_cid",
          ) !=
          Some(@publication.publication_contract_identity(row_receipt)) ||
          @publication.effect_apply_receipt_row_field(
            receipt, row_cid, "dispatch_entry_cid",
          ) !=
          @publication.effect_row_outcome_receipt_dispatch_identity(row_receipt) ||
          @publication.effect_apply_receipt_row_attempt_sequence(
            receipt, row_cid,
          ) !=
          Some(head.attempt_sequence) ||
          @publication.effect_row_outcome_receipt_row_identity(row_receipt) !=
          Some(row_cid) ||
          @publication.effect_row_outcome_receipt_terminal_state(row_receipt) !=
          Some(expected_partition) {
          return Err(ForeignTerminalReceipt(row_index))
        }
      }
      _ =>
        if terminal_receipts[row_index] is Some(_) {
          return Err(ForeignTerminalReceipt(row_index))
        }
    }
  }
  Ok(())
}
