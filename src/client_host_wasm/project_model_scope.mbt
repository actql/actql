///|
// The maximum follows the exact closed scope grammar, including its seal.
// Authored/installed text uses the same writer to count escaped bytes. All
// four fixed identities and every slot CID use the canonical ASCII alphabet.
fn portable_model_scope_dimensions(
  slots : Int,
  account : @authorization.AdmittedAccountConfiguration,
  entry : String,
  principal : String,
  connection : String,
  resource : String,
  context : String,
  barrier : String,
) -> (Int, Int)? {
  let syntax =
    #|{"version":"actql-model-invocation-scope/0.1","run_definition_cid":"","task_index":9007199254740991,"strategy_revision":0,"inference_barrier_cid":"","input_artifact_cid":"","model_call_slot_cids":[],"provider_binding_cid":"","authorization_context":{"account_id":"","configuration_cid":"","entry_id":"","principal":"","connection":"","resource":"","operation":"infer","boundary":"activation","context_cid":""},"self_cid":""}
  if slots < 0 || slots > 100 {
    return None
  }
  let text = try {
    let writer = @encode.measuring_writer(16384, 10, 2)
    @encode.begin_array(writer)
    for
      field in [
        account.account_id(),
        account.configuration_cid(),
        entry,
        principal,
        connection,
        resource,
        context,
        barrier,
      ] {
      @encode.string_value(writer, field)
    }
    @encode.end_array(writer)
    // Remove this measurement array's delimiters, separators and the quotes
    // that the scope's fixed punctuation already includes.
    @encode.finish_measurement(writer).to_int64() - 25L
  } catch {
    _ => return None
  }
  let bytes = syntax.length().to_int64() + 284L + 74L * slots.to_int64() + text
  if bytes > 16384L {
    return None
  }

  Some((bytes.to_int(), 20 + slots))
}

///|
// Both the sealed Scope and original call links survive binding. All input
// documents, graph and Provider evidence remain borrowed. The current scope
// writer, sealer and validation arrays share the original Model startup.
fn portable_model_scope_capacity(
  bytes : Int,
  nodes : Int,
  slots : Int,
  depth? : Int = 4,
) -> @execution.ExecutionCapacity? {
  guard @publication.run_evidence_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(codec) &&
    @encode.text_writer_construction_inventory(bytes, nodes, depth)
    is Some(writer) &&
    @execution.preparation_array_representation(4L, 6L * slots.to_int64(), true)
    is Some(aliases) else {
    return None
  }
  @execution.preparation_execution_capacity({
    retained: {
      record_headers: codec.retained.record_headers +
      4L +
      aliases.record_headers,
      reference_slots: codec.retained.reference_slots +
      24L +
      aliases.reference_slots,
      scalar_words: codec.retained.scalar_words + 8L + aliases.scalar_words,
      owned_utf16_units: codec.retained_utf16_units + 32L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      // Closed boundary, account evaluation, provider coordinate projection,
      // slot-reference validation, return/option carriers and input draft.
      record_headers: codec.record_headers +
      writer.record_headers +
      96L +
      6L * slots.to_int64(),
      reference_slots: codec.reference_slots +
      writer.reference_slots +
      166L +
      12L * slots.to_int64(),
      scalar_words: codec.scalar_words +
      writer.scalar_words +
      124L +
      4L * slots.to_int64(),
      owned_utf16_units: codec.owned_utf16_units +
      writer.owned_utf16_units +
      bytes.to_int64(),
      owned_wire_bytes: codec.owned_wire_bytes,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
}

///|
// Both evidence bodies survive. Their respective writers and validation
// scratch retire between the synchronous Scope and dispatch preparations.
fn portable_model_serial_evidence_capacity(
  first : @execution.ExecutionCapacity,
  second : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity? {
  let a = @execution.execution_capacity_retained_bytes(first)
  let b = @execution.execution_capacity_retained_bytes(second)
  let work = Int64::max(
    @execution.execution_capacity_execution_bytes(first) - a,
    @execution.execution_capacity_execution_bytes(second) - b,
  )
  guard @execution.checked_preparation_add_product(a, b, 1L) is Some(held) &&
    @execution.checked_preparation_add_product(held, work, 1L) is Some(peak) else {
    return None
  }
  @execution.execution_capacity(held, peak)
}

///|
fn portable_model_task_authorization(
  current : StoredRunConfiguration,
  graph : @host.ClientInferPlanGraph,
) -> (String, String, String)? {
  let task = @environment.model_execution_task(
    @host.client_infer_plan_graph_execution_contract(graph),
  )
  let connection = @environment.model_task_connector(task)
  let resource = @environment.model_task_identity(task).2
  match
    @authorization.evaluate_account(current.account, {
      principal: current.tuple.principal,
      connection,
      resource,
      operation: "infer",
    }) {
    @authorization.Allow(entry) => Some((connection, resource, entry))
    _ => None
  }
}

///|
// Resolve the exact Model member under the same durable current Run and
// selected installation as the advancing Task.
fn portable_model_task_original(
  value : Instance,
  record : StoredManagedTask,
) -> Result[
  (StoredPortableModelRun, StoredPortableModelMember, StoredRunConfiguration)?,
  @local_run.LocalComputeIssue,
] {
  portable_model_task_retained(value, record, require_current=true)
}

///|
// Retiring a worker uses the exact already retained member even if dispatch
// currentness is lost. This lookup alone cannot authorize a new use of it.
fn portable_model_task_retained(
  value : Instance,
  record : StoredManagedTask,
  require_current? : Bool = false,
) -> Result[
  (StoredPortableModelRun, StoredPortableModelMember, StoredRunConfiguration)?,
  @local_run.LocalComputeIssue,
] {
  guard value.computes.get(record.compute) is Some(compute) &&
    compute.host is Some(host) &&
    @local_run.local_compute_model_run(host) is Some(adopted) else {
    return Ok(None)
  }
  guard stored_compute_original_run(value, compute) is Some(original) &&
    value.run_configurations.get(original.configuration) is Some(configuration) else {
    return Err(Configuration)
  }
  guard configuration.sdk is Some({ portable_model: Some(_), .. }) else {
    return Ok(None)
  }
  guard value.run_configurations.get(record.current_configuration)
    is Some(current) &&
    physical_equal(current, configuration) &&
    value.preparations.get(original.preparation)
    is Some({ project_request: Some({ model_run: Some(run), .. }), .. }) &&
    run.adopted is Some(retained) &&
    physical_equal(adopted, retained) &&
    (!require_current || managed_task_run_current(value, record) == 0) else {
    return Err(AuthorizationMismatch)
  }
  for selected_task in run.members {
    let (task_index, _, _) = @host.client_infer_occurrence_coordinates(
      selected_task.graph.occurrence,
    )
    if task_index == record.task {
      return Ok(Some((run, selected_task, current)))
    }
  }
  Ok(None)
}

///|
// A typed Scope is evidence; no port, Entry, capture or dispatch is installed.
fn bind_waiting_portable_model_scope(
  value : Instance,
  record : StoredManagedTask,
) -> Result[Unit, @local_run.LocalComputeIssue] {
  let (run, selected_task, current) = match
    portable_model_task_original(value, record) {
    Err(issue) => return Err(issue)
    Ok(None) => return Ok(())
    Ok(Some(original)) => original
  }
  let task_index = record.task
  guard selected_task.active is Some(active) &&
    @infer.prepared_call_set(active) is Some(prepared) &&
    @infer.call_scope(active) is Some(scope) &&
    @host.client_infer_call_scope_unit_id(scope) is Some(unit_id) else {
    return Err(Configuration)
  }
  if @model.prepared_model_scope(prepared) is Some(_) {
    return Ok(())
  }
  guard portable_model_task_authorization(current, selected_task.graph)
    is Some((connection, resource, entry)) else {
    return Err(AuthorizationMismatch)
  }
  let provider = @model.admitted_model_invocation_provider_binding(
    selected_task.provider,
  )
  guard @publication.model_invocation_provider_originals(provider)
    is Some((installed, revision, contract, configuration)) &&
    installed == connection else {
    return Err(Configuration)
  }
  let boundary : @publication.ModelInvocationBoundary = {
    unit_id,
    task_index: task_index.to_int64(),
    strategy_revision: 0L,
    inference_barrier_cid: @host.client_infer_plan_graph_barrier_cid(
      selected_task.graph,
    ),
    account_id: current.account.account_id(),
    configuration_cid: current.account.configuration_cid(),
    entry_id: entry,
    principal: current.tuple.principal,
    connection,
    resource,
    context_cid: @publication.run_publication_execution_context(
      run.compiled.admission,
    ),
    installation_revision_cid: revision,
    configuration_contract_cid: contract,
    provider_configuration_cid: configuration,
  }
  guard @model.project_prepared_model_invocation_scope(
      run.definition,
      prepared,
      provider,
      boundary,
      selected_task.scope_bytes,
      selected_task.scope_nodes,
      4,
    )
    is Ok(projected) &&
    managed_task_run_current(value, record) == 0 &&
    @infer.bind_model_scope(active, prepared, projected, provider, boundary)
    is Ok(_) else {
    return Err(Configuration)
  }
  Ok(())
}

///|
/// Set up the current dispatch authority on this waiting original. The clock
/// is borrowed from the same physical Host operation and cannot be used by
/// later advancement. That advance will need its own live clock and Store.
pub fn prepare_portable_model_dispatch(
  nonce : Int64,
  handle : Int,
  clock_input : Int,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.tasks.get(handle) is Some(record) &&
    !record.pending &&
    !record.closing &&
    record.issue is None &&
    record.progress is Some({ waiting: true, .. }) &&
    value.copies.get(clock_input) is Some((slot, _)) else {
    return -2
  }
  guard portable_model_task_original(value, record)
    is Ok(Some((run, selected_task, current))) &&
    selected_task.active is Some(active) &&
    @infer.prepared_call_set(active) is Some(prepared) &&
    @model.prepared_model_scope(prepared) is Some(scope) else {
    return -32
  }
  if selected_task.dispatch is Some(_) ||
    selected_task.dispatch_clock.val is Some(_) {
    return -3
  }
  guard input_cursor(value, slot) is Some(cursor) &&
    @decode.closed_object(cursor, ["observed_at"]) is Ok(fields) &&
    required_text(fields, "observed_at") is Some(at) &&
    at.length() <= 64 else {
    return -31
  }
  let clock = selected_task.dispatch_clock
  record.pending = true
  clock.val = Some(at)
  defer {
    clock.val = None
    record.pending = false
  }
  let (evidence_bytes, evidence_nodes, evidence_depth) = selected_task.dispatch_extent
  let admission = @host.issue_client_infer_dispatch_admission(
    run.compiled,
    run.definition,
    current.account,
    current.tuple.principal,
    at,
    model_scope=Some(scope),
    evidence_bytes~,
    evidence_nodes~,
    evidence_depth~,
    observe_current=() => {
      guard clock.val is Some(now) &&
        !record.closing &&
        managed_task_run_current(value, record) == 0 else {
        return Err(@host.ForeignRun)
      }
      Ok((current.account, now))
    },
  )
  match admission {
    Err(@host.Expired) => -36
    Err(_) => -32
    Ok(admitted) => {
      if @host.check_client_infer_dispatch_current(admitted) is Err(_) {
        return -32
      }
      selected_task.dispatch = Some(admitted)
      0
    }
  }
}
