///|
priv struct StoredSDKFileStart {
  publication_material : Int
  dispatch_material : Int?
  mut capacity : @resources.CapacityReservation?
  mut step : @local_run.LocalCapturedTaskStartStep[Ref[Int], Int]?
  mut observed : @local_run.LocalCapturedTaskStartObservation[Ref[Int], Int]?
  mut reading : SDKFileStartReadOwner?
}

///|
/// Keep the caller that owns the synchronous physical Read. A terminal
/// File preflight can only identify its own interrupted Read through this.
priv enum SDKFileStartReadOwner {
  FileStartMaterialRead
  FileStartPreflightRead(StoredFilePublicationPreflight)
}

///|
fn reserve_sdk_file_start(
  value : Instance,
  run : Int,
  rows : Int,
  kind : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard value.materials.get(rows)
    is Some(
      {
        submission: Some({ file_publication_material: Some(publication), .. }),
        ..
      }
    ) &&
    value.materials.get(publication) is Some(parent) &&
    parent.run == run &&
    !parent.closing &&
    parent.produced &&
    parent.file_publication is Some(binding) &&
    binding.rows_material == rows &&
    binding.original is Some(_) else {
    return -35
  }
  let predecessor = if kind == 7 {
    if binding.dispatch_material is Some(_) {
      return -33
    }
    None
  } else {
    if binding.claim_material is Some(_) {
      return -33
    }
    guard binding.dispatch_material is Some(dispatch) &&
      value.materials.get(dispatch) is Some(reserved) &&
      reserved.run == run &&
      reserved.kind == 7 &&
      !reserved.closing &&
      reserved.produced &&
      reserved.file_start
      is Some({ publication_material, observed: Some(_), .. }) &&
      publication_material == publication else {
      return -35
    }
    Some(dispatch)
  }
  let handle = reserve_material_record(
    value, run, kind, physical_ticket, physical_copy_bytes,
  )
  if handle > 0 {
    if kind == 7 {
      binding.dispatch_material = Some(handle)
    } else {
      binding.claim_material = Some(handle)
    }
    value.materials[handle].file_start = Some({
      publication_material: publication,
      dispatch_material: predecessor,
      capacity: None,
      step: None,
      observed: None,
      reading: None,
    })
  }
  handle
}

///|
fn sdk_file_start_capacity() -> Int64? {
  @execution.preparation_representation_cost({
    // One tagged Read owner retains its original preflight reference.
    record_headers: 49L,
    reference_slots: 135L,
    scalar_words: 66L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
fn[T] with_sdk_file_start_read(
  value : Instance,
  handle : Int,
  material : StoredMaterial,
  start : StoredSDKFileStart,
  successor : Bool,
  consume : (
    @local_run.LocalCapturedTaskPublicationBinding[Ref[Int], Int],
    @local_run.LocalCapturedTaskStartObservation[Ref[Int], Int]?,
    StoredRunConfiguration,
    @host.ClientSavedSubmissionSnapshot,
    @host.ClientJournalPhysicalRow,
    () -> Result[Unit, Int],
    (Int64, Int64) -> Result[Unit, Int],
  ) -> Result[T, Int],
  live? : (Int, StoredPhysicalStart, StoredSDKFileManaged)? = None,
  preflight? : StoredFilePublicationPreflight? = None,
  selected_file_projection? : Bool = false,
) -> Result[T, Int] {
  if selected_file_projection &&
    (!successor || live is None || preflight is None) {
    return Err(-35)
  }
  if start.reading is Some(_) {
    return Err(-33)
  }
  guard !material.closing &&
    value.runs.get(material.run) is Some(run) &&
    value.materials.get(start.publication_material) is Some(publication) &&
    !publication.closing &&
    publication.run == material.run &&
    publication.file_publication is Some(binding) &&
    binding.original is Some(confirmed) &&
    binding.step is Some(published) &&
    start.capacity is Some(capacity) &&
    sdk_file_start_capacity() is Some(base) else {
    return Err(-2)
  }
  let original = match
    sdk_whole_file_journal_material_original(
      value,
      binding.rows_material,
      run.configuration,
      managed=live.map(item => item.2),
    ) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  let prior = match start.dispatch_material {
    None => {
      guard material.kind == 7 && binding.dispatch_material == Some(handle) else {
        return Err(-35)
      }
      None
    }
    Some(dispatch) => {
      guard material.kind == 8 &&
        binding.claim_material == Some(handle) &&
        binding.dispatch_material == Some(dispatch) &&
        value.materials.get(dispatch) is Some(predecessor) &&
        !predecessor.closing &&
        predecessor.kind == 7 &&
        predecessor.run == material.run &&
        predecessor.file_start
        is Some(
          {
            publication_material,
            step: Some(step),
            observed: Some(observed),
            ..
          }
        ) &&
        publication_material == start.publication_material else {
        return Err(-35)
      }
      Some((predecessor, step, observed))
    }
  }
  let expected = if successor {
    guard start.step is Some(step) else { return Err(-33) }
    @local_run.local_captured_task_start_successor(step)
  } else if prior is Some((_, step, _)) {
    @local_run.local_captured_task_start_successor(step)
  } else {
    let (row, body) = @local_run.local_captured_task_publication_rows(published)
    { key: row.key, revision: row.revision + 1L, body, }
  }
  let held = sdk_file_start_retained(base, start)
  let read_owner : SDKFileStartReadOwner = match preflight {
    Some(original) => FileStartPreflightRead(original)
    None => FileStartMaterialRead
  }
  fn alive() -> Result[Unit, Int] {
    guard value.materials.get(handle) is Some(active) &&
      physical_equal(active, material) &&
      !material.closing &&
      start.reading is Some(active_read) &&
      physical_equal(active_read, read_owner) &&
      material.file_start is Some(current_start) &&
      physical_equal(current_start, start) &&
      value.materials.get(start.publication_material)
      is Some(current_publication) &&
      physical_equal(current_publication, publication) &&
      !publication.closing &&
      binding.original is Some(proof) &&
      physical_equal(proof, confirmed) else {
      return Err(-9)
    }
    if prior is Some((predecessor, _, evidence)) {
      guard start.dispatch_material is Some(dispatch) &&
        value.materials.get(dispatch) is Some(current) &&
        physical_equal(current, predecessor) &&
        !current.closing &&
        current.file_start is Some({ observed: Some(observed), .. }) &&
        physical_equal(observed, evidence) else {
        return Err(-9)
      }
    }
    if live is Some((physical, custody, managed)) {
      guard value.physical_starts.get(physical) is Some(active) &&
        physical_equal(active, custody) &&
        custody.run == material.run &&
        custody.sdk_step == Some(handle) &&
        custody.file_managed is Some(original_run) &&
        physical_equal(original_run, managed) &&
        !managed.closing else {
        return Err(-9)
      }
    }
    Ok(())
  }
  start.reading = Some(read_owner)
  let result = with_sdk_file_run_snapshot(
    value,
    run,
    binding.rows_material,
    original,
    expected,
    capacity,
    held,
    alive,
    (_, saved, locator, current, fund) => {
      consume(
        confirmed,
        prior.map(value => value.2),
        original.configuration,
        saved,
        locator,
        current,
        fund,
      )
    },
    managed=live.map(item => item.2),
    selected_file_projection~,
  )
  start.reading = None
  result
}

///|
fn sdk_file_start_retained(base : Int64, start : StoredSDKFileStart) -> Int64 {
  match start.step {
    None => base
    Some(step) => {
      let (_, body) = @local_run.local_captured_task_start_rows(step)
      base + body.length().to_int64()
    }
  }
}

///|
fn close_sdk_file_start(value : Instance, start : StoredSDKFileStart) -> Int {
  if start.reading is Some(_) {
    return -9
  }
  start.observed = None
  start.step = None
  match start.capacity {
    None => 0
    Some(capacity) => {
      if @resources.settle_capacity(value.root, capacity) is Err(_) {
        return -4
      }
      start.capacity = None
      0
    }
  }
}

///|
fn sdk_file_start_retire_read(
  value : Instance,
  start : StoredSDKFileStart,
) -> Int {
  if start.reading is Some(_) {
    return -9
  }
  guard start.capacity is Some(capacity) &&
    sdk_file_start_capacity() is Some(base) else {
    return -2
  }
  if @resources.shrink_capacity_reservation(
      value.root,
      capacity,
      sdk_file_start_retained(base, start),
      0L,
    )
    is Ok(_) {
    0
  } else {
    -4
  }
}

///|
fn prepare_sdk_file_start_wire(
  kind : Int,
  publication : @local_run.LocalCapturedTaskPublicationBinding[Ref[Int], Int],
  dispatch : @local_run.LocalCapturedTaskStartObservation[Ref[Int], Int]?,
  configuration : StoredRunConfiguration,
  saved : @host.ClientSavedSubmissionSnapshot,
  locator : @host.ClientJournalPhysicalRow,
  current : () -> Result[Unit, Int],
  fund : (Int64, Int64) -> Result[Unit, Int],
) -> Result[(@local_run.LocalCapturedTaskStartStep[Ref[Int], Int], Bytes), Int] {
  guard @host.client_saved_submission_run_row(saved) is Some(run) else {
    return Err(-31)
  }
  guard sdk_journal_writer_capacity(4096, 32, 2) is Some(request) else {
    return Err(-4)
  }
  let request = request + 4096L
  match fund(0L, request) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let peak = Ref(request)
  let failure : Ref[Int?] = Ref(None)
  fn quote(retained : Int64, scratch : Int64) -> Bool {
    if failure.val is Some(_) {
      return false
    }
    match fund(retained, scratch) {
      Ok(_) => true
      Err(code) => {
        failure.val = Some(code)
        false
      }
    }
  }
  let step = match
    @local_run.prepare_local_captured_task_start_step(
      publication,
      run,
      @host.client_saved_submission_row(saved),
      locator,
      configuration.account,
      configuration.context_cid,
      () => {
        current().map_err(code => {
          @local_run.LocalRunPublicationBindingIssue::Current(
            @host.ClientLocalAdoptedCurrentIssue::Physical(code),
          )
        })
      },
      phase => {
        guard @host.client_run_journal_decode_construction(phase)
          is Some((retained, scratch)) else {
          if failure.val is None {
            failure.val = Some(-4)
          }
          return Err(@host.ClientJournalDecodingIssue::CustodyLost)
        }
        let work = request + retained + scratch
        if !quote(0L, work) {
          return Err(@host.ClientJournalDecodingIssue::CustodyLost)
        }
        peak.val = Int64::max(peak.val, work)
        Ok(())
      },
      (bytes, nodes, depth) => {
        guard sdk_journal_writer_capacity(bytes, nodes, depth) is Some(scratch) &&
          quote(bytes.to_int64(), peak.val + scratch) else {
          return Err(@host.ClientJournalEncodingIssue::CapacityExceeded)
        }
        Ok(())
      },
      dispatch~,
    ) {
    Ok(step) => step
    Err(issue) =>
      return Err(failure.val.unwrap_or(sdk_publication_binding_issue(issue)))
  }
  let (row, body) = @local_run.local_captured_task_start_rows(step)
  let bound = 6L * (row.key.length().to_int64() + body.length().to_int64()) +
    128L
  let limit = Int64::min(1048576L, bound).to_int()
  guard sdk_journal_writer_capacity(limit, 6, 1) is Some(scratch) &&
    quote(
      body.length().to_int64(),
      scratch + 2L * body.length().to_int64() + limit.to_int64(),
    ) else {
    return Err(failure.val.unwrap_or(-4))
  }
  sdk_start_step_wire(kind, row, body, limit).map(wire => {
    (step, @utf8.encode(wire))
  })
}

///|
fn produce_sdk_file_start(
  value : Instance,
  handle : Int,
  material : StoredMaterial,
  start : StoredSDKFileStart,
) -> Int {
  if value.closing ||
    value.runtime_closing ||
    material.closing ||
    material.output_closed {
    return -5
  }
  if material.produced {
    return observe_sdk_file_start(value, handle, start, false)
  }
  if material.invoked {
    return -33
  }
  guard sdk_file_start_capacity() is Some(base) else { return -4 }
  let capacity = match @resources.reserve_capacity(value.root, base, base) {
    Ok(token) => token
    Err(_) => return -4
  }
  start.capacity = Some(capacity)
  material.invoked = true
  let (step, wire) = match
    with_sdk_file_start_read(value, handle, material, start, false, (
      published,
      dispatch,
      configuration,
      saved,
      locator,
      current,
      fund,
    ) => {
      prepare_sdk_file_start_wire(
        material.kind,
        published,
        dispatch,
        configuration,
        saved,
        locator,
        current,
        fund,
      )
    }) {
    Ok(value) => value
    Err(code) => return code
  }
  start.step = Some(step)
  let result = status(
    @buffers.supply_buffer_output(value.pool, material.slot, wire),
  )
  if result != 0 {
    return result
  }
  let retired = sdk_file_start_retire_read(value, start)
  if retired == 0 {
    material.produced = true
  }
  retired
}

///|
fn observe_sdk_file_start(
  value : Instance,
  handle : Int,
  start : StoredSDKFileStart,
  confirm : Bool,
  live? : (Int, StoredPhysicalStart, StoredSDKFileManaged)? = None,
) -> Int {
  if start.reading is Some(_) {
    return -33
  }
  guard value.materials.get(handle) is Some(material) &&
    material.produced &&
    start.step is Some(step) else {
    return -2
  }
  let successor = confirm || start.observed is Some(_)
  let result = with_sdk_file_start_read(
    value,
    handle,
    material,
    start,
    successor,
    (_, _, configuration, saved, locator, current, _) => {
      guard @host.client_saved_submission_run_row(saved) is Some(run) else {
        return Err(-31)
      }
      let submitted = @host.client_saved_submission_row(saved)
      let read = () => {
        current().map_err(code => {
          @local_run.LocalRunPublicationBindingIssue::Current(
            @host.ClientLocalAdoptedCurrentIssue::Physical(code),
          )
        })
      }
      if successor {
        @local_run.confirm_local_captured_task_start_step(
          step,
          run,
          submitted,
          locator,
          configuration.account,
          configuration.context_cid,
          read,
        )
        .map(value => Some(value))
        .map_err(sdk_publication_binding_issue)
      } else {
        @local_run.validate_local_captured_task_start_step(
          step,
          run,
          submitted,
          locator,
          configuration.account,
          configuration.context_cid,
          read,
        )
        .map(_ => None)
        .map_err(sdk_publication_binding_issue)
      }
    },
    live~,
  )
  let retired = sdk_file_start_retire_read(value, start)
  match result {
    Err(code) => code
    Ok(_) if retired != 0 => retired
    Ok(observed) => {
      if observed is Some(_) && start.observed is None {
        start.observed = observed
      }
      0
    }
  }
}
