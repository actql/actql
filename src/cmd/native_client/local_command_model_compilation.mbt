///|
// The ordinary Request owns the Graphs and Task compilation. The original
// Read owns the adopted Model material through dispatch or command cleanup.
priv struct LocalCommandModelCompilation {
  program : @run_host.PreparedClientProgram
  compilation : @run_host.ClientTaskCompilation
  occurrences : Array[@run_host.ClientInferOccurrence]
  graphs : Array[@run_host.ClientInferPlanGraph]
  bounds : Array[@infer.Limits]
  installations : Array[@local_host.NativeModelHttpInstallation]
}

///|
fn LocalCommandPreparationOriginal::prepare_model_compilation(
  self : Self,
  capture : @local_host.NativeLocalJournalCapture,
  prepared : @run_host.PreparedClientProgram,
  installation : LocalModelHttpInstallationSettings,
  runtime : LocalPackagedRuntime,
) -> LocalCommandModelCompilation? raise ClientStop {
  let count = @run_host.prepared_client_composed_infer_count(prepared).unwrap_or_else(() => {
      stop("LocalOriginalModelUnavailable")
    },
  )
  if count == 0 {
    return None
  }
  guard self.business is Some(business) &&
    business.request_parent is Some(parent) &&
    business.request_input is Some(input) &&
    business.request_body is Some(@local_host.Program(borrow) as body) &&
    @initial_resources.preparation_body_borrow_value(borrow) is Some(original) &&
    physical_equal(original, prepared) else {
    stop("LocalBusinessOriginalUnavailable")
  }
  let occurrences = self.with_business_request(capture, () => {
    // Ordinary intake held the checked Program for normalization and authoring.
    // Switch to the SAME Request's funded Model Plan input before constructing
    // any occurrence/Graph inventory. Cleanup owns whichever borrow is live.
    match @local_host.return_native_client_submitted_request_body(body) {
      Err(_) => stop("LocalRequestBodyReturnPending")
      Ok(_) => business.request_body = None
    }
    let model_body = match
      @local_host.borrow_native_client_model_plan_input(parent, input) {
      Err(issue) => {
        self.retain_primary(CommandRequestPreparation(issue))
        stop("LocalRequestPreparationUnavailable")
      }
      Ok(value) => value
    }
    business.request_body = Some(model_body)
    guard model_body is @local_host.Program(model_input) &&
      @initial_resources.preparation_body_borrow_value(model_input)
      is Some(model_program) &&
      physical_equal(model_program, prepared) &&
      @run_host.prepared_client_composed_infer_occurrences(model_program)
      is Some(occurrences) &&
      occurrences.length() == count else {
      stop("LocalOriginalModelUnavailable")
    }
    occurrences
  })
  let contracts = runtime.installed_contracts
  let limits = local_project_mock_task_limits()
  let configuration = match
    capture.read_model_http_configuration_in_original_read(
      installation.files,
      installation.provider_id,
      installation.response_profile_cid,
      limits,
      execution_file=installation.execution_file,
      policy_file=installation.policy_file,
    ) {
    Ok(value) => value
    Err(issue) => {
      self.retain_primary(CommandBusinessModelHttp(issue))
      stop("LocalModelHttpInstallationRefused")
    }
  }
  let compilation_limits = @run_host.client_standard_pure_compilation_limits()
  let mut selected = None
  for index, occurrence in occurrences {
    let execution = match
      capture.prepare_model_http_execution_in_original_read(
        configuration, occurrence, limits,
      ) {
      Ok(value) => value
      Err(issue) => {
        self.retain_primary(CommandBusinessModelHttp(issue))
        stop("LocalModelHttpExecutionRefused")
      }
    }
    let installed = match
      capture.admit_model_http_installation_in_original_read(
        runtime.physical,
        execution,
        occurrence,
        limits.bodies,
        self.profile.diagnostic_ceiling,
      ) {
      Ok(value) => value
      Err(issue) => {
        self.retain_primary(CommandBusinessModelHttp(issue))
        stop("LocalModelHttpInstallationRefused")
      }
    }
    self.with_business_request(capture, () => {
      let graph = match
        @local_values.prepare_request_model_graph(
          parent,
          input,
          occurrence,
          execution.execution_contract(),
          contracts,
          manifests=native_request_manifests,
          compilation_limits~,
          caller_material=Some(
            native_model_compilation_storage(if index == 0 { count } else { 0 }),
          ),
        ) {
        Ok(graph) => graph
        Err(issue) => {
          self.retain_primary(CommandBusinessModelGraph(issue))
          stop("LocalOriginalModelGraphUnavailable")
        }
      }
      if selected is None {
        selected = Some(
          (Array(capacity=count), Array(capacity=count), Array(capacity=count)),
        )
      }
      let (graphs, providers, bounds) = selected.unwrap()
      let limits = match @infer.prepared_composed_bounds(occurrence, graph) {
        Ok(value) => value
        Err(issue) => {
          self.retain_primary(CommandBusinessModel(@local_host.Model(issue)))
          stop("LocalOriginalModelBoundsUnavailable")
        }
      }
      graphs.push(graph)
      providers.push(installed)
      bounds.push(limits)
    })
  }
  let (graphs, providers, bounds) = selected.unwrap()
  self.with_business_request(capture, () => {
    let result = if count == 1 {
      @local_values.prepare_request_model_compilation(
        parent,
        input,
        graphs[0],
        contracts,
        manifests=native_request_manifests,
        compilation_limits~,
      )
    } else {
      @local_values.prepare_request_models_compilation(
        parent,
        input,
        graphs,
        contracts,
        manifests=native_request_manifests,
        compilation_limits~,
      )
    }
    match result {
      Ok(compilation) =>
        Some({
          program: prepared,
          compilation,
          occurrences,
          graphs,
          bounds,
          installations: providers,
        })
      Err(issue) => {
        self.retain_primary(CommandBusinessModelGraph(issue))
        stop("LocalOriginalModelCompilationUnavailable")
      }
    }
  })
}

///|
fn LocalCommandBusinessPreparation::configured_model_compilation(
  self : Self,
  prepared : @run_host.PreparedClientProgram,
) -> LocalCommandModelCompilation? raise ClientStop {
  guard self.model_compilation is Some(model) else { return None }
  if !physical_equal(model.program, prepared) {
    stop("LocalBusinessOriginalUnavailable")
  }
  Some(model)
}

///|
// Fund the selected Native arrays and caller records before the first Graph
// returns. Each member separately funds the real Common bounds selection.
fn native_model_compilation_storage(
  count : Int,
) -> @execution.PreparationRepresentationUnits raise ClientStop {
  let bounds = @infer.prepared_composed_bounds_construction()
  if count == 0 {
    return bounds
  }
  let arrays = @execution.preparation_array_representation(
    if count == 1 {
      8L
    } else {
      7L
    },
    7L * count.to_int64() + (if count == 1 { 1L } else { 0L }),
    true,
  ).unwrap_or_else(() => stop("LocalOriginalModelBoundsUnavailable"))
  @execution.compose_preparation_representation([
    bounds,
    arrays,
    {
      // Compilation holder, member-selection tuple, Run Scope holder,
      // quantity record and their optional carriers. The grouped adoption
      // also passes the original Scope array in an optional argument. Each
      // provider owns open/retain/cleanup and two step callbacks, their tuple
      // and optional carriers, a retained Read slot and one OutputUse.
      // The configured Result limits retain the exact Plan, capacity, limits
      // and simultaneous extent pair. The Work vector and the simultaneous
      // publication constructor's original execution vector are funded above.
      // The task driver and physical cleanup callbacks coexist with one
      // synchronous Read-side action and its returned result.
      record_headers: 23L + 11L * count.to_int64(),
      reference_slots: 52L + 24L * count.to_int64(),
      scalar_words: 15L + 6L * count.to_int64(),
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
  ]).unwrap_or_else(() => stop("LocalOriginalModelBoundsUnavailable"))
}
