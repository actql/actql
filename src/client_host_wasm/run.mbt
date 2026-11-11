///|
/// Private installed Host configuration. Its Account Owner, not a Client
/// supplied grant or policy CID, evaluates authorization for each Program.
priv struct StoredRunConfiguration {
  borrow : @buffers.BufferBorrow
  account : @authorization.AdmittedAccountConfiguration
  tuple : @authorization.AccessTuple
  authority_scope_cid : String
  context_cid : String
  policy_cid : String
  run_namespace : String
  source_free_result_policy : (String, String)?
  host_current : Int?
  sdk : StoredSDKRunConfiguration?
}

///|
/// A handle owns the exact input loan before compilation can trap. This
/// record contains references and invocation custody, never durable Run state.
priv struct StoredRun {
  borrow : @buffers.BufferBorrow
  slot : @buffers.BufferSlot
  input_physical : Int
  configuration : Int
  preparation : Int
  mut invoked : Bool
  mut restoration : Int?
  mut physical_start_reserved : Bool
  mut native_source_reserved : Bool
  mut source_free_compute_reserved : Bool
  mut normalization : @local_run.LocalRunNormalization?
  mut outcome : Result[@local_run.LocalRunPlan, @local_run.LocalRunIssue]?
  mut finite_policy : @host.ClientLocalRunPolicyOriginal?
  mut sdk_submission : Int?
  mut saved_snapshot : @host.ClientSavedSubmissionSnapshot?
}

///|
fn required_text(object : @decode.ObjectView, name : String) -> String? {
  match @decode.required(object, name) {
    Ok(cursor) =>
      match @decode.text(cursor) {
        Ok(value) => Some(value)
        Err(_) => None
      }
    Err(_) => None
  }
}

///|
pub fn install_run_configuration(nonce : Int64, input : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "account", "principal", "connection", "resource", "operation", "authority_scope_cid",
      "context_cid", "policy_cid", "namespace", "source_free_result_policy",
    ])
    is Ok(object) &&
    required_text(object, "account") is Some(account_wire) &&
    required_text(object, "principal") is Some(principal) &&
    required_text(object, "connection") is Some(connection) &&
    required_text(object, "resource") is Some(resource) &&
    required_text(object, "operation") is Some(operation) &&
    required_text(object, "authority_scope_cid") is Some(authority_scope_cid) &&
    required_text(object, "context_cid") is Some(context_cid) &&
    required_text(object, "policy_cid") is Some(policy_cid) &&
    required_text(object, "namespace") is Some(run_namespace) &&
    @authorization.admit_account_configuration_json(account_wire) is Ok(account) else {
    return -30
  }
  // The installed Host supplies the genuine policy original. This field is
  // not a publisher grant; Source-backed Runs keep their checked Source policy.
  guard @decode.required(object, "source_free_result_policy")
    is Ok(policy_cursor) else {
    return -30
  }
  let source_free_result_policy = if @decode.is_null(policy_cursor) {
    None
  } else {
    guard @decode.closed_object(policy_cursor, ["cid", "body"]) is Ok(original) &&
      required_text(original, "cid") is Some(cid) &&
      required_text(original, "body") is Some(body) &&
      @host.admit_source_free_result_policy_body(cid, body, 65536, 8192, 64)
      is Ok(_) else {
      return -30
    }
    Some((cid, body))
  }
  let handle = value.next_handle
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  value.run_configurations[handle] = {
    borrow,
    account,
    tuple: { principal, connection, resource, operation, },
    authority_scope_cid,
    context_cid,
    policy_cid,
    run_namespace,
    source_free_result_policy,
    host_current: None,
    sdk: None,
  }
  value.next_handle += 1
  handle
}

///|
/// Product assembly uses original current material; no Account/scope/context
/// or policy CID supplied by Python can stand in for that existing Owner.
pub fn install_current_run_configuration(
  nonce : Int64,
  current : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.host_currents.get(current) is Some(original) &&
    original.material is Some(material) &&
    original.principal is Some(principal) &&
    original.connection is Some(connection) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  let account = match
    @host.client_local_adopted_current_account(material, original.store) {
    Ok(account) => account
    Err(issue) => return host_current_issue(issue)
  }
  let body = match
    @host.client_local_adopted_authority_scope_body(
      material,
      original.store,
      principal,
      connection,
    ) {
    Ok(body) => body
    Err(issue) => return host_current_issue(issue)
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["namespace", "source_free_result_policy"])
    is Ok(object) &&
    required_text(object, "namespace") is Some(run_namespace) &&
    @decode.required(object, "source_free_result_policy") is Ok(policy_cursor) &&
    @decode.closed_object(policy_cursor, ["cid", "body"]) is Ok(policy_object) &&
    required_text(policy_object, "cid") is Some(cid) &&
    required_text(policy_object, "body") is Some(policy_body) &&
    @host.admit_source_free_result_policy_body(
      cid, policy_body, 65536, 8192, 64,
    )
    is Ok(_) else {
    return -30
  }
  // Native's existing product setup uses this original authority scope as the
  // authorization context and the actual admitted Account CID as its policy.
  let authority_scope_cid = "sha256:" + @sha.hex(body)
  let handle = value.next_handle
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  value.run_configurations[handle] = {
    borrow,
    account,
    tuple: { principal, connection, resource: "run", operation: "submit", },
    authority_scope_cid,
    context_cid: authority_scope_cid,
    policy_cid: account.configuration_cid(),
    run_namespace,
    source_free_result_policy: Some((cid, policy_body)),
    host_current: Some(current),
    sdk: None,
  }
  value.next_handle += 1
  handle
}

///|
/// Recheck the existing original current supplier before protected Core work.
/// Low-level installed configurations retain their original trusted Host use;
/// product Local assembly never falls back to that raw input entry.
fn run_configuration_current(
  value : Instance,
  configuration : StoredRunConfiguration,
) -> Result[Unit, Int] {
  match configuration.host_current {
    None => Ok(())
    Some(handle) => {
      let code = validate_host_current(value.nonce, handle)
      if code == 0 {
        Ok(())
      } else {
        Err(code)
      }
    }
  }
}

///|
/// The issued handle precedes compilation. Reservation neither accepts a
/// Submission nor invokes Source, Compute, Model, Effect or durable storage.
pub fn reserve_run(
  nonce : Int64,
  configuration : Int,
  preparation : Int,
  input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.run_configurations.contains(configuration) &&
    value.preparations.get(preparation) is Some(prepared) &&
    stored_preparation_input(prepared) is Some(_) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  if value.next_handle == 2147483647 {
    return -4
  }
  let handle = value.next_handle
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  value.runs[handle] = {
    borrow,
    slot,
    input_physical: physical,
    configuration,
    preparation,
    invoked: false,
    restoration: None,
    physical_start_reserved: false,
    native_source_reserved: false,
    source_free_compute_reserved: false,
    normalization: None,
    outcome: None,
    finite_policy: None,
    sdk_submission: None,
    saved_snapshot: None,
  }
  value.next_handle += 1
  handle
}

///|
/// Compilation/readiness is not durable Run acceptance or physical start.
/// A interrupted invocation cannot silently recompile under the same handle.
pub fn prepare_run(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(handle) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    value.preparations.get(record.preparation) is Some(preparation) &&
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
  // Product finite configuration has a separate original-request entry. It
  // must never accept caller-supplied absolute adoption-time deadlines.
  if configuration.sdk is Some(_) {
    return -3
  }
  if record.restoration is Some(_) {
    return -3
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  if record.outcome is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  guard input_cursor(value, record.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "caller_request_id", "run_id", "created_at", "valid_until",
    ])
    is Ok(object) &&
    required_text(object, "caller_request_id") is Some(caller_request_id) &&
    required_text(object, "run_id") is Some(run_id) &&
    required_text(object, "created_at") is Some(created_at) &&
    required_text(object, "valid_until") is Some(valid_until) else {
    return -31
  }
  let prepared = @preparation.local_prepared_program(input)
  let permit = match
    @authorization.bind_dispatch_authorization(
      configuration.account,
      configuration.tuple,
      @authorization.Activation,
      @host.prepared_client_identity(prepared).program_definition_cid,
      configuration.context_cid,
    ) {
    Ok(value) => value
    Err(_) => {
      record.outcome = Some(Err(@local_run.AuthorizationMismatch))
      return 0
    }
  }
  record.outcome = Some(
    if @host.prepared_client_acquisition_count(prepared) == 0 {
      match configuration.source_free_result_policy {
        None => Err(@local_run.Admission(@host.InvalidResultPolicy))
        Some(original_policy) =>
          @local_run.prepare_source_free_local_publication_run(
            input,
            configuration.authority_scope_cid,
            caller_request_id,
            permit,
            configuration.account,
            configuration.tuple,
            configuration.context_cid,
            configuration.policy_cid,
            configuration.run_namespace,
            run_id,
            created_at,
            valid_until,
            original_policy,
            submitted=source_submission,
          )
      }
    } else {
      @local_run.prepare_captured_source_local_run(
        input,
        configuration.authority_scope_cid,
        caller_request_id,
        permit,
        configuration.account,
        configuration.tuple,
        configuration.context_cid,
        configuration.policy_cid,
        configuration.run_namespace,
        run_id,
        created_at,
        valid_until,
        submitted=source_submission,
      )
    },
  )
  0
}

///|
/// Restore the original request and codec-retained Run under current installed
/// authorization. This does not reserve a durable dispatch or start a task.
pub fn restore_run(nonce : Int64, handle : Int, materials : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.runs.get(handle) is Some(record) &&
    value.run_configurations.get(record.configuration) is Some(configuration) &&
    value.preparations.get(record.preparation) is Some(preparation) &&
    stored_preparation_input(preparation) is Some(input) &&
    value.restorations.get(materials) is Some(restoration) &&
    restoration.outcome is Some(Ok(restored)) &&
    restoration.expected_definition_cid is Some(definition_cid) else {
    return -2
  }
  match run_configuration_current(value, configuration) {
    Ok(_) => ()
    Err(code) => return code
  }
  if (record.restoration is Some(previous) && previous != materials) ||
    (record.invoked && record.restoration is None) {
    return -3
  }
  if record.outcome is Some(Ok(plan)) && configuration.sdk is Some(_) {
    return match sdk_restored_run_snapshot(value, handle, plan) {
      Ok(_) => 0
      Err(code) => code
    }
  }
  if record.outcome is Some(_) {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.restoration = Some(materials)
  record.invoked = true
  let retained_request = if configuration.sdk is Some(sdk) {
    guard restoration.sdk_configuration == Some(record.configuration) &&
      preparation.restoration == Some(materials) &&
      physical_equal(record.slot, restoration.borrow.slot) &&
      restoration.saved_original is Some(original) &&
      physical_equal(
        @preparation.local_prepared_program(input),
        @host.client_task_run_materials_retained_program(
          @host.client_saved_task_materials_input(original),
        ),
      ) else {
      return -35
    }
    let snapshot = match sdk_restoration_snapshot(value, restoration) {
      Ok(value) => value
      Err(code) => return code
    }
    let submitted = @host.client_saved_submission_record(snapshot)
    guard @host.client_saved_submission_run_row(snapshot) is Some(row) &&
      @host.decode_client_run_journal_row_with_observation_originals(row.body)
      is Ok((saved, Some(policy_wire), Some(_))) &&
      @publication.publication_contract_identity(saved.definition) ==
      definition_cid else {
      return -35
    }
    let policy = match
      @host.admit_client_local_run_policy_original(
        @utf8.encode(policy_wire),
        sdk.profile,
        submitted.reference,
        saved.request,
        saved.definition,
        sdk.adoption_cid,
        @publication.local_sdk_result_read_selection_cid(sdk.read),
      ) {
      Ok(value) => value
      Err(_) => return -35
    }
    record.finite_policy = Some(policy)
    record.sdk_submission = restoration.sdk_submission
    record.saved_snapshot = Some(snapshot)
    saved.request
  } else {
    guard @buffers.buffer_wire(value.pool, record.slot) is Some(bytes) else {
      return -5
    }
    let request_wire = @utf8.decode(bytes) catch { _ => return -12 }
    match @host.admit_client_request_identity_record_wire(request_wire) {
      Ok(value) => value
      Err(_) => return -31
    }
  }
  let permit = match
    @authorization.bind_dispatch_authorization(
      configuration.account,
      configuration.tuple,
      @authorization.Activation,
      @host.prepared_client_identity(@preparation.local_prepared_program(input)).program_definition_cid,
      configuration.context_cid,
    ) {
    Ok(permit) => permit
    Err(_) => {
      record.outcome = Some(Err(@local_run.AuthorizationMismatch))
      return 0
    }
  }
  // The original request's Source domain is independent of the SDK profile.
  let source_submission = if @host.client_request_input_cid(retained_request) !=
    @host.source_free_caller_input_intent_cid() {
    guard preparation.submitted is Some(original) else { return -35 }
    Some(original)
  } else {
    None
  }
  let outcome = if @host.prepared_client_acquisition_count(
      @preparation.local_prepared_program(input),
    ) ==
    0 {
    @local_run.restore_source_free_local_run_from_materials(
      input,
      restored,
      definition_cid,
      retained_request,
      configuration.authority_scope_cid,
      permit,
      configuration.account,
      configuration.tuple,
      configuration.context_cid,
      configuration.policy_cid,
      submitted=source_submission,
    )
  } else {
    @local_run.restore_captured_source_local_run_from_materials(
      input,
      restored,
      definition_cid,
      retained_request,
      configuration.authority_scope_cid,
      permit,
      configuration.account,
      configuration.tuple,
      configuration.context_cid,
      configuration.policy_cid,
      submitted=source_submission,
    )
  }
  record.outcome = Some(
    if configuration.sdk is Some(_) {
      match outcome {
        Ok(plan) =>
          @local_run.restore_source_free_local_run_policy_original(
            plan,
            restoration.saved_original.unwrap(),
          )
        Err(issue) => Err(issue)
      }
    } else {
      outcome
    },
  )
  0
}

///|
/// Fresh original saved rows for an already restored Run. This reuses the
/// canonical codec Owner and original Journal binding rather than manufacturing
/// a first-admission row candidate or treating a prior successful read as current.
fn sdk_restored_run_snapshot(
  value : Instance,
  run : Int,
  plan : @local_run.LocalRunPlan,
) -> Result[@host.ClientSavedSubmissionSnapshot, Int] {
  guard value.runs.get(run) is Some(record) &&
    record.outcome is Some(Ok(held)) &&
    physical_equal(held, plan) &&
    record.restoration is Some(restoration_handle) &&
    value.restorations.get(restoration_handle) is Some(restoration) &&
    restoration.outcome is Some(Ok(materials)) &&
    restoration.saved_original is Some(original) &&
    record.saved_snapshot is Some(prior) &&
    physical_equal(
      @local_run.local_run_prepared(plan),
      @host.client_task_run_materials_retained_program(
        @host.client_saved_task_materials_input(original),
      ),
    ) else {
    return Err(-2)
  }
  let snapshot = match sdk_restoration_snapshot(value, restoration) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  guard @host.client_saved_submission_run_row(snapshot) is Some(row) else {
    return Err(-35)
  }
  if @local_run.validate_local_saved_snapshot_rows(
      plan,
      prior,
      row,
      @host.client_saved_submission_row(snapshot),
    )
    is Err(_) {
    return Err(-35)
  }
  let checked = match
    @host.bind_client_saved_submission_task_materials(snapshot, materials) {
    Ok(value) => value
    Err(_) => return Err(-35)
  }
  let saved = @host.client_saved_submission_record(
    @host.client_saved_task_materials_snapshot(checked),
  )
  guard saved.run_admission is Some((request, definition, _)) &&
    @host.client_request_identity_relation(
      request,
      @local_run.local_run_request(plan),
    )
    is @host.SameRequest &&
    definition == @local_run.local_run_definition_cid(plan) else {
    return Err(-35)
  }
  record.saved_snapshot = Some(snapshot)
  Ok(snapshot)
}

///|
/// Private readiness codes are not public diagnostic classifications.
pub fn run_prepared(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) && value.runs.get(handle) is Some(record) else {
    return -2
  }
  match record.outcome {
    Some(Ok(_)) => 0
    Some(Err(_)) => -32
    None => -33
  }
}

///|
pub fn close_run(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) && value.runs.get(handle) is Some(record) else {
    return -2
  }
  if value.materials.values().any(material => material.run == handle) ||
    value.physical_starts.values().any(start => start.run == handle) ||
    value.native_sources.values().any(source => source.run == handle) {
    return -9
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.runs.remove(handle) |> ignore
  }
  result
}

///|
pub fn close_run_configuration(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.run_configurations.get(handle) is Some(record) else {
    return -2
  }
  if value.client_checks.values().any(report => report.configuration == handle) ||
    value.journal_observations
    .values()
    .any(child => child.configuration == handle) ||
    value.computes
    .values()
    .any(compute => compute.current_configuration == Some(handle)) ||
    value.materials
    .values()
    .any(material => {
      material.submission is Some(submission) &&
      submission.current_configuration == handle
    }) ||
    value.submissions.values().any(record => record.configuration == handle) ||
    value.publishers
    .values()
    .any(publisher => publisher.configuration == handle) ||
    value.tasks.values().any(task => task.current_configuration == handle) ||
    value.runs.values().any(run => run.configuration == handle) ||
    value.physical_starts
    .values()
    .any(start => start.current_configuration == handle) {
    return -9
  }
  let result = status(@buffers.return_buffer_borrow(value.pool, record.borrow))
  if result == 0 {
    value.run_configurations.remove(handle) |> ignore
  }
  result
}
