///|
/// Bounds one source-free Values occurrence and its Result export. Site
/// registration does not open the Local kernel or consume these limits.
pub(all) struct NativeRemoteValuesTaskLimits {
  finalization_quantum : Int
  max_finalization_rounds : Int
  row_decode : @execution.RetainedRowDecodeLimits
  bridge_max_entries : Int
  bridge_max_name_bytes : Int
  output : @output.NativeRemoteStandardTaskLimits
}

///|
pub(all) enum NativeRemoteValuesHostIssue {
  ForeignRun
  UnsupportedProgram
  InvalidInputBinding
  InvalidLimits
  Runtime(@runtime.NativeRemoteRuntimeIssue)
}

///|
/// One checked Values implementation selected before Site admission. The
/// runtime callback stays private to this composition boundary.
struct NativeRemoteValuesTaskExecutor {
  executor : @runtime.NativeRemoteTaskExecutor
}

///|
fn values_failure(
  code : String,
  cleanup : () -> Bool,
) -> @runtime.NativeRemotePhysicalExecution {
  if cleanup() {
    @runtime.prepare_native_remote_failure(code, false, false, true, () => true).unwrap()
  } else {
    @runtime.prepare_native_remote_failure(code, false, true, false, cleanup).unwrap()
  }
}

///|
/// Install one exact checked Values task for a native Remote Site. The
/// selected runtime still admits the dispatch, grant, bundle and budget before
/// invoking this executor. The admitted Run, compilation and source-free
/// binding are fixed at installation; no dispatch can replace them.
pub fn install_native_remote_values_task_executor(
  prepared : @host.PreparedClientProgram,
  compilation : @host.ClientValuesCompilation,
  admission : @publication.RunPublicationAdmission,
  run_definition : @publication.PublicationContract,
  input_binding : @remote.RemoteInputBinding,
  registry_body : String,
  values_body : String,
  fixed_ms : Int64,
  per_row_ms : Int64,
  per_wire_byte_ms : Int64,
  per_pair_ms : Int64,
  limits : NativeRemoteValuesTaskLimits,
) -> Result[NativeRemoteValuesTaskExecutor, NativeRemoteValuesHostIssue] {
  if limits.finalization_quantum < 1 ||
    limits.max_finalization_rounds < 1 ||
    limits.bridge_max_entries < 1 ||
    limits.bridge_max_name_bytes < 1 {
    return Err(InvalidLimits)
  }
  let identity = @host.prepared_client_identity(prepared)
  if @publication.check_run_publication_program_binding(
      admission,
      run_definition,
      identity.program_definition_cid,
      @host.prepared_client_program_semantics_cid(prepared),
      @host.prepared_client_check_environment_cid(prepared),
    )
    is Err(_) ||
    @publication.run_publication_compiled_plan_cid(admission) !=
    @publication.publication_contract_identity(
      @host.client_values_compilation_compiled_plan(compilation),
    ) ||
    @publication.run_publication_template_cid(admission) !=
    @publication.run_evidence_value_identity(
      @host.client_values_compilation_template(compilation),
    ) {
    return Err(ForeignRun)
  }
  let graph = @host.prepared_client_graph(prepared)
  if @strategy.graph_task_count(graph) != 1 ||
    @strategy.graph_task_input_count(graph, 0) != Some(0) ||
    @host.prepared_client_result_count(prepared) != 1 ||
    @host.client_values_compilation_result_names(compilation) !=
    [@host.prepared_client_result_name(prepared, 0).unwrap()] {
    return Err(UnsupportedProgram)
  }
  // This adapter has no physical input. An opaque binding identity cannot
  // smuggle a source or a local file into an Effect-free Values task.
  if @remote.remote_input_binding_body(input_binding) != "{}" {
    return Err(InvalidInputBinding)
  }
  let run_definition_cid = @publication.publication_contract_identity(
    run_definition,
  )
  let task_key = @host.client_values_compilation_plan_node_id(compilation)
  let binding_cid = @remote.remote_input_binding_cid(input_binding)
  let executor = @runtime.install_native_remote_task_executor(
    run_definition_cid,
    task_key,
    (request, binding, budget) => {
      if @remote.dispatch_request_task_scope(request) !=
        (run_definition_cid, task_key) ||
        @remote.remote_input_binding_cid(binding) != binding_cid ||
        !@remote.remote_input_binding_matches_dispatch(binding, request) ||
        @remote.dispatch_request_budget_cid(request) !=
        @remote.remote_dispatch_budget_cid(budget) {
        return values_failure("foreign-values-dispatch", () => true)
      }
      let setup = match
        @local.open_source_free_local_host(
          prepared, registry_body, values_body, fixed_ms, per_row_ms, per_wire_byte_ms,
          per_pair_ms,
        ) {
        Some(value) => value
        // The Local assembly API does not yet return a retryable cleanup
        // owner on failure. Retain explicit stop responsibility rather than
        // claiming physical cleanup from a missing handle.
        None => return values_failure("values-host-open", () => false)
      }
      let execution = match
        @local.execute_source_free_values(
          setup,
          limits.finalization_quantum,
          limits.max_finalization_rounds,
        ) {
        Ok(value) => value
        Err(_) => return values_failure("values-execution", () => false)
      }
      let result = match
        execution.prepare_result_export(
          0,
          limits.row_decode,
          limits.bridge_max_entries,
          limits.bridge_max_name_bytes,
          limits.output.output_export,
        ) {
        Ok(value) => value
        Err(_) =>
          return values_failure("values-result-export", () => execution.close())
      }
      @output.prepare_native_remote_standard_output_from_export(
        request,
        0,
        result.output_export(),
        () => {
          result.close()
          execution.close()
        },
        limits.output,
        budget,
      )
    },
  )
  match executor {
    Ok(value) => Ok({ executor: value, })
    Err(issue) => Err(Runtime(issue))
  }
}

///|
/// Compose a native Site from the checked Values task, verified runtime
/// component and durable Site journal. The common runtime remains the owner
/// of admission, physical stop, output custody and release transitions.
pub fn open_native_remote_values_site_runtime(
  site : @site.ExecutionSite,
  active_runtime : @bundle.NativeActiveRuntimeBinding,
  operation_capability_cid : String,
  issuer_capability_cid : String,
  executor : NativeRemoteValuesTaskExecutor,
  journal : @journal.Journal,
  bundles : @bundle.NativeRuntimeBundleStore,
  budgets : Array[@remote.RemoteDispatchBudget],
) -> Result[@runtime.NativeRemoteRuntime, NativeRemoteValuesHostIssue] {
  if budgets.is_empty() {
    return Err(InvalidLimits)
  }
  let registration = match
    @runtime.install_native_remote_runtime_registry_registration(
      site,
      active_runtime,
      operation_capability_cid,
      issuer_capability_cid,
      [executor.executor],
    ) {
    Ok(value) => value
    Err(issue) => return Err(Runtime(issue))
  }
  match
    @runtime.open_native_remote_runtime(
      journal,
      bundles,
      [registration],
      budgets,
    ) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Runtime(issue))
  }
}
