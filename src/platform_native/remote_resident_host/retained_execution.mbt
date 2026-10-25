///|
pub(all) enum ResidentRetainedExecutionIssue {
  Host(ResidentHostIssue)
  Input(@output.NativeRemoteRetainedTaskInputIssue)
  Compute(ResidentSourceComputeIssue)
  Inventory(@publication.PublicationInventoryIssue)
  EffectMaterials(@host.ClientEffectRunMaterialsIssue)
  EffectDispatch(@host.ClientEffectSourceDispatchIssue)
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
  restore_input : (@host.ClientRunMaterials, @remote.RemoteInputBinding) -> Result[
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
  release_retired_input? : (() -> Bool)? = None,
) -> Result[ResidentExecuted, ResidentRetainedExecutionFailure] {
  execute_resident_retained_attempt_owned(
    journal,
    execution,
    material,
    current,
    attempt_identity,
    claimant,
    executor_entry,
    (request, binding, materials) => {
      let rebuilt = match rebuild_materials(admission, request, materials) {
        Ok(value) => value
        Err(refusal) =>
          return Err(retained_execution_failed(Host(Refused(refusal))))
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
      let compute_failure : Ref[ResidentSourceComputeIssue?] = Ref(None)
      let executor = match
        install_resident_retained_compute_executor(
          rebuilt,
          configuration,
          input,
          material,
          request,
          codec,
          input_limits,
          current,
          execution.limits.output,
          observe_failure=issue => compute_failure.val = Some(issue),
          release_retired_input~,
        ) {
        Ok(value) => value
        Err(issue) => return Err(retained_execution_failed(Compute(issue)))
      }
      guard resident_linear_task_index(rebuilt, request) is Some(task) else {
        return Err(
          retained_execution_failed(Host(Refused(@resident.UnsupportedTask))),
        )
      }
      let result_definition_cid = if @strategy.graph_result_task(
          @host.prepared_client_graph(rebuilt.prepared),
          0,
        ) ==
        Some(task) {
        let inventory = match
          @publication.prepare_checked_publication_inventory(
            @host.prepared_client_identity(rebuilt.prepared).program_definition_cid,
            @host.client_task_compilation_result_names(compilation),
            [0],
          ) {
          Ok(value) => value
          Err(issue) => return Err(retained_execution_failed(Inventory(issue)))
        }
        match
          @publication.checked_publication_inventory_definition_cid(
            inventory, 0,
          ) {
          Ok(value) => Some(value)
          Err(issue) => return Err(retained_execution_failed(Inventory(issue)))
        }
      } else {
        None
      }
      Ok({
        input,
        executor,
        result_definition_cid,
        compute_failure,
        run_current: () => {
          @resident.check_resident_materials_current(rebuilt, current_time())
          is Ok(_)
        },
      })
    },
  )
}

///|
/// Execute the original saved Effect consumer envelope. Rebuilding materials
/// preserves the original Run and authorization lifetime. Input restoration
/// must use the existing producer/receiver Owners; it creates no new dispatch,
/// borrow or reservation. Computation completion does not publish an Effect
/// Result or imply approval: its private output remains owned by Runtime.
// Profile-bound materials require independent producer context; absent context
// remains an ordinary Owner refusal, never a request copied from candidate wire.
pub fn execute_resident_effect_retained_attempt(
  journal : @journal.Journal,
  execution : ResidentExecution,
  admission : ResidentRunAdmission,
  effect_limits : @host.ClientEffectComputationLimits,
  configuration : ResidentSourceComputeConfiguration,
  restore_input : (@host.ClientEffectRunMaterials, @remote.RemoteInputBinding) -> Result[
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
  retain_computation? : (ResidentSourceCompute) -> Unit,
  producer_context? : (@journal.Journal, @remote.DispatchRequest)? = None,
) -> Result[ResidentExecuted, ResidentRetainedExecutionFailure] {
  execute_resident_retained_attempt_owned(
    journal,
    execution,
    material,
    current,
    attempt_identity,
    claimant,
    executor_entry,
    (request, binding, wire) => {
      let rebuilt = match
        (match producer_context {
          Some((producer_journal, producer)) =>
            retained_effect_consumer_materials(
              producer_journal, producer, request, wire, admission, effect_limits,
            )
          None =>
            retained_effect_direct_materials(
              wire, request, admission, effect_limits,
            )
        }) {
        Ok(value) => value
        Err(issue) => return Err(retained_execution_failed(issue))
      }
      let fragment = match @host.issue_client_effect_task_fragment(rebuilt, 1) {
        Ok(value) => value
        Err(issue) =>
          return Err(retained_execution_failed(EffectDispatch(issue)))
      }
      if @remote.dispatch_request_task_scope(request) !=
        (
          @publication.publication_contract_identity(rebuilt.run_definition),
          @host.client_task_fragment_node_id(fragment),
        ) {
        return Err(retained_execution_failed(Input(InvalidBinding)))
      }
      guard admission.source is Some((source_ref, source_contract_cid)) &&
        configuration.source.source_ref == source_ref &&
        configuration.source.source_contract_cid == source_contract_cid else {
        return Err(retained_execution_failed(Compute(Source(ForeignInput))))
      }
      // Resolve the original checked Source before restoring any receiver.
      match
        prepare_resident_effect_source_requirement(
          rebuilt.prepared,
          0,
          0,
          configuration.installed_contracts,
          configuration.values_body,
          Some(configuration.source.fragment_contract_body),
          source_ref,
          source_contract_cid,
        ) {
        Ok(_) => ()
        Err(issue) =>
          return Err(retained_execution_failed(Compute(Source(issue))))
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
      let compute_failure : Ref[ResidentSourceComputeIssue?] = Ref(None)
      let executor = match
        install_resident_effect_retained_compute_executor(
          rebuilt,
          configuration,
          input,
          material,
          request,
          codec,
          input_limits,
          current,
          execution.limits.output,
          observe_failure=issue => compute_failure.val = Some(issue),
          retain_computation?,
        ) {
        Ok(value) => value
        Err(issue) => return Err(retained_execution_failed(Compute(issue)))
      }
      Ok({
        input,
        executor,
        result_definition_cid: None,
        compute_failure,
        run_current: () => {
          @host.client_effect_run_start_current(
            rebuilt.allowed,
            rebuilt.run_definition,
            current_time(),
          )
        },
      })
    },
  )
}

///|
// The legacy direct path has no independent original producer context. A
// candidate's absent request cannot select a trusted absent expected request.
fn retained_effect_direct_materials(
  body : String,
  consumer : @remote.DispatchRequest,
  admission : ResidentRunAdmission,
  limits : @host.ClientEffectComputationLimits,
) -> Result[@host.ClientEffectRunMaterials, ResidentRetainedExecutionIssue] {
  let materials = match
    @host.admit_client_effect_run_materials(
      body,
      @remote.dispatch_request_task_scope(consumer).0,
      admission.expressions,
      admission.operations,
      admission.manifests,
      admission.limits,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(EffectMaterials(issue))
  }
  if materials.normalization is Some(_) {
    return Err(EffectMaterials(Normalization(UnverifiedOriginalMaterials)))
  }
  Ok(materials)
}

///|
priv struct ResidentRetainedExecutionPlan {
  input : @output.NativeRemoteRetainedTaskInput
  executor : @output.NativeRemoteStandardTaskExecutor
  result_definition_cid : String?
  compute_failure : Ref[ResidentSourceComputeIssue?]
  run_current : () -> Bool
}

///|
// Material families prepare their existing checked Owner; the journal,
// physical start, completion and cleanup boundary is shared.
fn execute_resident_retained_attempt_owned(
  journal : @journal.Journal,
  execution : ResidentExecution,
  material : @transfer_client.NativeRemoteDestinationMaterialUse,
  current : @output.NativeRemoteRetainedInputCurrent,
  attempt_identity : String,
  claimant : String,
  executor_entry : ((String) -> Bool)?,
  prepare : (@remote.DispatchRequest, @remote.RemoteInputBinding, String) -> Result[
    ResidentRetainedExecutionPlan,
    ResidentRetainedExecutionFailure,
  ],
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
  let plan = match prepare(request, binding, materials) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let input = plan.input
  let executor = plan.executor
  let result_definition_cid = plan.result_definition_cid
  let compute_failure = plan.compute_failure
  let accepted_run_current = (plan.run_current)()
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
    Err(issue) =>
      return Err(retained_execution_failed(Compute(Source(Standard(issue)))))
  }
  match
    runtime.guard_executor_start(() => {
      accepted_run_current &&
      (plan.run_current)() &&
      @output.validate_native_remote_retained_task_input_borrow(
        input, material, current,
      )
      is Ok(_)
    }) {
    Ok(_) => ()
    Err(issue) =>
      return retained_execution_failed_after_runtime(
        runtime,
        Host(Runtime(issue)),
      )
  }
  match runtime.claim_starts_as(claimant) {
    Ok(_) => ()
    Err(issue) =>
      return retained_execution_failed_after_runtime(
        runtime,
        Host(Runtime(issue)),
      )
  }
  match executor_entry {
    Some(observer) =>
      match runtime.observe_executor_entry(observer) {
        Ok(_) => ()
        Err(issue) =>
          return retained_execution_failed_after_runtime(
            runtime,
            Host(Runtime(issue)),
          )
      }
    None => ()
  }
  match runtime.start(request, binding) {
    Ok(completion) =>
      Ok({ runtime, completion, request, result_definition_cid, })
    Err(@runtime.StartAuthorizationRejected) =>
      retained_execution_failed_after_runtime(
        runtime,
        Host(Refused(@resident.NotCurrent)),
      )
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
