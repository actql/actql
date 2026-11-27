///|
// These are selectors from the exact saved Journal rows. Store authentication
// and current RunRead are still mandatory before restoring a public status.
priv struct NativeSavedModelSettlement {
  scope_cid : String
  slot_cid : String
  call : @publication.RunEvidenceValue
  attempt : @publication.RunEvidenceValue
  authority : @publication.RunEvidenceValue
  accounting_cid : String
  outcome_cid : String
  capture_cid : String
  raw_cid : String
  success : NativeSavedModelSuccessLeaves?
}

///|
priv struct NativeSavedModelSuccessLeaves {
  observation_cid : String
  bundle_cid : String
}

///|
priv struct NativeSavedModelSuccessSelection {
  slot : Int
  scope_cid : String
  observation_cid : String
  dependency : NativeModelEntryDependency?
}

///|
priv enum NativeSavedModelSettlementSelection {
  SavedFailure(String, String) // exact Attempt and Raw from terminal status
  DependentSuccess(String, NativeSavedModelSuccessSelection)
  ReferencedSuccess(String, NativeCompletedModelDependencySlot) // producer Scope and exact slot identities
}

///|
fn fund_native_saved_model_parse(
  reads : NativeClientJournalReadAccess,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard @decode.preserving_json_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(inventory) &&
    @execution.preparation_representation_cost({
      record_headers: inventory.record_headers,
      reference_slots: inventory.reference_slots,
      scalar_words: inventory.scalar_words,
      owned_utf16_units: inventory.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(peak) else {
    return Err(CapacityExceeded)
  }
  let block = @sqlite.publication_construction_block_bound(nodes, nodes, bytes)
  fund_native_saved_model_construction(reads, peak, peak, block)
}

///|
fn fund_native_saved_model_selection(
  reads : NativeClientJournalReadAccess,
) -> Result[Unit, NativeClientRunJournalIssue] {
  // Hashing the Entry and each holding uses the same synchronous workspace.
  // Both observed rows and the admitted Entry leaves are still held.
  guard @encode.hash_writer_construction_inventory(64, 4) is Some(hash) &&
    @execution.preparation_representation_cost({
      record_headers: 80L,
      reference_slots: 160L,
      scalar_words: 96L,
      owned_utf16_units: 256L,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: hash.record_headers,
      reference_slots: hash.reference_slots,
      scalar_words: hash.scalar_words,
      owned_utf16_units: hash.owned_utf16_units,
      owned_wire_bytes: hash.owned_wire_bytes,
    })
    is Some(workspace) &&
    @execution.checked_preparation_add_product(retained, workspace, 1L)
    is Some(execution) else {
    return Err(CapacityExceeded)
  }
  let block = @sqlite.publication_construction_block_bound(64, 64, 2048)
  fund_native_saved_model_construction(reads, retained, execution, block)
}

///|
fn fund_native_saved_model_construction(
  reads : NativeClientJournalReadAccess,
  retained : Int64,
  execution : Int64,
  raw : Int64,
) -> Result[Unit, NativeClientRunJournalIssue] {
  // Whitebox SQL-only fixtures have no installed Domain reservation. The
  // consuming Native status reader supplies the original funded Read.
  match reads.before_metadata_construction {
    Some(prepare) if raw > 0L => prepare(retained, execution, raw)
    Some(_) => Err(CapacityExceeded)
    None => Ok(())
  }
}

///|
fn parse_native_saved_model_object(
  reads : NativeClientJournalReadAccess,
  body : Bytes,
  names : Array[String],
  nodes : Int,
  depth : Int,
) -> Result[@decode.ObjectView, NativeClientRunJournalIssue] {
  let bytes = body.length()
  match fund_native_saved_model_parse(reads, bytes, nodes, depth) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard @source.parse_json_bytes_preserving(body, {
      max_input_bytes: bytes,
      max_nodes: nodes,
      max_depth: depth,
    })
    is Ok(source) &&
    @decode.admit(source, {
      max_nodes: nodes,
      max_depth: depth,
      max_string_bytes: bytes,
      max_total_string_bytes: bytes,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, names) is Ok(fields) else {
    return Err(CustodyLost)
  }
  Ok(fields)
}

///|
fn read_native_saved_model_entry_leaf(
  reads : NativeClientJournalReadAccess,
  fields : @decode.ObjectView,
  field : String,
  kind : String,
) -> Result[@publication.RunEvidenceValue, NativeClientRunJournalIssue] {
  guard epoch_text(fields, field) is Some(wire) else { return Err(CustodyLost) }
  admit_native_saved_model_leaf(reads, wire, kind)
}

///|
fn admit_native_saved_model_leaf(
  reads : NativeClientJournalReadAccess,
  wire : String,
  kind : String,
  nodes? : Int = 256,
  depth? : Int = 8,
) -> Result[@publication.RunEvidenceValue, NativeClientRunJournalIssue] {
  fund_native_saved_model_leaf(reads, wire, 16384, nodes, depth).bind(_ => {
    @publication.admit_run_evidence_value(kind, wire, 16384, nodes, depth).map_err(_ => {
        CustodyLost
      },
    )
  })
}

///|
fn fund_native_saved_model_leaf(
  reads : NativeClientJournalReadAccess,
  wire : String,
  maximum : Int,
  nodes : Int,
  depth : Int,
) -> Result[Unit, NativeClientRunJournalIssue] {
  guard @scalar.admit_utf8_length(wire, maximum) is Ok(bytes) else {
    return Err(CustodyLost)
  }
  guard @publication.run_evidence_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(quote) &&
    @execution.preparation_representation_cost({
      record_headers: quote.retained.record_headers,
      reference_slots: quote.retained.reference_slots,
      scalar_words: quote.retained.scalar_words,
      owned_utf16_units: quote.retained_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: quote.record_headers,
      reference_slots: quote.reference_slots,
      scalar_words: quote.scalar_words,
      owned_utf16_units: quote.owned_utf16_units,
      owned_wire_bytes: quote.owned_wire_bytes,
    })
    is Some(workspace) &&
    @execution.checked_preparation_add_product(retained, workspace, 1L)
    is Some(execution) else {
    return Err(CustodyLost)
  }
  let block = @sqlite.publication_construction_block_bound(nodes, nodes, bytes)
  fund_native_saved_model_construction(reads, retained, execution, block)
}

///|
fn read_native_saved_model_row(
  reads : NativeClientJournalReadAccess,
  table : String,
  key : String,
  maximum : Int64,
) -> Result[Bytes, NativeClientRunJournalIssue] {
  match (reads.read_bounded)(table, key, maximum) {
    Ok(row) if row.revision == 0L &&
      row.body.length() > 0 &&
      row.body.length().to_int64() <= maximum => Ok(row.body)
    Ok(_) | Err(@sqlite.NotFound) => Err(CustodyLost)
    Err(@sqlite.BodyTooLarge) => Err(CapacityExceeded)
    Err(issue) => Err(Physical(issue))
  }
}

///|
// The enclosing status reader owns authorization and a live Store Read.
// Both points stay in the original Journal transaction. Success is selected
// from the actual producing Attempt and its original successful observation;
// a retained failure locator cannot select success evidence.
fn NativeClientRunJournal::read_saved_model_settlement_locked(
  self : NativeClientRunJournal,
  run : NativeClientRunRecord,
  binding : String,
  store_authority : String,
  selection : NativeSavedModelSettlementSelection,
  max_bytes : Int64,
  reads : NativeClientJournalReadAccess,
) -> Result[NativeSavedModelSettlement, NativeClientRunJournalIssue] {
  let (attempt_cid, selection_valid) = match selection {
    SavedFailure(attempt, raw) => (attempt, saved_effect_capture_cid_valid(raw))
    DependentSuccess(attempt, expected) =>
      (
        attempt,
        expected.slot >= 0 &&
        saved_effect_capture_cid_valid(expected.scope_cid) &&
        saved_effect_capture_cid_valid(expected.observation_cid),
      )
    ReferencedSuccess(scope, (slot, attempt, raw, bundle)) =>
      (
        attempt,
        slot >= 0 &&
        saved_effect_capture_cid_valid(scope) &&
        saved_effect_capture_cid_valid(raw) &&
        saved_effect_capture_cid_valid(bundle),
      )
  }
  guard self.transaction_active &&
    physical_equal(self.database, reads.database) &&
    run.dispatch_reserved &&
    run.physical_start_claimed &&
    run.checkpoint is None &&
    run.publication_binding == Some(binding) &&
    selection_valid &&
    saved_effect_capture_cid_valid(attempt_cid) &&
    saved_effect_capture_cid_valid(store_authority) &&
    max_bytes > 0L &&
    max_bytes < 2147483519L else {
    return Err(CustodyLost)
  }
  let entry = match
    read_native_saved_model_row(
      reads, "client_model_call_originals", attempt_cid, max_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let remaining = max_bytes - entry.length().to_int64()
  if remaining <= 0L {
    return Err(CapacityExceeded)
  }
  let settlement = match
    read_native_saved_model_row(
      reads, "client_model_call_settlements", attempt_cid, remaining,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let definition = run.definition
  let definition_cid = @publication.publication_contract_identity(definition)
  let request_cid = @host.client_request_scope_cid(run.request)
  let expected_dependency = match selection {
    DependentSuccess(_, original) => original.dependency
    _ => None
  }
  let referenced = selection is ReferencedSuccess(_, _)
  let entry_names = if referenced || expected_dependency is Some(_) {
    [
      "attempt", "authority", "call", "dependency", "request_scope_cid", "run_definition_cid",
      "slot", "version",
    ]
  } else {
    [
      "attempt", "authority", "call", "request_scope_cid", "run_definition_cid",
      "slot", "version",
    ]
  }
  guard native_model_entry_dependency_geometry(expected_dependency)
    is Some((_, expected_nodes, expected_depth)) else {
    return Err(CapacityExceeded)
  }
  let (entry_nodes, entry_depth) = if referenced {
    (24 + 16 * (entry.length() / 71), 7)
  } else {
    (expected_nodes, expected_depth)
  }
  let entry_fields = match
    parse_native_saved_model_object(
      reads, entry, entry_names, entry_nodes, entry_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let dependency = if referenced {
    match
      (
        epoch_text(entry_fields, "version"),
        @decode.lookup(entry_fields, "dependency"),
      ) {
      (Some(version), Some(cursor)) if version ==
        native_dependent_model_entry_version =>
        match
          admit_native_saved_dependent_inventory(
            reads, cursor, attempt_cid, entry_nodes,
          ) {
          Ok(value) => Some(value)
          Err(issue) => return Err(issue)
        }
      (Some(version), None) if version == native_plain_model_entry_version =>
        None
      _ => return Err(CustodyLost)
    }
  } else {
    expected_dependency
  }
  let entry_version = if dependency is Some(_) {
    native_dependent_model_entry_version
  } else {
    native_plain_model_entry_version
  }
  let settled_fields = match
    parse_native_saved_model_object(
      reads,
      settlement,
      [
        "attempt_cid", "entry_digest", "request_scope_cid", "run_definition_cid",
        "scope_cid", "store_binding", "version", "slot", "evidence",
      ],
      48,
      4,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard epoch_text(entry_fields, "version") == Some(entry_version) &&
    epoch_text(settled_fields, "version") ==
    Some("actql-native-model-call-settlement-original/0.1") &&
    epoch_text(entry_fields, "request_scope_cid") == Some(request_cid) &&
    epoch_text(settled_fields, "request_scope_cid") == Some(request_cid) &&
    epoch_text(entry_fields, "run_definition_cid") == Some(definition_cid) &&
    epoch_text(settled_fields, "run_definition_cid") == Some(definition_cid) &&
    epoch_text(settled_fields, "store_binding") == Some(binding) &&
    epoch_text(settled_fields, "attempt_cid") == Some(attempt_cid) &&
    epoch_text(settled_fields, "entry_digest") is Some(entry_digest) &&
    epoch_text(settled_fields, "scope_cid") is Some(scope_cid) &&
    @decode.lookup(entry_fields, "slot") is Some(entry_slot) &&
    @decode.int32(entry_slot) is Ok(slot) &&
    slot >= 0 &&
    @decode.lookup(settled_fields, "slot") is Some(settled_slot) &&
    @decode.int32(settled_slot) is Ok(other_slot) &&
    other_slot == slot &&
    @decode.lookup(settled_fields, "evidence") is Some(leaves) &&
    @decode.array_length(leaves) is Some(count) else {
    return Err(CustodyLost)
  }
  let raw_index = match selection {
    SavedFailure(_, _) if count == 7 || count == 8 => 5
    DependentSuccess(_, expected) if slot == expected.slot &&
      scope_cid == expected.scope_cid &&
      (count == 8 || count == 9) => 6
    ReferencedSuccess(scope, (original, _, _, _)) if slot == original &&
      scope_cid == scope &&
      (count == 8 || count == 9) => 6
    _ => return Err(CustodyLost)
  }
  let call = match
    read_native_saved_model_entry_leaf(
      reads, entry_fields, "call", "model_call_slot",
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let attempt = match
    read_native_saved_model_entry_leaf(
      reads, entry_fields, "attempt", "model_call_attempt",
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let authority = match
    read_native_saved_model_entry_leaf(
      reads, entry_fields, "authority", "model_dispatch_authority",
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if referenced || dependency is Some(_) {
    if dependency is Some(original) && original.scope != scope_cid {
      return Err(CustodyLost)
    }
    guard native_model_entry_dependency_geometry(dependency)
      is Some((_, nodes, depth)) &&
      journal_row_construction_working(entry.length(), nodes, depth)
      is Some((retained, execution, block)) else {
      return Err(CapacityExceeded)
    }
    match
      fund_native_saved_model_construction(reads, retained, execution, block) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match
      native_model_entry_body(
        run.request,
        definition,
        slot,
        call,
        attempt,
        authority,
        entry.length(),
        dependency~,
      ) {
      Ok(expected) if expected == entry => ()
      _ => return Err(CustodyLost)
    }
  }
  let slot_cid = @publication.run_evidence_value_identity(call)
  let authority_cid = @publication.run_evidence_value_identity(authority)
  match fund_native_saved_model_selection(reads) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard entry_digest == "sha256:" + @sha.hex(entry) &&
    @publication.run_evidence_value_identity(attempt) == attempt_cid &&
    @publication.check_retained_model_call_entry_scope(
      definition, scope_cid, call, attempt, authority,
    )
    is Ok(_) else {
    return Err(CustodyLost)
  }
  let selected : Array[String] = Array(capacity=count)
  let roles = [
    "model_call_attempt", "model_attempt_accounting", "model_attempt_outcome", "model_dispatch_authority",
    "model_slot_capture",
  ]
  for index in 0..<count {
    let role = if index < roles.length() {
      roles[index]
    } else if index == count - 1 {
      "model_capture_bundle"
    } else if index == raw_index {
      "model_raw_response"
    } else if index > raw_index {
      "model_attachment_admission"
    } else {
      "model_invocation_evidence"
    }
    guard @decode.element_at(leaves, index) is Some(leaf) &&
      @decode.closed_object(leaf, ["cid", "holding_cid", "role"]) is Ok(fields) &&
      epoch_text(fields, "role") == Some(role) &&
      epoch_text(fields, "cid") is Some(cid) &&
      saved_effect_capture_cid_valid(cid) &&
      @publication.model_scoped_private_holding_cid(
        definition, store_authority, scope_cid, slot_cid, attempt_cid, 1, "settled",
        role,
      )
      is Some(holding) &&
      epoch_text(fields, "holding_cid") == Some(holding) else {
      return Err(CustodyLost)
    }
    selected.push(cid)
  }
  guard selected[0] == attempt_cid && selected[3] == authority_cid else {
    return Err(CustodyLost)
  }
  let raw_cid = selected[raw_index]
  let success = match selection {
    SavedFailure(_, expected) if raw_cid == expected => None
    DependentSuccess(_, expected) if selected[5] == expected.observation_cid =>
      Some({ observation_cid: selected[5], bundle_cid: selected[count - 1], })
    ReferencedSuccess(_, (_, _, raw, bundle)) if raw_cid == raw &&
      selected[count - 1] == bundle =>
      Some({ observation_cid: selected[5], bundle_cid: bundle, })
    _ => return Err(CustodyLost)
  }
  Ok({
    scope_cid,
    slot_cid,
    call,
    attempt,
    authority,
    accounting_cid: selected[1],
    outcome_cid: selected[2],
    capture_cid: selected[4],
    raw_cid,
    success,
  })
}
