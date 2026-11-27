///|
/// Confirm the existing file-effect witness and its immutable receipt rows
/// before exposing a completed saved lifecycle. No filesystem target is opened.
fn[E] confirm_client_completed_file_effect(
  row : ClientJournalPhysicalRow,
  run : ClientRunJournalEncoding,
  checkpoint : ClientCheckpointJournalRecord,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  fund : (Int, Int, Int) -> Result[Unit, E],
  invalid : E,
) -> Result[Unit, E] {
  let entries = checkpoint.effect_ledger
  let key = client_request_scope_cid(run.request)
  let scope = client_request_authority_scope_cid(run.request)
  let preview = checkpoint.artifact.checkpoint.required_artifact_cid
  let limits = client_effect_ledger_wire_limits()
  guard !entries.is_empty() &&
    entries.length() % 3 == 0 &&
    row.revision == 6L + entries.length().to_int64() &&
    client_effect_ledger_base_witness(run.request, run.definition, checkpoint)
    is Some(base) else {
    return Err(invalid)
  }
  let mut witness = @utf8.decode(base) catch { _ => return Err(invalid) }
  fn stored(table, identity) {
    read(table, identity).bind(candidate => {
      guard candidate is Some(cell) &&
        cell.key == identity &&
        cell.revision == 0L else {
        return Err(invalid)
      }
      Ok(cell.body)
    })
  }
  for offset in 0..<(entries.length() / 3) {
    let prepared = entries[3 * offset]
    let dispatch = entries[3 * offset + 1]
    let terminal = entries[3 * offset + 2]
    guard @effect.effect_ledger_entry_state_code(prepared) == 0 &&
      @effect.effect_ledger_entry_state_code(dispatch) == 1 &&
      @effect.effect_ledger_entry_state_code(terminal) == 2 &&
      @effect.effect_ledger_entry_follows(Some(prepared), dispatch) &&
      @effect.effect_ledger_entry_follows(Some(dispatch), terminal) &&
      terminal.outcome_receipt_cid is Some(receipt_cid) else {
      return Err(invalid)
    }
    let meta = match stored("client_effect_response_meta", dispatch.cid) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    let raw = match stored("client_effect_response_bytes", dispatch.cid) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    let receipt_bytes = match stored("client_effect_row_receipt", receipt_cid) {
      Err(issue) => return Err(issue)
      Ok(value) => value
    }
    guard meta.length() > 0 &&
      meta.length() <= limits.max_wire_bytes &&
      !raw.is_empty() &&
      raw.length() <= 262144 &&
      !receipt_bytes.is_empty() &&
      receipt_bytes.length() <= limits.max_wire_bytes else {
      return Err(invalid)
    }
    match
      fund(
        meta.length() + raw.length() + receipt_bytes.length(),
        2 * limits.max_nodes,
        limits.max_depth,
      ) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let metadata = @utf8.decode(meta) catch { _ => return Err(invalid) }
    let receipt_wire = @utf8.decode(receipt_bytes) catch {
      _ => return Err(invalid)
    }
    guard @publication.admit_saved_effect_file_operation_receipt(
        metadata,
        raw,
        262144,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      is Ok(response) &&
      response.operation.effect_preview_cid == preview &&
      response.operation.dispatch_entry_cid == dispatch.cid &&
      response.operation.authorization_context_cid == scope &&
      response.operation.canonical_request_cid == dispatch.canonical_request_cid &&
      Some(response.operation.resolution_cid) == checkpoint.resolution_cid &&
      @publication.confirm_saved_effect_file_outcome(
        response,
        receipt_wire,
        receipt_cid,
        limits.max_wire_bytes,
        limits.max_nodes,
        limits.max_depth,
      ) else {
      return Err(invalid)
    }
    witness += "\nresponse\n" +
      dispatch.cid +
      "\n" +
      @sha.hex(meta) +
      "\nreceipt\n" +
      terminal.cid +
      "\n" +
      receipt_cid
  }
  match read("client_effect_custody", key) {
    Err(issue) => Err(issue)
    Ok(Some(original)) if original.key == key &&
      original.revision == entries.length().to_int64() &&
      original.body == @utf8.encode(witness) => Ok(())
    Ok(_) => Err(invalid)
  }
}

///|
fn[E] observe_client_effect_completion_index(
  namespace_id : String,
  authority_scope_cid : String,
  definition_cid : String,
  run_key : String,
  checkpoint : ClientCheckpointJournalRecord,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  fund : (Int, Int, Int) -> Result[Unit, E],
  invalid : E,
) -> Result[Unit, E] {
  guard @publication.publication_index_scope_storage_key(
      namespace_id, authority_scope_cid, definition_cid, 65536, 4096, 64,
    )
    is Ok(key) else {
    return Err(invalid)
  }
  let reference = match read("public_index", key) {
    Err(issue) => return Err(issue)
    Ok(Some(index)) if index.key == key &&
      index.revision == 0L &&
      index.body.length() == 71 =>
      @utf8.decode(index.body) catch {
        _ => return Err(invalid)
      }
    _ => return Err(invalid)
  }
  fn contract(name, identity) {
    let cell = match read("publication_contract", identity) {
      Err(issue) => return Err(issue)
      Ok(Some(cell)) if cell.key == identity &&
        cell.revision == 0L &&
        cell.body.length() > 0 &&
        cell.body.length() <= 65536 => cell
      _ => return Err(invalid)
    }
    match fund(cell.body.length(), Int::min(4096, cell.body.length()), 64) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    let wire = @utf8.decode(cell.body) catch { _ => return Err(invalid) }
    match @publication.admit_publication_contract(name, wire, 65536, 4096, 64) {
      Ok(value) if @publication.publication_contract_identity(value) == identity =>
        Ok(value)
      _ => Err(invalid)
    }
  }
  let index = match contract("public_index_entry", reference) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard @publication.publication_index_storage_key(index, 65536, 4096, 64)
    is Ok(expected) &&
    expected == key &&
    @publication.public_index_run_observation_cids(index)
    is Ok((receipt_cid, capture_cid)) else {
    return Err(invalid)
  }
  contract("run_receipt", receipt_cid).bind(receipt => {
    if !@publication.saved_file_final_receipt_matches(
        receipt,
        checkpoint.artifact.checkpoint.required_artifact_cid,
        capture_cid,
      ) {
      return Err(invalid)
    }
    match read("client_effect_publication", run_key) {
      Err(issue) => Err(issue)
      Ok(Some(anchor)) if anchor.revision == 0L &&
        anchor.key == run_key &&
        anchor.body ==
        client_effect_publication_anchor(
          definition_cid,
          checkpoint.artifact.checkpoint_cid,
          receipt_cid,
          reference,
        ) => Ok(())
      Ok(_) => Err(invalid)
    }
  })
}

///|
/// The selected Saved reader already checked the complete applied witness and
/// original index in its enclosing snapshot. Borrow only that Preview name.
pub fn client_completed_effect_file_preview(
  row : ClientJournalPhysicalRow,
  run : ClientRunJournalEncoding,
) -> String? {
  guard run.checkpoint is Some(wire) &&
    run.effect_material_originals is Some(_) &&
    decode_client_checkpoint_journal_row(
      wire,
      run.definition,
      client_effect_ledger_wire_limits(),
    )
    is Ok(checkpoint) &&
    checkpoint.state.status == @publication.Succeeded &&
    checkpoint.resume_intent is Some(intent) &&
    intent.state == @checkpoint.ResumeCompleted &&
    !checkpoint.effect_ledger.is_empty() &&
    row.revision == 6L + checkpoint.effect_ledger.length().to_int64() else {
    return None
  }
  Some(checkpoint.artifact.checkpoint.required_artifact_cid)
}

///|
fn client_effect_publication_anchor(
  definition : String,
  checkpoint : String,
  receipt : String,
  index : String,
) -> Bytes {
  @utf8.encode(definition + "\n" + checkpoint + "\n" + receipt + "\n" + index)
}
