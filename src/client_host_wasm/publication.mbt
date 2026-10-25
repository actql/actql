///|
/// Custody of existing bounded publication Owners, never durable Run state.
/// One reserved output retains the exact Source and all declared Result pins.
priv struct StoredPublication {
  source : Int
  preflight : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut results : Array[Int]
  publications : Array[@local_run.LocalResultPublication]
  snapshots : Array[@publication.CapturedResultSnapshot]
  mut snapshot : @host.PublicationOutputSnapshotPreparation?
  mut capture : @publication.CapturedRunIssuancePreparation?
  mut manifest : @local_run.LocalRunManifest?
  mut receipt : @publication.PublicationContract?
  mut captured : @publication.PublicationContract?
  mut index : Int
  mut max_work : Int64
  mut max_workspace : Int
  mut work : Int64
  mut progress : (Bool, Int)?
  mut invoked : Bool
  mut prepared : Bool
  mut pending : Bool
  mut failed : Bool
  mut closing : Bool
  mut produced : Bool
  mut output_closed : Bool
  mut commit_input : Int?
  mut commit_borrow : @buffers.BufferBorrow?
  mut commit : @publication.PublicationCommitPreparation?
  mut commit_view : @publication.PublicationCommitReadView?
  mut commit_index : @publication.PublicationContract?
  mut commit_progress : (Bool, Int)?
  mut commit_failed : Bool
  mut commit_finished : Bool
  mut observation_input : Int?
  mut observation_borrow : @buffers.BufferBorrow?
  mut observation_publisher : Int?
  mut observation : PublicationCommitObservation?
  mut observation_progress : (Bool, Int)?
  mut observation_index : @publication.PublicationContract?
  mut observation_failed : Bool
  mut observation_checked : Bool
  mut observation_closing : Bool
  mut lookup_input : Int?
  mut lookup_borrow : @buffers.BufferBorrow?
  mut lookup_publisher : Int?
  mut lookup_index : @publication.PublicationContract?
  mut lookup_identity : String?
  mut lookup_failed : Bool
  mut lookup_closing : Bool
}

///|
pub fn reserve_publication(
  nonce : Int64,
  source : Int,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.run_invocations.get(source)
    is Some(
      { closing: false, produced: true, invocation: Some(_), compute, .. }
    ) &&
    compute_publication_preflight(value, compute) is Some((preflight, prepared)) &&
    prepared.source == source &&
    !prepared.closing &&
    prepared.produced &&
    prepared.preflight is Some(_) &&
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) {
    return -3
  }
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 1048576, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  let borrow = @buffers.borrow_buffer(value.pool, input_slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.publications[handle] = {
    source,
    preflight,
    borrow,
    slot,
    results: [],
    publications: [],
    snapshots: [],
    snapshot: None,
    capture: None,
    manifest: None,
    receipt: None,
    captured: None,
    index: 0,
    max_work: 0L,
    max_workspace: 0,
    work: 0L,
    progress: None,
    invoked: false,
    prepared: false,
    pending: false,
    failed: false,
    closing: false,
    produced: false,
    output_closed: false,
    commit_input: None,
    commit_borrow: None,
    commit: None,
    commit_view: None,
    commit_index: None,
    commit_progress: None,
    commit_failed: false,
    commit_finished: false,
    observation_input: None,
    observation_borrow: None,
    observation_publisher: None,
    observation: None,
    observation_progress: None,
    observation_index: None,
    observation_failed: false,
    observation_checked: false,
    observation_closing: false,
    lookup_input: None,
    lookup_borrow: None,
    lookup_publisher: None,
    lookup_index: None,
    lookup_identity: None,
    lookup_failed: false,
    lookup_closing: false,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
fn publication_current(
  value : Instance,
  record : StoredPublication,
  account : @authorization.AdmittedAccountConfiguration,
  pending_confirmation? : Bool = false,
) -> Bool {
  guard value.run_invocations.get(record.source) is Some(source) &&
    value.computes.get(source.compute) is Some(compute) &&
    value.publication_preflights.get(record.preflight) is Some(preflight) &&
    preflight.source == record.source &&
    stored_preflight_current(value, preflight, account, pending_confirmation~) else {
    return false
  }
  if !pending_confirmation && (source.closing || compute.closing) {
    return false
  }
  for result in record.results {
    guard value.result_exports.get(result) is Some(output) &&
      output.issue is None else {
      return false
    }
    if !pending_confirmation && output.closing {
      return false
    }
  }
  for publication in record.publications {
    if @local_run.validate_local_result_publication_current(
        publication, account,
      )
      is Err(_) {
      return false
    }
  }
  true
}

///|
pub fn prepare_publication(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) &&
    value.run_invocations.get(record.source)
    is Some({ closing: false, invocation: Some(_), compute, .. }) &&
    value.computes.get(compute) is Some({ closing: false, host: Some(_), .. }) &&
    value.publication_preflights.get(record.preflight)
    is Some({ closing: false, preflight: Some(preflight), .. }) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if record.prepared {
    return if publication_current(value, record, current.account) {
      0
    } else {
      -32
    }
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["results", "max_work", "max_workspace_slots"])
    is Ok(object) &&
    @decode.required(object, "results") is Ok(results_cursor) &&
    @decode.elements(results_cursor) is Ok(results) &&
    results.length() > 0 &&
    results.length() <= value.workspace_slots &&
    required_int32(object, "max_work") is Some(max_work) &&
    max_work > 0 &&
    max_work <= 1000000 &&
    required_int32(object, "max_workspace_slots") is Some(max_workspace) &&
    max_workspace > 0 &&
    max_workspace <= 100000 else {
    return -31
  }
  if results.length() != @local_run.local_publication_preflight_count(preflight) {
    return -2
  }
  if @local_run.validate_local_publication_preflight_current(
      preflight,
      current.account,
    )
    is Err(_) {
    return -32
  }
  let handles : Array[Int] = []
  for result in results {
    guard @decode.int32(result) is Ok(result_handle) &&
      !handles.contains(result_handle) &&
      value.result_exports.get(result_handle)
      is Some(
        {
          task,
          stream: Some(_),
          ended: true,
          closing: false,
          pending: false,
          issue: None,
          ..
        }
      ) &&
      value.tasks.get(task) is Some({ compute: result_compute, .. }) &&
      result_compute == compute else {
      return -2
    }
    handles.push(result_handle)
  }
  // Retain every original parent before an Owner call can trap.
  record.results = handles
  record.max_work = max_work.to_int64()
  record.max_workspace = max_workspace
  record.pending = true
  for index, result in handles {
    let parent = value.result_exports.get(result).unwrap()
    let stream = parent.stream.unwrap()
    let issued = match parent.publication {
      Some(publication) =>
        @local_run.reuse_local_preflight_result_publication(
          preflight,
          index,
          publication,
          stream,
          current.account,
        )
      None =>
        @local_run.issue_local_preflight_result_publication(
          preflight,
          index,
          stream,
          current.account,
          1048576,
          100000,
          64,
        )
    }
    match issued {
      Ok(publication) => {
        parent.publication = Some(publication)
        record.publications.push(publication)
      }
      Err(_) => {
        record.failed = true
        record.pending = false
        return -32
      }
    }
  }
  record.pending = false
  record.prepared = true
  0
}

///|
fn advance_publication_owner(
  value : Instance,
  record : StoredPublication,
  account : @authorization.AdmittedAccountConfiguration,
  quantum : Int,
) -> Result[(Bool, Int), Unit] {
  if record.index < record.publications.length() {
    if record.snapshot is None {
      match
        @local_run.start_local_result_publication_snapshot(
          record.publications[record.index],
          account,
          1048576,
          100000,
          64,
        ) {
        Ok(snapshot) => record.snapshot = Some(snapshot)
        Err(_) => return Err(())
      }
    }
    let snapshot = record.snapshot.unwrap()
    let (done, work) = match snapshot.advance(quantum) {
      Ok(progress) => progress
      Err(_) => return Err(())
    }
    if done {
      match snapshot.finish() {
        Ok(snapshot) => record.snapshots.push(snapshot)
        Err(_) => return Err(())
      }
      record.snapshot = None
      record.index += 1
    }
    return Ok((false, work))
  }
  if record.capture is None {
    guard value.run_invocations.get(record.source)
      is Some({ invocation: Some(invocation), compute, .. }) &&
      value.computes.get(compute) is Some(compute) &&
      compute.host is Some(host) &&
      stored_compute_original_run(value, compute)
      is Some({ normalization: Some(normalization), .. }) else {
      return Err(())
    }
    let manifest = match
      @local_run.issue_local_run_manifest(
        host,
        invocation,
        record.publications,
        account,
        1048576,
        100000,
        64,
      ) {
      Ok(manifest) => manifest
      Err(_) => return Err(())
    }
    record.manifest = Some(manifest)
    match
      @local_run.start_local_run_capture(
        manifest,
        normalization,
        record.snapshots,
        account,
        1048576,
        100000,
        64,
        record.max_workspace,
      ) {
      Ok((capture, receipt)) => {
        record.receipt = Some(receipt)
        record.capture = Some(capture)
      }
      Err(_) => return Err(())
    }
  }
  record.capture.unwrap().advance(quantum).map_err(_ => ())
}

///|
pub fn advance_publication(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
  quantum : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) &&
    record.prepared &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || record.closing || record.produced {
    return -5
  }
  if quantum <= 0 {
    return -3
  }
  if record.pending || record.failed || record.progress is Some((true, _)) {
    return -33
  }
  if !publication_current(value, record, current.account) {
    return -32
  }
  let remaining = record.max_work - record.work
  if remaining <= 0L {
    record.failed = true
    return -32
  }
  let quantum = if remaining < quantum.to_int64() {
    remaining.to_int()
  } else {
    quantum
  }
  record.pending = true
  let progress = advance_publication_owner(
    value,
    record,
    current.account,
    quantum,
  )
  record.pending = false
  match progress {
    Err(_) => {
      record.failed = true
      -32
    }
    Ok((done, work)) => {
      if work < 0 || work > quantum {
        record.failed = true
        return -33
      }
      record.work += work.to_int64()
      record.progress = Some((done, work))
      if !publication_current(value, record, current.account) {
        record.failed = true
        return -32
      }
      0
    }
  }
}

///|
pub fn publication_progress(nonce : Int64, handle : Int, field : Int) -> Int64 {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) else {
    return -2L
  }
  if field == 2 {
    return record.work
  }
  guard record.progress is Some((done, work)) else { return -33L }
  match field {
    0 => if done { 1L } else { 0L }
    1 => work.to_int64()
    _ => -3L
  }
}

///|
pub fn finish_publication(
  nonce : Int64,
  handle : Int,
  current_configuration : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) &&
    value.run_configurations.get(current_configuration) is Some(current) else {
    return -2
  }
  if value.closing || record.closing {
    return -5
  }
  if !publication_current(value, record, current.account) {
    return -32
  }
  if record.produced {
    return 0
  }
  if record.pending || record.failed {
    return -33
  }
  guard record.progress is Some((true, _)) &&
    record.capture is Some(capture) &&
    record.manifest is Some(manifest) &&
    record.receipt is Some(receipt) else {
    return -7
  }
  record.pending = true
  let captured = capture.finish()
  record.pending = false
  match captured {
    Ok(captured) => record.captured = Some(captured)
    Err(_) => {
      record.failed = true
      return -32
    }
  }
  guard record.captured is Some(captured) else { return -33 }
  let writer = @encode.writer(1048576, 4, 1) catch {
    _ => {
      record.failed = true
      return -34
    }
  }
  let wire = try {
    @encode.begin_object(writer)
    for
      (name, contract) in [
        ("manifest", @local_run.local_run_manifest_contract(manifest)),
        ("receipt", receipt),
        ("captured_run", captured),
      ] {
      @encode.key(writer, name)
      @encode.string_value(
        writer,
        @publication.publication_contract_json(contract),
      )
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => {
      record.failed = true
      return -34
    }
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(wire)),
  )
  if result == 0 {
    record.produced = true
  } else {
    record.failed = true
  }
  result
}

///|
pub fn publication_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) else {
    return -2
  }
  match @buffers.buffer_length(value.pool, record.slot) {
    Some(length) => length
    None => -33
  }
}

///|
/// Release only the completed wire projection. Original Receipt, Captured Run,
/// Result pins, preflight and input borrow remain under their existing Owners.
pub fn retire_publication_output(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) else {
    return -2
  }
  if record.pending ||
    !record.produced ||
    record.manifest is None ||
    record.receipt is None ||
    record.captured is None {
    return -33
  }
  if record.output_closed {
    return 0
  }
  let code = status(@buffers.close_buffer(value.pool, record.slot))
  if code == 0 {
    record.output_closed = true
    value.copies.remove(handle) |> ignore
  }
  code
}

///|
pub fn close_publication(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.publications.get(handle) is Some(record) else {
    return -2
  }
  record.closing = true
  if value.payload_requests.values().any(child => child.publication == handle) {
    return -9
  }
  if value.commit_exports.values().any(child => child.publication == handle) {
    return -9
  }
  if value.result_bindings
    .values()
    .any(binding => binding.publication == handle) {
    return -9
  }
  if record.pending {
    return -33
  }
  if record.snapshot is Some(snapshot) {
    snapshot.cancel()
  }
  if record.capture is Some(capture) {
    capture.cancel()
  }
  if record.commit is Some(commit) {
    commit.cancel()
  }
  if record.observation_borrow is Some(borrow) {
    let result = status(@buffers.return_buffer_borrow(value.pool, borrow))
    if result != 0 {
      return result
    }
    record.observation_borrow = None
  }
  if record.lookup_borrow is Some(borrow) {
    let result = status(@buffers.return_buffer_borrow(value.pool, borrow))
    if result != 0 {
      return result
    }
    record.lookup_borrow = None
  }
  if record.commit_borrow is Some(borrow) {
    let result = status(@buffers.return_buffer_borrow(value.pool, borrow))
    if result != 0 {
      return result
    }
    record.commit_borrow = None
  }
  if !record.output_closed {
    let result = status(@buffers.close_buffer(value.pool, record.slot))
    if result != 0 {
      return result
    }
    record.output_closed = true
  }
  let result = match record.borrow {
    Ok(borrow) => status(@buffers.return_buffer_borrow(value.pool, borrow))
    Err(_) => 0
  }
  if result == 0 {
    // All child output use, the original commit input, the parent output and
    // the original Source/input borrow have acknowledged cleanup or stop.
    // A failed physical cleanup above retains this same cancelled view.
    if record.commit is Some(commit) && record.commit_view is Some(view) {
      match commit.release_view(view) {
        Err(_) => return -32
        Ok(_) => ()
      }
      record.commit_view = None
      record.commit = None
    }
    value.publications.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
