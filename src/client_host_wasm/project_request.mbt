///|
// Keep partial construction on the issued preparation. Physical input returns
// before the original platform working capacity is acknowledged.
priv struct StoredMockProjectRequest {
  working : @resources.PlatformVMWorkingCapacity
  mut region : @resources.BackedExecutionRegion[
    @resources.Ledger,
    @buffers.BufferSlot,
  ]?
  mut ticket : @resources.BackedExecutionDelegation[
    @resources.Ledger,
    @buffers.BufferSlot,
  ]?
  mut read : @resources.BackedExecutionReadUse[
    @resources.Ledger,
    @buffers.BufferSlot,
  ]?
  mut access : @resources.BackedExecutionLiveAccess[
    @resources.Ledger,
    @buffers.BufferSlot,
    @buffers.BufferSlot,
  ]?
  mut frame : @resources.ImportedChildLedger?
  mut initial : @resources.BackedPreparationAdmission[@buffers.BufferSlot]?
  mut parent : @local_host.ClientRequestPreparation[@buffers.BufferSlot]?
  mut submission : (Int, @host.ClientSavedSubmissionSnapshot)?
  mut target_check_input : @resources.PreparationBodyBorrow[
    @host.PreparedClientEffectComputation,
  ]?
  mut model_ready : Bool
  mut model_run_handle : Int?
  mut model_run : StoredPortableModelRun?
  mut model_input : @resources.PreparationBodyBorrow[
    @host.PreparedClientProgram,
  ]?
  mut portable_execution : StoredPortableExecution?
  mut effect_plan : StoredMockProjectEffectPlan?
  mut whole_file_sdk_run : Int?
  mut whole_file_sdk_phase : WholeFileSDKPhase
  mut whole_file_source : StoredSDKWholeFileSource?
  mut input_returned : Bool
  mut usage_observed : Bool
  mut final_usage : @resources.LedgerUsage?
}

///|
// Keep the Run and its one issued row material distinct. Retiring the output
// transport does not rewind the preparation or permit another first material.
priv enum WholeFileSDKPhase {
  AwaitingPlan
  PlanReady
  ReservingRows
  RowsReserved(Int)
}

///|
priv enum StoredSDKWholeFileSource {
  MockFile(StoredSDKMockWholeFileSource)
  LocalCsv(@host.ClientProjectLocalCsvSelection)
}

///|
priv struct StoredSDKMockWholeFileSource {
  file : StoredProjectInputPreparation
  bytes : Bytes
  selected : StoredMockEffectSourceSelection
  acquisition : @sourceviews.SourceAcquisition
}

///|
// A 4-byte private handle selects the already observed Submission loan.
const RETAINED_MOCK_REQUEST_KIND : Int = 5

///|
// Select before validation and check the same retained object after the fresh
// physical observation. The original append validation supplies key, body,
// revision, current, authority, and inventory checks in the active Read.
fn retained_project_request_snapshot(
  value : Instance,
  record : StoredPreparation,
  configuration_handle : Int,
  configuration : StoredRunConfiguration,
) -> Result[(Int, @host.ClientSavedSubmissionSnapshot), Int] {
  guard record.slot.wire_length == 4 &&
    @buffers.filled_payload_input_bytes(value.pool, record.borrow) is Some(wire) &&
    wire.length() == 4 else {
    return Err(-31)
  }
  let handle = wire[0].to_int() |
    (wire[1].to_int() << 8) |
    (wire[2].to_int() << 16) |
    (wire[3].to_int() << 24)
  guard handle > 0 &&
    configuration.host_current is Some(current) &&
    value.submissions.get(handle) is Some(submission) &&
    submission.kind == 3 &&
    submission.configuration == configuration_handle &&
    submission.produced &&
    !submission.output_closed &&
    submission.append_plan is Ready(@host.Retained(snapshot)) &&
    submission_snapshot_is_preparing(snapshot) else {
    return Err(-32)
  }
  let code = validate_submission_append(value.nonce, handle, current)
  if code != 0 {
    return Err(code)
  }
  guard value.submissions.get(handle) is Some(actual) &&
    physical_equal(actual, submission) &&
    !actual.output_closed &&
    actual.append_plan is Ready(@host.Retained(still)) &&
    physical_equal(still, snapshot) else {
    return Err(-32)
  }
  Ok((handle, snapshot))
}

///|
fn mock_project_request_configuration(
  value : Instance,
  environment : Int,
) -> (StoredRunConfiguration, StoredMockProjectCheck)? {
  guard value.original_metadata.get(environment) is Some(metadata) &&
    metadata.kind == 7 &&
    metadata.produced &&
    !metadata.output_closed &&
    metadata.project is Some(MockCheck(check)) &&
    check.environment is Some(_) &&
    check.prepared_publication is Some(_) &&
    value.run_configurations.get(check.configuration) is Some(configuration) &&
    configuration.host_current is Some(_) &&
    configuration.mock_project == Some(check.project) else {
    return None
  }
  Some((configuration, check))
}

///|
fn project_request_configuration(
  value : Instance,
  environment : Int,
) -> (StoredRunConfiguration, StoredMockProjectCheck)? {
  guard value.original_metadata.get(environment) is Some(metadata) else {
    return None
  }
  match metadata.project {
    Some(MockCheck(_)) => mock_project_request_configuration(value, environment)
    Some(PortableModelCheck(check)) => {
      guard metadata.kind == 7 &&
        metadata.produced &&
        !metadata.output_closed &&
        check.prepared_publication is Some(_) &&
        check.environment is Some(_) &&
        value.run_configurations.get(check.configuration) is Some(configuration) &&
        configuration.sdk is Some({ portable_model: Some(task), .. }) &&
        task == check.project &&
        configuration.host_current is Some(current) &&
        installed_portable_model_task(value, task, current) is Some(_) else {
        return None
      }
      Some((configuration, check))
    }
    Some(LocalCheck(check)) => {
      guard metadata.kind == 7 &&
        metadata.produced &&
        !metadata.output_closed &&
        check.environment is Some(_) &&
        check.prepared_publication is Some(_) &&
        check.local_file is Some(_) &&
        value.run_configurations.get(check.configuration) is Some(configuration) &&
        configuration.host_current is Some(_) &&
        configuration.local_project == Some(check.project) &&
        original_local_project_inputs(value, check.project) is Some(_) else {
        return None
      }
      Some((configuration, check))
    }
    _ => None
  }
}

///|
fn mock_project_request_backing_issue(
  issue : @resources.BackedExecutionIssue,
) -> Int {
  match issue {
    Resource(RetentionLimit | ExecutionLimit) => -4
    CleanupPending => -9
    Resource(_) => -10
    _ => -2
  }
}

///|
fn mock_project_request_issue(
  issue : @local_host.ClientRequestPreparationIssue,
) -> Int {
  match issue {
    Initial(reason) => imported_child_issue_code(reason)
    Capacity(_)
    | SnapshotCapacityExceeded(_, _)
    | ProgramCheck(Capacity(Resource(RetentionLimit | ExecutionLimit))) => -4
    ForeignOriginal => -2
    WrongPhase => -23
    Work(_) => -10
    _ => -31
  }
}

///|
fn begin_project_request(
  value : Instance,
  record : StoredPreparation,
  vm : @resources.PlatformVMCapacity,
) -> Result[
  (
    StoredMockProjectRequest,
    @local_host.ClientRequestPreparation[@buffers.BufferSlot],
  ),
  Int,
] {
  // Region, ticket, read use, live access, initialization and retirement
  // records share the fixed entry prefix. A stack of at most 65 Source levels
  // is traversed before the canonical Request constructor grows its own quote.
  // The empty Effect Plan slot and the captured File Run/ready latch are
  // already live at this entry.
  let retained = @execution.preparation_representation_cost({
    // Transfer funding retains one original callback and its captured
    // region, child and ceiling until this same Request retires.
    record_headers: 50L,
    reference_slots: 206L,
    scalar_words: 166L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  // The pinned Wasm Array doubles through capacity 128. At the last resize
  // it holds both 64 and 128 slots. Copied slots refer to the same frames.
  // Outside resize, popped slots can still retain old frames: allow all 128
  // occupied slots plus four active/replacement frames. Each frame owns one
  // reference and at most three words (tag, index, depth). Fixed remainder
  // covers the Array, two backings, pop result, two 13-word extent records
  // and the immediate caller/result controls. The input tree is still borrowed.
  let scratch = @execution.preparation_representation_cost({
    record_headers: 132L + 12L,
    reference_slots: 64L + 128L + 132L + 28L,
    scalar_words: 3L * 132L + 52L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  // The Check owner already funds the same prepared publication and its
  // Catalog. The Request funds its borrowed references, retained Submission,
  // and checker/control geometry independently of that immutable material.
  let prepared_controls = @execution.preparation_representation_cost({
    record_headers: 59L,
    reference_slots: 132L,
    scalar_words: 100L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  let retained = retained + prepared_controls
  let working = match
    @resources.reserve_platform_vm_working_capacity(vm, retained, scratch) {
    // The two quotes are checked and nonnegative. At this entrance,
    // InvalidCharge means their simultaneous backing exceeds the fixed VM.
    Err(Resource(InvalidCharge | RetentionLimit | ExecutionLimit)) =>
      return Err(-4)
    Err(issue) => return Err(imported_child_issue_code(issue))
    Ok(original) => original
  }
  let held : StoredMockProjectRequest = {
    working,
    region: None,
    ticket: None,
    read: None,
    access: None,
    frame: None,
    initial: None,
    parent: None,
    submission: None,
    target_check_input: None,
    model_ready: false,
    model_run_handle: None,
    model_run: None,
    model_input: None,
    portable_execution: None,
    effect_plan: None,
    whole_file_sdk_run: None,
    whole_file_sdk_phase: AwaitingPlan,
    whole_file_source: None,
    input_returned: false,
    usage_observed: false,
    final_usage: None,
  }
  record.project_request = Some(held)
  let slot = record.slot
  let policy = @local_host.client_local_resource_policy()
  let limits = @local_host.client_local_preparation_initial_limits(policy).unwrap()
  let region = match
    @resources.issue_platform_vm_preparation_region(working, value.root) {
    Err(issue) => return Err(mock_project_request_backing_issue(issue))
    Ok(original) => original
  }
  held.region = Some(region)
  let prefix = retained + scratch
  let ticket = match
    @resources.reserve_backed_execution_delegation(
      region,
      value.root,
      slot,
      {
        offset: 0L,
        length: prefix,
        payload_offset: 0L,
        payload_length: prefix,
      },
      ExclusiveWrite,
      { ..limits, attempts: 0, holdings: 0, transfer_bytes: 0L, },
      0L,
      0L,
    ) {
    Err(issue) => return Err(mock_project_request_backing_issue(issue))
    Ok(original) => original
  }
  held.ticket = Some(ticket)
  let read = match
    @resources.borrow_backed_execution_read_use(
      region,
      value.root,
      slot,
      ticket,
    ) {
    Err(issue) => return Err(mock_project_request_backing_issue(issue))
    Ok(original) => original
  }
  held.read = Some(read)
  let access = match
    @resources.issue_backed_execution_live_access(
      region,
      value.root,
      slot,
      ticket,
      read,
      slot,
    ) {
    Err(issue) => return Err(mock_project_request_backing_issue(issue))
    Ok(original) => original
  }
  held.access = Some(access)
  let projection = match
    @resources.admit_backed_execution_live_child(access, slot) {
    Err(issue) => return Err(mock_project_request_backing_issue(issue))
    Ok(original) => original
  }
  let initial = match
    @resources.prepare_backed_preparation_admission(projection, slot) {
    Err(issue) => return Err(imported_child_issue_code(issue))
    Ok(original) => original
  }
  held.initial = Some(initial)
  let frame = match
    @resources.backed_preparation_original_frame(initial, slot) {
    Err(issue) => return Err(imported_child_issue_code(issue))
    Ok(original) => original
  }
  held.frame = Some(frame)
  let parent = match
    @local_host.begin_backed_request_preparation(initial, slot, policy) {
    Err(issue) => return Err(mock_project_request_issue(issue))
    Ok(original) => original
  }
  held.parent = Some(parent)
  Ok((held, parent))
}

///|
fn prepare_project_request(value : Instance, record : StoredPreparation) -> Int {
  if value.closing || value.runtime_closing || record.started {
    return -23
  }
  guard project_request_configuration(value, record.environment)
    is Some((configuration, check)) &&
    check.environment is Some((checker, _, _)) &&
    check.prepared_publication is Some(checked_publication) &&
    value.platform_vm is Some(vm) else {
    return -2
  }
  record.started = true
  let (held, parent) = match begin_project_request(value, record, vm) {
    Ok(original) => original
    Err(code) => return code
  }
  // The existing append observer already checks the selected reader, Account,
  // exact key/body/revision and inventory. Pin its original, never packet bytes.
  let retained = match
    retained_project_request_snapshot(
      value,
      record,
      check.configuration,
      configuration,
    ) {
    Err(code) => return code
    Ok(original) => original
  }
  held.submission = Some(retained)
  let (_, snapshot) = retained
  let slot = record.slot
  match
    @local_host.check_request_retained_submitted_intent(
      parent,
      slot,
      @host.client_saved_submission_record(snapshot).intent,
      checker,
      checked_publication,
      public_primary=true,
    ) {
    Err(Preparation(issue)) => return mock_project_request_issue(issue)
    Err(InvalidInput) => return -31
    Err(Request(Preparation(issue))) => return mock_project_request_issue(issue)
    Err(Request(_)) => return -31
    Ok(_) => ()
  }
  let computation = match
    @local_host.finish_request_checked_computation(
      parent, slot, checker, checked_publication,
    ) {
    Err(Preparation(issue)) => return mock_project_request_issue(issue)
    Err(_) => return -31
    Ok(original) => original
  }
  if configuration.sdk is Some({ portable_model: Some(_), .. }) {
    if computation is Pure {
      return prepare_retained_portable_model(
        value, configuration, held, parent, slot,
      )
    }
    return -20
  }
  if configuration.local_project is Some(_) {
    guard computation is Pure &&
      @local_host.request_checked_pure_direct_source_count(parent, slot) ==
      Some(1L) else {
      return -20
    }
    return prepare_retained_local_csv_file(
      value, configuration, check, held, parent, slot, snapshot,
    )
  }
  if check.runtime_cid is Some(_) && computation is Pure {
    guard @local_host.request_checked_pure_direct_source_count(parent, slot)
      is Some(source_count) else {
      return -2
    }
    if source_count == 1L {
      return prepare_retained_mock_project_file(
        value, configuration, check, held, parent, slot, snapshot,
      )
    }
  }
  if check.runtime_cid is Some(_) && computation is Effect {
    match run_configuration_current(value, configuration) {
      Err(code) => return code
      Ok(_) => ()
    }
    let input = match
      @local_host.borrow_request_effect_plan_input(
        parent,
        slot,
        project_file=true,
      ) {
      Ok(input) => input
      Err(issue) => return mock_project_request_issue(issue)
    }
    held.target_check_input = Some(input)
    guard @resources.preparation_body_borrow_value(input) is Some(prepared) else {
      return -2
    }
    let plan = match
      prepare_mock_project_effect_plan(
        value, configuration, check, prepared, snapshot,
      ) {
      Err(code) => return code
      Ok(plan) => plan
    }
    // Keep the constructed Plan on its original Request even when return or
    // the subsequent current observation refuses. Only return success makes
    // this preparation available to the existing Run handoff.
    held.effect_plan = Some(plan)
    match @resources.return_preparation_body_borrow(input) {
      Ok(_) => held.target_check_input = None
      Err(_) => return -9
    }
  }
  match run_configuration_current(value, configuration) {
    Err(code) => code
    Ok(_) =>
      if check.runtime_cid is Some(_) && computation is Effect {
        guard held.effect_plan is Some(effect) else { return -2 }
        let code = mock_project_effect_plan_current(value, check, effect)
        if code == 0 {
          effect.ready = true
        }
        code
      } else {
        0
      }
  }
}

///|
// Prepare only the selected checked Pure File on this original Request. The
// existing Common parent keeps the artifact and Plan. No Run is adopted or
// published, no File is opened, and no Effect operation is selected here.
fn prepare_retained_mock_project_file(
  value : Instance,
  configuration : StoredRunConfiguration,
  check : StoredMockProjectCheck,
  held : StoredMockProjectRequest,
  parent : @local_host.ClientRequestPreparation[@buffers.BufferSlot],
  slot : @buffers.BufferSlot,
  snapshot : @host.ClientSavedSubmissionSnapshot,
) -> Int {
  match run_configuration_current(value, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  guard check.runtime_cid is Some(_) &&
    value.original_metadata.get(check.project) is Some(record) &&
    record.produced &&
    !record.output_closed &&
    record.project is Some(MockInputs(file)) &&
    file.inputs is Some(inputs) &&
    file.data is Some(_) &&
    file.data_body is Some(body) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    current.account is Some(account) else {
    return -2
  }
  let bytes = body.length()
  let page = @row_host.project_mock_row_page_limits()
  guard bytes > 0 && bytes <= page.max_bytes else { return -4 }
  let (request, selected) = match
    select_retained_project_whole_file(
      parent,
      slot,
      snapshot,
      configuration.authority_scope_cid,
    ) {
    Ok(original) => original
    Err(code) => return code
  }
  let acquisition = @local_host.client_request_whole_file_source(selected)
  let source = @sourceviews.mode_input(
    @sourceviews.source_acquisition_mode(acquisition),
  )
  let declaration = @sourceviews.declaration(source)
  let selected_row = match
    select_mock_effect_source(
      inputs.sources,
      declaration.connector,
      declaration.resource,
      @sourceviews.selected_cid(source),
      Ref(@host.client_standard_effect_computation_limits().effects.max_work),
    ) {
    Ok(original) => original
    Err(code) => return code
  }
  guard @authorization.evaluate_account(account, {
      principal: configuration.tuple.principal,
      connection: selected_row.source.connection,
      resource: selected_row.row.view.resource,
      operation: "read",
    })
    is Allow(_) else {
    return -20
  }
  let input_limits = @local_host.installed_row_input_policy(
    page.max_rows,
    bytes,
    Int::min(page.max_nodes, bytes),
    page.max_depth,
    page.max_rows,
  )
  if compile_retained_project_whole_file(
      value,
      parent,
      slot,
      request,
      selected,
      selected_row.source.relation,
      input_limits,
      bytes.to_int64(),
      bytes.to_int64(),
    )
    is Err(code) {
    return code
  }
  match run_configuration_current(value, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  guard value.original_metadata.get(check.project) is Some(still) &&
    physical_equal(still, record) &&
    still.produced &&
    !still.output_closed &&
    still.project is Some(MockInputs(still_file)) &&
    physical_equal(still_file, file) &&
    still_file.data_body is Some(still_body) &&
    physical_equal(still_body, body) &&
    @local_host.inspect_request_whole_file_plan_original(parent, slot, (
      original,
      _,
      _,
    ) => physical_equal(original, request))
    is Some(true) else {
    return -2
  }
  held.whole_file_source = Some(
    MockFile({ file, bytes: body, selected: selected_row, acquisition, }),
  )
  0
}

///|
fn stop_mock_project_request(
  root : @resources.Ledger,
  held : StoredMockProjectRequest,
) -> Int {
  guard held.frame is Some(frame) else { return 0 }
  if held.model_run is Some(run) {
    if !quiesce_portable_model_run(root, run) {
      return -9
    }
    if run.adopted is None {
      held.model_run = None
    }
  }
  if held.model_input is Some(input) {
    match @resources.return_preparation_body_borrow(input) {
      Err(@resources.BorrowReturned) | Ok(_) => held.model_input = None
      Err(_) => return -9
    }
  }
  if held.portable_execution is Some(execution) {
    execution.bounds = None
  }
  if held.target_check_input is Some(input) {
    match @resources.return_preparation_body_borrow(input) {
      Err(@resources.BorrowReturned) | Ok(_) => held.target_check_input = None
      Err(_) => return -9
    }
  }
  if held.effect_plan is Some(effect) && effect.journal is Some(journal) {
    match @resources.return_preparation_body_borrow(journal.plan) {
      Err(@resources.BorrowReturned) | Ok(_) => effect.journal = None
      Err(_) => return -9
    }
  }
  if held.parent is Some(parent) {
    match @local_host.abort_request_preparation_after_cleanup(parent) {
      Err(Initial(Unavailable)) | Ok(_) => ()
      Err(issue) => return mock_project_request_issue(issue)
    }
  }
  held.effect_plan = None
  match @resources.stop_imported_child_ledger(frame) {
    Err(issue) => return imported_child_issue_code(issue)
    Ok(_) => ()
  }
  report_mock_project_child_stop(held)
}

///|
fn report_mock_project_child_stop(held : StoredMockProjectRequest) -> Int {
  if held.usage_observed {
    return 0
  }
  guard held.initial is Some(initial) else { return -9 }
  match @resources.report_stopped_backed_preparation_usage(initial) {
    Err(issue) => return imported_child_issue_code(issue)
    Ok(usage) => held.final_usage = usage
  }
  held.usage_observed = true
  0
}

///|
fn retire_mock_project_access(
  held : StoredMockProjectRequest,
  slot : @buffers.BufferSlot,
) -> Int {
  guard held.access is Some(access) else { return 0 }
  match
    @resources.retire_backed_execution_live_child_after_owner_ack(access, slot) {
    Err(issue) => mock_project_request_backing_issue(issue)
    Ok(_) => {
      held.access = None
      0
    }
  }
}

///|
fn close_mock_project_request(
  value : Instance,
  record : StoredPreparation,
  held : StoredMockProjectRequest,
) -> Int {
  held.whole_file_source = None
  let slot = record.slot
  if !held.usage_observed {
    let code = stop_mock_project_request(value.root, held)
    if code != 0 {
      return code
    }
  }
  if !held.input_returned {
    let code = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
    if code != 0 {
      return code
    }
    held.input_returned = true
  }
  let retired = retire_mock_project_access(held, slot)
  if retired != 0 {
    return retired
  }
  if held.model_run is Some({ adopted: Some(adopted), .. }) {
    // Adoption consumed the Request initializer. After reporting its stopped
    // usage and retiring the live access, only this Run can finish that loan.
    if @local_host.retire_installed_managed_run(adopted) is Err(_) {
      return -9
    }
    held.model_run = None
    held.initial = None
    held.frame = None
  } else if held.parent is Some(parent) {
    match @local_host.abort_request_preparation_after_cleanup(parent) {
      Err(issue) => return mock_project_request_issue(issue)
      Ok(_) => {
        held.parent = None
        held.initial = None
        held.frame = None
      }
    }
  } else if held.initial is Some(initial) {
    match @resources.cleanup_backed_preparation_admission(initial) {
      Err(issue) => return imported_child_issue_code(issue)
      Ok(_) => {
        held.initial = None
        held.frame = None
      }
    }
  }
  if held.portable_execution is Some(execution) {
    match @resources.settle_capacity(value.root, execution.capacity) {
      Ok(_) => held.portable_execution = None
      Err(_) => return -9
    }
  }
  if held.region is Some(region) {
    if held.ticket is Some(ticket) {
      if held.read is Some(read) {
        match
          @resources.return_backed_execution_read_use_after_owner_ack(
            region,
            value.root,
            slot,
            ticket,
            read,
          ) {
          Err(issue) => return mock_project_request_backing_issue(issue)
          Ok(_) => held.read = None
        }
      }
      match
        @resources.settle_backed_execution_after_owner_ack(
          region,
          value.root,
          slot,
          ticket,
          held.final_usage,
        ) {
        Err(issue) => return mock_project_request_backing_issue(issue)
        Ok(_) => held.ticket = None
      }
    }
    match @resources.close_backed_execution_region(region, value.root) {
      Err(issue) => return mock_project_request_backing_issue(issue)
      Ok(false) => return -9
      Ok(true) => held.region = None
    }
  }
  match
    @resources.close_platform_vm_working_capacity_after_cleanup(held.working) {
    Err(issue) => imported_child_issue_code(issue)
    Ok(_) => 0
  }
}
