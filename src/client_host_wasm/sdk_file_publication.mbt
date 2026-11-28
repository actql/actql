///|
priv struct StoredSDKFilePublication {
  rows_material : Int
  mut capacity : @resources.CapacityReservation?
  mut step : @local_run.LocalCapturedTaskPublicationStep[Ref[Int], Int]?
  mut original : @local_run.LocalCapturedTaskPublicationBinding[Ref[Int], Int]?
  mut reading : Bool
  mut dispatch_material : Int?
  mut claim_material : Int?
}

///|
fn reserve_sdk_file_publication(
  value : Instance,
  run : Int,
  configuration : Int,
  rows : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  match sdk_whole_file_journal_material_original(value, rows, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  guard value.materials.get(rows) is Some({ submission: Some(submitted), .. }) else {
    return -2
  }
  if submitted.file_publication_material is Some(_) {
    return -33
  }
  let handle = reserve_material_record(
    value, run, 9, physical_ticket, physical_copy_bytes,
  )
  if handle > 0 {
    submitted.file_publication_material = Some(handle)
    value.materials[handle].file_publication = Some({
      rows_material: rows,
      capacity: None,
      step: None,
      original: None,
      reading: false,
      dispatch_material: None,
      claim_material: None,
    })
  }
  handle
}

///|
fn sdk_file_publication_capacity() -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: 45L,
    reference_slots: 125L,
    scalar_words: 64L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
// Reuse the physical current, adopting configuration and complete File
// journal. This callback cannot outlive the same trusted Store snapshot.
fn[T] with_sdk_file_publication_read(
  value : Instance,
  handle : Int,
  binding : StoredSDKFilePublication,
  successor : Bool,
  consume : (
    WholeFileJournalOriginal,
    StoredHostCurrent,
    @host.ClientSavedSubmissionSnapshot,
    @host.ClientJournalPhysicalRow,
    () -> Result[Unit, Int],
    (Int64, Int64) -> Result[Unit, Int],
  ) -> Result[T, Int],
) -> Result[T, Int] {
  if binding.reading {
    return Err(-33)
  }
  guard value.materials.get(handle) is Some(material) &&
    !material.closing &&
    material.kind == 9 &&
    value.runs.get(material.run) is Some(run) &&
    value.materials.get(binding.rows_material)
    is Some({ submission: Some(submission), .. }) &&
    submission.file_publication_material == Some(handle) &&
    binding.capacity is Some(capacity) &&
    sdk_file_publication_capacity() is Some(base) else {
    return Err(-2)
  }
  let original = match
    sdk_whole_file_journal_material_original(
      value,
      binding.rows_material,
      run.configuration,
    ) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  let (key, initial, _, _) = @host.client_run_journal_append_rows(
    original.candidate.run,
  )
  let expected : @host.ClientJournalPhysicalRow = if successor {
    guard binding.step is Some(step) else { return Err(-33) }
    let (prior, body) = @local_run.local_captured_task_publication_rows(step)
    { key: prior.key, revision: prior.revision + 1L, body, }
  } else {
    { key, revision: 0L, body: initial, }
  }
  let held = match binding.step {
    None => base
    Some(step) => {
      let (_, body) = @local_run.local_captured_task_publication_rows(step)
      base + body.length().to_int64()
    }
  }
  binding.reading = true
  let result = with_sdk_file_run_snapshot(
    value,
    run,
    binding.rows_material,
    original,
    expected,
    capacity,
    held,
    () => {
      guard value.materials.get(handle) is Some(active) &&
        physical_equal(active, material) &&
        !material.closing &&
        material.file_publication is Some(selected) &&
        physical_equal(selected, binding) &&
        binding.reading else {
        return Err(-9)
      }
      Ok(())
    },
    (physical, saved, locator, current, fund) => {
      consume(original, physical, saved, locator, current, fund)
    },
  )
  binding.reading = false
  result
}

///|
// Shared File physical Read. Its caller owns material/phase and capacity;
// this function does not retain observed rows across that Read.
fn[T] with_sdk_file_run_snapshot(
  value : Instance,
  run : StoredRun,
  rows_material : Int,
  original : WholeFileJournalOriginal,
  expected : @host.ClientJournalPhysicalRow,
  capacity : @resources.CapacityReservation,
  held : Int64,
  alive : () -> Result[Unit, Int],
  consume : (
    StoredHostCurrent,
    @host.ClientSavedSubmissionSnapshot,
    @host.ClientJournalPhysicalRow,
    () -> Result[Unit, Int],
    (Int64, Int64) -> Result[Unit, Int],
  ) -> Result[T, Int],
  managed? : StoredSDKFileManaged? = None,
  selected_file_projection? : Bool = false,
) -> Result[T, Int] {
  let configuration = original.configuration
  guard configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(physical) &&
    physical.material is Some(adopted) &&
    physical.generation is Some(generation) else {
    return Err(-2)
  }
  fn current() -> Result[Unit, Int] {
    sdk_whole_file_journal_material_current(
      value,
      rows_material,
      run.configuration,
      original,
      () => {
        host_current_physical(value, physical).bind(_ => {
          guard value.host_currents.get(current_handle) is Some(current) &&
            physical_equal(current, physical) &&
            physical.material is Some(active_adoption) &&
            physical_equal(active_adoption, adopted) &&
            physical.generation == Some(generation) else {
            return Err(-9)
          }
          alive()
        })
      },
      managed~,
    )
  }
  let materials = original.candidate.task_materials.plan
  current().bind(_ => {
    with_sdk_run_journal_snapshot(
      value,
      @host.client_saved_submission_record(original.preparing).reference,
      materials.request,
      materials.definition,
      expected,
      original.candidate.locator.0,
      Some(original.candidate.task_materials),
      physical.physical,
      capacity,
      held,
      current,
      (saved, locator, fund) => consume(physical, saved, locator, current, fund),
      selected_file_projection~,
    )
  })
}

///|
fn close_sdk_file_publication(
  value : Instance,
  binding : StoredSDKFilePublication,
) -> Int {
  if binding.reading {
    return -9
  }
  binding.original = None
  binding.step = None
  match binding.capacity {
    None => 0
    Some(capacity) =>
      if @resources.settle_capacity(value.root, capacity) is Ok(_) {
        binding.capacity = None
        0
      } else {
        -4
      }
  }
}

///|
fn sdk_file_publication_retire_read(
  value : Instance,
  binding : StoredSDKFilePublication,
) -> Int {
  guard binding.capacity is Some(capacity) &&
    sdk_file_publication_capacity() is Some(base) &&
    binding.step is Some(step) else {
    return -2
  }
  let (_, body) = @local_run.local_captured_task_publication_rows(step)
  if @resources.shrink_capacity_reservation(
      value.root,
      capacity,
      base + body.length().to_int64(),
      0L,
    )
    is Ok(_) {
    0
  } else {
    -4
  }
}

///|
fn prepare_sdk_file_publication_wire(
  original : WholeFileJournalOriginal,
  physical : StoredHostCurrent,
  saved : @host.ClientSavedSubmissionSnapshot,
  locator : @host.ClientJournalPhysicalRow,
  current : () -> Result[Unit, Int],
  fund : (Int64, Int64) -> Result[Unit, Int],
) -> Result[
  (@local_run.LocalCapturedTaskPublicationStep[Ref[Int], Int], Bytes),
  Int,
] {
  let configuration = original.configuration
  guard configuration.sdk is Some(sdk) &&
    physical.material is Some(adopted) &&
    physical.generation is Some((device, inode)) else {
    return Err(-2)
  }
  guard sdk_journal_writer_capacity(4096, 32, 2) is Some(request_scratch) &&
    sdk_journal_writer_capacity(4096, 8, 2) is Some(binding_scratch) else {
    return Err(-4)
  }
  let request_scratch = request_scratch + 4096L
  match fund(0L, request_scratch) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let decode_peak = Ref(request_scratch)
  let primary : Ref[Int?] = Ref(None)
  fn quote(retained : Int64, scratch : Int64) -> Bool {
    if primary.val is Some(_) {
      return false
    }
    match current().bind(_ => fund(retained, scratch)).bind(_ => current()) {
      Ok(_) => true
      Err(code) => {
        primary.val = Some(code)
        false
      }
    }
  }
  let checked_current = () => {
    current().map_err(code => {
      @local_run.LocalRunPublicationBindingIssue::Current(
        @host.ClientLocalAdoptedCurrentIssue::Physical(code),
      )
    })
  }
  let step = match
    @local_run.prepare_local_captured_task_publication_binding(
      original.preparing,
      saved,
      locator,
      original.candidate,
      original.candidate.task_materials.plan,
      adopted,
      physical.store,
      configuration.account.account_id(),
      configuration.tuple,
      configuration.run_namespace,
      sdk.store_authority_cid,
      device,
      inode,
      checked_current,
      () => {
        if quote(0L, decode_peak.val + binding_scratch + 8192L) {
          Ok(())
        } else {
          Err(@local_run.CapacityExceeded)
        }
      },
      phase => {
        guard @host.client_run_journal_decode_construction(phase)
          is Some((retained, scratch)) else {
          if primary.val is None {
            primary.val = Some(-4)
          }
          return Err(@host.ClientJournalDecodingIssue::CustodyLost)
        }
        if !quote(0L, retained + scratch + request_scratch) {
          return Err(@host.ClientJournalDecodingIssue::CustodyLost)
        }
        decode_peak.val = Int64::max(
          decode_peak.val,
          retained + scratch + request_scratch,
        )
        Ok(())
      },
      (bytes, nodes, depth) => {
        guard sdk_journal_writer_capacity(bytes, nodes, depth) is Some(scratch) &&
          quote(
            bytes.to_int64(),
            decode_peak.val + binding_scratch + 8192L + scratch,
          ) else {
          return Err(@host.ClientJournalEncodingIssue::CapacityExceeded)
        }
        Ok(())
      },
    ) {
    Ok(step) => step
    Err(issue) =>
      return Err(primary.val.unwrap_or(sdk_publication_binding_issue(issue)))
  }
  let (prior, body) = @local_run.local_captured_task_publication_rows(step)
  let bound = 6L * (body.length().to_int64() + prior.key.length().to_int64()) +
    128L
  let limit = Int64::min(1048576L, bound).to_int()
  guard sdk_journal_writer_capacity(limit, 6, 1) is Some(scratch) &&
    quote(
      body.length().to_int64(),
      scratch + 2L * body.length().to_int64() + limit.to_int64(),
    ) else {
    return Err(primary.val.unwrap_or(-4))
  }
  sdk_publication_step_wire(
    "publication",
    prior.key,
    prior.revision,
    body,
    limit,
  ).map(wire => (step, @utf8.encode(wire)))
}

///|
fn produce_sdk_file_publication(
  value : Instance,
  handle : Int,
  material : StoredMaterial,
  binding : StoredSDKFilePublication,
) -> Int {
  if value.closing ||
    value.runtime_closing ||
    material.closing ||
    material.output_closed {
    return -5
  }
  if material.produced {
    return observe_sdk_file_publication(value, handle, binding, false)
  }
  if material.invoked {
    return -33
  }
  guard sdk_file_publication_capacity() is Some(base) else { return -4 }
  let capacity = match @resources.reserve_capacity(value.root, base, base) {
    Ok(value) => value
    Err(_) => return -4
  }
  binding.capacity = Some(capacity)
  material.invoked = true
  let (step, wire) = match
    with_sdk_file_publication_read(
      value, handle, binding, false, prepare_sdk_file_publication_wire,
    ) {
    Ok(value) => value
    Err(code) => return code
  }
  binding.step = Some(step)
  // Transfer the wire to the output's independent Buffer reservation before
  // settling the construction workspace. Only the successor body stays here.
  let code = status(
    @buffers.supply_buffer_output(value.pool, material.slot, wire),
  )
  if code != 0 {
    return code
  }
  let settled = sdk_file_publication_retire_read(value, binding)
  if settled == 0 {
    material.produced = true
  }
  settled
}

///|
fn observe_sdk_file_publication(
  value : Instance,
  handle : Int,
  binding : StoredSDKFilePublication,
  confirm : Bool,
) -> Int {
  if binding.reading {
    return -33
  }
  guard value.materials.get(handle) is Some(material) &&
    material.produced &&
    binding.step is Some(step) else {
    return -2
  }
  let successor = confirm || binding.original is Some(_)
  let result = with_sdk_file_publication_read(
    value,
    handle,
    binding,
    successor,
    (original, _, saved, locator, current, _) => {
      let checked_current = () => {
        current().map_err(code => {
          @local_run.LocalRunPublicationBindingIssue::Current(
            @host.ClientLocalAdoptedCurrentIssue::Physical(code),
          )
        })
      }
      if successor {
        guard @host.client_saved_submission_run_row(saved) is Some(run) else {
          return Err(-31)
        }
        @local_run.confirm_local_captured_task_publication_binding(
          step,
          run,
          @host.client_saved_submission_row(saved),
          locator,
          checked_current,
        )
        .map(value => Some(value))
        .map_err(sdk_publication_binding_issue)
      } else {
        @local_run.validate_local_captured_task_publication_binding(
          step,
          original.preparing,
          saved,
          locator,
          checked_current,
        )
        .map(_ => None)
        .map_err(sdk_publication_binding_issue)
      }
    },
  )
  let settled = sdk_file_publication_retire_read(value, binding)
  match result {
    Err(code) => code
    Ok(_) if settled != 0 => settled
    Ok(original) => {
      // A new read can reconfirm the old body, but must not replace the
      // nominal publication proof held by the original dispatch reservation.
      if original is Some(_) && binding.original is None {
        binding.original = original
      }
      0
    }
  }
}
