///|
/// How this Site rebuilds and admits run materials: the check-environment
/// profiles it supports, the compiler manifests it trusts and the bounds of
/// every body. Site configuration, never taken from a dispatch.
pub(all) struct ResidentRunAdmission {
  expressions : @context.ExpressionProfiles
  operations : @context.PureOperationProfiles
  manifests : @host.ClientCompilationManifests
  limits : @host.ClientValuesRunMaterialsLimits
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
}

///|
fn admit_materials(
  admission : ResidentRunAdmission,
  request : @remote.DispatchRequest,
  materials : String,
  now : String,
) -> Result[@host.ClientValuesRunMaterials, @resident.ResidentDispatchRefusal] {
  let (run_definition_cid, _) = @remote.dispatch_request_task_scope(request)
  let rebuilt = match
    @host.admit_client_values_run_materials(
      materials,
      run_definition_cid,
      admission.expressions,
      admission.operations,
      admission.manifests,
      admission.limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(MaterialsRejected(issue))
  }
  match @resident.check_resident_run_current(rebuilt, now) {
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
  match admit_materials(admission, request, materials, now) {
    Ok(_) => ()
    Err(refusal) => return Ok(Refused(refusal))
  }
  let attempt = match @remote.dispatch_request_attempt_identity(request) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match queue.reserve(attempt) {
    Ok(_) => ()
    Err(refusal) => return Ok(Refused(refusal))
  }
  let envelope = match
    @remote.remote_poll_dispatch_materials_json(request, binding, materials) {
    Ok(value) => value
    Err(issue) => {
      ignore(queue.remove(attempt))
      return Err(Protocol(issue))
    }
  }
  match journal.retain_dispatch_envelope(request, envelope) {
    Ok(_) => ()
    Err(issue) => {
      ignore(queue.remove(attempt))
      return Err(Journal(issue))
    }
  }
  match journal.accept(request) {
    Ok(_) => ()
    Err(issue) => {
      ignore(queue.remove(attempt))
      return Err(Journal(issue))
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
        ignore(queue.remove(attempt))
        Err(Protocol(@remote.DispatchIdentityMismatch))
      }
    Err(issue) => {
      ignore(queue.remove(attempt))
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
  now : String,
  executor_entry : ((String) -> Bool)?,
) -> Result[
  (@runtime.NativeRemoteRuntime, @runtime.NativeRemoteRuntimeCompletion),
  ResidentHostIssue,
] {
  let envelope = match journal.dispatch_envelope(attempt_identity) {
    Ok(Some(value)) => value
    Ok(None) => return Err(EnvelopeMissing)
    Err(issue) => return Err(Journal(issue))
  }
  let dispatch = match @remote.admit_remote_poll_dispatch_json(envelope) {
    Ok(value) => value
    Err(_) => return Err(EnvelopeMissing)
  }
  let request = @remote.remote_poll_dispatch_request(dispatch)
  let binding = @remote.remote_poll_dispatch_input_binding(dispatch)
  guard @remote.remote_poll_dispatch_run_materials(dispatch) is Some(materials) &&
    @remote.dispatch_request_attempt_identity(request) is Ok(identity) &&
    identity == attempt_identity else {
    return Err(EnvelopeMissing)
  }
  let rebuilt = match admit_materials(admission, request, materials, now) {
    Ok(value) => value
    Err(refusal) => return Err(Refused(refusal))
  }
  let executor = match
    @values.install_native_remote_values_task_executor(
      rebuilt.prepared,
      rebuilt.compilation,
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
    Err(issue) => return Err(Values(issue))
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
    Err(issue) => return Err(Values(issue))
  }
  match runtime.claim_starts_as(claimant) {
    Ok(_) => ()
    Err(issue) => return Err(Runtime(issue))
  }
  match executor_entry {
    Some(observer) =>
      match runtime.observe_executor_entry(observer) {
        Ok(_) => ()
        Err(issue) => return Err(Runtime(issue))
      }
    None => ()
  }
  match runtime.start(request, binding) {
    Ok(completion) => Ok((runtime, completion))
    Err(issue) => {
      ignore(runtime.close())
      Err(Runtime(issue))
    }
  }
}
