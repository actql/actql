///|
pub(all) enum ResidentRetainedExecutionIssue {
  Host(ResidentHostIssue)
  Input(@output.NativeRemoteRetainedTaskInputIssue)
  Compute(ResidentSourceComputeIssue)
  Inventory(@publication.PublicationInventoryIssue)
}

///|
/// Pre-admission failure leaves the pinned borrow with its caller. Once a
/// Runtime has acquired input cleanup, a failed close retains that same
/// Runtime here. Neither case permits another attempt or Source acquisition.
pub(all) struct ResidentRetainedExecutionFailure {
  issue : ResidentRetainedExecutionIssue
  pending_runtime : @runtime.NativeRemoteRuntime?
}

///|
fn retained_execution_failed(
  issue : ResidentRetainedExecutionIssue,
) -> ResidentRetainedExecutionFailure {
  { issue, pending_runtime: None, }
}

///|
fn retained_execution_failed_after_runtime(
  runtime : @runtime.NativeRemoteRuntime,
  issue : ResidentRetainedExecutionIssue,
) -> Result[ResidentExecuted, ResidentRetainedExecutionFailure] {
  match runtime.close() {
    Ok(_) => Err(retained_execution_failed(issue))
    Err(_) => Err({ issue, pending_runtime: Some(runtime), })
  }
}

///|
/// Execute the exact saved consumer envelope in the existing holder. Its
/// restore-input port reissues the checked edge against these rebuilt materials
/// and re-admits the saved binding against live producer and Transfer Owners.
/// It creates no physical borrow, reservation or dispatch acceptance.
/// The holder keeps the producer, receiver and their cleanup duties separate.
pub fn execute_resident_retained_attempt(
  journal : @journal.Journal,
  execution : ResidentExecution,
  admission : ResidentRunAdmission,
  configuration : ResidentSourceComputeConfiguration,
  restore_input : (
    @host.ClientRunMaterials,
    @remote.RemoteInputBinding,
  ) -> Result[
    @output.NativeRemoteRetainedTaskInput,
    @output.NativeRemoteRetainedTaskInputIssue,
  ],
  material : @transfer_client.NativeRemoteDestinationMaterialUse,
  codec : @output.NativeRemoteStandardRowCodec,
  input_limits : @output.NativeRemoteStandardTransferSourceLimits,
  current : @output.NativeRemoteRetainedInputCurrent,
  attempt_identity : String,
  claimant : String,
  current_time : () -> String,
  executor_entry : ((String) -> Bool)?,
) -> Result[ResidentExecuted, ResidentRetainedExecutionFailure] {
  let envelope = match journal.dispatch_envelope(attempt_identity) {
    Ok(Some(value)) => value
    Ok(None) => return Err(retained_execution_failed(Host(EnvelopeMissing)))
    Err(issue) => return Err(retained_execution_failed(Host(Journal(issue))))
  }
  let dispatch = match @remote.admit_remote_poll_dispatch_json(envelope) {
    Ok(value) => value
    Err(_) => return Err(retained_execution_failed(Host(EnvelopeMissing)))
  }
  let request = @remote.remote_poll_dispatch_request(dispatch)
  guard @remote.remote_poll_dispatch_run_materials(dispatch) is Some(materials) &&
    @remote.dispatch_request_attempt_identity(request) is Ok(identity) &&
    identity == attempt_identity else {
    return Err(retained_execution_failed(Host(EnvelopeMissing)))
  }
  let binding = @remote.remote_poll_dispatch_input_binding(dispatch)
  if @transfer_client.destination_material_use_reader_id(material) !=
    @remote.dispatch_request_identity(request) {
    return Err(retained_execution_failed(Input(ForeignTransfer)))
  }
  match journal.require(request) {
    Ok(_) => ()
    Err(issue) => return Err(retained_execution_failed(Host(Journal(issue))))
  }
  let rebuilt = match rebuild_materials(admission, request, materials) {
    Ok(value) => value
    Err(refusal) => return Err(retained_execution_failed(Host(Refused(refusal))))
  }
  guard rebuilt.compilation is @host.Tasks(compilation) &&
    admission.source is Some((source_ref, source_contract_cid)) &&
    configuration.source.source_ref == source_ref &&
    configuration.source.source_contract_cid == source_contract_cid else {
    return Err(retained_execution_failed(Compute(Source(ForeignInput))))
  }
  let input = match restore_input(rebuilt, binding) {
    Ok(value) => value
    Err(issue) => return Err(retained_execution_failed(Input(issue)))
  }
  let expected = @output.native_remote_retained_task_input_binding(input)
  if @remote.remote_input_binding_body(binding) !=
    @remote.remote_input_binding_body(expected) ||
    !@remote.remote_input_binding_matches_dispatch(expected, request) {
    return Err(retained_execution_failed(Input(InvalidBinding)))
  }
  match
    @output.validate_native_remote_retained_task_input_borrow(
      input, material, current,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(retained_execution_failed(Input(issue)))
  }
  // The original Run lifetime and the independent live input custody are
  // checked again at Runtime's exclusive start boundary, not from saved JSON.
  let accepted_run_current = @resident.check_resident_materials_current(
      rebuilt, current_time(),
    )
    is Ok(_)
  let compute_failure : Ref[ResidentSourceComputeIssue?] = Ref(None)
  let executor = match
    install_resident_retained_compute_executor(
      rebuilt, configuration, input, material, request, codec, input_limits,
      current, execution.limits.output,
      observe_failure=issue => compute_failure.val = Some(issue),
    ) {
    Ok(value) => value
    Err(issue) => return Err(retained_execution_failed(Compute(issue)))
  }
  let inventory = match
    @publication.prepare_checked_publication_inventory(
      @host.prepared_client_identity(rebuilt.prepared).program_definition_cid,
      @host.client_task_compilation_result_names(compilation),
      [0],
    ) {
    Ok(value) => value
    Err(issue) => return Err(retained_execution_failed(Inventory(issue)))
  }
  let result_definition_cid = match
    @publication.checked_publication_inventory_definition_cid(inventory, 0) {
    Ok(value) => value
    Err(issue) => return Err(retained_execution_failed(Inventory(issue)))
  }
  let runtime = match
    @output.open_native_remote_standard_site_runtime(
      execution.site,
      execution.active_runtime,
      execution.operation_capability_cid,
      execution.issuer_capability_cid,
      [executor],
      journal,
      execution.bundles,
      execution.budgets,
    ) {
    Ok(value) => value
    Err(issue) => return Err(retained_execution_failed(Compute(Source(Standard(issue)))))
  }
  match
    runtime.guard_executor_start(() => {
      accepted_run_current &&
      @resident.check_resident_materials_current(rebuilt, current_time())
      is Ok(_) &&
      @output.validate_native_remote_retained_task_input_borrow(
        input, material, current,
      )
      is Ok(_)
    }) {
    Ok(_) => ()
    Err(issue) =>
      return retained_execution_failed_after_runtime(runtime, Host(Runtime(issue)))
  }
  match runtime.claim_starts_as(claimant) {
    Ok(_) => ()
    Err(issue) =>
      return retained_execution_failed_after_runtime(runtime, Host(Runtime(issue)))
  }
  match executor_entry {
    Some(observer) =>
      match runtime.observe_executor_entry(observer) {
        Ok(_) => ()
        Err(issue) =>
          return retained_execution_failed_after_runtime(runtime, Host(Runtime(issue)))
      }
    None => ()
  }
  match runtime.start(request, binding) {
    Ok(completion) =>
      Ok({ runtime, completion, request, result_definition_cid: Some(result_definition_cid), })
    Err(@runtime.StartAuthorizationRejected) =>
      retained_execution_failed_after_runtime(runtime, Host(Refused(@resident.NotCurrent)))
    Err(issue) =>
      retained_execution_failed_after_runtime(
        runtime,
        match compute_failure.val {
          Some(cause) => Compute(cause)
          None => Host(Runtime(issue))
        },
      )
  }
}
