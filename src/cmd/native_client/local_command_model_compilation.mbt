///|
// The ordinary Request owns the Graphs and Task compilation. The original
// Read owns the adopted Model material through dispatch or command cleanup.
priv struct LocalCommandModelCompilation {
  program : @run_host.PreparedClientProgram
  compilation : @run_host.ClientTaskCompilation
  _graphs : Array[@run_host.ClientInferPlanGraph]
  _executions : Array[@local_host.NativeModelHttpExecution]
}

///|
fn LocalCommandPreparationOriginal::prepare_model_compilation(
  self : Self,
  capture : @local_host.NativeLocalJournalCapture,
  prepared : @run_host.PreparedClientProgram,
  installation : LocalModelHttpInstallationSettings,
  contracts : @local_values.ClientInstalledSequenceContracts,
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
  let (occurrences, graphs, executions) = self.with_business_request(capture, () => {
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
    (occurrences, Array(capacity=count), Array(capacity=count))
  })
  let limits = local_project_mock_task_limits()
  let configuration = match
    capture.read_model_http_configuration_in_original_read(
      installation.files,
      installation.provider_id,
      installation.response_profile_cid,
      limits,
      execution_file=installation.execution_file,
    ) {
    Ok(value) => value
    Err(issue) => {
      self.retain_primary(CommandBusinessModelHttp(issue))
      stop("LocalModelHttpInstallationRefused")
    }
  }
  let compilation_limits = @run_host.client_standard_pure_compilation_limits()
  for occurrence in occurrences {
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
    self.with_business_request(capture, () => {
      match
        @local_values.prepare_request_model_graph(
          parent,
          input,
          occurrence,
          execution.execution_contract(),
          contracts,
          manifests=native_request_manifests,
          compilation_limits~,
        ) {
        Ok(graph) => {
          graphs.push(graph)
          executions.push(execution)
        }
        Err(issue) => {
          self.retain_primary(CommandBusinessModelGraph(issue))
          stop("LocalOriginalModelGraphUnavailable")
        }
      }
    })
  }
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
          _graphs: graphs,
          _executions: executions,
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
) -> @run_host.ClientTaskCompilation? raise ClientStop {
  guard self.model_compilation is Some(model) else { return None }
  if !physical_equal(model.program, prepared) {
    stop("LocalBusinessOriginalUnavailable")
  }
  Some(model.compilation)
}
