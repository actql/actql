///|
/// Trusted Site configuration, never decoded from Program or dispatch input.
/// The checked logical Source must match before its database is opened.
pub(all) struct ResidentSourceConfiguration {
  source_ref : String
  source_contract_cid : String
  library : @duckdb.Library
  retained_output_root : String?
  database_path : String
  memory_bytes : Int64
  database_schema : String
  table : String
  query_contract_body : String
  evidence_contract_body : String
  two_receipt_contract_body : String
  fragment_contract_body : String
  ledger : @resources.LedgerLimits
}

///|
pub(all) enum ResidentSourceIssue {
  UnsupportedSource
  ForeignInput
  Query(@local.ClientLocalQueryIssue)
  Acquisition(@local.ClientDuckDBAcquisitionIssue)
  Binding(@duckdb_native.NativeReadOnlySourceIssue)
  Task(@host.ClientTaskDispatchIssue)
  Fragment(@host.ClientTaskFragmentIssue)
  Inventory(@publication.PublicationInventoryIssue)
  Standard(@output.NativeRemoteStandardHostIssue)
}

///|
/// Prepare the acquisition requirement from the same checked Effect owner.
/// Trusted Site identity is checked before selection or physical I/O. This
/// grants neither Source read authority nor Effect approval; the executor must
/// still recheck current authority/lifetime and hold its exclusive start claim.
pub fn prepare_resident_effect_source_requirement(
  prepared : @host.PreparedClientEffectComputation,
  task : Int,
  source_index : Int,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  source_ref : String,
  source_contract_cid : String,
) -> Result[@planning.QueryRequirement, ResidentSourceIssue] {
  let requirement = match
    @local.prepare_effect_local_query_requirement(
      prepared,
      task,
      source_index,
      registry_body,
      values_body,
      fragment_body,
      None,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Query(issue))
  }
  match
    require_resident_source_identity(
      requirement, source_ref, source_contract_cid,
    ) {
    Ok(_) => Ok(requirement)
    Err(issue) => Err(issue)
  }
}

///|
fn require_resident_source_identity(
  requirement : @planning.QueryRequirement,
  source_ref : String,
  source_contract_cid : String,
) -> Result[Unit, ResidentSourceIssue] {
  guard @planning.query_requirement_source_evidence_facts(requirement)
    is Some(facts) else {
    return Err(UnsupportedSource)
  }
  let values = @planning.query_source_evidence_fact_values(facts)
  if values[0] != source_ref || values[1] != source_contract_cid {
    return Err(ForeignInput)
  }
  Ok(())
}

///|
/// The role comes from the original checked graph, not a transport-selected
/// task count or a fabricated producer Result definition.
priv enum ResidentSourceDispatchRole {
  PublicSourceResult
  InternalSourceProducer
}

///|
fn resident_source_dispatch_role(
  materials : @host.ClientRunMaterials,
  request : @remote.DispatchRequest,
) -> Result[ResidentSourceDispatchRole, ResidentSourceIssue] {
  let prepared = materials.prepared
  guard materials.compilation is @host.Tasks(compilation) else {
    return Err(UnsupportedSource)
  }
  let graph = @host.prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph)
  if !resident_linear_graph(graph) ||
    @host.prepared_client_acquisition_count(prepared) != 1 ||
    @host.prepared_client_result_count(prepared) != 1 ||
    @strategy.graph_result_task(graph, 0) != Some(count - 1) ||
    @strategy.graph_task_target(graph, 0) is Some(_) ||
    @host.bind_client_task_run(
      prepared,
      compilation,
      materials.admission,
      materials.run_definition,
    )
    is Err(_) {
    return Err(UnsupportedSource)
  }
  let fragment = match
    @host.issue_prepared_client_task_fragment(
      prepared,
      0,
      @host.client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Fragment(issue))
  }
  if @remote.dispatch_request_task_scope(request) !=
    (
      @publication.publication_contract_identity(materials.run_definition),
      @host.client_task_fragment_node_id(fragment),
    ) {
    return Err(ForeignInput)
  }
  if count == 1 {
    Ok(PublicSourceResult)
  } else {
    Ok(InternalSourceProducer)
  }
}

///|
fn install_resident_source_executor(
  materials : @host.ClientRunMaterials,
  compilation : @host.ClientTaskCompilation,
  binding : @remote.RemoteInputBinding,
  request : @remote.DispatchRequest,
  execution : ResidentExecution,
  source : ResidentSourceConfiguration,
  current_time : () -> String,
  observe? : (ResidentSourceComputeEvent) -> Bool,
) -> Result[
  (@output.NativeRemoteStandardTaskExecutor, String?),
  ResidentSourceIssue,
] {
  let role = match resident_source_dispatch_role(materials, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if role is InternalSourceProducer {
    return install_resident_acquisition_task_executor(
      materials,
      compilation,
      binding,
      request,
      execution,
      source,
      current_time,
      observe?,
    ).map(executor => (executor, None))
  }
  let prepared = materials.prepared
  let inventory = match
    @publication.prepare_checked_publication_inventory(
      @host.prepared_client_identity(prepared).program_definition_cid,
      @host.client_task_compilation_result_names(compilation),
      [0],
    ) {
    Ok(value) => value
    Err(issue) => return Err(Inventory(issue))
  }
  let result_definition_cid = match
    @publication.checked_publication_inventory_definition_cid(inventory, 0) {
    Ok(value) => value
    Err(issue) => return Err(Inventory(issue))
  }
  install_resident_acquisition_task_executor(
    materials,
    compilation,
    binding,
    request,
    execution,
    source,
    current_time,
    observe?,
  ).map(executor => (executor, Some(result_definition_cid)))
}

///|
/// Install the checked acquisition task through the existing Runtime. Its
/// internal output can feed a dependent task without inventing a public Result,
/// executing the consumer, or opening the configured Source at installation.
pub fn install_resident_acquisition_task_executor(
  materials : @host.ClientRunMaterials,
  compilation : @host.ClientTaskCompilation,
  binding : @remote.RemoteInputBinding,
  request : @remote.DispatchRequest,
  execution : ResidentExecution,
  source : ResidentSourceConfiguration,
  current_time : () -> String,
  observe? : (ResidentSourceComputeEvent) -> Bool,
) -> Result[@output.NativeRemoteStandardTaskExecutor, ResidentSourceIssue] {
  let prepared = materials.prepared
  let graph = @host.prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph)
  if !resident_linear_graph(graph) ||
    @host.prepared_client_acquisition_count(prepared) != 1 ||
    @host.prepared_client_result_count(prepared) != 1 ||
    @strategy.graph_result_task(graph, 0) != Some(count - 1) ||
    @strategy.graph_task_target(graph, 0) is Some(_) ||
    @host.bind_client_task_run(
      prepared,
      compilation,
      materials.admission,
      materials.run_definition,
    )
    is Err(_) {
    return Err(UnsupportedSource)
  }
  // A dependent consumer must not rely on a process-local capture surviving
  // holder recreation. This is trusted Site configuration, not Run materials.
  if count > 1 && source.retained_output_root is None {
    return Err(UnsupportedSource)
  }
  let output_storage = source.retained_output_root.map(root => {
    () => {
      @retained_file.begin_native_retained_task_file(
        root,
        @remote.dispatch_request_identity(request)[7:].to_owned(),
        execution.limits.output.max_retained_bytes,
      ).map_err(_ => "source-output-storage")
    }
  })
  let expected = match @host.prepare_client_task_input_binding(prepared, 0) {
    Ok(value) => value
    Err(issue) => return Err(Task(issue))
  }
  if @remote.remote_input_binding_body(binding) !=
    @remote.remote_input_binding_body(expected) ||
    !@remote.remote_input_binding_matches_dispatch(binding, request) {
    return Err(ForeignInput)
  }
  let requirement = match
    @local.prepare_local_query_requirement(
      prepared,
      0,
      0,
      execution.registry_body,
      execution.values_body,
      Some(source.fragment_contract_body),
      None,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Query(issue))
  }
  match
    require_resident_source_identity(
      requirement,
      source.source_ref,
      source.source_contract_cid,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let setup = match
    @local.prepare_client_duckdb_acquisition(
      requirement,
      source.database_schema,
      source.table,
      source.query_contract_body,
      source.evidence_contract_body,
      source.two_receipt_contract_body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Acquisition(issue))
  }
  let configured = @duckdb_host.configured_native_host_source(setup)
  if configured != (source.source_ref, source.source_contract_cid) {
    return Err(ForeignInput)
  }
  let physical = match
    @duckdb_native.prepare_native_read_only_source_binding(
      setup,
      source.database_path,
      source.memory_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Binding(issue))
  }
  guard @duckdb_host.prepare_native_source_evidence_context(requirement)
    is Ok(context) &&
    @planning.query_requirement_source_evidence_facts(requirement)
    is Some(facts) else {
    return Err(UnsupportedSource)
  }
  let fact_values = @planning.query_source_evidence_fact_values(facts)
  let policy = fact_values[3]
  let authority = @remote.dispatch_request_journal_key(request)[0]
  let fragment = match
    @host.issue_prepared_client_task_fragment(
      prepared,
      0,
      @host.client_standard_values_sequence_limits(),
      1000000,
      100000,
      100,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Fragment(issue))
  }
  let definition_cid = @publication.publication_contract_identity(
    materials.run_definition,
  )
  let task_key = @host.client_task_fragment_node_id(fragment)
  if @remote.dispatch_request_task_scope(request) != (definition_cid, task_key) {
    return Err(ForeignInput)
  }
  let failure = fn(code : String, cleanup : () -> Bool) {
    @output.prepare_native_remote_standard_input_failure(code, cleanup).unwrap()
  }
  // Only the common runtime calls this factory, after admission, lifetime
  // recheck, exclusive start claim and the single executor-entry observation.
  let factory = match
    @output.register_native_remote_standard_dispatch_run_factory(
      request,
      binding,
      () => {
        if observe is Some(record) && !record(AcquisitionEntered) {
          return Err(failure("source-open", () => true))
        }
        let started = current_time()
        let runtime = match
          @duckdb_native.open_native_read_only_source_acquisition(
            physical,
            setup,
            source.library,
            @remote.dispatch_request_identity(request),
          ) {
          Ok(value) => value
          Err(_) => return Err(failure("source-open", () => true))
        }
        let close = () => {
          @duckdb_native.close_native_acquisition_runtime(runtime)
          true
        }
        if @duckdb_native.execute_native_acquisition_runtime(runtime) is Err(_) {
          return Err(failure("source-acquire", close))
        }
        let completed = current_time()
        guard @duckdb_native.native_acquisition_runtime_source_capture(runtime)
          is Ok(capture) &&
          @duckdb_host.native_host_source_capture_source(capture)
          is Ok(captured_source) else {
          return Err(failure("source-capture", close))
        }
        if observe is Some(record) && !record(ProducerCaptured) {
          return Err(failure("source-capture", close))
        }
        let limits = execution.limits.output.output_export
        guard @query.identify_captured_source_relation(
            captured_source,
            limits.max_rows,
            limits.values,
            limits.payload_wire,
            limits.logical_wire,
            limits.schema,
            limits.max_batch_bytes,
          )
          is Ok(identity) &&
          @host.issue_captured_source_input_logical(
            graph, captured_source, identity, requirement,
          )
          is Ok(logical) &&
          @duckdb_host.issue_native_host_source_evidence(
            capture, context, identity, logical, authority, policy, completed,
          )
          is Ok(evidence) else {
          return Err(failure("source-observation", close))
        }
        let captured = match
          @host.open_prepared_captured_client_run(
            prepared,
            captured_source,
            source.ledger,
          ) {
          Ok(value) => value
          Err(_) => return Err(failure("source-retention", close))
        }
        let observation = Some(dispatch => {
          @remote.prepare_remote_source_observation(
            dispatch, 0, evidence, logical, started, completed,
          )
        })
        // A public Source Result still needs its checked Result projection.
        // A producer feeding another task exports its exact internal task port.
        let owned = if count == 1 {
          @output.prepare_native_remote_standard_acquired_run_owner(
            captured,
            0,
            close,
            source_observation=observation,
            output_storage~,
          )
        } else {
          @output.prepare_native_remote_standard_acquired_task_owner(
            captured,
            0,
            captured_source,
            close,
            source_observation=observation,
            output_storage~,
          )
        }
        match owned {
          Ok(value) => Ok(value)
          Err(_) =>
            Err(
              failure("source-owner", () => {
                @strategy.stop_captured_dag(captured)
                close()
              }),
            )
        }
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Standard(issue))
  }
  match
    @output.install_native_remote_standard_bound_task_executor(
      definition_cid,
      task_key,
      0,
      factory,
      execution.limits.output,
    ) {
    Ok(executor) => Ok(executor)
    Err(issue) => Err(Standard(issue))
  }
}
