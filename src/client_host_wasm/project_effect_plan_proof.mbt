///|
priv struct StoredMockEffectPlanVerification {
  verifier : @strategy.CapturedEffectPlanVerifier
  charge : Int64
  mut row : Int
}

///|
// Re-read the selected completed Result under the original Preview and
// charged Task drive. The retained proof borrows its immutable originals.
fn advance_original_mock_effect_plan_proofs(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
) -> Int {
  guard targets.bound is Some(preview) else { return -32 }
  let count = targets.members.length()
  // Once all proofs return, the next Result snapshot may own this workspace
  // across advances. Only the incomplete proof may require it to be empty.
  if targets.plan_proofs is Some(proofs) && proofs.length() == count {
    return if targets.plan_verification is None { 0 } else { -32 }
  }
  guard targets.workspace is None else { return -32 }
  guard targets.plan_proofs is Some(proofs) else {
    guard @execution.preparation_array_representation(
        1L,
        count.to_int64(),
        false,
      )
      is Some(array) &&
      fund_original_mock_effect_target_data(drive, {
        ..array,
        record_headers: array.record_headers + count.to_int64(),
        reference_slots: array.reference_slots + 4L * count.to_int64(),
        scalar_words: array.scalar_words + count.to_int64(),
      }) else {
      return -4
    }
    targets.plan_proofs = Some(Array(capacity=count))
    return 1
  }
  let index = proofs.length()
  guard index < count &&
    targets.members.get(index) is Some(target) &&
    mock_effect_target_read_current(original, target.original) &&
    target.capture.original() is Some((_, stream, receipt)) else {
    return -32
  }
  let limits = @host.client_standard_effect_computation_limits().effects
  let fields = target.original.write.writable_fields.length()
  guard targets.plan_verification is Some(active) else {
    guard mock_effect_preview_plan_workspace(fields) is Some(charge) &&
      fund_original_mock_effect_target_bytes(drive, charge) else {
      return -4
    }
    let verifier = match
      @strategy.prepare_captured_effect_plan_verifier(
        preview,
        index,
        fields,
        limits.max_work,
      ) {
      Ok(verifier) => verifier
      Err(_) => return -31
    }
    targets.plan_verification = Some({ verifier, charge, row: 0, })
    return 1
  }
  if active.row == target.count {
    guard @strategy.finish_captured_effect_plan_verifier(active.verifier)
      is Ok(proof) else {
      return -31
    }
    proofs.push(proof)
    targets.plan_verification = None
    return if return_original_mock_effect_target_bytes(drive, active.charge) {
      1
    } else {
      -9
    }
  }
  guard target.rows.get(active.row) is Some(row) &&
    target.capture.proposal_row(index, active.row) is Some(proposal) &&
    physical_equal(row.proposal, proposal) &&
    @execution.completed_relation_export_snapshot_extent(stream, receipt)
    is Ok((bytes, nodes, count, depth)) &&
    count == target.count else {
    return -32
  }
  let max_bytes = limits.max_admission_text_bytes
  let max_nodes = limits.max_admission_nodes
  let depth = Int::min(depth, limits.max_admission_depth)
  let projected = Int64::min(
    max_bytes.to_int64(),
    3L * row.request.length().to_int64() + 128L,
  ).to_int()
  guard @encode.measuring_writer_construction_extent(depth, depth)
    is Some(writer) &&
    @values.wire_emit_workspace_construction_inventory(4 * (depth + 4))
    is Some(emit) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + emit.record_headers + 16L,
      reference_slots: writer.reference_slots + emit.reference_slots + 32L,
      scalar_words: writer.scalar_words + emit.scalar_words + 20L,
      owned_utf16_units: emit.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(peak) &&
    @resources.reserve_capacity(drive.ledger, 0L, peak) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  let selected = match
    @execution.read_completed_relation_export_canonical_row(
      stream,
      receipt,
      active.row,
      Int::min(bytes, max_bytes),
      Int::min(nodes, max_nodes),
      depth,
      (row_bytes, row_nodes, _) => {
        @host.client_protocol_metadata_construction_bytes(
          Int::max(row_bytes, projected),
          row_nodes.to_int64() +
          16L * depth.to_int64() +
          16L * fields.to_int64() +
          64L,
          copies=4,
        )
        is Some((construction, _)) &&
        @execution.checked_preparation_add_product(peak, 1L, construction)
        is Some(total) &&
        @resources.grow_capacity_reservation(drive.ledger, workspace, 0L, total)
        is Ok(_)
      },
    ) {
    Ok(value) => value
    Err(@execution.Admission(@execution.CaptureLimit)) => return -4
    Err(_) => return -31
  }
  if @strategy.check_captured_effect_plan_row(
      active.verifier,
      selected,
      active.row,
      fields,
      limits.max_work,
      projected,
      max_nodes,
      limits.max_admission_depth,
    )
    is Err(_) {
    return -31
  }
  if !release_original_mock_effect_target_document(drive, targets) {
    return -9
  }
  active.row += 1
  1
}
