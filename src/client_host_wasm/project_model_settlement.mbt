///|
// The Model is parked on its own call settlement. This cursor can export
// private evidence for that same slot, without advancing or acknowledging it.
priv struct PortableModelSettlement {
  capacity : @resources.CapacityReservation
  mut retained : Int64
  peak : Int64
  mut output : Int?
  mut proof : @infer.ModelCallSettlementOriginal?
  mut exporter : @model.ModelCaptureExport?
  mut wire : StringBuilder?
  mut bytes : Int
  mut exact_packet_bytes : Int?
  mut persistence : PortableModelSettlementStore?
  mut failed : Bool
}

///|
fn portable_model_settlement_original(
  value : Instance,
  record : StoredManagedTask,
) -> (
  StoredPortableModelRun,
  StoredPortableModelMember,
  @infer.Execution,
  @model.ModelPreparedCallSet,
  @publication.BoundModelInvocationScope,
)? {
  guard !record.pending &&
    !record.closing &&
    record.issue is None &&
    record.progress is Some({ settlement: Some(_), .. }) &&
    portable_model_task_original(value, record)
    is Ok(Some((run, selected_task, _))) &&
    selected_task.transport_worker is RawReady(_) &&
    !selected_task.transport_stop &&
    selected_task.entry_journal is Some({ state: Confirmed, .. }) &&
    selected_task.raw_save is Some(_) &&
    selected_task.active is Some(active) &&
    @infer.prepared_call_set(active) is Some(prepared) &&
    @model.prepared_model_scope(prepared) is Some(scope) else {
    return None
  }
  Some((run, selected_task, active, prepared, scope))
}

///|
// One bounded invocation-evidence document, the original structured answer
// and fixed outer fields. This bounds the existing cursor and its temporary
// string builder. The later output loan uses only exact canonical lengths.
fn portable_model_settlement_bundle_bound(run : StoredPortableModelRun) -> Int {
  let response = @environment.model_response_profile_limits(
      run.response_profile,
    ).response_bytes
  (16384 + 512 + 6 * response.min(1048576)).min(
    @publication.private_evidence_plaintext_limit(1048576),
  )
}

///|
fn portable_model_settlement_capacity(
  run : StoredPortableModelRun,
  bundle : Int,
) -> (Int64, Int64)? {
  let profile = @environment.model_response_profile_limits(run.response_profile)
  guard @publication.run_evidence_admission_construction_inventory(
      16384, 256, 8,
    )
    is Some(proof) &&
    @encode.hash_writer_construction_inventory(
      1024 + profile.parse_nodes + 32,
      profile.parse_depth + 16,
    )
    is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: 3L * proof.retained.record_headers + 80L,
      reference_slots: 3L * proof.retained.reference_slots + 128L,
      scalar_words: 3L * proof.retained.scalar_words + 64L,
      owned_utf16_units: 3L * proof.retained_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(retained) &&
    @execution.preparation_representation_cost({
      record_headers: proof.record_headers + writer.record_headers + 128L,
      reference_slots: proof.reference_slots + writer.reference_slots + 128L,
      scalar_words: proof.scalar_words + writer.scalar_words + 96L,
      owned_utf16_units: proof.owned_utf16_units +
      writer.owned_utf16_units +
      5L * bundle.to_int64(),
      owned_wire_bytes: proof.owned_wire_bytes + 2L * bundle.to_int64(),
    })
    is Some(scratch) &&
    @execution.checked_preparation_add_product(retained, scratch, 1L)
    is Some(peak) else {
    return None
  }
  Some((retained, peak))
}

///|
pub fn advance_portable_model_settlement(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  quantum : Int,
) -> Int {
  guard quantum > 0 &&
    selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_settlement_original(value, record)
    is Some((run, selected_task, active, prepared, scope)) &&
    selected_task.dispatch_clock.val is None &&
    selected_task.dispatch is Some(admission) &&
    portable_entry_clock(value, clock_input) is Some(at) else {
    return -32
  }
  selected_task.dispatch_clock.val = Some(at)
  defer {
    selected_task.dispatch_clock.val = None
  }
  if @host.check_client_infer_dispatch_current(admission) is Err(_) {
    return -37
  }
  let bundle = portable_model_settlement_bundle_bound(run)
  let limits = @model.model_call_settlement_export_limits(
    bundle,
    selected_task.limits.model.max_work,
  )
  let saved = match selected_task.settlement {
    Some(saved) => saved
    None => {
      guard portable_model_settlement_capacity(run, bundle)
        is Some((retained, peak)) else {
        return -4
      }
      let capacity = match
        @resources.reserve_capacity(value.root, retained, peak) {
        Ok(admitted) => admitted
        Err(_) => return -4
      }
      let held : PortableModelSettlement = {
        capacity,
        retained,
        peak,
        output: None,
        proof: None,
        exporter: None,
        wire: None,
        bytes: 0,
        exact_packet_bytes: None,
        persistence: None,
        failed: true,
      }
      selected_task.settlement = Some(held)
      guard @infer.prepare_call_settlement_original(active, prepared, scope)
        is Ok(proof) &&
        selected_task.entry_journal is Some({ attempt_cid: Some(attempt), .. }) &&
        proof.attempt_cid == attempt else {
        return -34
      }
      held.proof = Some(proof)
      guard @model.start_model_call_settlement_export(proof.settlement, limits)
        is Ok(exporter) else {
        return -34
      }
      held.exporter = Some(exporter)
      held.wire = Some(StringBuilder())
      held.failed = false
      held
    }
  }
  guard !saved.failed &&
    saved.proof is Some(proof) &&
    saved.exporter is Some(exporter) &&
    saved.wire is Some(wire) else {
    return -32
  }
  saved.failed = true
  guard @model.advance_model_capture_export(exporter, quantum)
    is Ok((complete, chunk, _)) &&
    chunk.length() <= bundle - saved.bytes else {
    return -34
  }
  wire.write_string(chunk)
  saved.bytes += chunk.length()
  if !complete {
    saved.failed = false
    return 0
  }
  prove_portable_model_settlement_capture(
    value.root,
    saved,
    proof,
    exporter,
    wire,
  )
}

///|
fn prove_portable_model_settlement_capture(
  root : @resources.Ledger,
  saved : PortableModelSettlement,
  proof : @infer.ModelCallSettlementOriginal,
  exporter : @model.ModelCaptureExport,
  wire : StringBuilder,
) -> Int {
  // The original two-pass cursor already held its own workspace. Use its
  // terminal measurements to pay for the next parser before it allocates.
  guard @model.model_capture_export_identity(exporter) is Some(cid) &&
    @model.model_capture_export_wire_usage(exporter)
    is Some((size, nodes, depth)) &&
    @publication.run_evidence_admission_construction_inventory(
      size, nodes, depth,
    )
    is Some(capture) &&
    @execution.preparation_representation_cost({
      record_headers: capture.retained.record_headers,
      reference_slots: capture.retained.reference_slots,
      scalar_words: capture.retained.scalar_words,
      owned_utf16_units: capture.retained_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(capture_retained) &&
    @execution.preparation_representation_cost({
      record_headers: capture.record_headers,
      reference_slots: capture.reference_slots,
      scalar_words: capture.scalar_words,
      owned_utf16_units: capture.owned_utf16_units + size.to_int64(),
      owned_wire_bytes: capture.owned_wire_bytes,
    })
    is Some(parse_bytes) else {
    return -34
  }
  let retained = saved.retained + capture_retained
  let peak = saved.peak.max(retained + parse_bytes + 4L * size.to_int64())
  if @resources.grow_capacity_reservation(root, saved.capacity, retained, peak)
    is Err(_) {
    return -4
  }
  let text = wire.to_string()
  guard @publication.admit_run_evidence_value(
      "model_capture_bundle", text, size, nodes, depth,
    )
    is Ok(bundle) &&
    @publication.run_evidence_value_identity(bundle) == cid &&
    @publication.run_evidence_value_json(bundle) == text &&
    @model.cleanup_model_capture_export(exporter) is Ok(true) else {
    return -34
  }
  saved.exporter = None
  saved.wire = None
  proof.leaves.push(bundle)
  guard portable_model_settlement_packet_bound(proof) is Some(bound) &&
    @resources.shrink_capacity_reservation(
      root,
      saved.capacity,
      retained,
      retained,
    )
    is Ok(_) else {
    return -9
  }
  saved.exact_packet_bytes = Some(bound)
  saved.retained = retained
  saved.failed = false
  1
}

///|
fn portable_model_settlement_packet_bound(
  proof : @infer.ModelCallSettlementOriginal,
) -> Int? {
  // Five canonical CIDs, eight LF bytes and the three positive dimensions.
  let mut bytes = 5 * 71 +
    8 +
    proof.slot.to_string().length() +
    proof.count.to_string().length() +
    proof.leaves.length().to_string().length()
  for leaf in proof.leaves {
    let role = @publication.run_evidence_value_name(leaf)
    guard @publication.run_evidence_value_wire_usage(leaf) is Some((size, _, _)) else {
      return None
    }
    // Identity, holding, and the existing domain-separated AAD.
    let identity = @publication.run_evidence_value_identity(leaf)
    guard @publication.private_evidence_aad(role, identity) is Some(aad) else {
      return None
    }
    bytes += role.length() +
      2 * 71 +
      5 +
      aad.length() +
      size.to_string().length() +
      size
  }
  if bytes > 1048576 {
    None
  } else {
    Some(bytes)
  }
}

///|
pub fn portable_model_settlement_bound(
  nonce : Int64,
  handle : Int,
  compute : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    record.compute == compute &&
    portable_model_settlement_original(value, record)
    is Some((_, selected_task, _, _, _)) &&
    selected_task.settlement
    is Some(
      { exact_packet_bytes: Some(bound), output: None, failed: false, .. }
    ) else {
    return -32
  }
  bound
}

///|
pub fn reserve_portable_model_settlement(
  nonce : Int64,
  handle : Int,
  compute : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  let bound = portable_model_settlement_bound(nonce, handle, compute)
  if bound <= 0 {
    return bound
  }
  guard selected(nonce) is Some(value) &&
    value.computes.get(compute)
    is Some({ origin: SourceFree(run_handle, _), .. }) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_settlement_original(value, record)
    is Some((_, selected_task, _, _, _)) &&
    selected_task.settlement is Some(saved) &&
    physical_copy_bytes >= 2L * bound.to_int64() else {
    return -32
  }
  let output = reserve_material_record(
    value,
    run_handle,
    14,
    physical_ticket,
    physical_copy_bytes,
    wire_limit=bound,
  )
  if output > 0 {
    saved.output = Some(output)
  }
  output
}

///|
pub fn produce_portable_model_settlement(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
  material : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    portable_model_settlement_original(value, record)
    is Some((run, selected_task, _, _, _)) &&
    portable_model_task_original(value, record)
    is Ok(Some((_, _, { sdk: Some(sdk), .. }))) &&
    selected_task.settlement
    is Some(
      { proof: Some(proof), exact_packet_bytes: Some(bound), failed: false, .. } as saved
    ) &&
    saved.output == Some(material) &&
    selected_task.dispatch_clock.val is None &&
    selected_task.dispatch is Some(admission) &&
    portable_entry_clock(value, clock_input) is Some(at) &&
    value.materials.get(material)
    is Some({ kind: 14, invoked: false, closing: false, .. } as output) else {
    return -32
  }
  selected_task.dispatch_clock.val = Some(at)
  defer {
    selected_task.dispatch_clock.val = None
  }
  if @host.check_client_infer_dispatch_current(admission) is Err(_) {
    return -37
  }
  // This output's replay copies are already funded by the physical loan.
  // The temporary builders can hold up to two simultaneous whole-frame
  // intermediates along with the next leaf's borrowed canonical text.
  let retained = saved.retained
  let peak = retained + 3L * bound.to_int64() + 2048L
  if @resources.grow_capacity_reservation(
      value.root,
      saved.capacity,
      retained,
      peak,
    )
    is Err(_) {
    return -4
  }
  output.invoked = true
  let result = emit_portable_model_settlement(
    value, run, sdk, proof, output, bound,
  )
  if @resources.shrink_capacity_reservation(
      value.root,
      saved.capacity,
      retained,
      retained,
    )
    is Err(_) {
    return if result == 0 { -9 } else { result }
  }
  if result == 0 {
    output.produced = true
  }
  result
}

///|
fn emit_portable_model_settlement(
  value : Instance,
  run : StoredPortableModelRun,
  sdk : StoredSDKRunConfiguration,
  proof : @infer.ModelCallSettlementOriginal,
  output : StoredMaterial,
  bound : Int,
) -> Int {
  let mut frame = @utf8.encode(
    "\{proof.scope_cid}\n\{proof.slot_cid}\n\{proof.attempt_cid}\n\{proof.slot}\n\{proof.count}\n\{proof.leaves.length()}\n\{sdk.adoption_cid}\n\{sdk.store_authority_cid}\n",
  )
  for leaf in proof.leaves {
    let body = @utf8.encode(@publication.run_evidence_value_json(leaf))
    let role = @publication.run_evidence_value_name(leaf)
    let cid = @publication.run_evidence_value_identity(leaf)
    guard portable_model_settlement_holding(run, sdk, proof, role)
      is Some(holding) &&
      @publication.private_evidence_aad(role, cid) is Some(aad) else {
      return -34
    }
    frame = frame +
      @utf8.encode("\{role}\n\{cid}\n\{holding}\n") +
      aad +
      @utf8.encode("\n\{body.length()}\n") +
      body
  }
  if frame.length() != bound {
    return -34
  }
  status(@buffers.supply_buffer_output(value.pool, output.slot, frame))
}

///|
fn retire_portable_model_settlement(
  root : @resources.Ledger,
  selected_task : StoredPortableModelMember,
) -> Bool {
  guard selected_task.settlement is Some(saved) else { return true }
  if saved.exporter is Some(exporter) {
    @model.cancel_model_capture_export(exporter) |> ignore
    @model.advance_model_capture_export(exporter, 1) |> ignore
    guard @model.cleanup_model_capture_export(exporter) is Ok(true) else {
      return false
    }
    saved.exporter = None
  }
  if @resources.settle_capacity(root, saved.capacity) is Err(_) {
    return false
  }
  selected_task.settlement = None
  true
}
