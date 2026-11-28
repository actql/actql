///|
priv enum PortableModelRawStoreState {
  Building
  Ready
  Offered
  Observed(Int)
  Validated(@model.ModelPhysicalCallPoll)
}

///|
/// A single scoped Raw cell. It retains the sealed output and the proof of
/// the bounded physical readback until that original Store reader has closed.
priv struct PortableModelRawStore {
  output : Int
  mut state : PortableModelRawStoreState
  mut response_capacity : @resources.CapacityReservation?
}

///|
fn portable_model_raw_store_original(
  value : Instance,
  record : StoredManagedTask,
) -> (
  StoredPortableModelMember,
  @model.ModelRawCaptureSave,
  @model.ModelPhysicalCall,
)? {
  guard !record.pending &&
    !record.closing &&
    record.issue is None &&
    portable_model_task_original(value, record)
    is Ok(Some((_, selected_task, _))) &&
    selected_task.transport_worker is ClosedAwaitingRaw(_, _) &&
    !selected_task.transport_stop &&
    selected_task.raw_save is Some(save) &&
    selected_task.transport is Some(call) &&
    selected_task.raw_plaintext_bytes > 0 else {
    return None
  }
  Some((selected_task, save, call))
}

///|
pub fn portable_model_raw_sealed_bound(
  nonce : Int64,
  handle : Int,
  compute : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.compute == compute &&
    portable_model_raw_store_original(value, record)
    is Some((selected_task, _, _)) &&
    selected_task.raw_store is None else {
    return -32
  }
  // The existing canonical envelope's fixed framing, nonce and tag are
  // bounded by 256 bytes; reserve the Base64 ciphertext separately.
  let outer = 256 + 4 * ((selected_task.raw_plaintext_bytes + 2) / 3)
  outer.min(1048576)
}

///|
pub fn reserve_portable_model_raw_sealed(
  nonce : Int64,
  handle : Int,
  compute : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  let bound = portable_model_raw_sealed_bound(nonce, handle, compute)
  if bound <= 0 {
    return bound
  }
  guard selected(nonce) is Some(value) &&
    value.computes.get(compute)
    is Some({ origin: SourceFree(run_handle, _), .. }) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_raw_store_original(value, record)
    is Some((selected_task, _, _)) &&
    physical_copy_bytes >= 2L * bound.to_int64() else {
    return -32
  }
  let output = reserve_material_record(
    value,
    run_handle,
    13,
    physical_ticket,
    physical_copy_bytes,
    wire_limit=bound,
  )
  if output > 0 {
    selected_task.raw_store = Some({
      output,
      state: Building,
      response_capacity: None,
    })
  }
  output
}

///|
fn portable_model_raw_store_capacity(plaintext : Int) -> (Int64, Int64)? {
  // The saved Chat carrier keeps one actual UTF-8-decoded body and its
  // receipt. Sealing and authentication use their own physical buffers.
  // Include the transient canonical encoding and verified plaintext decoder
  // stacks, byte projections and overlapping strings under this same debit.
  let extent = plaintext.to_int64()
  guard @execution.preparation_representation_cost({
      record_headers: 10L,
      reference_slots: 20L,
      scalar_words: 14L,
      owned_utf16_units: extent,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: 64L,
      reference_slots: 80L,
      scalar_words: 64L,
      owned_utf16_units: 8L * extent + 512L,
      owned_wire_bytes: 8L * extent + 512L,
    })
    is Some(scratch) &&
    @execution.checked_preparation_add_product(retained, scratch, 1L)
    is Some(peak) else {
    return None
  }
  Some((retained, peak))
}

///|
pub fn produce_portable_model_raw_sealed(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_raw_store_original(value, record)
    is Some((selected_task, save, _)) &&
    selected_task.raw_store
    is Some({ output, state: Building, response_capacity: None, } as store) &&
    output == material &&
    selected_task.dispatch_clock.val is None &&
    selected_task.raw_borrow is None &&
    value.materials.get(material)
    is Some({ kind: 13, invoked: false, closing: false, .. } as held) &&
    value.copies.get(input) is Some((slot, _)) &&
    slot.wire_length == selected_task.raw_plaintext_bytes + 28 &&
    portable_entry_clock(value, clock_input) is Some(at) &&
    portable_model_raw_store_capacity(selected_task.raw_plaintext_bytes)
    is Some((retained, peak)) else {
    return -32
  }
  selected_task.dispatch_clock.val = Some(at)
  defer {
    selected_task.dispatch_clock.val = None
  }
  if @model.model_raw_capture_save_current(save) is Err(_) {
    return -37
  }
  let capacity = match @resources.reserve_capacity(value.root, retained, peak) {
    Ok(admitted) => admitted
    Err(_) => return -4
  }
  store.response_capacity = Some(capacity)
  held.invoked = true
  let code = with_portable_raw_input(value, selected_task, slot, packet => {
    guard @publication.encode_private_evidence_envelope(packet)
      is Some(envelope) &&
      envelope.length() <= 1048576 else {
      return -34
    }
    status(@buffers.supply_buffer_output(value.pool, held.slot, envelope))
  })
  if code == 0 {
    held.produced = true
    store.state = Ready
  }
  code
}

///|
fn with_portable_raw_input(
  value : Instance,
  selected_task : StoredPortableModelMember,
  slot : @buffers.BufferSlot,
  consume : (Bytes) -> Int,
) -> Int {
  let borrow = match
    @buffers.borrow_filled_payload_input(value.pool, slot, () => true) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  selected_task.raw_borrow = Some(borrow)
  let code = match @buffers.filled_payload_input_bytes(value.pool, borrow) {
    Some(bytes) => consume(bytes)
    None => -33
  }
  let stopped = status(@buffers.return_buffer_borrow(value.pool, borrow))
  if stopped == 0 {
    selected_task.raw_borrow = None
  }
  if code == 0 {
    stopped
  } else {
    code
  }
}

///|
/// Open the once-only write under its original Store snapshot, then record
/// the authenticated input returned during the matching physical readback.
/// Neither observation authorizes examining a decoded response.
pub fn inspect_portable_model_raw_store(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_raw_store_original(value, record)
    is Some((selected_task, save, _)) &&
    selected_task.raw_store is Some(store) &&
    store.output == material &&
    value.materials.get(material)
    is Some({ kind: 13, produced: true, closing: false, .. }) &&
    selected_task.dispatch_clock.val is None &&
    portable_entry_clock(value, clock_input) is Some(at) else {
    return -32
  }
  selected_task.dispatch_clock.val = Some(at)
  defer {
    selected_task.dispatch_clock.val = None
  }
  if @model.model_raw_capture_save_current(save) is Err(_) {
    return -37
  }
  match store.state {
    Ready if input == 0 => store.state = Offered
    Offered if input > 0 => {
      guard value.copies.get(input) is Some((slot, _)) &&
        !slot.output_only &&
        !slot.input_complete &&
        !slot.retired &&
        slot.written == slot.wire_length &&
        slot.wire_length == selected_task.raw_plaintext_bytes else {
        return -32
      }
      store.state = Observed(input)
    }
    _ => return -32
  }
  0
}

///|
/// Admit the response only after the original physical transaction and
/// readback returned. Refusal after an attempted write remains Unknown.
pub fn finish_portable_model_raw_store(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
  mode : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_task_retained(value, record)
    is Ok(Some((_, selected_task, _))) &&
    selected_task.raw_store is Some(store) &&
    store.output == material &&
    value.materials.get(material) is Some({ kind: 13, .. }) &&
    selected_task.transport_worker is ClosedAwaitingRaw(_, _) else {
    return -32
  }
  if mode == 0 {
    selected_task.transport_worker = ClosedUnknown
    return 0
  }
  if mode == 2 {
    guard clock_input == 0 &&
      !record.closing &&
      !record.pending &&
      !selected_task.transport_stop &&
      store.state is Validated(response) else {
      return -32
    }
    // Publish only after the trusted Host's validation reader returned.
    selected_task.transport_worker = RawReady(response)
    return 0
  }
  guard mode == 1 &&
    portable_model_raw_store_original(value, record) is Some((_, save, call)) &&
    selected_task.dispatch_clock.val is None &&
    selected_task.raw_borrow is None &&
    store.state is Observed(input) &&
    value.copies.get(input) is Some((slot, _)) &&
    store.response_capacity is Some(capacity) &&
    portable_model_raw_store_capacity(selected_task.raw_plaintext_bytes)
    is Some((retained, _)) &&
    portable_entry_clock(value, clock_input) is Some(at) else {
    return -32
  }
  selected_task.dispatch_clock.val = Some(at)
  defer {
    selected_task.dispatch_clock.val = None
  }
  let admitted : Ref[@model.ModelPhysicalCallPoll?] = Ref(None)
  let code = with_portable_raw_input(value, selected_task, slot, authenticated => {
    guard @model.portable_model_saved_chat_response(
        save,
        call,
        authenticated,
        selected_task.raw_plaintext_bytes,
      )
      is Ok((_, response)) else {
      return -37
    }
    admitted.val = Some(response)
    0
  })
  if code != 0 {
    return code
  }
  guard admitted.val is Some(response) else { return -33 }
  match
    @resources.shrink_capacity_reservation(
      value.root,
      capacity,
      retained,
      retained,
    ) {
    Ok(_) => {
      store.state = Validated(response)
      0
    }
    Err(_) => -9
  }
}

///|
/// Resume only the original response after its physical successor. A live
/// worker or unidentified pause cannot make this task runnable. The existing
/// managed dispatch advances and charges its own bounded Model decoder.
pub fn advance_portable_model_response(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  quantum : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    !record.closing &&
    !record.pending &&
    record.issue is None &&
    portable_model_task_original(value, record)
    is Ok(Some((_, selected_task, _))) &&
    selected_task.transport_worker is (RawReady(_) | ClosedUnknown) &&
    selected_task.dispatch_clock.val is None &&
    portable_entry_clock(value, clock_input) is Some(at) else {
    return -32
  }
  selected_task.dispatch_clock.val = Some(at)
  defer {
    selected_task.dispatch_clock.val = None
  }
  if record.progress is Some({ settlement: Some(_), .. }) {
    guard selected_task.settlement
      is Some({ proof: Some(proof), persistence: Some(store), .. }) else {
      return 3
    }
    match store.state {
      Confirmed => {
        guard @model.acknowledge_model_call_settlement(proof.settlement) else {
          return -35
        }
        store.state = Applied
      }
      Applied => ()
      _ => return 3
    }
  }
  let code = advance_managed_task(nonce, handle, quantum)
  if code != 0 {
    return code
  }
  match record.progress {
    Some({ complete: true, .. }) => 1
    Some({ settlement: Some(_), .. }) => 3
    Some({ await_io: true, .. }) => 4
    _ => 0
  }
}
