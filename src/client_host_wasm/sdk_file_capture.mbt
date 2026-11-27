///|
// Borrow the exact Source selected by the adopted File Plan. The paid File
// owner and the existing publication/start claim must both still be current.
fn sdk_file_source_current(
  value : Instance,
  start : Int,
) -> Result[
  (
    StoredPhysicalStart,
    StoredSDKFileManaged,
    @local_host.ClientInstalledManagedRun,
    WholeFileJournalOriginal,
    StoredSDKWholeFileSource,
  ),
  Int,
] {
  guard value.physical_starts.get(start) is Some(custody) &&
    custody.file_managed is Some(managed) && !managed.closing &&
    sdk_file_physical_claim(value, custody) is Some((step, claim)) else {
    return Err(-2)
  }
  let ready = check_sdk_file_physical_start(value, start, custody, step, claim)
  if ready != 0 { return Err(ready) }
  guard value.physical_starts.get(start) is Some(active) && physical_equal(active, custody) &&
    value.runs.get(custody.run) is Some(run) &&
    value.preparations.get(run.preparation) is Some(preparation) &&
    preparation.project_request is Some(held) &&
    held.whole_file_source is Some(source) &&
    project_request_configuration(value, preparation.environment)
    is Some((configuration, check)) &&
    value.original_metadata.get(check.project) is Some(metadata) &&
    metadata.produced &&
    !metadata.output_closed &&
    sdk_whole_file_rows_handle(value, custody.run, run.configuration)
    is Some(rows) else {
    return Err(-9)
  }
  if source is MockFile(original) {
    guard metadata.project is Some(MockInputs(still)) &&
      physical_equal(still, original.file) &&
      still.data_body is Some(bytes) &&
      physical_equal(bytes, original.bytes) else {
      return Err(-9)
    }
  }
  let owner = match
    @local_host.observe_request_capture_transfer(managed.transfer) {
    Ok(Some(owner)) => owner
    Err(CleanupPending) => return Err(-9)
    _ => return Err(-35)
  }
  let journal = match
    sdk_whole_file_journal_material_original(
      value,
      rows,
      run.configuration,
      managed=Some(managed),
    ) {
    Ok(journal) => journal
    Err(code) => return Err(code)
  }
  guard physical_equal(configuration, journal.configuration) else {
    return Err(-2)
  }
  let permitted = match source {
    MockFile(original) =>
      @authorization.evaluate_account(configuration.account, {
        principal: configuration.tuple.principal,
        connection: original.selected.source.connection,
        resource: original.selected.row.view.resource,
        operation: "read",
      })
      is Allow(_)
    LocalCsv(original) => {
      guard metadata.project is Some(LocalInputs(_)) &&
        check.local_file is Some(checker) &&
        configuration.host_current is Some(current_handle) &&
        value.host_currents.get(current_handle) is Some(current) &&
        current.account is Some(account) else {
        return Err(-2)
      }
      original.read_current(checker, account, configuration.tuple.principal)
    }
  }
  if !permitted {
    return Err(-20)
  }
  Ok((custody, managed, owner, journal, source))
}

///|
// The existing Project Source work frame selects File only after an observed
// kind-8 claim and managed transfer. Its packet format and output stay intact.
fn advance_original_file_capture(
  value : Instance,
  handle : Int,
  record : StoredOriginalMetadata,
  start : Int,
  occurrence : Int,
  wire : Bytes,
) -> Int {
  if occurrence != 0 { return -20 }
  let (custody, managed, owner, journal, source) = match sdk_file_source_current(value, start) {
    Ok(value) => value
    Err(code) => return code
  }
  let materials = journal.candidate.task_materials.plan
  if !record.invoked {
    let child = match reserve_sdk_whole_source_capture(
        value, handle, record, start, occurrence, wire, managed.source,
        materials.compiled, materials.definition,
      ) {
      Ok(child) => child
      Err(code) => return code
    }
    let opened = match source {
      MockFile(original) =>
        open_sdk_mock_file_rows(
          value, custody, managed, owner, journal, child, original, handle,
        )
      LocalCsv(original) =>
        open_sdk_local_csv_rows(
          managed.source, owner, materials.compiled.owner, materials.request,
          child, original, handle,
        )
    }
    if opened != 0 {
      return opened
    }
  }
  guard managed.source.capture == Some(handle) &&
    record.project is Some(FileCapture(child)) &&
    child.start == start &&
    child.occurrence == occurrence else {
    return -33
  }
  advance_sdk_whole_source_rows(value, handle, record, child, managed.source, () => {
    match sdk_file_source_current(value, start) {
      Err(code) => code
      Ok((active, current, _, _, retained)) =>
        if physical_equal(active, custody) && physical_equal(current, managed) &&
          physical_equal(retained, source) { 0 } else { -9 }
    }
  })
}

///|
fn reserve_sdk_whole_source_capture(
  value : Instance,
  handle : Int,
  record : StoredOriginalMetadata,
  start : Int,
  occurrence : Int,
  wire : Bytes,
  source : StoredSDKWholeSourceTransfer,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
) -> Result[StoredMockEffectCapture, Int] {
  guard source.capture is None else { return Err(-35) }
  record.invoked = true
  let started_at = @utf8.decode(wire[8:]) catch { _ => return Err(-31) }
  if !@publication.run_publication_start_current(
      @host.client_compiled_run_admission(compiled),
      definition,
      started_at,
    ) {
    return Err(-32)
  }
  let capacity = match @resources.reserve_capacity(value.root, 4096L, 4096L) {
    Ok(capacity) => capacity
    Err(_) => return Err(-4)
  }
  let child : StoredMockEffectCapture = {
    start,
    occurrence,
    started_at,
    capacity,
    charged: 4096L,
    read: None,
    acquisition: None,
    rows: None,
    document: None,
    target: None,
    advancing: false,
    captured: None,
    identity_scan: None,
    identity: None,
  }
  record.project = Some(FileCapture(child))
  source.capture = Some(handle)
  Ok(child)
}

///|
fn advance_sdk_whole_source_rows(
  value : Instance,
  handle : Int,
  record : StoredOriginalMetadata,
  child : StoredMockEffectCapture,
  source : StoredSDKWholeSourceTransfer,
  require_current : () -> Int,
) -> Int {
  if source.csv_read is Some(csv) {
    guard csv.capture == handle else { return -35 }
    match csv.phase {
      AwaitingOffer | PreparingOffer | Offered(_) | ReadyToRead(_, _) => return 1
      Supplying(_) | ReservingExtent => return -33
      Failed(code, _) => return code
      Received => ()
    }
  }
  if record.produced {
    return if child.captured is Some(capture) &&
      child.identity is Some(identity) &&
      @row_host.row_capture_source(capture) is Ok(input) &&
      @query.captured_source_relation_identity_matches_source(identity, input) {
      0
    } else {
      -31
    }
  }
  if child.identity_scan is Some(scan) {
    let advanced = advance_mock_effect_source_identity(value, child, scan)
    if advanced != 0 { return advanced }
    let current = require_current()
    if current != 0 { return current }
    let code = status(@buffers.supply_buffer_output(value.pool, record.slot, b""))
    if code == 0 { record.produced = true }
    return code
  }
  guard child.advancing && child.rows is Some(rows) else { return -33 }
  match @row_host.advance_row_capture(rows, 256) {
    Err(issue) => {
      child.advancing = false
      return mock_effect_capture_issue(issue)
    }
    Ok((false, _)) => return 1
    Ok((true, _)) => ()
  }
  child.advancing = false
  guard @row_host.capture_row_run(rows) is Ok(captured) &&
    @row_host.row_capture_source(captured) is Ok(_) else {
    return -31
  }
  child.captured = Some(captured)
  begin_mock_effect_source_identity(value, child, captured)
}

///|
fn open_sdk_mock_file_rows(
  value : Instance,
  custody : StoredPhysicalStart,
  managed : StoredSDKFileManaged,
  owner : @local_host.ClientInstalledManagedRun,
  journal : WholeFileJournalOriginal,
  child : StoredMockEffectCapture,
  original : StoredSDKMockWholeFileSource,
  handle : Int,
) -> Int {
  let materials = journal.candidate.task_materials.plan
  let (read, _, acquisition, _) = match
    @local_host.begin_installed_managed_whole_source_read(
      owner,
      materials.compiled.owner,
      materials.request,
      original.selected.source.relation,
    ) {
    Ok(read) => read
    Err(AlreadyBound) => return -35
    Err(InsufficientCapacity | MetadataCapacityUnavailable) => return -4
    Err(_) => return -20
  }
  accept_original_project_capture_rows(
    value,
    child,
    original.selected,
    read,
    acquisition,
    original.bytes,
    _ => {
      value.physical_starts.get(child.start) is Some(active) &&
      physical_equal(active, custody) &&
      active.file_managed is Some(selected) &&
      physical_equal(selected, managed) &&
      managed.source.capture == Some(handle)
    },
  )
}

///|
fn sdk_file_source_acquisition(
  source : StoredSDKWholeFileSource,
) -> @sourceviews.SourceAcquisition {
  match source {
    MockFile(original) => original.acquisition
    LocalCsv(original) => original.source_acquisition()
  }
}
