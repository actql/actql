///|
const MOCK_EFFECT_SOURCE_CAPTURE_KIND : Int = 14

///|
priv struct StoredMockEffectCapture {
  start : Int
  occurrence : Int
  started_at : String
  capacity : @resources.CapacityReservation
  mut charged : Int64
  mut read : @local_host.ClientInstalledSourceRead?
  mut acquisition : @row_host.RowInputAcquisition?
  mut rows : @row_host.RowRun?
  mut document : @row_host.RelationDocument?
  mut target : @row_host.RelationTargetDocument?
  mut advancing : Bool
  mut captured : @row_host.RowSourceCapture?
  mut identity_scan : StoredMockSourceIdentityScan?
  mut identity : @query.CapturedSourceRelationIdentity?
}

///|
priv struct StoredMockSourceIdentityScan {
  scan : @query.CapturedSourceCellIdentityScan
  prior : Int64
}

///|
priv struct StoredMockEffectCompute {
  bound : @host.PreparedClientEffectRun
  host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]
  dag : @strategy.CapturedEffectRunDAG
  mut source_evidence : StoredMockEffectSourceEvidence?
  mut task_drive : StoredMockEffectTaskDrive?
  mut attempted : Bool
}

///|
fn authorize_mock_effect_source(
  original : MockEffectJournalObservationOriginal,
  selected : StoredMockEffectSourceSelection,
) -> Bool {
  @authorization.evaluate_account(original.configuration.account, {
    principal: original.configuration.tuple.principal,
    connection: selected.source.connection,
    resource: selected.row.view.resource,
    operation: "read",
  })
  is Allow(_)
}

///|
fn mock_effect_capture_issue(issue : @row_host.RowHostIssue) -> Int {
  match issue {
    Physical(_) => -4
    InvalidState => -23
    _ => -31
  }
}

///|
fn mock_effect_claimed_current(
  value : Instance,
  start : Int,
) -> Result[
  (MockEffectJournalObservationOriginal, @local_host.ClientInstalledManagedRun),
  Int,
] {
  guard value.physical_starts.get(start) is Some(custody) &&
    custody.mock_managed is Some(managed) &&
    mock_effect_physical_claim(value, custody) is Some((handle, claim)) else {
    return Err(-2)
  }
  let code = check_mock_effect_physical_start(value, custody, handle, claim)
  if code != 0 {
    return Err(code)
  }
  mock_effect_journal_observation_original(
    value,
    claim.rows,
    custody.current_configuration,
    managed=Some(managed),
  ).map(original => (original, managed))
}

///|
fn mock_effect_capture_current(
  value : Instance,
  start : Int,
  occurrence : Int,
) -> Result[
  (MockEffectJournalObservationOriginal, @local_host.ClientInstalledManagedRun),
  Int,
] {
  mock_effect_claimed_current(value, start).bind(pair => {
    let (original, _) = pair
    guard original.effect.sources.get(occurrence) is Some(selected) &&
      authorize_mock_effect_source(original, selected) else {
      return Err(-20)
    }
    Ok(pair)
  })
}

///|
fn fund_mock_effect_capture(
  value : Instance,
  child : StoredMockEffectCapture,
  units : @execution.PreparationRepresentationUnits?,
) -> Bool {
  guard units is Some(units) &&
    @execution.preparation_representation_cost(units) is Some(bytes) &&
    @execution.checked_preparation_add_product(child.charged, 1L, bytes)
    is Some(next) &&
    @resources.grow_capacity_reservation(value.root, child.capacity, next, next)
    is Ok(_) else {
    return false
  }
  child.charged = next
  true
}

///|
fn release_mock_effect_capture_document(
  child : StoredMockEffectCapture,
) -> Bool {
  if child.target is Some(target) {
    if !@row_host.discard_relation_target_document_original(target) {
      return false
    }
    child.target = None
  }
  if child.document is Some(document) {
    if !@row_host.discard_relation_document_original(document) {
      return false
    }
    child.document = None
  }
  true
}

///|
fn accept_original_mock_effect_capture(
  value : Instance,
  child : StoredMockEffectCapture,
  original : MockEffectJournalObservationOriginal,
  managed : @local_host.ClientInstalledManagedRun,
) -> Int {
  guard original.effect.sources.get(child.occurrence) is Some(selected) else {
    return -20
  }
  let (read, _, acquisition, _) = match
    @local_host.begin_installed_effect_managed_whole_source_read(
      managed,
      original.journal.materials.prepared,
      original.effect.request,
      selected.source.relation,
      child.occurrence,
    ) {
    Ok(read) => read
    Err(AlreadyBound) => return -35
    Err(InsufficientCapacity | MetadataCapacityUnavailable) => return -4
    Err(_) => return -20
  }
  accept_original_project_capture_rows(
    value, child, selected, read, acquisition, original.effect.data,
    _ => {
      value.physical_starts.get(child.start) is Some(custody) &&
      custody.mock_managed is Some(owner) &&
      physical_equal(owner, managed) &&
      !value.closing && !value.runtime_closing
    },
  )
}

///|
// One funded document/projection/RowRun path for the already selected
// Project source. Callers keep their own captured Plan and authorization.
fn accept_original_project_capture_rows(
  value : Instance,
  child : StoredMockEffectCapture,
  selected : StoredMockEffectSourceSelection,
  read : @local_host.ClientInstalledSourceRead,
  acquisition : @row_host.RowInputAcquisition,
  bytes : Bytes,
  original_stop : (@row_host.RowAttempt) -> Bool,
) -> Int {
  let source = selected.source
  let selection = selected.row
  child.read = Some(read)
  child.acquisition = Some(acquisition)
  let geometry = @row_host.row_input_acquisition_limits(acquisition)
  let run = match
    @local_host.start_installed_whole_source_read_rows(
      read,
      acquisition,
      "mock-project-" + child.occurrence.to_string(),
      original_stop,
      bytes.length().to_int64(),
      geometry.page.max_bytes.to_int64(),
    ) {
    Ok(run) => run
    Err(Acquisition(issue)) => return mock_effect_capture_issue(issue)
    Err(_) => return -23
  }
  child.rows = Some(run)
  match
    @row_host.begin_row_run_with_page_limits(
      run,
      geometry.page,
      geometry.max_rows,
    ) {
    Err(issue) => return mock_effect_capture_issue(issue)
    Ok(_) => ()
  }
  let charge = match @row_host.charge_row_run_page(run, bytes) {
    Err(issue) => return mock_effect_capture_issue(issue)
    Ok(charge) => charge
  }
  let resource = selection.view.resource
  let limits = mock_project_record_read_limits(
    source,
    selection,
    bytes.length(),
    @row_host.project_mock_row_page_limits(),
  )
  guard fund_mock_effect_capture(
    value,
    child,
    @row_host.relation_document_mapping_construction_inventory(limits),
  ) else {
    return -4
  }
  guard @row_host.prepare_relation_document_contract(
      source.relation,
      resource,
      selection.primary_identity,
      limits,
    )
    is Ok(contract) else {
    return -31
  }
  let typed = @row_host.relation_document_prepared_contract(contract)
  // The mapping and document must use the same Common profile. Whole-Source
  // acceptance independently checks the raw payload's actual page geometry.
  guard fund_mock_effect_capture(
      value,
      child,
      @row_host.relation_document_raw_construction_inventory(limits),
    ) &&
    fund_mock_effect_capture(
      value,
      child,
      @row_host.relation_document_projection_construction_inventory(
        {
          original: typed,
          items_path_depth: selection.items_path.length(),
          key_path_depth: Some(selection.key_path.length()),
          writable_fields: 0,
        },
        limits,
      ),
    ) else {
    return -4
  }
  guard @row_host.admit_relation_document(bytes, limits, 16777216)
    is Ok(document) else {
    return -31
  }
  child.document = Some(document)
  guard @row_host.project_relation_target_document(
      document,
      source.relation,
      resource,
      selection.items_path,
      Some(selection.key_path),
      selection.primary_identity,
      [],
      prepared_contract=Some(contract),
    )
    is Ok(target) else {
    return -31
  }
  child.target = Some(target)
  match
    @row_host.accept_charged_relation_input_document(
      run, charge, acquisition, target, 16777216,
    ) {
    Err(issue) => return mock_effect_capture_issue(issue)
    Ok(_) => ()
  }
  match @row_host.finish_row_run(run) {
    Err(issue) => return mock_effect_capture_issue(issue)
    Ok(_) => ()
  }
  if !release_mock_effect_capture_document(child) {
    return -9
  }
  match @row_host.begin_row_capture(run) {
    Err(issue) => return mock_effect_capture_issue(issue)
    Ok(_) => ()
  }
  if @resources.shrink_capacity_reservation(
      value.root,
      child.capacity,
      4096L,
      0L,
    )
    is Err(_) {
    return -4
  }
  child.charged = 4096L
  child.advancing = true
  0
}

///|
fn fund_mock_effect_source_identity(
  value : Instance,
  child : StoredMockEffectCapture,
  retained : Int64,
  required : @execution.ExecutionCapacity,
) -> Bool {
  let bytes = Int64::max(
    @execution.execution_capacity_retained_bytes(required),
    @execution.execution_capacity_execution_bytes(required),
  )
  guard @execution.checked_preparation_add_product(retained, 1L, bytes)
    is Some(next) else {
    return false
  }
  if next <= child.charged {
    return true
  }
  if @resources.grow_capacity_reservation(
      value.root,
      child.capacity,
      next,
      next,
    )
    is Err(_) {
    return false
  }
  child.charged = next
  true
}

///|
fn begin_mock_effect_source_identity(
  value : Instance,
  child : StoredMockEffectCapture,
  capture : @row_host.RowSourceCapture,
) -> Int {
  guard child.acquisition is Some(acquisition) &&
    @row_host.row_capture_source(capture) is Ok(source) else {
    return -33
  }
  let bounds = @row_host.row_input_acquisition_limits(acquisition)
  let wire = bounds.wire
  guard @query.captured_source_cell_identity_start_capacity(source)
    is Some(required) &&
    @query.captured_source_cell_identity_workspace_slots(
      source,
      bounds.retention,
      wire,
      wire,
    )
    is Some(slots) else {
    return -4
  }
  let prior = child.charged
  if !fund_mock_effect_source_identity(value, child, prior, required) {
    return -4
  }
  match
    @query.start_captured_source_cell_identity(
      source,
      bounds.max_rows,
      bounds.retention,
      wire,
      wire,
      {
        max_fields: wire.max_columns,
        max_bytes: wire.max_bytes,
        max_nodes: wire.max_nodes,
        max_depth: wire.max_depth,
      },
      bounds.retention.max_work,
      slots,
      wire.max_bytes,
    ) {
    Ok(scan) => {
      child.identity_scan = Some({ scan, prior, })
      child.advancing = true
      1
    }
    Err(Unavailable) => -33
    Err(_) => -31
  }
}

///|
fn advance_mock_effect_source_identity(
  value : Instance,
  child : StoredMockEffectCapture,
  held : StoredMockSourceIdentityScan,
) -> Int {
  if !child.advancing {
    return -33
  }
  child.advancing = false
  guard @query.captured_source_cell_identity_next_capacity(held.scan)
    is Some(required) &&
    fund_mock_effect_source_identity(value, child, held.prior, required) else {
    return -4
  }
  match @query.advance_captured_source_cell_identity(held.scan, 31, required) {
    Err(Unavailable) => return -33
    Err(_) => return -31
    Ok((false, _)) => {
      child.advancing = true
      return 1
    }
    Ok((true, _)) => ()
  }
  let identity = match @query.finish_captured_source_cell_identity(held.scan) {
    Err(Unavailable) => return -33
    Err(_) => return -31
    Ok(identity) => identity
  }
  child.identity = Some(identity)
  child.identity_scan = None
  guard @query.captured_source_relation_identity_retained_capacity(identity)
    is Some(held_capacity) &&
    @execution.checked_preparation_add_product(
      held.prior,
      1L,
      @execution.execution_capacity_retained_bytes(held_capacity),
    )
    is Some(retained) &&
    retained <= child.charged &&
    @resources.shrink_capacity_reservation(
      value.root,
      child.capacity,
      retained,
      retained,
    )
    is Ok(_) else {
    return -4
  }
  child.charged = retained
  0
}

///|
// The final Source capture installs the ordinary configured Effect DAG. The
// Sources remain children of this start and their Reads own the rows. Neither
// an equal replacement Source nor a completed child of another start is input.
fn open_original_mock_effect_compute(
  value : Instance,
  child : StoredMockEffectCapture,
  original : MockEffectJournalObservationOriginal,
  managed : @local_host.ClientInstalledManagedRun,
) -> Int {
  guard value.physical_starts.get(child.start) is Some(start) else { return -2 }
  if start.mock_effect_compute_started {
    return if start.mock_effect_compute is Some(_) { 0 } else { -33 }
  }
  let count = original.effect.sources.length()
  let mut ready = 0
  for record in value.original_metadata.values() {
    if record.project is Some(MockEffectCapture(candidate)) &&
      candidate.start == child.start &&
      candidate.identity is Some(_) &&
      candidate.captured is Some(_) &&
      (record.produced || physical_equal(candidate, child)) {
      ready += 1
    }
  }
  if ready < count {
    return 0
  }
  guard ready == count && count > 0 else { return -31 }
  if !original.effect.sources.all(selected => {
      authorize_mock_effect_source(original, selected)
    }) {
    return -20
  }
  let retained = child.charged
  let n = count.to_int64()
  // Indexed handles and the Common bridge's array copy are temporary. The
  // existing admitted managed Plan already owns the resulting DAG and Host.
  guard fund_mock_effect_capture(
    value,
    child,
    Some({
      record_headers: 8L + 4L * n,
      reference_slots: 16L + 6L * n,
      scalar_words: 16L + 4L * n,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
  ) else {
    return -4
  }
  let code = {
    let ordered = FixedArray::make(count, None)
    for record in value.original_metadata.values() {
      if record.project is Some(MockEffectCapture(candidate)) &&
        candidate.start == child.start &&
        candidate.identity is Some(identity) &&
        candidate.captured is Some(capture) &&
        (record.produced || physical_equal(candidate, child)) {
        let index = candidate.occurrence
        guard index >= 0 &&
          index < count &&
          ordered[index] is None &&
          @row_host.row_capture_source(capture) is Ok(source) &&
          @query.captured_source_relation_identity_matches_source(
            identity, source,
          ) else {
          return -31
        }
        ordered[index] = Some(source)
      }
    }
    let sources = Array(capacity=count)
    for slot in ordered {
      guard slot is Some(source) else { return -31 }
      sources.push(source)
    }
    let materials = original.journal.materials
    guard @host.bind_client_effect_compiled_run(
        materials.prepared,
        materials.allowed,
        materials.run_definition,
      )
      is Ok(bound) else {
      return -32
    }
    // Keep this one-shot attempt on the physical-start parent before Common
    // can take any borrows. The same parent owns terminal stop after unwind.
    start.mock_effect_compute_started = true
    match
      @local_host.open_installed_effect_managed_host(managed, bound, sources) {
      Ok(Some((host, dag, _))) => {
        start.mock_effect_compute = Some({
          bound,
          host,
          dag,
          source_evidence: None,
          task_drive: None,
          attempted: false,
        })
        0
      }
      Err(InsufficientCapacity | MetadataCapacityUnavailable) => -4
      Err(ForeignOriginal) => -2
      Err(CleanupPending) => -9
      Err(_) | Ok(None) => -23
    }
  }
  if code != 0 {
    return code
  }
  if @resources.shrink_capacity_reservation(
      value.root,
      child.capacity,
      retained,
      0L,
    )
    is Err(_) {
    return -4
  }
  child.charged = retained
  0
}

///|
fn advance_original_project_capture(
  value : Instance,
  handle : Int,
  record : StoredOriginalMetadata,
) -> Int {
  guard record.borrow is Ok(borrow) &&
    @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(wire) &&
    wire.length() == 32 else {
    return -31
  }
  let start = mock_effect_descriptor_field(wire, 0)
  let occurrence = mock_effect_descriptor_field(wire, 4)
  guard start > 0 && occurrence >= 0 else { return -31 }
  if value.physical_starts.get(start) is Some({ model_file: Some(_), .. }) {
    return advance_original_portable_model_file_source(value, handle, record, start, occurrence, wire)
  }
  if value.physical_starts.get(start) is Some({ file_managed: Some(_), .. }) {
    return advance_original_file_capture(value, handle, record, start, occurrence, wire)
  }
  advance_original_mock_effect_capture(value, record, start, occurrence, wire)
}

///|
fn advance_original_mock_effect_capture(
  value : Instance,
  record : StoredOriginalMetadata,
  start : Int,
  occurrence : Int,
  wire : Bytes,
) -> Int {
  let (original, managed) = match
    mock_effect_capture_current(value, start, occurrence) {
    Ok(selected) => selected
    Err(code) => return code
  }
  if record.produced {
    guard record.project is Some(MockEffectCapture(child)) &&
      child.captured is Some(captured) &&
      child.identity is Some(identity) &&
      @row_host.row_capture_source(captured) is Ok(source) &&
      @query.captured_source_relation_identity_matches_source(identity, source) else {
      return -31
    }
    return 0
  }
  if !record.invoked {
    record.invoked = true
    let started_at = @utf8.decode(wire[8:]) catch { _ => return -31 }
    if !@host.client_effect_run_start_current(
        original.journal.materials.allowed,
        original.journal.materials.run_definition,
        started_at,
      ) {
      return -32
    }
    let capacity = match @resources.reserve_capacity(value.root, 4096L, 4096L) {
      Ok(capacity) => capacity
      Err(_) => return -4
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
    record.project = Some(MockEffectCapture(child))
    let code = accept_original_mock_effect_capture(
      value, child, original, managed,
    )
    if code != 0 {
      return code
    }
  }
  guard record.project is Some(MockEffectCapture(child)) &&
    child.start == start &&
    child.occurrence == occurrence else {
    return -33
  }
  if child.identity_scan is Some(scan) {
    let code = advance_mock_effect_source_identity(value, child, scan)
    if code != 0 {
      return code
    }
    return finish_original_mock_effect_capture(value, record, child)
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
fn finish_original_mock_effect_capture(
  value : Instance,
  record : StoredOriginalMetadata,
  child : StoredMockEffectCapture,
) -> Int {
  let start = child.start
  let occurrence = child.occurrence
  match mock_effect_capture_current(value, start, occurrence) {
    Err(code) => return code
    Ok((original, managed)) => {
      let opened = open_original_mock_effect_compute(
        value, child, original, managed,
      )
      if opened != 0 {
        return opened
      }
      if value.physical_starts.get(start) is Some(physical) &&
        physical.mock_effect_compute is Some(_) {
        match mock_effect_capture_current(value, start, occurrence) {
          Err(code) => return code
          Ok(_) => ()
        }
      }
    }
  }
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, b""))
  if code == 0 {
    record.produced = true
  }
  code
}

///|
fn close_original_mock_effect_capture(
  value : Instance,
  child : StoredMockEffectCapture,
) -> Int {
  child.advancing = false
  if child.identity_scan is Some(scan) {
    // The existing Host close export cannot reenter a running Wasm call.
    @query.cancel_captured_source_cell_identity_after_unwind(scan.scan)
    child.identity_scan = None
  }
  if child.captured is Some(_) &&
    value.physical_starts.get(child.start) is Some(start) &&
    start.mock_effect_compute_started {
    if start.mock_effect_compute is Some(compute) &&
      compute.task_drive is Some(drive) {
      drive.failed = true
      if !retire_original_mock_effect_artifacts(drive) {
        return -9
      }
      drive.source_unit = None
      drive.inputs = None
    }
    guard start.mock_managed is Some(managed) &&
      @local_host.stop_installed_effect_managed_host_after_unwind(managed, () => {
        stop_original_mock_effect_work(start)
      }) else {
      return -9
    }
  }
  child.captured = None
  child.identity = None
  if !release_mock_effect_capture_document(child) {
    return -9
  }
  if child.read is Some(read) {
    if @local_host.retire_installed_source_read(read) is Err(_) {
      guard child.rows is Some(rows) &&
        @row_host.advance_row_capture_cleanup(rows, 256) is Ok(true) &&
        @local_host.retire_installed_source_read(read) is Ok(_) else {
        return -9
      }
    }
    child.read = None
    child.acquisition = None
    child.rows = None
  }
  match @resources.settle_capacity(value.root, child.capacity) {
    Err(_) => -4
    Ok(_) => 0
  }
}
