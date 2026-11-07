///|
// The existing fixed Source-free provider selection and compiler manifests.
// These immutable contracts select no Resource/current/permission or callback.
let native_request_provider_factory : (@execution.ExecutionCapacity) -> Array[
  @local_compute.ManagedProvider,
] = _ => []

///|
let native_request_manifests : @run_host.ClientCompilationManifests = @run_host.admit_client_compilation_manifests(
  @compiler_environment.compiler_grammar_manifest_wire(),
  @compiler_environment.compiler_barrier_contract_manifest_wire(),
  10000,
  1000,
  20,
).unwrap()

///|
// Borrow only this retained execution while the original Journal Read is
// suspended. Keep the attempted entry before it can fail. A primary callback
// refusal never becomes success because the original scope return succeeded.
fn[T] LocalCommandPreparationOriginal::with_business_request(
  self : LocalCommandPreparationOriginal,
  capture : @local_host.NativeLocalJournalCapture,
  callback : () -> T raise ClientStop,
) -> T raise ClientStop {
  guard self.host is Some(host) &&
    self.business is Some(business) &&
    self.journal is Some(original) &&
    physical_equal(original, capture) &&
    business.execution is Some(execution) &&
    !business.active &&
    !self.closing &&
    !self.closed else {
    stop("LocalBusinessOriginalUnavailable")
  }
  command_preparation_result(
    capture
    .suspend_original_read_for_preparation()
    .map_err(issue => CommandAdoption(issue)),
    stage=Some("request-suspend"),
  )
  business.active = true
  command_preparation_result(
    host
    .enter_domain_retained_execution(execution)
    .map_err(issue => CommandRetainedExecution(issue)),
    stage=Some("request-enter"),
  )
  let result = Ok(callback()) catch { ClientStop(message) => Err(message) }
  let returned = host
    .leave_domain_retained_execution(execution)
    .map_err(issue => CommandRetainedExecution(issue))
  if returned is Ok(_) {
    business.active = false
  }
  let resumed = if returned is Ok(_) {
    capture
    .resume_original_read_after_preparation()
    .map_err(issue => CommandAdoption(issue))
  } else {
    returned
  }
  match result {
    Err(message) => {
      self.retain_primary(CommandApplication(message))
      if resumed is Err(issue) {
        self.retain_primary(issue)
      }
      stop(message)
    }
    Ok(value) => {
      command_preparation_result(resumed, stage=Some("request-return"))
      value
    }
  }
}

///|
fn LocalCommandPreparationOriginal::begin_business_request(
  self : LocalCommandPreparationOriginal,
  capture : @local_host.NativeLocalJournalCapture,
) -> Unit raise ClientStop {
  guard self.business is Some(business) &&
    business.request_input is Some(input) &&
    business.request_initial is Some(initial) &&
    business.request_parent is None &&
    business.execution is Some(_) &&
    !business.active &&
    self.journal is Some(original) &&
    physical_equal(original, capture) &&
    !self.closing &&
    !self.closed else {
    stop("LocalBusinessOriginalUnavailable")
  }
  // The nominal Request/census controls outlive its payload frame. Construct
  // only this fixed entrance in the existing outer initialization lifetime,
  // while the SAME original Journal Read is suspended. No payload runs here.
  command_preparation_result(
    capture
    .suspend_original_read_for_preparation()
    .map_err(issue => CommandAdoption(issue)),
    stage=Some("request-control-suspend"),
  )
  let prepared = @local_values.begin_backed_request_preparation(
    initial,
    input,
    @local_values.client_local_resource_policy(),
  )
  if prepared is Ok(parent) {
    business.request_parent = Some(parent)
  }
  let resumed = capture
    .resume_original_read_after_preparation()
    .map_err(issue => CommandAdoption(issue))
  match prepared {
    Err(issue) => {
      self.retain_primary(CommandRequestPreparation(issue))
      if resumed is Err(issue) {
        self.retain_primary(issue)
      }
      stop("LocalRequestPreparationUnavailable")
    }
    Ok(_) =>
      command_preparation_result(resumed, stage=Some("request-control-return"))
  }
}

///|
fn LocalCommandPreparationOriginal::prepare_business_request(
  self : LocalCommandPreparationOriginal,
  capture : @local_host.NativeLocalJournalCapture,
  intent : @run_host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
) -> @local_host.NativeClientSubmittedPreparation raise ClientStop {
  guard self.business is Some(business) &&
    business.request_input is Some(input) &&
    business.request_parent is Some(parent) &&
    business.request_intent is None else {
    stop("LocalBusinessOriginalUnavailable")
  }
  business.request_intent = Some(intent)
  self.with_business_request(capture, () => {
    let (publication, _) = local_command_project_publication(environment)
    match
      @local_host.prepare_native_client_submitted_request_input(
        parent, input, intent, environment, publication,
      ) {
      Err(issue) => local_stop_submitted_preparation(issue)
      Ok((preparation, holder)) => {
        business.request_body = Some(holder)
        preparation
      }
    }
  })
}

///|
fn LocalCommandBusinessPreparation::request_compilation(
  self : LocalCommandBusinessPreparation,
) -> @run_host.ClientRunCompilation raise ClientStop {
  guard self.original.business is Some(business) &&
    business.request_parent is Some(parent) &&
    business.request_input is Some(input) &&
    business.request_intent is Some(original_intent) &&
    physical_equal(original_intent, self.intent) else {
    stop("LocalBusinessOriginalUnavailable")
  }
  self.original.with_business_request(self.capture, () => {
    let limits = @local_values.request_program_compilation_limits(parent, input).unwrap_or_else(() => {
        stop("LocalCompilerLimitsUnavailable")
      },
    )
    match
      @local_values.prepare_request_program_compilation(
        parent,
        input,
        self.installed_contracts,
        manifests=native_request_manifests,
        compilation_limits=limits,
        retained_output=false,
        provider_factory=native_request_provider_factory,
      ) {
      Ok(value) => value
      Err(issue) => {
        local_compilation_failure_tags(issue, native_timing_amount)
        stop("LocalCompilationNotReady")
      }
    }
  })
}

///|
fn LocalCommandBusinessPreparation::adopt_request_run(
  self : LocalCommandBusinessPreparation,
  request : @run_host.ClientRequestIdentity,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.request_parent is Some(parent) &&
    business.request_input is Some(input) &&
    business.request_intent is Some(original_intent) &&
    physical_equal(original_intent, self.intent) &&
    business.request_run is None else {
    stop("LocalBusinessOriginalUnavailable")
  }
  self.original.with_business_request(self.capture, () => {
    let limits = @local_values.request_program_compilation_limits(parent, input).unwrap_or_else(() => {
        stop("LocalCompilerLimitsUnavailable")
      },
    )
    @local_values.prepare_request_program_module_body(
      parent,
      input,
      self.installed_contracts,
      manifests=native_request_manifests,
      compilation_limits=limits,
      retained_output=false,
      provider_factory=native_request_provider_factory,
    ).unwrap_or_else(() => stop("LocalModulePreparationUnavailable"))
    let run = @local_values.begin_request_program_managed_run(parent, request).unwrap_or_else(() => {
        stop("LocalRequestRunUnavailable")
      },
    )
    // Retain the original Run before any scope/current return can fail.
    business.request_run = Some(run)
    business.request_parent = None
    business.request_initial = None
    business.request_input = None
    business.request_intent = None
  })
}

///|
// Consume the already checked Effect and its same Request borrow inside the
// original backed execution. This is the first sequence compiler, never a
// second input/check compiler or a durable admission/approval/write permit.
fn LocalCommandBusinessPreparation::compile_effect_first(
  self : LocalCommandBusinessPreparation,
  scope : String,
  configuration_cid : String,
  namespace_id : String,
  request_id : String,
  now : String,
  until : String,
  request : @run_host.ClientRequestIdentity,
) -> LocalEffectFirstCompilation raise ClientStop {
  guard self.original.business is Some(business) &&
    business.request_parent is Some(parent) &&
    business.request_input is Some(input) &&
    business.request_intent is Some(intent) &&
    physical_equal(intent, self.intent) &&
    business.request_body is Some(@local_host.Effect(borrow)) &&
    @local_host.native_client_submitted_preparation(self.preparation)
    is EffectComputation(prepared) &&
    @initial_resources.preparation_body_borrow_value(borrow) is Some(original) &&
    physical_equal(original, prepared) else {
    stop("LocalBusinessOriginalUnavailable")
  }
  self.original.with_business_request(self.capture, () => {
    let occurrences = @run_host.prepared_client_effect_infer_occurrences(
      prepared,
    ).unwrap_or_else(() => stop("LocalOriginalModelUnavailable"))
    let infers = if occurrences.is_empty() {
      []
    } else {
      guard self.original.project is Some(project) &&
        project.mock_declarations is Some(mock) else {
        stop("LocalOriginalModelUnavailable")
      }
      mock.prepare_effect_graphs(
        parent,
        input,
        prepared,
        self.environment,
        self.installed_contracts,
      )
    }
    let direct = @run_host.select_client_effect_direct_acquisition_occurrences(
      prepared, 1000000,
    ).unwrap_or_else(() => stop("LocalOriginalSourceUnavailable"))
    let source_inputs = if @run_host.client_direct_acquisition_occurrence_count(
        direct,
      ) ==
      0 {
      []
    } else {
      guard self.original.project is Some(project) &&
        project.mock_declarations is Some(mock) else {
        stop("LocalOriginalSourceUnavailable")
      }
      mock.prepare_effect_sources(prepared, direct)
    }
    local_effect_first_compilation(
      self.preparation,
      scope,
      configuration_cid,
      namespace_id,
      request_id,
      now,
      until,
      infers~,
      request=Some(request),
      source_inputs~,
    )
  })
}
