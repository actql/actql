///|
fn prepare_mock_waiting_candidate(
  original : StoredMockEffectWaiting,
  materials : @host.ClientEffectRunMaterials,
  accepted : @host.ClientEffectRunJournalAppend,
  claim : @host.ClientEffectFirstStartStep,
  before : @host.ClientJournalPhysicalRow,
  persisted : @checkpoint.PersistedCheckpoint,
  store : (String, String, UInt64, UInt64),
  at : String,
) -> Result[Bytes, Int] {
  let checkpoint = persisted.artifact
  if !@host.client_effect_run_start_current(
      materials.allowed,
      materials.run_definition,
      at,
    ) {
    return Err(-32)
  }
  let prepared = materials.prepared
  let count = @host.prepared_client_effect_result_count(prepared)
  guard count <= 128 else { return Err(-31) }
  let mut names = 0L
  for index in 0..<count {
    guard @host.prepared_client_effect_result_name(prepared, index)
      is Some(name) &&
      @encode.quoted_string_construction_extent(name) is Some((quoted, _)) else {
      return Err(-32)
    }
    names += quoted
  }
  guard @encode.quoted_string_construction_extent(checkpoint.wire)
    is Some((checkpoint_wire_bytes, _)) &&
    @encode.quoted_string_construction_extent(
      checkpoint.checkpoint.checkpoint_id,
    )
    is Some((checkpoint_id_bytes, _)) &&
    checkpoint.checkpoint.run_id() is Some(run_id) &&
    @encode.quoted_string_construction_extent(run_id) is Some((run_id_bytes, _)) else {
    return Err(-32)
  }
  // Lifecycle state contains a fixed object, the original Run and two
  // Checkpoint ID occurrences, and one availability object per result.
  // The journal wrapper quotes that canonical state once and also retains
  // the original checkpoint wire and declared names.
  let result_slots = count.to_int64()
  let state_bytes = 512L +
    run_id_bytes +
    2L * checkpoint_id_bytes +
    names +
    128L * result_slots
  let envelope = Int64::min(
    262144L,
    768L + checkpoint_wire_bytes + 2L * state_bytes + names,
  )
  guard @host.client_protocol_metadata_construction_bytes(
      envelope.to_int(),
      128L + 18L * result_slots,
      copies=3,
    )
    is Some((checkpoint_geometry, _)) &&
    sdk_journal_writer_capacity(4096, 8, 2) is Some(binding_geometry) &&
    @execution.checked_preparation_add_product(
      checkpoint_geometry, binding_geometry, 1L,
    )
    is Some(checkpoint_scratch) else {
    return Err(-4)
  }
  // The exact claimed row already holds the predecessor bytes and Run key.
  // A waiting successor replaces only its two null fields. The existing
  // Checkpoint and Store-binding encoders produce compact JSON, so quoting
  // their text at most doubles it. Retain this new owner before decoding and
  // emission, then reduce it to the resulting Run, witness and locator bytes.
  let retained_limit = MOCK_WAITING_CONTROL_BYTES +
    original.checkpoint_bytes +
    before.body.length().to_int64() +
    2L * envelope +
    2L * 4096L +
    512L +
    3L * 72L +
    2L * 4096L +
    512L +
    128L
  guard @resources.grow_capacity_reservation(
      original.ledger,
      original.capacity,
      retained_limit,
      MOCK_WAITING_CONTROL_BYTES,
    )
    is Ok(_) else {
    return Err(-4)
  }
  let decode_retained = Ref(0L)
  let working = Ref(MOCK_WAITING_CONTROL_BYTES)
  let refused = Ref(false)
  let fund = (extent : Int64) => {
    let peak = Int64::max(working.val, extent)
    if @resources.grow_capacity_reservation(
        original.ledger,
        original.capacity,
        retained_limit,
        peak,
      )
      is Err(_) {
      refused.val = true
      false
    } else {
      working.val = peak
      true
    }
  }
  let step = match
    @host.prepare_client_effect_waiting_step(
      materials,
      accepted,
      claim,
      before,
      checkpoint,
      persisted,
      store,
      at,
      true,
      before_decode=Some(stage => {
        guard @host.client_run_journal_decode_construction(
            stage,
            require_retained_identity=true,
          )
          is Some((live, scratch)) &&
          fund(MOCK_WAITING_CONTROL_BYTES + Int64::max(live, scratch)) else {
          refused.val = true
          return Err(@host.ClientJournalDecodingIssue::CustodyLost)
        }
        if stage is @host.RunJournalRetained(_, _, _, _) {
          decode_retained.val = live
        }
        Ok(())
      }),
      before_checkpoint=Some(() => {
        let admitted = fund(
          MOCK_WAITING_CONTROL_BYTES + decode_retained.val + checkpoint_scratch,
        )
        if !admitted {
          refused.val = true
        }
        admitted
      }),
      before_encode=Some((bytes, nodes, depth, checkpoint_units) => {
        guard sdk_journal_writer_capacity(bytes, nodes, depth) is Some(scratch) &&
          fund(
            MOCK_WAITING_CONTROL_BYTES +
            4L * checkpoint_units.to_int64() +
            128L * result_slots +
            binding_geometry +
            decode_retained.val +
            scratch,
          ) else {
          refused.val = true
          return Err(@host.ClientJournalEncodingIssue::CapacityExceeded)
        }
        Ok(())
      }),
    ) {
    Ok(step) => step
    Err(_) => return Err(if refused.val { -4 } else { -35 })
  }
  let retained = mock_waiting_retained(original, step)
  guard retained <= retained_limit &&
    @resources.shrink_capacity_reservation(
      original.ledger,
      original.capacity,
      retained,
      512L,
    )
    is Ok(_) else {
    return Err(-4)
  }
  original.candidate = Some(step)
  mock_waiting_candidate_header(
    step.before,
    step.body,
    step.witness,
    step.locator,
  )
}

///|
fn mock_waiting_retained(
  original : StoredMockEffectWaiting,
  step : @host.ClientEffectWaitingStep,
) -> Int64 {
  MOCK_WAITING_CONTROL_BYTES +
  original.checkpoint_bytes +
  step.body.length().to_int64() +
  step.witness.body.length().to_int64() +
  step.locator.body.length().to_int64() +
  2L * step.locator.key.length().to_int64()
}

///|
fn mock_waiting_candidate_header(
  before : @host.ClientJournalPhysicalRow,
  run : Bytes,
  witness_row : @host.ClientJournalPhysicalRow,
  locator_row : @host.ClientJournalPhysicalRow,
) -> Result[Bytes, Int] {
  // Closed framing: i64 revision, three u32 body sizes, Run CID and locator hex,
  // with each original body borrowed separately by its fixed table ordinal.
  let witness = witness_row.body
  let locator = locator_row.body
  let length = 155 + run.length() + witness.length() + locator.length()
  guard before.revision >= 0L &&
    before.revision < 9223372036854775807L &&
    witness_row.key == before.key &&
    witness_row.revision == 0L &&
    locator_row.revision == 0L &&
    @scalar.admit_utf8_length(before.key, 71) == Ok(71) &&
    @scalar.admit_utf8_length(locator_row.key, 64) == Ok(64) &&
    length <= MOCK_EFFECT_REVIEW_READ_MAX else {
    return Err(-31)
  }
  let run_key = @utf8.encode(before.key)
  let locator_key = @utf8.encode(locator_row.key)
  Ok(
    Bytes::makei(155, index => {
      if index < 8 {
        (before.revision >> (8 * index)).to_int().to_byte()
      } else if index < 12 {
        (run.length() >> (8 * (index - 8))).to_byte()
      } else if index < 16 {
        (witness.length() >> (8 * (index - 12))).to_byte()
      } else if index < 20 {
        (locator.length() >> (8 * (index - 16))).to_byte()
      } else if index < 91 {
        run_key[index - 20]
      } else {
        locator_key[index - 91]
      }
    }),
  )
}

///|
const MOCK_EFFECT_WAITING_KIND : Int = 19

///|
const MOCK_WAITING_CONTROL_BYTES : Int64 = 4096L

///|
priv struct StoredMockEffectWaiting {
  start : Int
  ledger : @resources.Ledger
  capacity : @resources.CapacityReservation
  checkpoint : @checkpoint.PersistedCheckpoint
  checkpoint_bytes : Int64
  observed_at : String
  mut construction_attempted : Bool
  mut candidate : @host.ClientEffectWaitingStep?
}

///|
fn mock_effect_review_child_active(value : Instance, start : Int) -> Bool {
  value.original_metadata
  .values()
  .any(child => {
    match child.project {
      Some(MockEffectReviewRead(owner)) => owner == start
      Some(MockEffectWaiting(held)) => held.start == start
      _ => false
    }
  })
}

///|
fn prepare_original_mock_effect_waiting(
  value : Instance,
  record : StoredOriginalMetadata,
  input : @buffers.BufferBorrow,
) -> Int {
  guard @buffers.filled_payload_input_bytes(value.pool, input) is Some(packet) &&
    packet.length() == 28 else {
    return -31
  }
  let handle = mock_effect_descriptor_field(packet, 0)
  let at = @utf8.decode(packet[4:]) catch { _ => return -31 }
  guard value.physical_starts.get(handle) is Some(custody) &&
    custody.mock_managed is Some(_) &&
    mock_effect_physical_claim(value, custody) is Some((_, claim)) &&
    claim.confirmed &&
    claim.step is Some(_) &&
    custody.mock_effect_compute is Some({ task_drive: Some(drive), .. }) &&
    !drive.failed &&
    !drive.stepping &&
    drive.targets is Some(targets) &&
    targets.workspace is None &&
    targets.effect_review is Some({ persisted: Some(persisted), .. }) &&
    !targets.waiting_started else {
    return -32
  }
  if mock_effect_review_child_active(value, handle) {
    return -9
  }
  match mock_effect_claimed_current(value, handle) {
    Err(code) => return code
    Ok(_) => ()
  }
  // Only the exact acknowledged Checkpoint leaf survives the physical
  // Source/Compute stop. Its separate bounded copy owns the same immutable
  // artifact while the capture graph returns its own reservations.
  guard @scalar.admit_utf8_length(persisted.artifact.wire, 65536) is Ok(bytes) &&
    @execution.preparation_representation_cost({
      // Original sealed wire and the already checked typed fields, their
      // strings, subject/requirement containers, time, and this parent.
      record_headers: 64L,
      reference_slots: 128L,
      scalar_words: 48L,
      owned_utf16_units: 3L * bytes.to_int64() + 256L,
      owned_wire_bytes: 0L,
    })
    is Some(checkpoint_bytes) &&
    @resources.reserve_capacity(
      value.root,
      MOCK_WAITING_CONTROL_BYTES + checkpoint_bytes,
      MOCK_WAITING_CONTROL_BYTES,
    )
    is Ok(capacity) else {
    return -4
  }
  let waiting : StoredMockEffectWaiting = {
    start: handle,
    ledger: value.root,
    capacity,
    checkpoint: persisted,
    checkpoint_bytes,
    observed_at: at,
    construction_attempted: false,
    candidate: None,
  }
  record.project = Some(MockEffectWaiting(waiting))
  targets.waiting_started = true
  1
}

///|
fn advance_original_mock_effect_waiting(
  value : Instance,
  record : StoredOriginalMetadata,
  waiting : StoredMockEffectWaiting,
) -> Int {
  if waiting.construction_attempted {
    return -33
  }
  waiting.construction_attempted = true
  let handle = waiting.start
  guard waiting.candidate is None &&
    value.physical_starts.get(handle) is Some(custody) &&
    custody.mock_managed is Some(managed) &&
    custody.mock_effect_compute
    is Some(
      { task_drive: None, source_evidence: Some({ publication: None, .. }), .. }
    ) &&
    mock_effect_physical_claim(value, custody) is Some((_, claim)) &&
    claim.confirmed &&
    claim.step is Some(step) else {
    return -32
  }
  if value.original_metadata
    .values()
    .any(child => {
      child.project is Some(MockEffectCapture(capture)) &&
      capture.start == handle
    }) {
    return -9
  }
  let original = match mock_effect_claimed_current(value, handle) {
    Ok((selected, _)) => selected
    Err(code) => return code
  }
  let configuration = original.configuration
  guard configuration.sdk is Some(sdk) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    current.generation is Some((device, inode)) else {
    return -35
  }
  let wire = match
    prepare_mock_waiting_candidate(
      waiting,
      original.journal.materials,
      original.candidate,
      step,
      mock_effect_start_next_row(step),
      waiting.checkpoint,
      (configuration.run_namespace, sdk.store_authority_cid, device, inode),
      waiting.observed_at,
    ) {
    Ok(wire) => wire
    Err(code) => return code
  }
  let observation = mock_effect_journal_observation_current(
    value,
    claim.rows,
    custody.current_configuration,
    current.physical,
    original,
    managed=Some(managed),
  )
  if observation != 0 {
    return observation
  }
  guard waiting.candidate is Some(candidate) &&
    @resources.shrink_capacity_reservation(
      waiting.ledger,
      waiting.capacity,
      mock_waiting_retained(waiting, candidate),
      0L,
    )
    is Ok(_) else {
    return -4
  }
  status(@buffers.supply_buffer_output(value.pool, record.slot, wire))
}

///|
// This accepts the exact three resulting rows under the current original
// transaction. Only the physical Host distinguishes pre-COMMIT inspection
// from a later returned confirmation Read. Neither can perform a write here.
fn confirm_original_mock_effect_waiting(
  value : Instance,
  record : StoredOriginalMetadata,
) -> Int {
  guard record.project is Some(MockEffectWaiting(waiting)) &&
    waiting.candidate is Some(candidate) &&
    value.physical_starts.get(waiting.start) is Some(custody) &&
    custody.mock_managed is Some(managed) &&
    mock_effect_physical_claim(value, custody) is Some((_, claim)) &&
    value.runs.get(custody.run) is Some(run) &&
    value.run_configurations.get(run.configuration) is Some(configuration) &&
    configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(scope) &&
    claim.confirmed &&
    !claim.reading else {
    return -32
  }
  let original = match
    mock_effect_journal_observation_original(
      value,
      claim.rows,
      run.configuration,
      managed=Some(managed),
    ) {
    Ok(original) => original
    Err(code) => return code
  }
  let retained = mock_waiting_retained(waiting, candidate)
  guard @resources.grow_capacity_reservation(
      waiting.ledger,
      waiting.capacity,
      retained,
      retained + 262144L + 16384L,
    )
    is Ok(_) else {
    return -4
  }
  claim.reading = true
  defer {
    claim.reading = false
  }
  let current = () => {
    guard claim.reading &&
      record.project is Some(MockEffectWaiting(actual)) &&
      physical_equal(waiting, actual) &&
      value.host_currents.get(handle) is Some(now) &&
      physical_equal(now, scope) else {
      return Err(-9)
    }
    let result = mock_effect_journal_observation_current(
      value,
      claim.rows,
      run.configuration,
      scope.physical,
      original,
      managed=Some(managed),
    )
    if result == 0 {
      Ok(())
    } else {
      Err(result)
    }
  }
  let observed = @host.confirm_client_effect_waiting_step(
    candidate,
    (table, key) => physical_journal_row(scope.physical, current, 1, table, key),
    -35,
  )
  let released = @resources.shrink_capacity_reservation(
    waiting.ledger,
    waiting.capacity,
    retained,
    0L,
  )
  match observed {
    Err(code) => code
    Ok(_) => if released is Ok(_) { 0 } else { -4 }
  }
}

///|
const MOCK_EFFECT_WAITING_FIELD_KIND : Int = 23

///|
fn produce_original_mock_effect_waiting_field(
  value : Instance,
  record : StoredOriginalMetadata,
  borrow : @buffers.BufferBorrow,
) -> Int {
  guard @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(packet) &&
    packet.length() == 16 else {
    return -31
  }
  let parent = mock_effect_descriptor_field(packet, 0)
  let ordinal = mock_effect_descriptor_field(packet, 4)
  let offset = mock_effect_descriptor_field(packet, 8)
  let size = mock_effect_descriptor_field(packet, 12)
  guard offset >= 0 && size > 0 && size <= 8192 else { return -31 }
  guard value.original_metadata.get(parent) is Some(owner) &&
    owner.produced &&
    !owner.output_closed &&
    owner.project is Some(MockEffectWaiting(waiting)) &&
    waiting.candidate is Some(candidate) &&
    @resources.capacity_reservation_covers(
      waiting.ledger,
      waiting.capacity,
      mock_waiting_retained(waiting, candidate),
      0L,
    ) else {
    return -32
  }
  let body = match ordinal {
    0 => candidate.body
    1 => candidate.witness.body
    2 => candidate.locator.body
    _ => return -31
  }
  guard size <= body.length() && offset <= body.length() - size else {
    return -31
  }
  record.project = Some(MockEffectWaitingField(parent))
  match mock_effect_claimed_current(value, waiting.start) {
    Err(code) => return code
    Ok(_) => ()
  }
  status(
    @buffers.supply_buffer_output(
      value.pool,
      record.slot,
      Bytes::makei(size, index => body[offset + index]),
    ),
  )
}
