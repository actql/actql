///|
priv enum PortableModelSettlementStoreState {
  Encoding
  Ready
  Offered
  Observed
  Confirmed
  Uncertain
  Applied
}

///|
priv struct PortableModelSettlementStore {
  output : Int
  mut state : PortableModelSettlementStoreState
  mut index : Bytes?
}

///|
fn portable_model_settlement_holding(
  run : StoredPortableModelRun,
  sdk : StoredSDKRunConfiguration,
  proof : @infer.ModelCallSettlementOriginal,
  role : String,
) -> String? {
  @publication.model_scoped_private_holding_cid(
    run.definition,
    sdk.store_authority_cid,
    proof.scope_cid,
    proof.slot_cid,
    proof.attempt_cid,
    1,
    "settled",
    role,
  )
}

///|
// The existing index has eight fixed keys and at most eight leaf locators.
// Each encrypted envelope adds Base64 ciphertext, nonce, tag and fixed syntax.
let model_settlement_index_limit = 4096

///|
fn portable_model_settlement_sealed_dimensions(
  proof : @infer.ModelCallSettlementOriginal,
) -> (Int, Int)? {
  let mut input = 0
  let mut output = model_settlement_index_limit
  for leaf in proof.leaves {
    guard @publication.run_evidence_value_wire_usage(leaf)
      is Some((bytes, _, _)) &&
      bytes > 0 &&
      bytes <= @publication.private_evidence_plaintext_limit(1048576) else {
      return None
    }
    input += bytes + 28
    output += 257 + 4 * ((bytes + 2) / 3)
  }
  if input > 1048576 || output > 1048576 {
    None
  } else {
    Some((input, output))
  }
}

///|
pub fn portable_model_settlement_store_bound(
  nonce : Int64,
  handle : Int,
  compute : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.compute == compute &&
    portable_model_settlement_original(value, record)
    is Some((_, member_, _, _, _)) &&
    member_.settlement
    is Some(
      {
        exact_packet_bytes: Some(_),
        proof: Some(proof),
        persistence: None,
        failed: false,
        ..
      }
    ) &&
    portable_model_settlement_sealed_dimensions(proof) is Some((_, wire)) else {
    return -32
  }
  wire
}

///|
pub fn reserve_portable_model_settlement_store(
  nonce : Int64,
  handle : Int,
  compute : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  let bound = portable_model_settlement_store_bound(nonce, handle, compute)
  if bound <= 0 {
    return bound
  }
  guard selected(nonce) is Some(value) &&
    value.computes.get(compute)
    is Some({ origin: SourceFree(run_handle, _), .. }) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_settlement_original(value, record)
    is Some((_, member_, _, _, _)) &&
    member_.settlement is Some(saved) &&
    physical_copy_bytes >= 2L * bound.to_int64() else {
    return -32
  }
  let output = reserve_material_record(
    value,
    run_handle,
    15,
    physical_ticket,
    physical_copy_bytes,
    wire_limit=bound,
  )
  if output > 0 {
    saved.persistence = Some({ output, state: Encoding, index: None, })
  }
  output
}

///|
pub fn produce_portable_model_settlement_store(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_settlement_original(value, record)
    is Some((run, member_, _, _, scope)) &&
    portable_model_task_original(value, record)
    is Ok(Some((_, _, { sdk: Some(sdk), .. }))) &&
    member_.settlement
    is Some({ proof: Some(proof), persistence: Some(store), .. } as saved) &&
    store.output == material &&
    store.state is Encoding &&
    value.materials.get(material)
    is Some({ kind: 15, invoked: false, closing: false, .. } as output) &&
    member_.raw_borrow is None &&
    member_.dispatch_clock.val is None &&
    member_.capture is Some(capture) &&
    member_.dispatch is Some(admission) &&
    @host.client_model_raw_capture_matches(capture, admission, scope) &&
    @model.model_call_settlement_slot(proof.settlement) == Some(proof.slot) &&
    member_.entry_journal
    is Some({ state: Confirmed, entry_digest: Some(entry_digest), .. }) &&
    value.copies.get(input) is Some((slot, _)) &&
    !slot.input_complete &&
    portable_model_settlement_sealed_dimensions(proof)
    is Some((length, maximum)) &&
    slot.wire_length == length &&
    portable_entry_clock(value, clock_input) is Some(at) &&
    @encode.text_writer_construction_inventory(
      model_settlement_index_limit, 48, 4,
    )
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + 144L,
      reference_slots: writer.reference_slots + 224L,
      scalar_words: writer.scalar_words + 128L,
      owned_utf16_units: writer.owned_utf16_units + 4L * maximum.to_int64(),
      owned_wire_bytes: 4L * maximum.to_int64(),
    })
    is Some(scratch) else {
    return -32
  }
  member_.dispatch_clock.val = Some(at)
  defer {
    member_.dispatch_clock.val = None
  }
  // The Raw body is already authenticated. The cursor has moved past
  // that Raw entry; recheck the same registration for this settled slot.
  if @host.check_client_model_raw_capture_current(capture) is Err(_) ||
    @host.check_client_infer_dispatch_current(admission) is Err(_) {
    return -37
  }
  let retained = saved.retained + model_settlement_index_limit.to_int64()
  if @resources.grow_capacity_reservation(
      value.root,
      saved.capacity,
      retained,
      retained + scratch,
    )
    is Err(_) {
    return -4
  }
  saved.retained = retained
  output.invoked = true
  let code = with_portable_raw_input(value, member_, slot, packet => {
    guard @model.encode_model_call_settlement_journal(
        run.request,
        run.definition,
        proof.slot,
        proof.scope_cid,
        proof.slot_cid,
        proof.attempt_cid,
        sdk.store_authority_cid,
        sdk.store_authority_cid,
        entry_digest,
        proof.leaves,
        model_settlement_index_limit,
      )
      is Ok(index) else {
      return -34
    }
    let mut frame = index
    let mut offset = 0
    for leaf in proof.leaves {
      let (bytes, _, _) = @publication.run_evidence_value_wire_usage(leaf).unwrap()
      let next = offset + bytes + 28
      guard next <= packet.length() &&
        @publication.encode_private_evidence_envelope(
          packet[offset:next].to_owned(),
        )
        is Some(body) else {
        return -34
      }
      frame = frame + b"\n" + body
      offset = next
    }
    guard offset == packet.length() else { return -34 }
    let result = status(
      @buffers.supply_buffer_output(value.pool, output.slot, frame),
    )
    if result == 0 {
      store.index = Some(index)
    }
    result
  })
  if @resources.shrink_capacity_reservation(
      value.root,
      saved.capacity,
      retained,
      retained,
    )
    is Err(_) {
    return if code == 0 { -9 } else { code }
  }
  if code == 0 {
    output.produced = true
    store.state = Ready
  }
  code
}

///|
/// Admit one write and observe the exact same generation-zero index under
/// the separate authenticated readback reader. No Call is acknowledged here.
pub fn inspect_portable_model_settlement_store(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
  mode : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_settlement_original(value, record)
    is Some((_, member_, _, _, scope)) &&
    portable_model_task_original(value, record)
    is Ok(Some((_, _, configuration))) &&
    member_.settlement
    is Some({ proof: Some(proof), persistence: Some(store), .. }) &&
    store.output == material &&
    store.index is Some(index) &&
    value.materials.get(material)
    is Some({ kind: 15, produced: true, closing: false, .. }) &&
    member_.capture is Some(capture) &&
    member_.dispatch is Some(admission) &&
    @host.client_model_raw_capture_matches(capture, admission, scope) &&
    @model.model_call_settlement_slot(proof.settlement) == Some(proof.slot) &&
    member_.dispatch_clock.val is None &&
    portable_entry_clock(value, clock_input) is Some(at) else {
    return -32
  }
  member_.dispatch_clock.val = Some(at)
  defer {
    member_.dispatch_clock.val = None
  }
  // The Raw body is already authenticated. The cursor has moved past
  // that Raw entry; recheck the same registration for this settled slot.
  if @host.check_client_model_raw_capture_current(capture) is Err(_) ||
    @host.check_client_infer_dispatch_current(admission) is Err(_) {
    return -37
  }
  match store.state {
    Ready if mode == 0 => store.state = Offered
    Offered if mode == 1 => {
      guard sdk_run_journal_port(
          value,
          configuration,
          1,
          "client_model_call_settlements",
          proof.attempt_cid,
          expected_body_length=Some(index.length()),
        )
        is Ok(Some(row)) &&
        row.revision == 0L &&
        row.key == proof.attempt_cid &&
        row.body == index else {
        return -35
      }
      store.state = Observed
    }
    _ => return -32
  }
  0
}

///|
/// The Host reports the already ended exact Store inspection. Subsequent
/// Model advance consumes this passive observation under a fresh Read.
pub fn finish_portable_model_settlement_store(
  nonce : Int64,
  handle : Int,
  material : Int,
  mode : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_task_retained(value, record) is Ok(Some((_, member_, _))) &&
    member_.settlement is Some({ persistence: Some(store), .. }) &&
    store.output == material &&
    value.materials.get(material) is Some({ kind: 15, .. }) else {
    return -32
  }
  match store.state {
    Observed if mode == 1 && !record.closing => store.state = Confirmed
    Encoding | Ready | Offered | Observed if mode == 0 =>
      store.state = Uncertain
    _ => return -32
  }
  0
}
