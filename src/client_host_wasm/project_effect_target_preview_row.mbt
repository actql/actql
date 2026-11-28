///|
const MOCK_EFFECT_PREVIEW_PENDING_CID : String = "sha256:0000000000000000000000000000000000000000000000000000000000000000"

///|
// Convert one row per advance, after all collection documents and their
// scratch have retired. The same Run retains the request and admitted row.
fn advance_original_mock_effect_file_preview_rows(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  inputs : @strategy.CapturedEffectInputs,
  publication : @host.ClientEffectDirectSourcesPublication,
  run : @strategy.CapturedEffectRunDAG,
) -> Int {
  while targets.preview_member < targets.members.length() {
    let member_index = targets.preview_member
    let selected_member = targets.members[member_index]
    let row_index = targets.preview_row
    if !mock_effect_target_read_current(original, selected_member.original) {
      return -20
    }
    if row_index == selected_member.rows.length() {
      if selected_member.preview_identity is None {
        let evidence = match
          prepare_original_mock_effect_preview_identity(
            drive,
            targets,
            original.check,
            selected_member,
          ) {
          Ok(evidence) => evidence
          Err(code) => return code
        }
        selected_member.preview_identity = Some(evidence)
        return if release_original_mock_effect_target_document(drive, targets) {
          1
        } else {
          -9
        }
      }
      if selected_member.preview_source is None {
        let source = match
          prepare_original_mock_effect_preview_source(
            drive, targets, original, selected_member, inputs, publication, member_index,
          ) {
          Ok(source) => source
          Err(code) => return code
        }
        selected_member.preview_source = Some(source)
        return if release_original_mock_effect_target_document(drive, targets) {
          1
        } else {
          -9
        }
      }
      if selected_member.effect_identity is None {
        let effect_identity = match
          prepare_original_mock_effect_member_identity(
            drive, targets, original, selected_member, inputs, member_index,
          ) {
          Ok(identity) => identity
          Err(code) => return code
        }
        selected_member.effect_identity = Some(effect_identity)
        return if release_original_mock_effect_target_document(drive, targets) {
          1
        } else {
          -9
        }
      }
      let fields = match
        prepare_original_mock_effect_member_draft(
          drive, targets, original, selected_member, inputs, member_index,
        ) {
        Ok(fields) => fields
        Err(code) => return code
      }
      selected_member.draft_fields = Some(fields)
      guard release_original_mock_effect_target_document(drive, targets) else {
        return -9
      }
      guard selected_member.draft_fields is Some(retained) &&
        physical_equal(retained, fields) else {
        return -32
      }
      targets.preview_member += 1
      targets.preview_row = 0
      return 1
    }
    let held = selected_member.rows[row_index]
    guard selected_member.capture.proposal_row(member_index, row_index)
      is Some(proposal) &&
      physical_equal(proposal, held.proposal) &&
      proposal.selector().value is @values.Text(identity) else {
      return -32
    }
    let (preview, source_bytes) = match
      prepare_original_mock_effect_file_preview_row(
        drive, targets, identity, held,
      ) {
      Ok(value) => value
      Err(code) => return code
    }
    if !transfer_original_mock_effect_preview_document(
        drive, held, preview, source_bytes,
      ) {
      return -4
    }
    guard release_original_mock_effect_target_document(drive, targets) else {
      return -9
    }
    guard held.body is EncodedPreview(retained) &&
      physical_equal(retained, preview) else {
      return -32
    }
    targets.preview_row += 1
    return 1
  }
  if targets.completed is Some(completed) {
    guard completed.keys.length() == targets.members.length() else {
      return -32
    }
    if targets.bound is Some(bound) {
      return if physical_equal(
          @strategy.captured_effect_preview_ledger_identity(bound),
          completed.identity,
        ) {
        0
      } else {
        -32
      }
    }
    let bound = match
      bind_original_mock_effect_completed_preview(
        drive, targets, original, completed, run, inputs, publication,
      ) {
      Ok(value) => value
      Err(code) => return code
    }
    targets.bound = Some(bound)
    return if release_original_mock_effect_target_document(drive, targets) {
      1
    } else {
      -9
    }
  }
  if targets.draft is None {
    let draft = match
      prepare_original_mock_effect_preview_draft(
        drive, targets, original, publication,
      ) {
      Ok(draft) => draft
      Err(code) => return code
    }
    targets.draft = Some(draft)
    return if release_original_mock_effect_target_document(drive, targets) {
      1
    } else {
      -9
    }
  }
  guard targets.draft is Some(draft) &&
    @publication.run_evidence_value_name(draft.authoring) == "authoring_context" else {
    return -32
  }
  if targets.authored is None {
    let authored = match
      prepare_original_mock_effect_semantic_preview(
        drive, targets, original, draft,
      ) {
      Ok(value) => value
      Err(code) => return code
    }
    // Install the funded original before releasing scratch, so cleanup can
    // still find it if the original settlement refuses.
    targets.authored = Some(authored)
    return if release_original_mock_effect_target_document(drive, targets) {
      1
    } else {
      -9
    }
  }
  if targets.dispatch_keys is None {
    guard targets.authored is Some(authored) else { return -32 }
    if !retire_original_mock_effect_preview_draft_document(drive, draft) {
      return -9
    }
    let keys = match
      prepare_original_mock_effect_preview_dispatch_keys(
        drive, targets, original, authored,
      ) {
      Ok(value) => value
      Err(code) => return code
    }
    targets.dispatch_keys = Some(keys)
    return if release_original_mock_effect_target_document(drive, targets) {
      1
    } else {
      -9
    }
  }
  let completed = match
    prepare_original_mock_effect_preview_completion(drive, targets, original) {
    Ok(value) => value
    Err(code) => return code
  }
  if !retain_original_mock_effect_preview_completion(drive, targets, completed) {
    return -4
  }
  if release_original_mock_effect_target_document(drive, targets) {
    1
  } else {
    -9
  }
}

///|
fn mock_effect_preview_document_charge(
  document : @encode.EncodedDocument,
) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: 2L,
    reference_slots: 1L,
    scalar_words: 3L,
    owned_utf16_units: @encode.document_text(document).length().to_int64(),
    owned_wire_bytes: 0L,
  })
}

///|
// The two checked documents are borrowed by the same row. Five object
// builders with fifteen field pairs, their emitter closures and options
// remain local to one traversal. Only two containers are open outside the
// embedded documents. The writer pays for the exact measured output Text.
fn mock_effect_file_preview_workspace(bytes : Int) -> Int64? {
  guard @encode.text_writer_live_key_inventory(bytes, 15, 2) is Some(writer) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: writer.record_headers + 72L,
    reference_slots: writer.reference_slots + 128L,
    scalar_words: writer.scalar_words + 54L,
    owned_utf16_units: writer.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
fn prepare_original_mock_effect_file_preview_row(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  identity : String,
  row : StoredMockEffectTargetRow,
) -> Result[(@encode.EncodedDocument, Int64), Int] {
  guard targets.workspace is None &&
    targets.document is None &&
    targets.target is None &&
    row.body is PendingPreview(before, changes, source_bytes) else {
    return Err(-32)
  }
  guard mock_effect_file_preview_workspace(0) is Some(measured) &&
    @resources.reserve_capacity(drive.ledger, 0L, measured) is Ok(workspace) else {
    return Err(-4)
  }
  targets.workspace = Some(workspace)
  let limits = @host.client_standard_effect_computation_limits()
  let emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure = writer => {
    @host.emit_client_effect_file_preview_update(
      writer,
      identity,
      before,
      changes,
      row.version,
      MOCK_EFFECT_PREVIEW_PENDING_CID,
    )
  }
  let (bytes, nodes, depth) = try {
    let writer = @encode.measuring_writer(
      limits.effects.max_admission_text_bytes,
      limits.effects.max_admission_nodes,
      limits.effects.max_admission_depth,
    )
    emit(writer)
    @encode.finish_measurement_usage(writer)
  } catch {
    _ => return Err(-31)
  }
  guard mock_effect_file_preview_workspace(bytes) is Some(peak) &&
    @resources.grow_capacity_reservation(drive.ledger, workspace, 0L, peak)
    is Ok(_) else {
    return Err(-4)
  }
  let preview = try {
    let writer = @encode.writer(bytes, nodes, depth)
    emit(writer)
    @encode.finish_document(writer)
  } catch {
    _ => return Err(-31)
  }
  Ok((preview, source_bytes))
}

///|
// Transfer the new document from the live scratch to the row. The caller
// has returned the emitter and its borrows before replacing the two inputs.
// A failed resize keeps the original capacity token available to cleanup.
fn transfer_original_mock_effect_preview_document(
  drive : StoredMockEffectTaskDrive,
  row : StoredMockEffectTargetRow,
  preview : @encode.EncodedDocument,
  source_bytes : Int64,
) -> Bool {
  let charged = drive.charged
  guard source_bytes >= 0L &&
    source_bytes <= charged.retained_bytes &&
    source_bytes <= charged.execution_bytes &&
    mock_effect_preview_document_charge(preview) is Some(output) &&
    @execution.execution_capacity(
      charged.retained_bytes - source_bytes,
      charged.execution_bytes - source_bytes,
    )
    is Some(without_source) &&
    @execution.execution_capacity(output, output) is Some(output_capacity) &&
    @execution.add_execution_capacity(without_source, output_capacity)
    is Some(next) else {
    return false
  }
  if output > source_bytes &&
    @resources.grow_capacity_reservation(
      drive.ledger,
      drive.capacity,
      next.retained_bytes,
      next.execution_bytes,
    )
    is Err(_) {
    return false
  }
  row.body = EncodedPreview(preview)
  if output < source_bytes &&
    @resources.shrink_capacity_reservation(
      drive.ledger,
      drive.capacity,
      next.retained_bytes,
      next.execution_bytes,
    )
    is Err(_) {
    return false
  }
  drive.charged = next
  true
}
