///|
/// Selected metadata references, not current permission or Run acceptance.
priv struct StoredSDKRunConfiguration {
  profile : @host.ClientLocalRunPolicyProfile
  read : @publication.LocalSDKResultReadSelection
  adoption_cid : String
  store_authority_cid : String
  portable_model : Int?
}

///|
fn sdk_run_append_issue(issue : @host.ClientRunJournalAppendIssue[Int]) -> Int {
  match issue {
    Observation(code) => code
    ChangedIntent => -45
    ForeignRun => -35
    CapacityExceeded => -4
    InvalidOriginal => -31
    Encoding(_) => -34
  }
}

///|
fn sdk_run_journal_port(
  value : Instance,
  configuration : StoredRunConfiguration,
  mode : Int,
  table : String,
  key : String,
  expected_body_length? : Int? = None,
) -> Result[@host.ClientJournalPhysicalRow?, Int] {
  guard configuration.sdk is Some(_) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) else {
    return Err(-32)
  }
  physical_journal_row(
    current.physical,
    () => run_configuration_current(value, configuration),
    mode,
    table,
    key,
    expected_body_length~,
  )
}

///|
// Exact point observation on the existing physical Run Definition index.
// An absent supplier keeps the original compatibility census; a malformed or
// refused observation from a selected supplier remains the original failure.
fn sdk_physical_journal_boolean(
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  table : String,
  key : String,
) -> Result[Bool?, Int] {
  match read(table, key) {
    Ok(None) => Ok(None)
    Ok(Some(row)) if row.key == key && row.revision == 0L =>
      match row.body {
        b"0" => Ok(Some(false))
        b"1" => Ok(Some(true))
        _ => Err(-32)
      }
    Ok(Some(_)) => Err(-32)
    Err(code) => Err(code)
  }
}

///|
fn sdk_task_material_count_matches(
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, Int],
  count : Int,
) -> Result[Bool?, Int] {
  sdk_physical_journal_boolean(
    read,
    "client_sqlite_task_material_count",
    count.to_string(),
  )
}

///|
/// Same-snapshot physical candidate on the installed indexed Store. The
/// actual writer enforces Definition uniqueness inside the original append.
fn sdk_run_append_candidate(
  value : Instance,
  configuration : StoredRunConfiguration,
  plan : @local_run.LocalRunPlan,
  original : @host.ClientLocalRunPolicyOriginal,
  task_materials : @local_run.LocalRunTaskMaterialsOriginal?,
) -> Result[@host.ClientRunJournalAppend, Int] {
  guard configuration.host_current is Some(handle) &&
    value.host_currents.get(handle) is Some(current) else {
    return Err(-32)
  }
  if physical_journal_schema(current.physical) != 1 {
    return Err(-41)
  }
  let read = (table, key) => {
    sdk_run_journal_port(value, configuration, 1, table, key)
  }
  let observation = match
    @host.capture_client_run_observation_originals(
      @local_run.local_run_compiled(plan),
      @local_run.local_run_definition(plan),
    ) {
    Ok(original) => original
    Err(_) => return Err(-31)
  }
  match
    @host.prepare_indexed_client_run_journal_append(
      @local_run.local_run_request(plan),
      @local_run.local_run_definition(plan),
      1024,
      read,
      submission_append_run_inspection,
      -31,
      original,
      observation,
      task_materials.map(@local_run.local_run_task_materials_original_cid),
      task_materials.map(@local_run.local_run_task_materials_original_policy),
    ) {
    Ok(Append(candidate)) => Ok(candidate)
    // A saved Run cannot be backfilled into a preparing Submission or replaced
    // with a newly issued Policy. Its original recovery path is separate.
    Ok(Retained(_)) => Err(-35)
    Err(issue) => Err(sdk_run_append_issue(issue))
  }
}

///|
fn sdk_selected_original(
  value : Instance,
  current : StoredHostCurrent,
  name : String,
  max_bytes : Int,
) -> Result[Bytes, Int] {
  let key = "file:" + name
  match
    physical_journal_row(
      current.physical,
      () => host_current_physical(value, current),
      1,
      "client_local_settings",
      key,
    ) {
    Ok(Some(row)) if row.key == key &&
      row.revision == 0L &&
      row.body.length() <= max_bytes => Ok(row.body)
    Ok(_) => Err(-32)
    Err(code) => Err(code)
  }
}

///|
/// The actual same-Store selection and current Owner supply every original.
/// No SDK profile/body/CID parameter can stand in for these observations.
pub fn install_sdk_run_configuration(
  nonce : Int64,
  current_handle : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.host_currents.get(current_handle) is Some(current) &&
    current.account_original is Some(account) &&
    current.adoption_original is Some(adoption) else {
    return -2
  }
  let read = name => sdk_selected_original(value, current, name, 65536)
  // Metadata admission is fenced on both sides by the existing current Owner.
  let code = validate_host_current(nonce, current_handle)
  if code != 0 {
    return code
  }
  let dependencies = match read("retention.json") {
    Ok(bytes) => bytes
    Err(code) => return code
  }
  let retention = match read("retention-policy.json") {
    Ok(bytes) => bytes
    Err(code) => return code
  }
  let store = match read("store.json") {
    Ok(bytes) => bytes
    Err(code) => return code
  }
  let policy = match read("result-policy.json") {
    Ok(bytes) => bytes
    Err(code) => return code
  }
  let originals : @host.ClientLocalProductCommonOriginals = {
    account,
    retention_dependencies: dependencies,
    retention_policy: retention,
    store,
    result_policy: policy,
  }
  let profile_wire = match
    sdk_selected_original(value, current, "run-policy-profile.json", 8192) {
    Ok(bytes) => @utf8.decode(bytes) catch { _ => return -31 }
    Err(code) => return code
  }
  let profile = match
    @host.admit_client_local_run_policy_profile(profile_wire, originals) {
    Ok(profile) => profile
    Err(_) => return -32
  }
  let read_wire = match
    sdk_selected_original(value, current, "sdk-read.json", 8192) {
    Ok(bytes) => @utf8.decode(bytes) catch { _ => return -31 }
    Err(code) => return code
  }
  // Validate the input relation before reserving a configuration handle. A
  // negative return must not orphan a newly installed configuration loan.
  guard value.copies.get(input) is Some((slot, _)) &&
    input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "namespace", "source_free_result_policy", "mock_project", "local_project",
      "portable_model",
    ])
    is Ok(fields) &&
    required_text(fields, "namespace") == Some("local") &&
    @decode.required(fields, "source_free_result_policy") is Ok(original_policy) &&
    @decode.closed_object(original_policy, ["cid", "body"]) is Ok(policy_fields) &&
    required_text(policy_fields, "cid") == Some("sha256:" + @sha.hex(policy)) &&
    required_text(policy_fields, "body") is Some(policy_text) &&
    @utf8.encode(policy_text) == policy else {
    return -32
  }
  let portable_model = match @decode.lookup(fields, "portable_model") {
    None => None
    Some(_) => {
      guard @decode.lookup(fields, "mock_project") is None &&
        required_int32(fields, "portable_model") is Some(handle) &&
        installed_portable_model_task(value, handle, current_handle)
        is Some(installed) else {
        return -32
      }
      if @decode.lookup(fields, "local_project") is Some(_) {
        guard required_int32(fields, "local_project") is Some(local_handle) &&
          original_local_project_inputs(value, local_handle)
          is Some(file_inputs) &&
          value.original_metadata.get(installed.parent) is Some(task) &&
          task.project is Some(ModelTask(typed)) &&
          file_inputs.model_registry == Some(typed.parent) &&
          file_inputs.model_configuration == Some(handle) else {
          return -32
        }
      }
      Some(handle)
    }
  }
  let connection = match @decode.lookup(fields, "local_project") {
    None => "local"
    Some(_) => {
      guard required_int32(fields, "local_project") is Some(handle) &&
        original_local_project_inputs(value, handle) is Some(_) &&
        current.connection is Some(connection) else {
        return -32
      }
      connection
    }
  }
  let selection = match
    @publication.admit_local_sdk_result_read_selection(
      read_wire,
      @host.client_local_run_policy_profile_cid(profile),
      "sha256:" + @sha.hex(originals.result_policy),
      connection~,
      permits_accepted_run_policy=@decode.lookup(fields, "local_project")
        is Some(_),
    ) {
    Ok(selection) => selection
    Err(_) => return -32
  }
  let code = validate_host_current(nonce, current_handle)
  if code != 0 {
    return code
  }
  let handle = install_selected_current_run_configuration(
    nonce, current_handle, input, portable_model,
  )
  if handle <= 0 {
    return handle
  }
  let configuration = value.run_configurations[handle]
  value.run_configurations[handle] = {
    ..configuration,
    sdk: Some({
      profile,
      read: selection,
      adoption_cid: "sha256:" + @sha.hex(adoption),
      store_authority_cid: "sha256:" + @sha.hex(store),
      portable_model,
    }),
  }
  handle
}

///|
/// Lookup is mandatory before finite issuance. Kind 2 requires restoration.
/// A prepared Effect returns 3 so its row transport can borrow the Run clock.
pub fn prepare_sdk_run(nonce : Int64, handle : Int, submission : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(handle) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    configuration.sdk is Some(sdk) &&
    value.submissions.get(submission) is Some(observation) &&
    observation.configuration == record.configuration &&
    observation.kind == 3 &&
    value.preparations.get(record.preparation) is Some(preparation) else {
    return -2
  }
  let portable = match sdk.portable_model {
    None => None
    Some(_) => {
      guard retained_sdk_portable_request(
          value,
          preparation,
          record.configuration,
          configuration,
          submission,
        )
        is Some(original) &&
        !observation.output_closed else {
        return -35
      }
      if original.model_run_handle is Some(other) && other != handle {
        return -33
      }
      Some(original)
    }
  }
  if preparation.kind == RETAINED_MOCK_REQUEST_KIND && portable is None {
    if preparation.project_request is Some({ effect_plan: Some(_), .. }) {
      let code = prepare_sdk_mock_effect(
        value, handle, record, preparation, configuration, submission, observation,
      )
      return if code == 0 { 3 } else { code }
    }
    let code = prepare_sdk_whole_file(
      value, handle, record, preparation, configuration, submission, observation,
    )
    return if code == 0 { 4 } else { code }
  }
  let (prepared, intent) = match portable {
    Some({ model_input: Some(input), parent: Some(parent), .. }) => {
      guard @resources.preparation_body_borrow_value(input) is Some(prepared) &&
        @local_host.request_submitted_intent_original(parent, preparation.slot)
        is Some(intent) else {
        return -35
      }
      (prepared, intent)
    }
    Some(_) => return -35
    None => {
      guard preparation.submitted is Some(original) &&
        stored_preparation_input(preparation) is Some(input) else {
        return -2
      }
      (
        @preparation.local_prepared_program(input),
        @preparation.local_submitted_preparation_intent(original),
      )
    }
  }
  let source_submission = if preparation.source is Some(_) {
    guard stored_preparation_source_submission(value, record.preparation)
      is Some(original) else {
      return -35
    }
    Some(original)
  } else {
    None
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  if record.restoration is Some(_) ||
    (record.sdk_submission is Some(previous) && previous != submission) {
    return -3
  }
  let saved = match
    observe_submission_append(value, observation, configuration) {
    Ok(@host.Retained(saved)) => saved
    Ok(@host.Append(_)) => return -35
    Err(code) => return code
  }
  let retained = @host.client_saved_submission_record(saved)
  if @host.client_submitted_intent_cid(retained.intent) !=
    @host.client_submitted_intent_cid(intent) {
    return -45
  }
  if retained.run_admission is Some(_) {
    record.sdk_submission = Some(submission)
    return 2
  }
  if portable is Some({ submission: Some((_, before)), .. }) {
    let prior = @host.client_saved_submission_row(before)
    let observed = @host.client_saved_submission_row(saved)
    if observed.key != prior.key ||
      observed.revision != prior.revision ||
      observed.body != prior.body {
      return -35
    }
  }
  let request_result = match (portable, source_submission) {
    (Some(original), None) =>
      prepare_retained_portable_identity(
        value, original, prepared, configuration, retained,
      )
    (Some(_), Some(_)) => return -35
    (None, Some(original)) =>
      @preparation.local_submitted_preparation_request(
        original,
        configuration.authority_scope_cid,
        @host.client_submission_reference_record_request_id(retained.reference),
      ).map_err(_ => -31)
    (None, None) =>
      @host.prepare_source_free_client_request_identity(
        prepared,
        configuration.authority_scope_cid,
        @host.client_submission_reference_record_request_id(retained.reference),
      ).map_err(_ => -31)
  }
  let request = match request_result {
    Ok(request) => request
    Err(code) => return code
  }
  // Inspect the original logical request before issuing a Plan, Run or Policy.
  // A preparing Submission plus an already saved Run is not fresh acceptance.
  match
    @host.read_client_retained_run_journal(
      request,
      (table, key) => sdk_run_journal_port(value, configuration, 1, table, key),
      submission_append_run_inspection,
      -31,
    ) {
    Ok(None) => ()
    Ok(Some(_)) => return -35
    Err(issue) => return sdk_run_append_issue(issue)
  }
  if record.outcome is Some(_) {
    return if portable is Some(_) { 5 } else { 0 }
  }
  if record.invoked {
    return -33
  }
  // Physical clock and chosen Run id only: Python supplies no expiry/Policy.
  let (run_id, _, at) = match
    sdk_first_run_clock(value, record, retained.reference) {
    Err(code) => return code
    Ok(original) => original
  }
  record.invoked = true
  record.sdk_submission = Some(submission)
  if portable is Some(original) {
    original.model_run_handle = Some(handle)
  }
  let retention = match
    @host.issue_client_local_run_retention_policy(sdk.profile, at) {
    Ok(value) => value
    Err(_) => return -31
  }
  let until = match @publication.result_retention_available_until(retention) {
    Ok(value) => value
    Err(_) => return -31
  }
  let permit = match
    @authorization.bind_dispatch_authorization(
      configuration.account,
      configuration.tuple,
      @authorization.Activation,
      @host.prepared_client_identity(prepared).program_definition_cid,
      configuration.context_cid,
    ) {
    Ok(value) => value
    Err(_) => return -32
  }
  guard configuration.source_free_result_policy is Some(policy) else {
    return -32
  }
  let (plan, portable_submission) = if portable
    is Some({ parent: Some(parent), .. } as original) {
    let slot = preparation.slot
    match
      @local_host.reserve_request_portable_model_run_metadata(
        parent,
        slot,
        request,
        configuration.context_cid,
        configuration.policy_cid,
        configuration.run_namespace,
        run_id,
        at,
        until,
      ) {
      Ok(_) => ()
      Err(Preparation(issue)) => return mock_project_request_issue(issue)
      Err(_) => return -31
    }
    match
      @local_host.issue_request_portable_model_run_metadata(
        parent,
        slot,
        permit,
        configuration.account,
        configuration.tuple,
      ) {
      Ok(_) => ()
      Err(MetadataPreparation(issue)) =>
        return mock_project_request_issue(issue)
      Err(_) => return -31
    }
    match
      @local_host.prepare_request_portable_model_run_materials(
        parent, slot, policy,
      ) {
      Ok(_) => ()
      Err(Preparation(issue)) => return mock_project_request_issue(issue)
      Err(_) => return -31
    }
    if @checked.source_execution_count(
        @strategy.graph_program(@host.prepared_client_graph(prepared)),
      ) >
      0 {
      let code = prepare_portable_model_file_request(
        value,
        original,
        preparation.environment,
        configuration,
        parent,
        slot,
        request,
      )
      if code != 0 {
        return code
      }
    }
    match
      @local_run.bind_original_portable_model_local_run(
        parent,
        slot,
        request,
        permit,
        configuration.account,
        configuration.tuple,
        configuration.context_cid,
      ) {
      Ok((plan, submitted)) => (plan, Some(submitted))
      Err(_) => return -31
    }
  } else {
    guard stored_preparation_input(preparation) is Some(input) else {
      return -2
    }
    match
      @local_run.prepare_source_free_local_publication_run(
        input,
        configuration.authority_scope_cid,
        @host.client_submission_reference_record_request_id(retained.reference),
        permit,
        configuration.account,
        configuration.tuple,
        configuration.context_cid,
        configuration.policy_cid,
        configuration.run_namespace,
        run_id,
        at,
        until,
        policy,
        submitted=source_submission,
      ) {
      Ok(value) => (value, None)
      Err(issue) => {
        record.outcome = Some(Err(issue))
        return 0
      }
    }
  }
  let request = @local_run.local_run_request(plan)
  let definition = @local_run.local_run_definition(plan)
  let read_selection = match portable {
    Some(
      {
        portable_execution: Some({ file: Some({ read_selection, .. }), .. }),
        ..
      }
    ) => read_selection
    _ => sdk.read
  }
  let packet = match
    @host.bind_client_local_run_policy_original(
      sdk.profile,
      retained.reference,
      request,
      definition,
      retention,
      at,
      sdk.adoption_cid,
      @publication.local_sdk_result_read_selection_cid(read_selection),
    ) {
    Ok(value) => value
    Err(_) => return -31
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  if portable_submission is Some(submitted) {
    preparation.submitted = Some(submitted)
    preparation.outcome = Some(
      Ok(@preparation.local_submitted_preparation_input(submitted)),
    )
  }
  record.finite_policy = Some(packet)
  record.outcome = Some(Ok(plan))
  if portable is Some(_) {
    5
  } else {
    0
  }
}

///|
// Common selection for the admitted File parent before and after transfer.
// The consumer still checks the held or transferred nominal Plan.
fn sdk_whole_file_project_parent(
  value : Instance,
  preparation : StoredPreparation,
  configuration : StoredRunConfiguration,
) -> @local_host.ClientRequestPreparation[@buffers.BufferSlot]? {
  guard preparation.kind == RETAINED_MOCK_REQUEST_KIND &&
    configuration.sdk is Some(_) &&
    preparation.project_request is Some(held) &&
    held.effect_plan is None &&
    held.target_check_input is None &&
    held.submission is Some(_) &&
    held.parent is Some(parent) &&
    held.whole_file_source is Some(source) &&
    project_request_configuration(value, preparation.environment)
    is Some((original_configuration, check)) &&
    physical_equal(configuration, original_configuration) else {
    return None
  }
  let bound = match source {
    MockFile(original) =>
      check.runtime_cid is Some(_) &&
      configuration.mock_project == Some(check.project) &&
      value.original_metadata.get(check.project) is Some(metadata) &&
      metadata.produced &&
      !metadata.output_closed &&
      metadata.project is Some(MockInputs(file)) &&
      physical_equal(file, original.file) &&
      file.inputs is Some(_) &&
      file.data is Some(_) &&
      file.data_body is Some(body) &&
      physical_equal(body, original.bytes)
    LocalCsv(original) =>
      configuration.local_project == Some(check.project) &&
      check.local_file is Some(local_check) &&
      original.matches_check(local_check)
  }
  if bound {
    Some(parent)
  } else {
    None
  }
}

///|
fn sdk_whole_file_request(
  value : Instance,
  preparation : StoredPreparation,
  configuration : StoredRunConfiguration,
) -> @host.ClientRequestIdentity? {
  guard sdk_whole_file_project_parent(value, preparation, configuration)
    is Some(parent) else {
    return None
  }
  @local_host.inspect_request_whole_file_plan_original(
    parent,
    preparation.slot,
    (request, _, _) => request,
  )
}

///|
// The preparing snapshot belongs to the held Request. Transport retirement
// only releases its output buffer. The caller checks currentness and decides
// whether its operation still needs that output.
fn sdk_whole_file_preparing_submission(
  value : Instance,
  preparation : StoredPreparation,
  configuration : Int,
  handle : Int,
) -> (StoredSubmissionProjection, @host.ClientSavedSubmissionSnapshot)? {
  guard preparation.project_request is Some(held) &&
    held.submission is Some((original_handle, original)) &&
    original_handle == handle &&
    value.submissions.get(handle) is Some(observation) &&
    observation.kind == 3 &&
    observation.configuration == configuration &&
    observation.produced &&
    observation.append_plan is Ready(@host.Retained(snapshot)) &&
    physical_equal(snapshot, original) &&
    submission_snapshot_is_preparing(snapshot) else {
    return None
  }
  Some((observation, snapshot))
}

///|
// Admit one original Run handle against the same preparing receipt, current
// Account, and backed File Plan. The existing Store stage remains responsible
// for constructing and committing rows. No Run or Source starts here.
fn prepare_sdk_whole_file(
  value : Instance,
  handle : Int,
  run : StoredRun,
  preparation : StoredPreparation,
  configuration : StoredRunConfiguration,
  submission : Int,
  observation : StoredSubmissionProjection,
) -> Int {
  guard sdk_whole_file_request(value, preparation, configuration)
    is Some(request) &&
    preparation.project_request is Some(held) &&
    held.parent is Some(parent) &&
    held.access is Some(access) &&
    run.restoration is None &&
    !observation.output_closed &&
    sdk_whole_file_preparing_submission(
      value,
      preparation,
      run.configuration,
      submission,
    )
    is Some((original_observation, snapshot)) &&
    physical_equal(original_observation, observation) else {
    return -35
  }
  if held.whole_file_sdk_run is Some(previous) && previous != handle {
    return -33
  }
  let saved = @host.client_saved_submission_record(snapshot)
  guard @host.client_submission_reference_matches_request(
      saved.reference,
      request,
    ) &&
    @authorization.bind_dispatch_authorization(
      configuration.account,
      configuration.tuple,
      @authorization.Activation,
      @host.client_request_program_cid(request),
      configuration.context_cid,
    )
    is Ok(_) else {
    return -32
  }
  match sdk_first_run_clock(value, run, saved.reference) {
    Err(code) => return code
    Ok(_) => ()
  }
  fn current() -> Result[Unit, Int] {
    match run_configuration_current(value, configuration) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    guard value.runs.get(handle) is Some(active_run) &&
      physical_equal(active_run, run) &&
      value.preparations.get(run.preparation) is Some(active_preparation) &&
      physical_equal(active_preparation, preparation) &&
      sdk_whole_file_request(value, preparation, configuration)
      is Some(original) &&
      physical_equal(original, request) &&
      sdk_whole_file_preparing_submission(
        value,
        preparation,
        run.configuration,
        submission,
      )
      is Some((active_observation, active_snapshot)) &&
      physical_equal(active_observation, observation) &&
      !observation.output_closed &&
      physical_equal(active_snapshot, snapshot) else {
      return Err(-9)
    }
    Ok(())
  }
  match current() {
    Err(code) => return code
    Ok(_) => ()
  }
  match
    retained_project_request_snapshot(
      value,
      preparation,
      run.configuration,
      configuration,
    ) {
    Ok((original, saved)) if original == submission &&
      physical_equal(saved, snapshot) => ()
    Ok(_) => return -35
    Err(code) => return code
  }
  match
    @host.read_client_retained_run_journal(
      request,
      (table, key) => sdk_run_journal_port(value, configuration, 1, table, key),
      submission_append_run_inspection,
      -31,
    ) {
    Ok(None) => ()
    Ok(Some(_)) => return -35
    Err(issue) => return sdk_run_append_issue(issue)
  }
  match current() {
    Err(code) => return code
    Ok(_) => ()
  }
  if run.invoked || held.whole_file_sdk_run is Some(_) {
    return if (
        held.whole_file_sdk_phase is PlanReady ||
        held.whole_file_sdk_phase is RowsReserved(_)
      ) &&
      held.whole_file_sdk_run == Some(handle) &&
      run.sdk_submission == Some(submission) {
      0
    } else {
      -33
    }
  }
  run.invoked = true
  run.sdk_submission = Some(submission)
  held.whole_file_sdk_run = Some(handle)
  match
    @local_host.fund_platform_vm_request_whole_file_plan(
      parent,
      preparation.slot,
      request,
      access,
    ) {
    Err(issue) => return mock_project_request_backing_issue(issue)
    Ok(_) => ()
  }
  match current() {
    Err(code) => return code
    Ok(_) => ()
  }
  held.whole_file_sdk_phase = PlanReady
  0
}

///|
// Use the same installed clock packet and original epoch for either Plan kind.
fn sdk_first_run_clock(
  value : Instance,
  record : StoredRun,
  reference : @host.ClientSubmissionReferenceRecord,
) -> Result[(String, Double, String), Int] {
  guard input_cursor(value, record.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["run_id", "now"]) is Ok(fields) &&
    required_text(fields, "run_id") is Some(run_id) &&
    required_number(fields, "now") is Some(now) &&
    now >= 0.0 &&
    now <= 9007199254740991.0 &&
    now.floor() == now &&
    @values.epoch_milliseconds_timestamp(now.to_int64()) is Some(at) else {
    return Err(-31)
  }
  let epoch = @host.client_submission_epoch_token_body(
    @host.client_submission_reference_record_epoch(reference),
  )
  guard @host.submission_epoch_validity(epoch, now) is Ok(Admissible) else {
    return Err(-46)
  }
  Ok((run_id, now, at))
}

///|
// These four bounded bodies share the same Local SDK issuers.
fn fund_sdk_first_run_definition(
  configuration : StoredRunConfiguration,
  run_id : String,
  before_body : (String, Int, Int, Int) -> Bool,
) -> Bool {
  let definition_bound = Int64::min(
    100000L,
    2048L +
    6L *
    (
      run_id.length().to_int64() +
      configuration.run_namespace.length().to_int64()
    ),
  ).to_int()
  before_body("retention_policy_read", 2048, 32, 2) &&
  before_body("prepared_invocation_read", 2048, 32, 2) &&
  before_body("run_authorization_read", 2048, 32, 2) &&
  before_body("run_definition_read", definition_bound, 32, 2)
}

///|
// The first row material owner calls this only within its original funded
// stage. It borrows the original Run clock packet and selected checked Task
// compilation. No submission candidate, Source read or journal write occurs.
fn issue_sdk_whole_file_materials(
  value : Instance,
  handle : Int,
  rows_handle : Int,
  run : StoredRun,
  preparation : StoredPreparation,
  configuration : StoredRunConfiguration,
  original : @host.ClientSavedSubmissionSnapshot,
  same_stage_current : () -> Result[Unit, Int],
  fund_body : (String, Int, Int, Int) -> Result[Unit, Int],
  fund_policy : (Int64, Int64) -> Result[Unit, Int],
) -> Result[
  (
    @host.ClientCapturedTaskRunMaterials,
    @host.ClientLocalRunPolicyOriginal,
    Double,
  ),
  Int,
] {
  guard configuration.sdk is Some(sdk) &&
    preparation.project_request is Some(held) &&
    held.parent is Some(parent) &&
    sdk_whole_file_rows_handle(value, handle, run.configuration) ==
    Some(rows_handle) &&
    run.invoked &&
    run.sdk_submission is Some(submission) &&
    run.restoration is None &&
    sdk_whole_file_preparing_submission(
      value,
      preparation,
      run.configuration,
      submission,
    )
    is Some((_, snapshot)) &&
    physical_equal(snapshot, original) &&
    sdk_whole_file_request(value, preparation, configuration) is Some(request) else {
    return Err(-35)
  }
  fn current() -> Result[Unit, Int] {
    same_stage_current()
    .bind(_ => run_configuration_current(value, configuration))
    .bind(_ => same_stage_current())
    .bind(_ => {
      guard value.runs.get(handle) is Some(active_run) &&
        physical_equal(active_run, run) &&
        value.preparations.get(run.preparation) is Some(active_preparation) &&
        physical_equal(active_preparation, preparation) &&
        sdk_whole_file_rows_handle(value, handle, run.configuration) ==
        Some(rows_handle) &&
        sdk_whole_file_preparing_submission(
          value,
          preparation,
          run.configuration,
          submission,
        )
        is Some((_, still)) &&
        physical_equal(still, original) &&
        sdk_whole_file_request(value, preparation, configuration)
        is Some(active_request) &&
        physical_equal(active_request, request) else {
        return Err(-9)
      }
      Ok(())
    })
  }
  match current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let reference = @host.client_saved_submission_record(original).reference
  guard @host.client_submission_reference_matches_request(reference, request) &&
    @authorization.bind_dispatch_authorization(
      configuration.account,
      configuration.tuple,
      @authorization.Activation,
      @host.client_request_program_cid(request),
      configuration.context_cid,
    )
    is Ok(_) else {
    return Err(-32)
  }
  let (run_id, now, at) = match sdk_first_run_clock(value, run, reference) {
    Err(issue) => return Err(issue)
    Ok(clock) => clock
  }
  let funding_failure : Ref[Int?] = Ref(None)
  let before_body = (purpose, bytes, nodes, depth) => {
    if funding_failure.val is Some(_) {
      return false
    }
    match
      current()
      .bind(_ => fund_body(purpose, bytes, nodes, depth))
      .bind(_ => current()) {
      Ok(_) => true
      Err(issue) => {
        funding_failure.val = Some(issue)
        false
      }
    }
  }
  if !fund_sdk_first_run_definition(configuration, run_id, before_body) {
    return Err(funding_failure.val.unwrap_or(-4))
  }
  guard @local_host.inspect_request_whole_file_plan_original(
      parent,
      preparation.slot,
      (identity, prepared, tasks) => (identity, prepared, tasks),
    )
    is Some((identity, prepared, tasks)) &&
    physical_equal(identity, request) else {
    return Err(-35)
  }
  guard @host.issue_client_local_run_retention_policy(sdk.profile, at)
    is Ok(retention) &&
    @publication.result_retention_available_until(retention) is Ok(until) &&
    @host.issue_client_task_compiled_run(
      prepared,
      tasks,
      configuration.context_cid,
      configuration.policy_cid,
      until,
    )
    is Ok(compiled) &&
    @host.issue_client_compiled_run_definition(
      compiled,
      configuration.run_namespace,
      run_id,
      at,
      until,
    )
    is Ok(definition) else {
    return Err(-34)
  }
  let projected = @local_host.issue_request_whole_file_run_materials(
    parent,
    preparation.slot,
    request,
    compiled,
    definition,
    before_body,
  )
  if funding_failure.val is Some(issue) {
    return Err(issue)
  }
  let materials = match projected {
    Err(_) => return Err(-34)
    Ok(value) => value
  }
  match current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let read_selection = if held.whole_file_source is Some(MockFile(_)) {
    guard sdk_accepted_file_read_selection_capacity(sdk)
      is Some((held, scratch)) else {
      return Err(-4)
    }
    match
      fund_policy(held, scratch)
      .bind(_ => current())
      .bind(_ => issue_sdk_accepted_file_read_selection(configuration, sdk)) {
      Ok(selection) => selection
      Err(issue) => return Err(issue)
    }
  } else {
    guard @publication.local_sdk_result_read_selection_uses_accepted_run_policy(
      sdk.read,
    ) else {
      return Err(-32)
    }
    sdk.read
  }
  guard @host.client_local_run_policy_original_construction_capacity(
      definition, retention,
    )
    is Some((retained, scratch)) else {
    return Err(-4)
  }
  match fund_policy(retained, scratch).bind(_ => current()) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @host.bind_client_local_run_policy_original(
      sdk.profile,
      reference,
      request,
      definition,
      retention,
      at,
      sdk.adoption_cid,
      @publication.local_sdk_result_read_selection_cid(read_selection),
    )
    is Ok(policy) else {
    return Err(-31)
  }
  current().map(_ => (materials, policy, now))
}
