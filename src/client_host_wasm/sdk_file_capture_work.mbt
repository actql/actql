///|
// The original captured RowRun remains the Source owner; this child holds only
// the shared Pure host and its original selected Plan.
priv struct StoredSDKFileCaptureWork {
  source : Int
  prepared : @host.PreparedClientProgram
  request : @host.ClientRequestIdentity
  capacity : @resources.CapacityReservation
  mut host : (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedDAG,
    Array[@execution.GeneratedSequence],
  )?
  mut tasks : @local_host.LocalEffectTaskExecution?
  mut task_capacity : @resources.CapacityReservation?
  mut result : @local_host.LocalValuesExecution?
  mut invocation : StoredSDKFilePublicationOriginal?
  mut invocation_capacity : @resources.CapacityReservation?
  mut invocation_ready : Bool
  mut results_ready : Bool
  mut stepping : Bool
  mut failed : Bool
  mut closing : Bool
}

///|
priv struct StoredSDKFilePublicationOriginal {
  source_evidence : @publication.RunEvidenceValue
  _logical_input : @publication.RunEvidenceValue
  observation : @publication.RunEvidenceValue
  invocation : @publication.PublicationContract
  _data_policy_cid : String
  _source_relation_cid : String
  _finite_policy : @host.ClientLocalRunPolicyOriginal
}

///|
fn sdk_file_capture_work_capacity() -> Int64? {
  guard @execution.preparation_array_representation(2L, 2L, true) is Some(views) else {
    return None
  }
  @execution.preparation_representation_cost({
    record_headers: views.record_headers + 14L,
    reference_slots: views.reference_slots + 33L,
    scalar_words: views.scalar_words + 10L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
fn open_sdk_file_capture_work(
  value : Instance,
  start : Int,
  at : String,
  record : StoredOriginalMetadata,
) -> Int {
  let (custody, managed, owner, journal, selected) = match
    sdk_file_source_current(value, start) {
    Ok(selected) => selected
    Err(code) => return code
  }
  let materials = journal.candidate.task_materials.plan
  guard sdk_file_physical_claim(value, custody) is Some((_, claim)) &&
    claim.observed is Some(observed) &&
    @local_run.local_captured_task_start_finite_policy(
      observed,
      journal.candidate,
    )
    is Some(finite_policy) &&
    managed.capture_work is None &&
    managed.source.capture is Some(source) &&
    value.original_metadata.get(source) is Some(original) &&
    original.produced &&
    !original.output_closed &&
    original.project is Some(FileCapture(child)) &&
    child.start == start &&
    child.captured is Some(capture) &&
    @row_host.row_capture_source(capture) is Ok(acquired) else {
    return -35
  }
  if !@publication.run_publication_start_current(
      @host.client_compiled_run_admission(materials.compiled),
      materials.definition,
      at,
    ) {
    return -32
  }
  guard sdk_file_capture_work_capacity() is Some(controls) else { return -4 }
  let capacity = match
    @resources.reserve_capacity(value.root, controls, controls) {
    Ok(value) => value
    Err(_) => return -4
  }
  let work : StoredSDKFileCaptureWork = {
    source,
    prepared: materials.compiled.owner,
    request: materials.request,
    capacity,
    host: None,
    tasks: None,
    task_capacity: None,
    result: None,
    invocation: None,
    invocation_capacity: None,
    invocation_ready: false,
    results_ready: false,
    stepping: false,
    failed: false,
    closing: false,
  }
  // Place the existing source dependency before the Common open. A failed
  // configuration can already own a captured DAG and must use its cleanup.
  managed.capture_work = Some(work)
  let opened = match
    @local_host.open_installed_managed_capture_host(
      owner,
      work.prepared,
      work.request,
      [acquired],
    ) {
    Ok(host) => host
    Err(Managed(InsufficientCapacity | MetadataCapacityUnavailable)) =>
      return -4
    Err(Managed(CleanupPending)) => return -9
    Err(Managed(ForeignOriginal)) => return -35
    Err(_) => return -23
  }
  work.host = Some(opened)
  let bound = bind_sdk_file_invocation(
    owner, work, journal, selected, child, finite_policy, at,
  )
  if bound != 0 {
    return bound
  }
  match sdk_file_source_current(value, start) {
    Err(code) => return code
    Ok((active, current, current_owner, live_journal, _)) => {
      guard physical_equal(active, custody) &&
        physical_equal(current, managed) &&
        physical_equal(current_owner, owner) &&
        physical_equal(live_journal.candidate, journal.candidate) &&
        sdk_file_physical_claim(value, active) is Some((_, live_claim)) &&
        physical_equal(live_claim, claim) &&
        live_claim.observed is Some(live_observed) &&
        physical_equal(live_observed, observed) &&
        value.original_metadata.get(source) is Some(current_source) &&
        physical_equal(current_source, original) &&
        current_source.produced &&
        current.capture_work is Some(active_work) &&
        physical_equal(active_work, work) &&
        active_work.host is Some(_) &&
        active_work.invocation is Some(_) &&
        !work.closing else {
        return -9
      }
    }
  }
  if @resources.shrink_capacity_reservation(value.root, capacity, controls, 0L)
    is Err(_) {
    return -4
  }
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, b""))
  if code == 0 {
    work.invocation_ready = true
    record.produced = true
  }
  code
}

///|
fn sdk_file_invocation_capacity(
  graph : @strategy.CheckedDAG,
  source_ref : String,
  classification : String,
  started_at : String,
  observed_at : String,
) -> (Int64, Int64)? {
  // These four canonical documents contain just one Source and reference
  // the existing Run/Template by CID. Their fixed keys, constant values and
  // canonical CIDs (including the four self-CIDs) fit in 2304 bytes.
  // Charge variable Source metadata and clock strings by worst JSON escaping.
  let bytes = 2304L +
    6L *
    (
      source_ref.length().to_int64() +
      classification.length().to_int64() +
      started_at.length().to_int64() +
      2L * observed_at.length().to_int64()
    )
  let tasks = @strategy.graph_task_count(graph).to_int64()
  let results = @strategy.graph_result_count(graph).to_int64()
  let sources = @checked.source_execution_count(@strategy.graph_program(graph)).to_int64()
  // The retained products include their canonical trees. Selector and
  // verification vectors are temporary and follow the admitted graph.
  guard bytes <= 2147483647L &&
    @host.client_protocol_metadata_construction_bytes(
      bytes.to_int(),
      64L,
      copies=2,
    )
    is Some((retained, _)) &&
    @host.client_protocol_metadata_construction_bytes(
      bytes.to_int(),
      128L + 4L * tasks + 8L * results + 4L * sources,
      copies=4,
    )
    is Some((execution, _)) else {
    return None
  }
  Some((retained, execution))
}

///|
fn bind_sdk_file_invocation(
  owner : @local_host.ClientInstalledManagedRun,
  work : StoredSDKFileCaptureWork,
  journal : WholeFileJournalOriginal,
  selected : StoredSDKWholeFileSource,
  child : StoredMockEffectCapture,
  finite_policy : @host.ClientLocalRunPolicyOriginal,
  at : String,
) -> Int {
  guard work.invocation_capacity is None &&
    work.host is Some((_, dag, _)) &&
    child.captured is Some(capture) &&
    child.acquisition is Some(acquisition) &&
    child.identity is Some(identity) &&
    @row_host.row_capture_source(capture) is Ok(input) &&
    @row_host.row_input_acquisition_matches_source(
      acquisition,
      sdk_file_source_acquisition(selected),
    ) &&
    @query.captured_source_relation_identity_matches_source(identity, input) else {
    return -35
  }
  let ledger = @strategy.captured_dag_ledger(dag)
  let task = journal.candidate.task_materials
  let materials = task.plan
  let policy_cid = journal.candidate.publication_policy_root
  let facts = @row_host.row_input_acquisition_facts(acquisition)
  let scope = @host.client_request_authority_scope_cid(materials.request)
  let graph = @strategy.captured_dag_graph(dag)
  guard sdk_file_invocation_capacity(
      graph,
      facts.source_ref,
      facts.data_classification,
      child.started_at,
      at,
    )
    is Some((retained, execution)) else {
    return -4
  }
  let capacity = match
    @resources.reserve_capacity(ledger, retained, execution) {
    Ok(capacity) => capacity
    Err(_) => return -4
  }
  work.invocation_capacity = Some(capacity)
  let logical_input = match
    @host.issue_captured_whole_source_input_logical(
      graph,
      input,
      identity,
      sdk_file_source_acquisition(selected),
    ) {
    Ok(value) => value
    Err(_) => return -31
  }
  let source = match
    @row_host.issue_row_input_source_evidence(
      acquisition,
      capture,
      identity,
      logical_input,
      scope,
      facts.source_data_policy_cid,
      at,
    ) {
    Ok(value) => value
    Err(issue) => return mock_effect_capture_issue(issue)
  }
  let (observation, invocation) = match
    @local_host.issue_program_whole_source_publication_invocation(
      owner,
      work.prepared,
      materials.compiled,
      materials.definition,
      capture,
      identity,
      source,
      logical_input,
      scope,
      policy_cid,
      child.started_at,
      at,
      65536,
      8192,
      64,
    ) {
    Ok(value) => value
    Err(_) => return -31
  }
  let (matched_dag, source_relation_cid) = match
    @local_host.installed_single_whole_publication_source(
      owner,
      work.prepared,
      work.request,
      materials.compiled,
      materials.definition,
      invocation,
      capture,
      identity,
    ) {
    Ok(original) => original
    Err(CleanupPending) => return -9
    Err(InsufficientCapacity | MetadataCapacityUnavailable) => return -4
    Err(_) => return -35
  }
  if !physical_equal(matched_dag, dag) {
    return -35
  }
  work.invocation = Some({
    source_evidence: source,
    _logical_input: logical_input,
    observation,
    invocation,
    _data_policy_cid: policy_cid,
    _source_relation_cid: source_relation_cid,
    _finite_policy: finite_policy,
  })
  // The adopted owner retains the same Invocation and evidence until close.
  if @resources.shrink_capacity_reservation(ledger, capacity, retained, 0L)
    is Err(_) {
    return -4
  }
  0
}

///|
fn begin_sdk_file_task_driver(
  work : StoredSDKFileCaptureWork,
  owner : @local_host.ClientInstalledManagedRun,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  dag : @strategy.CapturedDAG,
) -> Int {
  if work.task_capacity is Some(_) {
    return -33
  }
  guard @local_host.stepped_whole_source_local_tasks_control_capacity(
      @strategy.captured_dag_graph(dag),
    )
    is Some(base) &&
    @execution.preparation_representation_cost({
      record_headers: 8L,
      reference_slots: 20L,
      scalar_words: 8L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(controls) &&
    @execution.execution_capacity(controls, controls) is Some(extra) &&
    @execution.add_execution_capacity(base, extra) is Some(quote) else {
    return -4
  }
  let capacity = match
    @resources.reserve_capacity(
      @strategy.captured_dag_ledger(dag),
      quote.retained_bytes,
      quote.execution_bytes,
    ) {
    Ok(capacity) => capacity
    Err(_) => return -4
  }
  work.task_capacity = Some(capacity)
  match
    @local_host.begin_stepped_whole_source_local_tasks(
      owner,
      work.prepared,
      work.request,
      setup,
    ) {
    Ok(tasks) => {
      work.tasks = Some(tasks)
      0
    }
    Err(issue) => mock_effect_task_issue(issue)
  }
}

///|
fn advance_sdk_file_tasks(
  value : Instance,
  start : Int,
  at : String,
  record : StoredOriginalMetadata,
) -> Int {
  guard value.physical_starts.get(start) is Some(original_start) &&
    original_start.file_managed is Some(original_holder) &&
    original_holder.capture_work is Some(work) &&
    !work.closing &&
    !work.stepping &&
    !work.failed &&
    work.invocation_ready &&
    work.invocation is Some(_) &&
    !work.results_ready &&
    work.host is Some((setup, dag, _)) else {
    return -33
  }
  let (custody, managed, owner, journal, _) = match
    sdk_file_source_current(value, start) {
    Ok(original) => original
    Err(code) => {
      work.failed = true
      return code
    }
  }
  let materials = journal.candidate.task_materials.plan
  guard physical_equal(custody, original_start) &&
    physical_equal(managed, original_holder) &&
    managed.capture_work is Some(active) &&
    physical_equal(active, work) &&
    !work.closing else {
    return -9
  }
  if !@publication.run_publication_start_current(
      @host.client_compiled_run_admission(materials.compiled),
      materials.definition,
      at,
    ) {
    work.failed = true
    return -32
  }
  if work.result is Some(_) {
    return -33
  }
  let request = file_publication_request_current(value, work)
  if request != 0 {
    return request
  }
  if work.tasks is None {
    let opened = begin_sdk_file_task_driver(work, owner, setup, dag)
    if opened != 0 {
      work.failed = true
      return opened
    }
  }
  guard work.tasks is Some(tasks) else { return -33 }
  let primary : Ref[Int?] = Ref(None)
  fn current() -> Bool {
    if primary.val is Some(_) {
      return false
    }
    match sdk_file_source_current(value, start) {
      Err(code) => {
        primary.val = Some(code)
        false
      }
      Ok((active, holder, live_owner, _, _)) => {
        if !physical_equal(active, custody) ||
          !physical_equal(holder, managed) ||
          !physical_equal(live_owner, owner) ||
          work.closing ||
          !(holder.capture_work is Some(live) && physical_equal(live, work)) {
          primary.val = Some(-9)
          return false
        }
        let request = file_publication_request_current(value, work)
        if request != 0 {
          primary.val = Some(request)
          return false
        }
        true
      }
    }
  }
  work.stepping = true
  let progress = tasks.advance(256, current)
  work.stepping = false
  match progress {
    Err(issue) => {
      work.failed = true
      primary.val.unwrap_or(mock_effect_task_issue(issue))
    }
    Ok(false) => 1
    Ok(true) => {
      if !current() {
        work.failed = true
        return primary.val.unwrap_or(-32)
      }
      guard tasks.result() is Some(result) else {
        work.failed = true
        return -31
      }
      work.result = Some(result)
      let code = status(
        @buffers.supply_buffer_output(value.pool, record.slot, b""),
      )
      if code == 0 {
        work.results_ready = true
        record.produced = true
      } else {
        work.failed = true
      }
      code
    }
  }
}

///|
fn retire_sdk_file_capture_work(
  value : Instance,
  start : Int,
  source : Int,
) -> Int {
  guard value.physical_starts.get(start) is Some(custody) &&
    custody.file_managed is Some(managed) &&
    managed.source.capture == Some(source) else {
    return -9
  }
  guard managed.capture_work is Some(work) else { return 0 }
  if work.source != source {
    return -9
  }
  work.closing = true
  if file_publication_preflight(value, work) {
    return -9
  }
  let owner = match
    @local_host.observe_request_capture_transfer(managed.transfer) {
    Ok(Some(owner)) => owner
    _ => return -9
  }
  // This close runs after the entered Wasm call unwound. Actual operations
  // settle before the captured DAG, aliases and original Source can retire.
  work.stepping = false
  work.invocation_ready = false
  work.results_ready = false
  work.result = None
  if work.tasks is Some(tasks) {
    if !tasks.close() {
      return -9
    }
    work.tasks = None
  }
  if work.task_capacity is Some(capacity) {
    guard work.host is Some((_, dag, _)) else { return -9 }
    if @resources.settle_capacity(@strategy.captured_dag_ledger(dag), capacity)
      is Err(_) {
      return -4
    }
    work.task_capacity = None
  }
  if !@local_host.stop_installed_pure_capture_host_after_unwind(
      owner,
      work.prepared,
      work.request,
    ) {
    return -9
  }
  work.invocation = None
  if work.invocation_capacity is Some(capacity) {
    guard work.host is Some((_, dag, _)) else { return -9 }
    if @resources.settle_capacity(@strategy.captured_dag_ledger(dag), capacity)
      is Err(_) {
      return -4
    }
    work.invocation_capacity = None
  }
  work.host = None
  if @resources.settle_capacity(value.root, work.capacity) is Err(_) {
    return -4
  }
  managed.capture_work = None
  0
}
