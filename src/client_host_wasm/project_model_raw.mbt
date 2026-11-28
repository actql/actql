///|
// The closed descriptor has ten SHA-256 identities, one bounded timestamp,
// three integers and fixed scalar fields. The five frame separators carry
// four original identities and the existing AAD before the plaintext.
let portable_model_raw_descriptor_limit = 2048

///|
let portable_model_raw_prefix_limit : Int = 4 * 71 + 512 + 5

///|
fn portable_model_raw_plaintext_limit(bytes : Int) -> Int {
  portable_model_raw_descriptor_limit + 1 + 4 * ((bytes + 2) / 3)
}

///|
fn portable_model_raw_original(
  value : Instance,
  record : StoredManagedTask,
) -> (
  StoredPortableModelMember,
  StoredRunConfiguration,
  @buffers.BufferSlot,
  Int,
)? {
  guard !record.pending &&
    !record.closing &&
    record.issue is None &&
    portable_model_task_original(value, record)
    is Ok(Some((run, selected_task, configuration))) &&
    selected_task.transport_worker is ClosedAwaitingRaw(input, http_status) &&
    !selected_task.transport_stop &&
    selected_task.raw_save is None &&
    value.copies.get(input) is Some((raw, _)) &&
    !raw.retired &&
    raw.wire_length <=
    @environment.model_response_profile_limits(run.response_profile).response_bytes &&
    raw.wire_length <= 1048576 else {
    return None
  }
  Some((selected_task, configuration, raw, http_status))
}

///|
/// Bound the same complete physical response before allocating its material.
/// The installed Store has a one MiB per-record limit, including AES envelope.
pub fn portable_model_raw_bound(
  nonce : Int64,
  handle : Int,
  compute : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.compute == compute &&
    portable_model_raw_original(value, record)
    is Some((selected_task, _, raw, _)) &&
    selected_task.raw_output is None else {
    return -32
  }
  let plaintext = portable_model_raw_plaintext_limit(raw.wire_length)
  if plaintext > @publication.private_evidence_plaintext_limit(1048576) {
    return -4
  }
  plaintext + portable_model_raw_prefix_limit
}

///|
pub fn reserve_portable_model_raw(
  nonce : Int64,
  handle : Int,
  compute : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  let bound = portable_model_raw_bound(nonce, handle, compute)
  if bound <= 0 {
    return bound
  }
  guard selected(nonce) is Some(value) &&
    value.computes.get(compute)
    is Some({ origin: SourceFree(run_handle, _), .. }) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_raw_original(value, record) is Some((selected_task, _, _, _)) &&
    physical_copy_bytes >= 2L * bound.to_int64() else {
    return -32
  }
  let output = reserve_material_record(
    value,
    run_handle,
    12,
    physical_ticket,
    physical_copy_bytes,
    wire_limit=bound,
  )
  if output > 0 {
    selected_task.raw_output = Some(output)
  }
  output
}

///|
// The issuers parse/seal a flat descriptor and a fixed holding preimage.
// Co-count those bounded writers, both canonical views, and the Base64,
// UTF-16, UTF-8 and framing overlap. Only the descriptor and bound save
// remain after the call returns. The input/output buffers are already paid.
fn portable_model_raw_workspace(plaintext : Int) -> (Int64, Int64)? {
  let descriptor = portable_model_raw_descriptor_limit
  guard @publication.run_evidence_admission_construction_inventory(
      descriptor, 40, 2,
    )
    is Some(admission) &&
    @encode.text_writer_construction_inventory(descriptor, 40, 2)
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: admission.retained.record_headers + 24L,
      reference_slots: admission.retained.reference_slots + 40L,
      scalar_words: admission.retained.scalar_words + 22L,
      owned_utf16_units: admission.retained_utf16_units + 2L * 71L,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: 3L * admission.record_headers +
      3L * writer.record_headers +
      48L,
      reference_slots: 3L * admission.reference_slots +
      3L * writer.reference_slots +
      96L,
      scalar_words: 3L * admission.scalar_words + 3L * writer.scalar_words + 64L,
      owned_utf16_units: 3L * admission.owned_utf16_units +
      3L * writer.owned_utf16_units +
      4L * plaintext.to_int64() +
      512L,
      owned_wire_bytes: 3L * admission.owned_wire_bytes +
      4L * plaintext.to_int64() +
      512L,
    })
    is Some(scratch) &&
    @execution.checked_preparation_add_product(retained, scratch, 1L)
    is Some(peak) else {
    return None
  }
  Some((retained, peak))
}

///|
/// Create the original Core descriptor and authenticated plaintext preimage.
/// No Store acknowledgment or decoder can run from this projection alone.
pub fn produce_portable_model_raw(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_raw_original(value, record)
    is Some((selected_task, configuration, raw, http_status)) &&
    selected_task.raw_output == Some(material) &&
    selected_task.raw_capacity is None &&
    selected_task.entry_journal
    is Some({ state: Confirmed, attempt_cid: Some(attempt), .. }) &&
    selected_task.transport is Some(call) &&
    selected_task.capture is Some(capture) &&
    selected_task.dispatch_clock.val is None &&
    configuration.sdk is Some(sdk) &&
    value.materials.get(material)
    is Some({ kind: 12, invoked: false, closing: false, .. } as output) &&
    portable_entry_clock(value, clock_input) is Some(at) else {
    return -32
  }
  let plaintext = portable_model_raw_plaintext_limit(raw.wire_length)
  guard portable_model_raw_workspace(plaintext) is Some((retained, peak)) else {
    return -4
  }
  selected_task.dispatch_clock.val = Some(at)
  defer {
    selected_task.dispatch_clock.val = None
  }
  if @model.entered_model_http_chat_material(call, capture) is Err(_) {
    return -37
  }
  let capacity = match @resources.reserve_capacity(value.root, retained, peak) {
    Ok(admitted) => admitted
    Err(_) => return -4
  }
  selected_task.raw_capacity = Some(capacity)
  output.invoked = true
  let code = match
    @buffers.borrow_filled_payload_input(value.pool, raw, () => true) {
    Ok(borrow) => {
      selected_task.raw_borrow = Some(borrow)
      let result = fill_portable_model_raw(
        value, selected_task, output, borrow, call, capture, sdk, attempt, http_status,
        at, plaintext,
      )
      let stopped = status(@buffers.return_buffer_borrow(value.pool, borrow))
      if stopped == 0 {
        selected_task.raw_borrow = None
      }
      if result == 0 {
        stopped
      } else {
        result
      }
    }
    Err(issue) => issue_code(issue)
  }
  match
    @resources.shrink_capacity_reservation(
      value.root,
      capacity,
      retained,
      retained,
    ) {
    Ok(_) => code
    Err(_) => if code == 0 { -9 } else { code }
  }
}

///|
fn fill_portable_model_raw(
  value : Instance,
  selected_task : StoredPortableModelMember,
  output : StoredMaterial,
  input : @buffers.BufferBorrow,
  call : @model.ModelPhysicalCall,
  capture : @host.ClientModelRawCaptureRegistration,
  sdk : StoredSDKRunConfiguration,
  attempt : String,
  http_status : Int,
  at : String,
  plaintext : Int,
) -> Int {
  guard @buffers.filled_payload_input_bytes(value.pool, input) is Some(bytes) else {
    return -33
  }
  guard @model.observe_model_raw_capture(
      call,
      capture,
      "sha256:" + @sha.hex(bytes),
      bytes.length(),
      http_status,
      true,
      at,
    )
    is Ok(save) else {
    return -37
  }
  selected_task.raw_save = Some(save)
  guard @model.model_raw_capture_save_portable_input(
      save, call, bytes, plaintext,
    )
    is Ok((preimage, aad)) else {
    return -37
  }
  let (_, holding, _, _, _) = @publication.model_raw_response_store_binding(
    @model.model_raw_capture_save_binding(save),
  )
  let prefix = @utf8.encode(
    "\{holding}\n\{attempt}\n\{sdk.adoption_cid}\n\{sdk.store_authority_cid}\n",
  )
  let result = status(
    @buffers.supply_buffer_output(
      value.pool,
      output.slot,
      prefix + aad + b"\n" + preimage,
    ),
  )
  if result == 0 {
    output.produced = true
    selected_task.raw_plaintext_bytes = preimage.length()
  }
  result
}
