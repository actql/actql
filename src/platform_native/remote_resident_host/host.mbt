///|
/// How this Site rebuilds and admits run materials: the check-environment
/// profiles it supports, the compiler manifests it trusts and the bounds of
/// every body. Site configuration, never taken from a dispatch.
pub(all) struct ResidentRunAdmission {
  expressions : @context.ExpressionProfiles
  operations : @context.PureOperationProfiles
  manifests : @host.ClientCompilationManifests
  limits : @host.ClientValuesRunMaterialsLimits
  source : (String, String)?
}

///|
pub(all) enum ResidentHostIssue {
  Journal(@journal.NativeRemoteJournalIssue)
  Client(@client.NativeRemoteClientIssue)
  Protocol(@remote.DispatchIssue)
  /// The kept envelope is missing or no longer admits.
  EnvelopeMissing
  Refused(@resident.ResidentDispatchRefusal)
  Values(@values.NativeRemoteValuesHostIssue)
  Source(ResidentSourceIssue)
  Runtime(@runtime.NativeRemoteRuntimeIssue)
}

///|
/// The outcome of offering one polled dispatch to the resident Site.
pub(all) enum ResidentAcceptance {
  /// Durable, acknowledged to the Coordinator, and queued for the executor
  /// slot under this attempt identity.
  Accepted(String, @remote.DispatchRequest)
  /// Refused before acceptance: nothing was written and nothing starts.
  Refused(@resident.ResidentDispatchRefusal)
  /// An exact redelivery of an attempt that already left Accepted. Its
  /// current durable record was reported; it is never queued again.
  AlreadyStarted(String)
}

///|
fn rebuild_materials(
  admission : ResidentRunAdmission,
  request : @remote.DispatchRequest,
  materials : String,
) -> Result[@host.ClientRunMaterials, @resident.ResidentDispatchRefusal] {
  let (run_definition_cid, _) = @remote.dispatch_request_task_scope(request)
  match
    @host.admit_client_run_materials(
      materials,
      run_definition_cid,
      admission.expressions,
      admission.operations,
      admission.manifests,
      admission.limits,
    ) {
    Ok(value) => Ok(value)
    Err(@host.ClientRunMaterialsIssue::Values(issue)) =>
      Err(MaterialsRejected(issue))
    Err(@host.ClientRunMaterialsIssue::Tasks(issue)) =>
      Err(TaskMaterialsRejected(issue))
  }
}

///|
fn admit_materials(
  admission : ResidentRunAdmission,
  request : @remote.DispatchRequest,
  materials : String,
  binding : @remote.RemoteInputBinding,
  now : String,
) -> Result[@host.ClientRunMaterials, @resident.ResidentDispatchRefusal] {
  let rebuilt = match rebuild_materials(admission, request, materials) {
    Ok(value) => value
    Err(refusal) => return Err(refusal)
  }
  if rebuilt.compilation is @host.Tasks(_) {
    let graph = @host.prepared_client_graph(rebuilt.prepared)
    if @strategy.graph_task_count(graph) != 1 ||
      @host.prepared_client_acquisition_count(rebuilt.prepared) != 1 ||
      @host.prepared_client_result_count(rebuilt.prepared) != 1 ||
      @strategy.graph_result_task(graph, 0) != Some(0) ||
      @strategy.graph_task_target(graph, 0) is Some(_) {
      return Err(@resident.UnsupportedTask)
    }
    guard admission.source is Some((source_ref, source_contract_cid)) &&
      @host.prepared_client_source_evidence_facts(rebuilt.prepared, 0, 0)
      is Some(facts) else {
      return Err(@resident.ForeignSource)
    }
    let selected = @planning.query_source_evidence_fact_values(facts)
    if selected[0] != source_ref || selected[1] != source_contract_cid {
      return Err(@resident.ForeignSource)
    }
    guard @host.prepare_client_task_input_binding(rebuilt.prepared, 0)
      is Ok(expected) else {
      return Err(@resident.UnsupportedTask)
    }
    if @remote.remote_input_binding_body(binding) !=
      @remote.remote_input_binding_body(expected) ||
      !@remote.remote_input_binding_matches_dispatch(binding, request) {
      return Err(@resident.ForeignSource)
    }
  }
  match @resident.check_resident_materials_current(rebuilt, now) {
    Ok(_) => Ok(rebuilt)
    Err(refusal) => Err(refusal)
  }
}

///|
/// Offer one polled dispatch to the resident Site (parent process). In order:
/// the Site's own delegation, the rebuilt Run, its lifetime at the Site's
/// clock, room in the bounded accepted queue. Only then is the exact envelope
/// kept, the dispatch accepted durably and the acceptance acknowledged. The
/// executor is never started here.
pub fn accept_resident_dispatch(
  journal : @journal.Journal,
  client : @http.Client,
  observation_url : String,
  delegation : @resident.ResidentSiteDelegation,
  site_generation : Int,
  queue : @resident.ResidentAcceptedQueue,
  admission : ResidentRunAdmission,
  dispatch : @remote.RemotePollDispatch,
  now : String,
) -> Result[ResidentAcceptance, ResidentHostIssue] {
  let request = @remote.remote_poll_dispatch_request(dispatch)
  let binding = @remote.remote_poll_dispatch_input_binding(dispatch)
  guard @remote.remote_poll_dispatch_run_materials(dispatch) is Some(materials) else {
    return Ok(Refused(MaterialsMissing))
  }
  match
    @resident.check_resident_dispatch_delegation(
      delegation, request, site_generation,
    ) {
    Ok(_) => ()
    Err(refusal) => return Ok(Refused(refusal))
  }
  match admit_materials(admission, request, materials, binding, now) {
    Ok(_) => ()
    Err(refusal) => return Ok(Refused(refusal))
  }
  let attempt = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  // Only a reservation made by this call is undone on a later failure; an
  // attempt already waiting keeps its place.
  let reserved = !queue.contains(attempt)
  match queue.reserve(attempt) {
    Ok(_) => ()
    Err(refusal) => return Ok(Refused(refusal))
  }
  let release = () => if reserved { ignore(queue.remove(attempt)) }
  let envelope = match
    @remote.remote_poll_dispatch_materials_json(request, binding, materials) {
    Ok(value) => value
    Err(issue) => {
      release()
      return Err(Protocol(issue))
    }
  }
  match journal.retain_dispatch_envelope(request, envelope) {
    Ok(_) => ()
    Err(issue) => {
      release()
      return Err(Journal(issue))
    }
  }
  let accepted = match journal.accept(request) {
    Ok((_, record)) => record
    Err(issue) => {
      release()
      return Err(Journal(issue))
    }
  }
  if !@remote.remote_runtime_record_startable(accepted) {
    ignore(queue.remove(attempt))
    // The redelivery is answered with the attempt's current durable record;
    // nothing starts again. Until the common redelivery rules (O5) fix which
    // form a Coordinator admits for an already acknowledged attempt, the
    // dispatch response is tried first and the status form after a 404.
    return match
      @client.acknowledge_acceptance(journal, client, observation_url, request) {
      Ok(_) => Ok(AlreadyStarted(attempt))
      Err(@client.HttpStatus(404)) =>
        match
          @client.acknowledge_status(journal, client, observation_url, request) {
          Ok(_) => Ok(AlreadyStarted(attempt))
          Err(issue) => Err(Client(issue))
        }
      Err(issue) => Err(Client(issue))
    }
  }
  // The durable Accepted record stays when the acknowledgement is lost; an
  // exact redelivery acknowledges it again. Unconfirmed work is not queued.
  match
    @client.acknowledge_acceptance(journal, client, observation_url, request) {
    Ok(record) =>
      if @remote.dispatch_record_matches_request(record, request) {
        Ok(Accepted(attempt, request))
      } else {
        release()
        Err(Protocol(@remote.DispatchIdentityMismatch))
      }
    Err(issue) => {
      release()
      Err(Client(issue))
    }
  }
}

///|
/// What the executing process (the slot holder) needs to run one attempt.
pub(all) struct ResidentExecution {
  site : @site.ExecutionSite
  active_runtime : @bundle.NativeActiveRuntimeBinding
  operation_capability_cid : String
  issuer_capability_cid : String
  bundles : @bundle.NativeRuntimeBundleStore
  budgets : Array[@remote.RemoteDispatchBudget]
  registry_body : String
  values_body : String
  fixed_ms : Int64
  per_row_ms : Int64
  per_wire_byte_ms : Int64
  per_pair_ms : Int64
  limits : @values.NativeRemoteValuesTaskLimits
  source : ResidentSourceConfiguration?
}

///|
/// One executed attempt whose output the holder's runtime owns.
pub(all) struct ResidentExecuted {
  runtime : @runtime.NativeRemoteRuntime
  completion : @runtime.NativeRemoteRuntimeCompletion
  request : @remote.DispatchRequest
  result_definition_cid : String
}

///|
/// A failed execution with its primary cause. `pending_runtime` is set when
/// the runtime existed and its cleanup is not confirmed: the caller keeps it,
/// retries only `close` until that succeeds, and never starts it again.
pub(all) struct ResidentExecutionFailure {
  issue : ResidentHostIssue
  pending_runtime : @runtime.NativeRemoteRuntime?
}

///|
fn failed(issue : ResidentHostIssue) -> ResidentExecutionFailure {
  { issue, pending_runtime: None, }
}

///|
fn failed_after_runtime(
  runtime : @runtime.NativeRemoteRuntime,
  issue : ResidentHostIssue,
) -> Result[ResidentExecuted, ResidentExecutionFailure] {
  match runtime.close() {
    Ok(_) => Err({ issue, pending_runtime: None, })
    Err(_) => Err({ issue, pending_runtime: Some(runtime), })
  }
}

///|
/// Run one accepted attempt in the executing process. The kept envelope is
/// read back and the Run rebuilt again from its materials, its lifetime is
/// checked at the Site's clock, and the start is an exclusive claim by
/// `claimant`: a holder that does not win the claim writes nothing and does
/// not execute. The returned runtime owns the output until it is released.
pub fn execute_resident_attempt(
  journal : @journal.Journal,
  execution : ResidentExecution,
  admission : ResidentRunAdmission,
  attempt_identity : String,
  claimant : String,
  current_time : () -> String,
  executor_entry : ((String) -> Bool)?,
) -> Result[ResidentExecuted, ResidentExecutionFailure] {
  let envelope = match journal.dispatch_envelope(attempt_identity) {
    Ok(Some(value)) => value
    Ok(None) => return Err(failed(EnvelopeMissing))
    Err(issue) => return Err(failed(Journal(issue)))
  }
  let dispatch = match @remote.admit_remote_poll_dispatch_json(envelope) {
    Ok(value) => value
    Err(_) => return Err(failed(EnvelopeMissing))
  }
  let request = @remote.remote_poll_dispatch_request(dispatch)
  let binding = @remote.remote_poll_dispatch_input_binding(dispatch)
  guard @remote.remote_poll_dispatch_run_materials(dispatch) is Some(materials) &&
    @remote.dispatch_request_attempt_identity(request) is Ok(identity) &&
    identity == attempt_identity else {
    return Err(failed(EnvelopeMissing))
  }
  let rebuilt = match rebuild_materials(admission, request, materials) {
    Ok(value) => value
    Err(refusal) => return Err(failed(Refused(refusal)))
  }
  // Receipt already accepted this exact Run. A lifetime refusal here must
  // acquire the existing exclusive start claim and terminate through the
  // runtime owner; returning while still Accepted would indefinitely retry
  // the queue head. No physical call is permitted by this claim.
  let accepted_run_current = @resident.check_resident_materials_current(
      rebuilt,
      current_time(),
    )
    is Ok(_)
  let (runtime, result_definition_cid) = match rebuilt.compilation {
    @host.Tasks(compilation) => {
      guard execution.source is Some(source) else {
        return Err(failed(Source(UnsupportedSource)))
      }
      let (executor, result_definition_cid) = match
        install_resident_source_executor(
          rebuilt, compilation, binding, request, execution, source, current_time,
        ) {
        Ok(value) => value
        Err(issue) => return Err(failed(Source(issue)))
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
        Err(issue) => return Err(failed(Source(Standard(issue))))
      }
      (runtime, result_definition_cid)
    }
    @host.Values(compilation) => {
      let executor = match
        @values.install_native_remote_values_task_executor(
          rebuilt.prepared,
          compilation,
          rebuilt.admission,
          rebuilt.run_definition,
          binding,
          execution.registry_body,
          execution.values_body,
          execution.fixed_ms,
          execution.per_row_ms,
          execution.per_wire_byte_ms,
          execution.per_pair_ms,
          execution.limits,
        ) {
        Ok(value) => value
        Err(issue) => return Err(failed(Values(issue)))
      }
      let runtime = match
        @values.open_native_remote_values_site_runtime(
          execution.site,
          execution.active_runtime,
          execution.operation_capability_cid,
          execution.issuer_capability_cid,
          executor,
          journal,
          execution.bundles,
          execution.budgets,
        ) {
        Ok(value) => value
        Err(issue) => return Err(failed(Values(issue)))
      }
      (runtime, executor.result_definition_cid())
    }
  }
  // From here the runtime may own cleanup: every failure keeps it until its
  // close is confirmed.
  match
    runtime.guard_executor_start(() => {
      let current = @resident.check_resident_materials_current(
        rebuilt,
        current_time(),
      )
      accepted_run_current && current is Ok(_)
    }) {
    Ok(_) => ()
    Err(issue) => return failed_after_runtime(runtime, Runtime(issue))
  }
  match runtime.claim_starts_as(claimant) {
    Ok(_) => ()
    Err(issue) => return failed_after_runtime(runtime, Runtime(issue))
  }
  match executor_entry {
    Some(observer) =>
      match runtime.observe_executor_entry(observer) {
        Ok(_) => ()
        Err(issue) => return failed_after_runtime(runtime, Runtime(issue))
      }
    None => ()
  }
  match runtime.start(request, binding) {
    Ok(completion) =>
      Ok({ runtime, completion, request, result_definition_cid, })
    Err(@runtime.StartAuthorizationRejected) =>
      failed_after_runtime(runtime, Refused(@resident.NotCurrent))
    Err(issue) => failed_after_runtime(runtime, Runtime(issue))
  }
}
