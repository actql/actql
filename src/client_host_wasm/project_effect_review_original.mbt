///|
priv struct StoredMockEffectReview {
  continuation_usage : (Int, Int, Int)
  invocation : @publication.PublicationContract
  checkpoint : @checkpoint.SealedCheckpoint
  mut persisted : @checkpoint.PersistedCheckpoint?
}

///|
priv struct StoredMockEffectPublicReview {
  cid : String
  wire : String
}

///|
fn reserve_mock_effect_public_review_inventory(
  returned : @publication.EffectPreviewIdentityConstructionInventory,
  scratch : @publication.EffectPreviewIdentityConstructionInventory,
) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: returned.record_headers + scratch.record_headers,
    reference_slots: returned.reference_slots + scratch.reference_slots,
    scalar_words: returned.scalar_words + scratch.scalar_words,
    owned_utf16_units: returned.owned_utf16_units + scratch.owned_utf16_units,
    owned_wire_bytes: returned.owned_wire_bytes + scratch.owned_wire_bytes,
  })
}

///|
fn construct_original_mock_effect_public_review(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  identity : @publication.EffectPreviewIdentity,
  preview : String,
) -> Int {
  let limits = @host.client_standard_effect_computation_limits().effects
  let scope = @host.client_request_authority_scope_cid(original.effect.request)
  guard scope == original.configuration.authority_scope_cid &&
    targets.workspace is None else {
    return -32
  }
  guard sdk_journal_writer_capacity(1, 64, limits.max_admission_depth)
    is Some(preflight) &&
    @resources.reserve_capacity(drive.ledger, 0L, preflight + 16384L)
    is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  guard @publication.effect_review_original_projection_input_inventory(
      identity,
      preview,
      limits.max_admission_text_bytes,
      limits.max_admission_nodes,
      limits.max_admission_depth,
    )
    is Some(input) &&
    reserve_mock_effect_public_review_inventory(input, {
      record_headers: 0L,
      reference_slots: 0L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(input_bytes) &&
    @execution.checked_preparation_add_product(
      preflight + 16384L,
      input_bytes,
      1L,
    )
    is Some(measuring) &&
    @resources.grow_capacity_reservation(drive.ledger, workspace, 0L, measuring)
    is Ok(_) else {
    return -4
  }
  let refused = Ref(false)
  let review = match
    @publication.project_effect_review_projection(
      identity,
      preview,
      scope,
      ["effect_scope_approved"],
      @host.client_local_effect_review_redaction_policy_cid(),
      65536,
      limits.max_admission_nodes,
      limits.max_admission_depth,
      preview_limits=Some(
        (
          limits.max_admission_text_bytes,
          limits.max_admission_nodes,
          limits.max_admission_depth,
        ),
      ),
      before_emission=Some(geometry => {
        if @publication.effect_review_projection_sealing_inventory(geometry)
          is Some(output) &&
          reserve_mock_effect_public_review_inventory(input, output)
          is Some(combined) &&
          @execution.checked_preparation_add_product(
            preflight + 16384L,
            combined,
            1L,
          )
          is Some(peak) &&
          @resources.grow_capacity_reservation(
            drive.ledger,
            workspace,
            0L,
            peak,
          )
          is Ok(_) {
          true
        } else {
          refused.val = true
          false
        }
      }),
    ) {
    Err(_) => return if refused.val { -4 } else { -31 }
    Ok(value) => {
      guard @publication.effect_review_projection_binding_facts(value)
        is Some((preview_cid, _, authority, claims)) &&
        preview_cid == @publication.effect_preview_semantic_identity(identity) &&
        authority == scope &&
        claims == ["effect_scope_approved"] else {
        return -32
      }
      {
        wire: @publication.run_evidence_value_json(value),
        cid: @publication.run_evidence_value_identity(value),
      }
    }
  }
  guard @execution.preparation_representation_cost({
      record_headers: 6L,
      reference_slots: 7L,
      scalar_words: 3L,
      owned_utf16_units: review.wire.length().to_int64() +
      review.cid.length().to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @resources.shrink_capacity_reservation(
      drive.ledger,
      workspace,
      0L,
      retained,
    )
    is Ok(_) &&
    fund_original_mock_effect_target_bytes(drive, retained) else {
    return -4
  }
  targets.review_projection = Some(review)
  if release_original_mock_effect_target_document(drive, targets) {
    1
  } else {
    -9
  }
}

///|
fn mock_effect_review_reference_workspace(count : Int64) -> Int64? {
  guard @encode.hash_writer_live_key_inventory(20, 2) is Some(writer) &&
    @execution.preparation_array_representation(5L, 5L * count, true)
    is Some(arrays) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + arrays.record_headers + 52L,
      reference_slots: writer.reference_slots + arrays.reference_slots + 96L,
      scalar_words: writer.scalar_words + arrays.scalar_words + 55L,
      owned_utf16_units: writer.owned_utf16_units,
      owned_wire_bytes: writer.owned_wire_bytes,
    })
    is Some(measuring) else {
    return None
  }
  Some(measuring)
}

///|
fn emit_original_mock_effect_review_reference(
  out : @encode.Writer,
  original : MockEffectJournalObservationOriginal,
  targets : StoredMockEffectTargetDrive,
  invocation : @publication.PublicationContract,
  captured : @publication.PreparedCapturedEffectRun,
) -> Result[Unit, Int] raise @encode.EncodeFailure {
  let materials = original.journal.materials
  let request = original.effect.request
  guard targets.draft is Some(draft) &&
    targets.completed is Some(completed) &&
    targets.public_manifest is Some(manifest) &&
    targets.public_receipt is Some(receipt) &&
    targets.public_results is Some(results) &&
    targets.review_projection is Some(review) &&
    @host.client_local_effect_review_unit_definition_cid(materials.allowed)
    is Ok(unit_definition_cid) &&
    manifest.definitions.length() == results.length() &&
    manifest.artifacts.length() == results.length() else {
    return Err(-32)
  }
  let derivations = Array(capacity=results.length())
  let orderings = Array(capacity=results.length())
  let retentions = Array(capacity=results.length())
  let schemas = Array(capacity=results.length())
  let codecs = Array(capacity=results.length())
  for index, result in results {
    guard result.output.definition() is Ok(definition) &&
      physical_equal(definition, manifest.definitions[index]) &&
      physical_equal(result.artifact, manifest.artifacts[index]) &&
      result.output.derivation() is Ok(derivation) &&
      result.output.ordering() is Ok(ordering) &&
      result.output.result_schema_wire() is Ok(schema) &&
      result.output.codec_contract_cid() is Ok(codec) else {
      return Err(-32)
    }
    derivations.push(derivation)
    orderings.push(ordering)
    retentions.push(result.retention)
    schemas.push(schema)
    codecs.push(codec)
  }
  let contract = @publication.prepared_captured_effect_run_contract(captured)
  @host.emit_client_local_effect_review_reference(
    out,
    @host.PythonMock,
    request,
    materials.run_definition,
    invocation,
    manifest.definitions,
    manifest.artifacts,
    derivations,
    orderings,
    retentions,
    schemas,
    codecs,
    manifest.manifest,
    receipt,
    contract,
    completed.wire,
    @publication.run_evidence_value_identity(draft.authoring),
    review.cid,
    unit_definition_cid=Some(unit_definition_cid),
    program_id=Some(
      @host.client_local_effect_review_program_id(materials.allowed),
    ),
  )
  Ok(())
}

///|
// Seal one Checkpoint from the original captured Run, the same bound Preview
// and every public Result occurrence. This step has no Store mutation.
fn seal_original_mock_effect_review(
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  publication : @host.ClientEffectDirectSourcesPublication,
  captured : @publication.PreparedCapturedEffectRun,
  at : String,
) -> Int {
  if targets.effect_review is Some(_) {
    return 0
  }
  let materials = original.journal.materials
  guard targets.workspace is None &&
    targets.review_capacity is None &&
    targets.completed is Some(completed) &&
    targets.bound is Some(bound) &&
    targets.public_manifest is Some(manifest) &&
    targets.public_results is Some(results) &&
    manifest.definitions.length() == results.length() &&
    manifest.artifacts.length() == results.length() else {
    return -32
  }
  let identity = @strategy.captured_effect_preview_ledger_identity(bound)
  if @publication.effect_preview_run_identity(identity) !=
    @publication.publication_contract_identity(materials.run_definition) {
    return -32
  }
  guard targets.review_projection is Some(review) else {
    return construct_original_mock_effect_public_review(
      drive,
      targets,
      original,
      identity,
      completed.wire,
    )
  }
  guard mock_effect_review_reference_workspace(results.length().to_int64())
    is Some(measuring) &&
    @resources.reserve_capacity(drive.ledger, 0L, measuring) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  let invocation = @host.client_effect_direct_sources_publication_invocation(
    publication,
  )
  let limits = @host.client_standard_effect_computation_limits().effects
  let (digest, bytes, nodes, depth) = try {
    let measure = @encode.hashing_writer(
      limits.max_admission_text_bytes,
      limits.max_admission_nodes,
      limits.max_admission_depth,
    )
    match
      emit_original_mock_effect_review_reference(
        measure, original, targets, invocation, captured,
      ) {
      Err(code) => return code
      Ok(_) => ()
    }
    @encode.finish_hash_metrics(measure)
  } catch {
    _ => return -31
  }
  guard @host.client_local_effect_review_checkpoint_wire_bound(
      materials.allowed,
      materials.run_definition,
      at,
    )
    is Some(checkpoint_bytes) &&
    @host.client_protocol_metadata_construction_bytes(
      checkpoint_bytes,
      32L,
      copies=2,
    )
    is Some((sealing, _)) &&
    @execution.checked_preparation_add_product(measuring, 1L, sealing)
    is Some(peak) &&
    @resources.grow_capacity_reservation(drive.ledger, workspace, 0L, peak)
    is Ok(_) else {
    return -4
  }
  let checkpoint = match
    @host.seal_client_local_effect_review_checkpoint(
      materials.allowed,
      materials.run_definition,
      @publication.effect_preview_semantic_identity(identity),
      "sha256:" + digest,
      at,
      review.cid,
    ) {
    Ok(value) => value
    Err(OriginalLifetime | ForeignSubject) => return -32
    Err(_) => return -31
  }
  guard @execution.preparation_representation_cost({
      record_headers: 33L,
      reference_slots: 45L,
      scalar_words: 36L,
      owned_utf16_units: 2L * checkpoint.wire.length().to_int64() + 71L,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @resources.retain_capacity_reservation_after_construction(
      drive.ledger,
      workspace,
      retained,
    )
    is Ok(_) else {
    return -48601
  }
  targets.effect_review = Some({
    continuation_usage: (bytes, nodes, depth),
    invocation,
    checkpoint,
    persisted: None,
  })
  targets.review_capacity = Some(workspace)
  targets.workspace = None
  targets.workspace_bytes = 0L
  0
}

///|
fn produce_original_mock_effect_continuation(
  value : Instance,
  record : StoredOriginalMetadata,
  start : Int,
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  original : MockEffectJournalObservationOriginal,
  captured : @publication.PreparedCapturedEffectRun,
  review : StoredMockEffectReview,
  offset : Int,
  size : Int,
) -> Int {
  guard targets.public_results is Some(results) else { return -32 }
  let (bytes, nodes, depth) = review.continuation_usage
  guard mock_effect_review_reference_workspace(results.length().to_int64())
    is Some(vectors) &&
    sdk_journal_writer_capacity(bytes, nodes, depth) is Some(writing) &&
    @execution.checked_preparation_add_product(vectors, 1L, writing)
    is Some(controls) &&
    @execution.checked_preparation_add_product(controls, 1L, bytes.to_int64())
    is Some(peak) &&
    @resources.reserve_capacity(drive.ledger, 0L, peak) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  let wire = try {
    let writer = @encode.writer(bytes, nodes, depth)
    match
      emit_original_mock_effect_review_reference(
        writer,
        original,
        targets,
        review.invocation,
        captured,
      ) {
      Err(code) => return code
      Ok(_) => ()
    }
    @encode.finish(writer)
  } catch {
    _ => return -31
  }
  guard @sha.text_hex(wire) is Ok(hash) &&
    review.checkpoint.checkpoint.continuation_state_cid == "sha256:" + hash else {
    return -32
  }
  guard @scalar.copy_utf8_byte_range(wire, offset, size) is Some(body) else {
    return -31
  }
  let result = match mock_effect_claimed_current(value, start) {
    Err(code) => code
    Ok(_) =>
      status(@buffers.supply_buffer_output(value.pool, record.slot, body))
  }
  let returned = release_original_mock_effect_target_document(drive, targets)
  if result != 0 {
    result
  } else if returned {
    0
  } else {
    -9
  }
}

///|
const MOCK_EFFECT_REVIEW_EXTENT_KIND : Int = 22

///|
const MOCK_EFFECT_REVIEW_READ_KIND : Int = 17

///|
const MOCK_EFFECT_REVIEW_READ_MAX : Int = 1048576

///|
// The transfer is scoped to the same physical start. It conveys private
// body bytes to the existing Host-owned Store operation; only a later
// authenticated Store Read can confirm the original Checkpoint.
fn produce_original_mock_effect_review_part(
  value : Instance,
  record : StoredOriginalMetadata,
  borrow : @buffers.BufferBorrow,
) -> Int {
  guard @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(packet) &&
    (
      packet.length() == 8 ||
      (packet.length() == 16 && record.kind == MOCK_EFFECT_REVIEW_READ_KIND)
    ) else {
    return -31
  }
  let start = mock_effect_descriptor_field(packet, 0)
  let part = mock_effect_descriptor_field(packet, 4)
  guard part >= 0 &&
    part <= 6 &&
    value.physical_starts.get(start) is Some(custody) &&
    custody.mock_effect_compute is Some({ task_drive: Some(drive), .. }) &&
    !drive.stepping &&
    !drive.failed &&
    drive.targets is Some(targets) &&
    targets.workspace is None &&
    targets.completed is Some(preview) &&
    targets.prepared_capture is Some(CompletedEffectCapture(captured)) &&
    targets.effect_review is Some(review) &&
    targets.review_projection is Some(projection) else {
    return -32
  }
  if mock_effect_review_child_active(value, start) {
    return -9
  }
  record.project = Some(MockEffectReviewRead(start))
  let original = match mock_effect_claimed_current(value, start) {
    Err(code) => return code
    Ok((original, _)) => original
  }
  if part == 4 || part == 5 {
    if record.kind == MOCK_EFFECT_REVIEW_EXTENT_KIND || packet.length() != 8 {
      return -31
    }
    return produce_original_mock_effect_review_coordinates(
      value, record, start, part, original, drive, targets, captured, preview, review,
    )
  }
  let chunk = packet.length() == 16
  let offset = if chunk { mock_effect_descriptor_field(packet, 8) } else { 0 }
  let requested = if chunk {
    mock_effect_descriptor_field(packet, 12)
  } else {
    0
  }
  if chunk &&
    (
      offset < 0 ||
      requested <= 0 ||
      requested > 8192 ||
      offset > MOCK_EFFECT_REVIEW_READ_MAX - requested
    ) {
    return -31
  }
  if part == 2 {
    if record.kind == MOCK_EFFECT_REVIEW_EXTENT_KIND {
      return supply_original_mock_effect_review_extent(
        value,
        record,
        review.continuation_usage.0,
      )
    }
    let bytes = review.continuation_usage.0
    let size = if chunk { requested } else { bytes }
    if size > bytes || offset > bytes - size {
      return -31
    }
    return produce_original_mock_effect_continuation(
      value, record, start, drive, targets, original, captured, review, offset, size,
    )
  }
  let wire = match part {
    0 =>
      @publication.publication_contract_json(
        @publication.prepared_captured_effect_run_contract(captured),
      )
    1 => preview.wire
    3 => review.checkpoint.wire
    6 => projection.wire
    _ => return -31
  }
  guard @scalar.admit_utf8_length(wire, MOCK_EFFECT_REVIEW_READ_MAX)
    is Ok(bytes) &&
    bytes > 0 else {
    return -4
  }
  if record.kind == MOCK_EFFECT_REVIEW_EXTENT_KIND {
    return supply_original_mock_effect_review_extent(value, record, bytes)
  }
  let size = if chunk { requested } else { bytes }
  guard size <= bytes &&
    offset <= bytes - size &&
    @scalar.copy_utf8_byte_range(wire, offset, size) is Some(body) else {
    return -31
  }
  match mock_effect_claimed_current(value, start) {
    Err(code) => return code
    Ok(_) => ()
  }
  status(@buffers.supply_buffer_output(value.pool, record.slot, body))
}

///|
fn supply_original_mock_effect_review_extent(
  value : Instance,
  record : StoredOriginalMetadata,
  bytes : Int,
) -> Int {
  status(
    @buffers.supply_buffer_output(
      value.pool,
      record.slot,
      Bytes::from_array([
        (bytes & 255).to_byte(),
        ((bytes >> 8) & 255).to_byte(),
        ((bytes >> 16) & 255).to_byte(),
        ((bytes >> 24) & 255).to_byte(),
      ]),
    ),
  )
}

///|
fn produce_original_mock_effect_review_coordinates(
  value : Instance,
  record : StoredOriginalMetadata,
  start : Int,
  part : Int,
  original : MockEffectJournalObservationOriginal,
  drive : StoredMockEffectTaskDrive,
  targets : StoredMockEffectTargetDrive,
  captured : @publication.PreparedCapturedEffectRun,
  preview : StoredMockEffectCompletedPreview,
  review : StoredMockEffectReview,
) -> Int {
  let configuration = original.configuration
  guard configuration.sdk is Some(sdk) &&
    configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) &&
    current.generation is Some((device, inode)) else {
    return -32
  }
  let definition = original.journal.materials.run_definition
  let preview_cid = @publication.effect_preview_semantic_identity(
    preview.identity,
  )
  let checkpoint = review.checkpoint
  guard @publication.effect_preview_run_identity(preview.identity) ==
    @publication.publication_contract_identity(definition) &&
    checkpoint.checkpoint.required_artifact_cid == preview_cid else {
    return -32
  }
  let (bytes, nodes, depth) = @host.client_local_private_evidence_key_codec_limits()
  guard sdk_journal_writer_capacity(4096, 8, 2) is Some(binding) &&
    sdk_journal_writer_capacity(bytes, nodes, depth) is Some(preimage) &&
    @encode.hash_writer_construction_inventory(32, 2) is Some(hash) &&
    @execution.preparation_representation_cost({
      record_headers: 2L * hash.record_headers + 4L,
      reference_slots: 2L * hash.reference_slots + 2L,
      scalar_words: 2L * hash.scalar_words + 4L,
      owned_utf16_units: 2L * (hash.owned_utf16_units + 71L),
      owned_wire_bytes: 2L * hash.owned_wire_bytes + bytes.to_int64(),
    })
    is Some(hash_scratch) &&
    @resources.reserve_capacity(
      drive.ledger,
      0L,
      binding + preimage + hash_scratch,
    )
    is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  let body = if part == 4 {
    guard @host.client_publication_store_binding_body(
        configuration.run_namespace,
        sdk.store_authority_cid,
        device,
        inode,
      )
      is Ok(binding) &&
      @host.client_local_private_evidence_key_preimage(
        sdk.adoption_cid,
        binding,
        @host.EffectReviewKey,
      )
      is Ok(preimage) else {
      return -34
    }
    preimage
  } else {
    guard @publication.effect_computation_record_holding_cid(
        definition,
        sdk.store_authority_cid,
      )
      is Some(capture_key) &&
      @publication.effect_preview_private_holding_cid(
        preview.identity,
        sdk.store_authority_cid,
      )
      is Some(preview_key) else {
      return -32
    }
    let capture_cid = @publication.publication_contract_identity(
      @publication.prepared_captured_effect_run_contract(captured),
    )
    try {
      let writer = @encode.writer(1024, 32, 2)
      @encode.begin_ordered_object(writer)
      for
        (key, field) in [
          ("capture_cid", capture_cid),
          ("capture_key", capture_key),
          ("checkpoint_cid", checkpoint.checkpoint_cid),
          ("continuation_cid", checkpoint.checkpoint.continuation_state_cid),
          ("preview_cid", preview_cid),
          ("preview_key", preview_key),
          ("review_cid", checkpoint.checkpoint.review_projection_cid),
        ] {
        @encode.ordered_key(writer, key)
        @encode.string_value(writer, field)
      }
      @encode.end_object(writer)
      @utf8.encode(@encode.finish(writer))
    } catch {
      _ => return -34
    }
  }
  let code = match mock_effect_claimed_current(value, start) {
    Err(code) => code
    Ok(_) =>
      status(@buffers.supply_buffer_output(value.pool, record.slot, body))
  }
  let released = release_original_mock_effect_target_document(drive, targets)
  if code != 0 {
    code
  } else if released {
    0
  } else {
    -9
  }
}

///|
const MOCK_EFFECT_CHECKPOINT_CONFIRM_KIND : Int = 18

///|
// The trusted Host supplies authenticated original wire in the same Store
// read. Equality is only the Checkpoint-specific observation; waiting still
// needs a separate original Run CAS and successor read.
fn confirm_original_mock_effect_checkpoint(
  value : Instance,
  record : StoredOriginalMetadata,
  borrow : @buffers.BufferBorrow,
) -> Int {
  guard @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(packet) &&
    packet.length() > 4 &&
    packet.length() <= 65540 else {
    return -31
  }
  let start = mock_effect_descriptor_field(packet, 0)
  guard value.physical_starts.get(start) is Some(custody) &&
    custody.mock_effect_compute is Some({ task_drive: Some(drive), .. }) &&
    !drive.stepping &&
    !drive.failed &&
    drive.targets is Some(targets) &&
    targets.workspace is None &&
    targets.prepared_capture is Some(CompletedEffectCapture(_)) &&
    targets.effect_review is Some(review) else {
    return -32
  }
  if mock_effect_review_child_active(value, start) {
    return -9
  }
  record.project = Some(MockEffectReviewRead(start))
  match mock_effect_claimed_current(value, start) {
    Err(code) => return code
    Ok(_) => ()
  }
  let length = packet.length() - 4
  guard @scalar.admit_utf8_length(review.checkpoint.wire, 65536) is Ok(expected) &&
    expected == length &&
    @host.client_protocol_metadata_construction_bytes(length, 16L)
    is Some((scratch, _)) &&
    @resources.reserve_capacity(drive.ledger, 0L, scratch) is Ok(workspace) else {
    return -4
  }
  targets.workspace = Some(workspace)
  let stored = @utf8.decode(packet[4:]) catch { _ => return -31 }
  guard @checkpoint.confirm_checkpoint_persisted(review.checkpoint, stored)
    is Ok(observed) else {
    return -32
  }
  match mock_effect_claimed_current(value, start) {
    Err(code) => return code
    Ok(_) => ()
  }
  if review.persisted is None {
    guard fund_original_mock_effect_target_data(drive, {
      record_headers: 2L,
      reference_slots: 2L,
      scalar_words: 2L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }) else {
      return -4
    }
    review.persisted = Some(observed)
  }
  if !release_original_mock_effect_target_document(drive, targets) {
    return -9
  }
  status(@buffers.supply_buffer_output(value.pool, record.slot, b""))
}
