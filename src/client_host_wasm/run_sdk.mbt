///|
/// Selected metadata references, not current permission or Run acceptance.
priv struct StoredSDKRunConfiguration {
  profile : @host.ClientLocalRunPolicyProfile
  read : @publication.LocalSDKResultReadSelection
  adoption_cid : String
  store_authority_cid : String
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
  )
}

///|
/// Same-snapshot physical candidate. The existing current/Account and complete
/// journal validators remain mandatory, independently of the candidate bytes.
fn sdk_run_append_candidate(
  value : Instance,
  configuration : StoredRunConfiguration,
  plan : @local_run.LocalRunPlan,
  original : @host.ClientLocalRunPolicyOriginal,
  task_materials : @local_run.LocalRunTaskMaterialsOriginal?,
) -> Result[@host.ClientRunJournalAppend, Int] {
  let scan = (table, key) => {
    sdk_run_journal_port(value, configuration, 0, table, key)
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
    @host.prepare_client_run_journal_append(
      @local_run.local_run_request(plan),
      @local_run.local_run_definition(plan),
      1024,
      scan,
      read,
      submission_append_run_inspection,
      () => {
        @host.inspect_client_empty_cancellation_inventory(
          1024, scan, read, -31, -42,
        )
      },
      -31,
      local_policy_original=Some(original),
      run_observation_originals=Some(observation),
      task_materials_cid=task_materials.map(
        @local_run.local_run_task_materials_original_cid,
      ),
      publication_policy_originals=task_materials.map(
        @local_run.local_run_task_materials_original_policy,
      ),
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
  let selection = match
    @publication.admit_local_sdk_result_read_selection(
      read_wire,
      @host.client_local_run_policy_profile_cid(profile),
      "sha256:" + @sha.hex(originals.result_policy),
    ) {
    Ok(selection) => selection
    Err(_) => return -32
  }
  // Validate the input relation before reserving a configuration handle. A
  // negative return must not orphan a newly installed configuration loan.
  guard value.copies.get(input) is Some((slot, _)) &&
    input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["namespace", "source_free_result_policy"])
    is Ok(fields) &&
    required_text(fields, "namespace") == Some("local") &&
    @decode.required(fields, "source_free_result_policy") is Ok(original_policy) &&
    @decode.closed_object(original_policy, ["cid", "body"]) is Ok(policy_fields) &&
    required_text(policy_fields, "cid") == Some("sha256:" + @sha.hex(policy)) &&
    required_text(policy_fields, "body") is Some(policy_text) &&
    @utf8.encode(policy_text) == policy else {
    return -32
  }
  let code = validate_host_current(nonce, current_handle)
  if code != 0 {
    return code
  }
  let handle = install_current_run_configuration(nonce, current_handle, input)
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
    }),
  }
  handle
}

///|
/// Lookup is mandatory before finite issuance. Saved-ready observations return
/// code 2 without issuing a Policy or another Run; restore uses its own Owner.
pub fn prepare_sdk_run(nonce : Int64, handle : Int, submission : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(handle) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    configuration.sdk is Some(sdk) &&
    value.submissions.get(submission) is Some(observation) &&
    observation.configuration == record.configuration &&
    observation.kind == 3 &&
    value.preparations.get(record.preparation) is Some(preparation) &&
    preparation.submitted is Some(original) &&
    stored_preparation_input(preparation) is Some(input) else {
    return -2
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
    @host.client_submitted_intent_cid(
      @preparation.local_submitted_preparation_intent(original),
    ) {
    return -45
  }
  if retained.run_admission is Some(_) {
    record.sdk_submission = Some(submission)
    return 2
  }
  let prepared = @preparation.local_prepared_program(input)
  let request_result = match source_submission {
    Some(original) =>
      @preparation.local_submitted_preparation_request(
        original,
        configuration.authority_scope_cid,
        @host.client_submission_reference_record_request_id(retained.reference),
      )
    None =>
      @host.prepare_source_free_client_request_identity(
        prepared,
        configuration.authority_scope_cid,
        @host.client_submission_reference_record_request_id(retained.reference),
      )
  }
  let request = match request_result {
    Ok(request) => request
    Err(_) => return -31
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
    return 0
  }
  if record.invoked {
    return -33
  }
  // Physical clock and chosen Run id only: Python supplies no expiry/Policy.
  guard input_cursor(value, record.slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["run_id", "now"]) is Ok(fields) &&
    required_text(fields, "run_id") is Some(run_id) &&
    required_number(fields, "now") is Some(now) &&
    now >= 0.0 &&
    now <= 9007199254740991.0 &&
    now.floor() == now &&
    @values.epoch_milliseconds_timestamp(now.to_int64()) is Some(at) else {
    return -31
  }
  let epoch = @host.client_submission_epoch_token_body(
    @host.client_submission_reference_record_epoch(retained.reference),
  )
  guard @host.submission_epoch_validity(epoch, now) is Ok(Admissible) else {
    return -46
  }
  record.invoked = true
  record.sdk_submission = Some(submission)
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
  let plan = match
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
    Ok(value) => value
    Err(issue) => {
      record.outcome = Some(Err(issue))
      return 0
    }
  }
  let request = @local_run.local_run_request(plan)
  let definition = @local_run.local_run_definition(plan)
  let packet = match
    @host.bind_client_local_run_policy_original(
      sdk.profile,
      retained.reference,
      request,
      definition,
      retention,
      at,
      sdk.adoption_cid,
      @publication.local_sdk_result_read_selection_cid(sdk.read),
    ) {
    Ok(value) => value
    Err(_) => return -31
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  record.finite_policy = Some(packet)
  record.outcome = Some(Ok(plan))
  0
}
