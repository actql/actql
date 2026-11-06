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
fn LocalCommandPreparationOriginal::prepare_business_request(
  self : LocalCommandPreparationOriginal,
  capture : @local_host.NativeLocalJournalCapture,
  input : @run_host.ClientSubmittedIntent,
  environment : @checked.CheckEnvironment,
) -> @local_host.NativeClientSubmittedPreparation raise ClientStop {
  guard self.business is Some(business) &&
    business.request_input is Some(original) &&
    physical_equal(original, input) &&
    business.request_initial is Some(initial) &&
    business.request_parent is None else {
    stop("LocalBusinessOriginalUnavailable")
  }
  self.with_business_request(capture, () => {
    let parent = @local_values.begin_backed_request_preparation(
      initial,
      input,
      @local_values.client_local_resource_policy(),
    ).unwrap_or_else(() => stop("LocalRequestPreparationUnavailable"))
    business.request_parent = Some(parent)
    // The original public environment has no alias substitution, exactly as
    // the old CLI query Context. Resource entry precedes all Catalog/lowering.
    let publication = @source_publication.prepare_published_query_environment(
      environment,
      "{\"environmentCid\":\"" +
      @checked.checking_environment_cid(environment) +
      "\",\"aliases\":[]}",
    ).unwrap_or_else(() => stop("InvalidLocalQueryContext"))
    match
      @local_host.prepare_native_client_submitted_request(
        parent, input, environment, publication,
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
    physical_equal(input, self.intent) else {
    stop("LocalBusinessOriginalUnavailable")
  }
  self.original.with_business_request(self.capture, () => {
    let limits = @local_values.request_program_compilation_limits(parent, input).unwrap_or_else(() => {
        stop("LocalCompilerLimitsUnavailable")
      },
    )
    @local_values.prepare_request_program_compilation(
      parent,
      input,
      self.installed_contracts,
      manifests=native_request_manifests,
      compilation_limits=limits,
      retained_output=false,
      provider_factory=native_request_provider_factory,
    ).unwrap_or_else(() => stop("LocalCompilationNotReady"))
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
    physical_equal(input, self.intent) &&
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
  })
}
