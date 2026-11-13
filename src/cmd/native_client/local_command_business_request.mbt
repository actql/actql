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
  // Bounded scalar snapshots use this existing Request control envelope. Keep
  // the SAME light parent across its callback; payload retirement severs its
  // heavy aliases, while scalar history remains readable without current I/O.
  let observation = if self.extent_diagnostics {
    match business.request_parent {
      Some(parent) =>
        Some((parent, @local_values.request_preparation_work_calls(parent)))
      None => None
    }
  } else {
    None
  }
  let result = Ok(callback()) catch { ClientStop(message) => Err(message) }
  if observation is Some((parent, before)) {
    record_request_work_delta(
      before,
      @local_values.request_preparation_work_calls(parent),
    )
  }
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
    if business.request_intake_units > 0L {
      // construct_business_intent returned before this entry. Keep the same
      // typed output and retire only its completed transport/construction peak.
      command_preparation_result(
        @local_values.finish_request_native_intake_wire(parent, input, intent).map_err(issue => {
            CommandRequestPreparation(issue)
          },
        ),
        stage=Some("request-intake-return"),
      )
    }
    let (publication, _) = local_command_project_publication(environment)
    match
      @local_host.prepare_native_client_submitted_request_input(
        parent,
        input,
        intent,
        environment,
        publication,
        verify_request_value_policy=match self.project {
          Some(project) =>
            project.mock_declarations.map(original => {
              subject => {
                original.verify_static_request_policy(environment, subject)
              }
            })
          None => None
        },
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
    let run = match self.file_source {
      Some((declaration, row)) => {
        guard @local_host.native_client_submitted_preparation(self.preparation)
          is Computation(prepared) &&
          business.file_capacity is None else {
          stop("LocalBusinessOriginalUnavailable")
        }
        let capacity = prepare_local_native_whole_file_request_module(
          parent,
          input,
          prepared,
          request,
          declaration._retained_declaration,
          row,
          self.installed_contracts,
          self.assets,
        )
        business.file_capacity = Some(capacity)
        if business.request_body is Some(holder) {
          @local_host.return_native_client_submitted_request_body(holder).unwrap_or_else(() => {
              stop("LocalRequestBodyReturnPending")
            },
          )
          |> ignore
          business.request_body = None
        }
        @local_values.begin_request_capture_managed_run(parent, request).unwrap_or_else(() => {
            stop("LocalRequestRunUnavailable")
          },
        )
      }
      None => {
        @local_values.prepare_request_program_module_body(
          parent,
          input,
          self.installed_contracts,
          manifests=native_request_manifests,
          compilation_limits=limits,
          retained_output=false,
          provider_factory=native_request_provider_factory,
          runtime_compilation_limits=Some(limits),
        ).unwrap_or_else(() => stop("LocalModulePreparationUnavailable"))
        @local_values.begin_request_program_managed_run(parent, request).unwrap_or_else(() => {
            stop("LocalRequestRunUnavailable")
          },
        )
      }
    }
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
  current_time : () -> String,
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
    let models = if occurrences.is_empty() {
      []
    } else {
      guard self.original.project is Some(project) &&
        project.mock_declarations is Some(mock) else {
        stop("LocalOriginalModelUnavailable")
      }
      match
        mock.prepare_effect_models(
          parent,
          input,
          occurrences,
          self.environment,
          self.installed_contracts,
        ) {
        Ok(value) => value
        Err(issue) => {
          self.original.retain_primary(CommandBusinessModelGraph(issue))
          stop("LocalOriginalModelGraphUnavailable")
        }
      }
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
    let first = local_effect_first_compilation(
      self.preparation,
      scope,
      configuration_cid,
      namespace_id,
      request_id,
      now,
      until,
      infers=models.map(value => value.graph),
      models~,
      request=Some(request),
      source_inputs~,
    )
    if !models.is_empty() {
      guard business.model_work.is_empty() else {
        stop("LocalOriginalModelWorkUnavailable")
      }
      let compiled = first.model_compiled.unwrap_or_else(() => {
        stop("LocalOriginalModelWorkUnavailable")
      })
      for selected in models {
        let work = match
          @local_host.prepare_native_client_mock_model_work(
            self.capture,
            first.request,
            compiled,
            first.definition,
            selected.graph,
            selected._retained_profile,
            selected._retained_provider,
            selected._retained_limits,
            self.principal,
            namespace_id,
            current_time,
          ) {
          Ok(value) => value
          Err(issue) => {
            self.original.retain_primary(CommandBusinessModel(issue))
            stop("LocalOriginalModelWorkUnavailable")
          }
        }
        // Retain each actual original before the next constructor or the
        // existing execution/Read return can fail. No Model open or I/O yet.
        business.model_work.push(work)
      }
    }
    first
  })
}

///|
// Consume the SAME precompiled Request and nominal identity. Route selection
// precedes its real constructor; a Query refusal can never become Whole.
// Original provider/Plan/module construction must remain on this same backed
// input. No second check/compiler, default limits, Node admission or Root exists.
fn[I] prepare_local_native_whole_file_request_module(
  parent : @local_values.ClientRequestPreparation[I],
  input : I,
  prepared : @run_host.PreparedClientProgram,
  request : @run_host.ClientRequestIdentity,
  declaration : @row_host.RowDeclaration,
  row : LocalProjectMockRowBinding,
  contracts : @local_values.ClientInstalledSequenceContracts,
  assets : @run_host.ClientLocalProductAssets,
) -> @local_values.ClientInstalledWholeSourceCapacity raise ClientStop {
  let route = @local_values.select_installed_source_input(
    prepared, request, 0, 0,
  ).unwrap_or_else(() => stop("LocalSourceInputSelectionUnavailable"))
  guard route is @sourceviews.WholeInputRoute(source) else {
    stop("LocalSourceExecutionProfileNotSupported")
  }
  let page = row.limits.page
  let capacity = @local_values.prepare_installed_whole_source_capacity(
    prepared,
    source,
    declaration,
    contracts,
    @local_values.installed_row_input_policy(
      page.max_rows,
      page.max_bytes,
      page.max_nodes,
      page.max_depth,
      page.max_rows,
    ),
    Some(row.provider.capacity()),
  ).unwrap_or_else(() => stop("LocalSourceCapacityUnavailable"))
  let plan = @local_values.prepare_installed_managed_whole_source_plan(
    prepared,
    request,
    capacity,
    page.max_bytes.to_int64(),
    page.max_bytes.to_int64(),
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    retained_output=false,
    provider_factory=native_request_provider_factory,
  ).unwrap_or_else(() => stop("LocalSourcePlanUnavailable"))
  let limits = @local_values.request_program_compilation_limits(parent, input).unwrap_or_else(() => {
      stop("LocalCompilerLimitsUnavailable")
    },
  )
  @local_values.prepare_request_capture_module_body(
    parent,
    input,
    plan,
    manifests=native_request_manifests,
    compilation_limits=limits,
    provider_factory=native_request_provider_factory,
  ).unwrap_or_else(() => stop("LocalModulePreparationUnavailable"))
  capacity
}
