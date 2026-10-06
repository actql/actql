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
  /// Durable and acknowledged to the Coordinator. The ordinary caller queues
  /// the attempt; a retained consumer stays in its existing producer holder.
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
    // The producer dispatch must name its original checked task. A dependent
    // consumer needs the retained-input connection and remains refused here.
    if resident_source_dispatch_role(rebuilt, request) is Err(_) {
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
  let result = retain_and_acknowledge_resident_dispatch(
    journal,
    client,
    observation_url,
    request,
    binding,
    materials,
    () => ignore(queue.remove(attempt)),
  )
  match result {
    Ok(Accepted(_, _)) => ()
    Ok(AlreadyStarted(_)) => ignore(queue.remove(attempt))
    _ => release()
  }
  result
}

///|
/// Both queue and retained-holder admission use this existing Site journal
/// boundary. An unconfirmed save/ACK never permits execution. No caller may
/// substitute a synthetic Accepted record for this result.
fn retain_and_acknowledge_resident_dispatch(
  journal : @journal.Journal,
  client : @http.Client,
  observation_url : String,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  materials : String,
  nonstartable : () -> Unit,
) -> Result[ResidentAcceptance, ResidentHostIssue] {
  let attempt = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let envelope = match
    @remote.remote_poll_dispatch_materials_json(request, binding, materials) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match journal.retain_dispatch_envelope(request, envelope) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  let accepted = match journal.accept(request) {
    Ok((_, record)) => record
    Err(issue) => return Err(Journal(issue))
  }
  if !@remote.remote_runtime_record_startable(accepted) {
    nonstartable()
    // Exact redelivery reports the same durable attempt, never a new start.
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
  match
    @client.acknowledge_acceptance(journal, client, observation_url, request) {
    Ok(record) =>
      if @remote.dispatch_record_matches_request(record, request) {
        Ok(Accepted(attempt, request))
      } else {
        Err(Protocol(@remote.DispatchIdentityMismatch))
      }
    Err(issue) => Err(Client(issue))
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
  /// Internal producer output has no public Named Result definition.
  result_definition_cid : String?
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
/// Install the existing checked executor and Runtime without entering it.
/// Ordinary execution and completed-output restoration use this same registry.
fn open_resident_attempt_runtime(
  journal : @journal.Journal,
  execution : ResidentExecution,
  rebuilt : @host.ClientRunMaterials,
  binding : @remote.RemoteInputBinding,
  request : @remote.DispatchRequest,
  current_time : () -> String,
  source_observe : ((ResidentSourceComputeEvent) -> Bool)?,
) -> Result[(@runtime.NativeRemoteRuntime, String?), ResidentExecutionFailure] {
  Ok(
    match rebuilt.compilation {
      // This resident transport installs read-only task/Values executors.
      // An enclosing Effect Run needs the installed Effect owner instead.
      @host.Effects(_) => return Err(failed(Refused(@resident.UnsupportedTask)))
      @host.Tasks(compilation) => {
        guard execution.source is Some(source) else {
          return Err(failed(Source(UnsupportedSource)))
        }
        let (executor, result_definition_cid) = match
          install_resident_source_executor(
            rebuilt,
            compilation,
            binding,
            request,
            execution,
            source,
            current_time,
            observe=event => {
              match source_observe {
                Some(observer) => observer(event)
                None => true
              }
            },
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
        (runtime, Some(executor.result_definition_cid()))
      }
    },
  )
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
  source_observe? : (ResidentSourceComputeEvent) -> Bool,
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
  let (runtime, result_definition_cid) = match
    open_resident_attempt_runtime(
      journal, execution, rebuilt, binding, request, current_time, source_observe,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
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
