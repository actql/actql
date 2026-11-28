///|
// The encoded original subtrees are borrowed. The request writer owns only
// six top-level fields, one active container, its returned text and digest.
fn original_mock_effect_file_request_workspace(bytes : Int) -> Int64? {
  guard @encode.text_writer_live_key_inventory(bytes, 6, 1) is Some(writer) &&
    @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: writer.record_headers + hash.record_headers + 16L,
    reference_slots: writer.reference_slots + hash.reference_slots + 24L,
    scalar_words: writer.scalar_words + hash.scalar_words + 12L,
    owned_utf16_units: writer.owned_utf16_units + hash.owned_utf16_units + 71L,
    owned_wire_bytes: hash.owned_wire_bytes,
  })
}

///|
fn prepare_original_mock_effect_file_request(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : StoredMockProjectWriteTarget,
  identity : String,
  before : @encode.EncodedDocument,
  changes : @encode.EncodedDocument,
  version : String,
  occupied : Int64,
) -> Result[(String, String), Int] {
  guard targets.workspace is Some(workspace) else { return Err(-32) }
  guard original_mock_effect_file_request_workspace(0).bind(bytes => {
      @execution.checked_preparation_add_product(occupied, 1L, bytes)
    })
    is Some(measurement) &&
    @resources.grow_capacity_reservation(
      drive.ledger,
      workspace,
      0L,
      measurement,
    )
    is Ok(_) else {
    return Err(-4)
  }
  let limits = @host.client_standard_effect_computation_limits().program.checking.compilation.artifacts
  let emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure = writer => {
    @host.emit_client_effect_file_update(
      writer,
      original.binding_cid,
      original.write.mapping.mapping_cid,
      identity,
      changes,
      before,
      version,
    )
  }
  let (bytes, nodes, depth) = try {
    let writer = @encode.measuring_writer(
      limits.bytes,
      limits.nodes,
      limits.depth,
    )
    emit(writer)
    @encode.finish_measurement_usage(writer)
  } catch {
    _ => return Err(-31)
  }
  guard original_mock_effect_file_request_workspace(bytes).bind(bytes => {
      @execution.checked_preparation_add_product(occupied, 1L, bytes)
    })
    is Some(total) &&
    @resources.grow_capacity_reservation(drive.ledger, workspace, 0L, total)
    is Ok(_) else {
    return Err(-4)
  }
  let request = try {
    let writer = @encode.writer(bytes, nodes, depth)
    emit(writer)
    @encode.finish(writer)
  } catch {
    _ => return Err(-31)
  }
  guard @sha.text_hex(request) is Ok(digest) else { return Err(-31) }
  Ok((request, "sha256:" + digest))
}

///|
// The same before and change documents both form the physical request and
// supply the later Preview row. Their backing transfers to this same Run.
fn prepare_observed_mock_effect_file_request(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  selected : StoredMockProjectWriteTarget,
  proposal : @local_host.InstalledEffectResultProposal,
  target : @row_host.RelationTargetDocument,
  identity : String,
) -> Result[
  (String, String, String, @encode.EncodedDocument, @encode.EncodedDocument),
  Int,
] {
  let before_original : Ref[@encode.EncodedDocument?] = Ref(None)
  guard @row_host.observe_relation_target(
      target,
      selected.source.relation,
      identity,
      before_document=Some(before_original),
    )
    is Ok(row) else {
    return Err(-31)
  }
  defer ignore(@row_host.discard_relation_target_row_original(row))
  guard before_original.val is Some(before) &&
    @row_host.relation_target_version(row) is Some(version) else {
    return Err(-32)
  }
  let changes = match
    validate_original_mock_effect_target_changes(
      drive, targets, selected, proposal, target, row, version,
    ) {
    Ok(document) => document
    Err(code) => return Err(code)
  }
  guard targets.workspace is Some(workspace) &&
    @execution.preparation_representation_cost({
      record_headers: 2L,
      reference_slots: 1L,
      scalar_words: 3L,
      owned_utf16_units: @encode.document_text(changes).length().to_int64(),
      owned_wire_bytes: 0L,
    }).bind(bytes => {
      @execution.checked_preparation_add_product(
        targets.workspace_bytes,
        1L,
        bytes,
      )
    })
    is Some(held) &&
    @resources.shrink_capacity_reservation(drive.ledger, workspace, 0L, held)
    is Ok(_) else {
    return Err(-4)
  }
  prepare_original_mock_effect_file_request(
    drive, targets, selected, identity, before, changes, version, held,
  ).map(result => (version, result.0, result.1, before, changes))
}
