///|
/// An environment port reopens only the exact saved output. Unavailable keeps
/// its cleanup callback; it does not report another execution failure.
pub(all) enum NativeCompletedOutputRestoration {
  RestoredCompletedOutput(NativeRemoteOutput)
  CompletedOutputUnavailable(String, () -> Bool)
}

///|
/// A trusted cleanup port proves exclusive custody independently of permission
/// to read/use output. It can only reconstruct the original physical release.
/// Runtime saves the first port with its owner; retries cannot replace custody.
pub(all) struct NativeCompletedCleanupRestoration {
  current : () -> Bool
  restore : (@journal.RecoveredSiteDispatch) -> () -> Bool
}

///|
/// Pending means Runtime owns the original resource responsibility. Refused
/// means no physical restoration or capacity acquisition was attempted.
pub(all) enum NativeCompletedRuntimeRestoration {
  CompletedRuntimeReady(NativeRemoteRuntimeCompletion)
  CompletedRuntimePending(NativeRemoteRuntimeIssue)
  CompletedRuntimeRefused(NativeRemoteRuntimeIssue)
}

///|
fn completed_restoration_site_current(
  site : @site.ExecutionSite,
  request : @remote.DispatchRequest,
) -> Bool {
  let scope = @remote.dispatch_request_execution_scope(request)
  scope[0] == @site.site_key(site) &&
  scope[1] == @site.site_generation(site).to_string() &&
  scope[2] == @site.site_runtime_revision(site) &&
  @site.site_available(site)
}

///|
fn restored_output_matches(
  owner : NativeRemoteRuntimeOwner,
  recovered : @journal.RecoveredSiteDispatch,
  output : NativeRemoteOutput,
) -> Bool {
  guard owner.subject is Some(subject) &&
    owner.holding_evidence_cid is Some(holding) &&
    @journal.recovered_site_dispatch_file_custody(recovered) is Some(saved) &&
    output.file_custody is Some(physical) else {
    return false
  }
  let facts = output.facts
  let rebuilt = match
    @remote.prepare_remote_managed_output_subject(
      @remote.dispatch_request_identity(owner.request),
      facts.material_generation,
      holding,
      facts.managed_profile_cid,
      facts.result_schema_cid,
      facts.logical_view_cid,
      facts.representation_codec_cid,
      @manifest.manifest_cid(facts.physical_manifest),
      @remote.remote_managed_output_measurement_cid(facts.measurement),
      facts.row_count,
      facts.retained_bytes,
    ) {
    Ok(value) => value
    Err(_) => return false
  }
  if @remote.remote_managed_output_subject_cid(rebuilt) !=
    @remote.remote_managed_output_subject_cid(subject) ||
    !@journal.native_output_file_custody_matches_request(
      physical,
      owner.request,
    ) ||
    @journal.native_output_file_custody_occurrence(saved) !=
    @journal.native_output_file_custody_occurrence(physical) ||
    @journal.native_output_file_custody_generation(saved) !=
    @journal.native_output_file_custody_generation(physical) ||
    @journal.native_output_file_custody_content_cid(saved) !=
    @journal.native_output_file_custody_content_cid(physical) {
    return false
  }
  match
    (
      @journal.recovered_site_dispatch_source_observation(recovered),
      output.source_observation,
    ) {
    (None, None) => true
    (Some(saved), Some(actual)) =>
      @remote.remote_source_observation_projection(saved) ==
      @remote.remote_source_observation_projection(actual)
    _ => false
  }
}

///|
/// Reconstitute one completed owner in the same live Site generation. The
/// trusted current port must validate actual Site authority and exclusive
/// holder custody; cached journal fields cannot establish those facts.
/// Call before new dispatch admission, retaining this Runtime on Pending.
/// No executor, start claim, evidence issuer or Source acquisition is called.
pub fn NativeRemoteRuntime::restore_completed(
  self : NativeRemoteRuntime,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  current : () -> Bool,
  restore_output : (@journal.RecoveredSiteDispatch) -> NativeCompletedOutputRestoration,
  cleanup? : NativeCompletedCleanupRestoration? = None,
) -> NativeCompletedRuntimeRestoration {
  if self.closed {
    return CompletedRuntimeRefused(Closed)
  }
  if !self.admitting.is_empty() {
    return CompletedRuntimeRefused(DispatchAlreadyStarted)
  }
  if !@remote.remote_input_binding_matches_dispatch(binding, request) {
    return CompletedRuntimeRefused(Protocol(@remote.DispatchIdentityMismatch))
  }
  let identity = @remote.dispatch_request_identity(request)
  if self.pending_cleanup.contains(identity) {
    return CompletedRuntimePending(CleanupPending("dispatch"))
  }
  let owner = match self.owners.get(identity) {
    Some(owner) => {
      if !@remote.dispatch_record_matches_request(owner.record, request) ||
        @remote.remote_input_binding_cid(owner.binding) !=
        @remote.remote_input_binding_cid(binding) {
        return CompletedRuntimeRefused(
          Protocol(@remote.DispatchIdentityMismatch),
        )
      }
      if !owner.restoration_pending {
        if !current() {
          return CompletedRuntimePending(StartAuthorizationRejected)
        }
        return match native_remote_runtime_completion(owner) {
          Ok(value) => CompletedRuntimeReady(value)
          Err(issue) => CompletedRuntimePending(issue)
        }
      }
      owner
    }
    None => {
      if !current() {
        return CompletedRuntimeRefused(StartAuthorizationRejected)
      }
      let registration = match self.registration_for(request) {
        Some(value) => value
        None => return CompletedRuntimeRefused(RuntimeUnsupported)
      }
      if !(registration.supports)(request) {
        return CompletedRuntimeRefused(RuntimeUnsupported)
      }
      if !completed_restoration_site_current(registration.site, request) {
        return CompletedRuntimeRefused(SiteUnavailable)
      }
      match
        self.bundles.verify_active_component_binding(
          registration.active_runtime,
        ) {
        Ok(_) => ()
        Err(issue) => return CompletedRuntimeRefused(Bundle(issue))
      }
      let recovered = match self.journal.observation(request) {
        Ok(value) => value
        Err(issue) => return CompletedRuntimeRefused(Journal(issue))
      }
      let record = @journal.recovered_site_dispatch_record(recovered)
      guard @journal.recovered_site_dispatch_evidence(recovered)
        is Some(evidence) &&
        @journal.recovered_site_dispatch_subject(recovered) is Some(subject) &&
        @journal.recovered_site_dispatch_measurement(recovered)
        is Some(measurement) &&
        @journal.recovered_site_dispatch_file_custody(recovered) is Some(_) else {
        return CompletedRuntimeRefused(OutputRejected)
      }
      let custody = match
        @remote.restore_remote_runtime_completed_custody(
          record, evidence, subject, measurement,
        ) {
        Ok(value) => value
        Err(issue) => return CompletedRuntimeRefused(Protocol(issue))
      }
      let budget = match self.budget_for(request) {
        Some(value) => value
        None => return CompletedRuntimeRefused(BudgetUnsupported)
      }
      let (_, holding, _, bytes) = @remote.remote_managed_output_subject_retention(
        subject,
      )
      let (retained, _) = @remote.remote_dispatch_budget_capacity(budget)
      if bytes > retained {
        return CompletedRuntimeRefused(OutputRejected)
      }
      if !current() {
        return CompletedRuntimeRefused(StartAuthorizationRejected)
      }
      let owner : NativeRemoteRuntimeOwner = {
        request,
        binding,
        record,
        registration,
        custody,
        bundle_hold_id: "dispatch:" + identity,
        operation: None,
        output: None,
        holding: None,
        holding_evidence_cid: Some(holding),
        physical_failure: None,
        evidence: Some(evidence),
        subject: Some(subject),
        measurement: Some(measurement),
        active_readers: 0,
        restoration_pending: true,
        restoration_current: Some(current),
        restoration_cleanup_port: cleanup,
        restoration_observation: Some(recovered),
        restoration_cleanup: None,
      }
      // Register responsibility before any reservation or physical callback.
      self.owners[identity] = owner
      owner
    }
  }
  // Reentrant physical adapters cannot admit or restore another dispatch.
  self.admitting[identity] = true
  let result = self.advance_completed_restoration(owner, restore_output)
  ignore(self.admitting.remove(identity))
  result
}

///|
fn completed_restoration_cleanup_current(
  owner : NativeRemoteRuntimeOwner,
) -> Bool {
  match owner.restoration_cleanup_port {
    Some(port) => (port.current)()
    None =>
      owner.restoration_current is Some(current) &&
      current() &&
      completed_restoration_site_current(owner.registration.site, owner.request)
  }
}

///|
fn NativeRemoteRuntime::finish_completed_cleanup_restoration(
  self : NativeRemoteRuntime,
  owner : NativeRemoteRuntimeOwner,
  issue : NativeRemoteRuntimeIssue,
) -> NativeCompletedRuntimeRestoration {
  if !completed_restoration_cleanup_current(owner) {
    return CompletedRuntimePending(StartAuthorizationRejected)
  }
  let latest = match self.journal.require_completed_cleanup(owner.request) {
    Ok(value) => value
    Err(issue) => return CompletedRuntimePending(Journal(issue))
  }
  if !@remote.confirm_remote_runtime_completed_cleanup_restoration(
      latest,
      owner.custody,
      owner.evidence.unwrap(),
      owner.subject.unwrap(),
      owner.measurement.unwrap(),
    ) {
    return CompletedRuntimePending(CustodyRejected)
  }
  owner.record = latest
  owner.restoration_pending = false
  let identity = @remote.dispatch_request_identity(owner.request)
  ignore(self.owners.remove(identity))
  self.pending_cleanup[identity] = owner
  CompletedRuntimePending(issue)
}

///|
fn NativeRemoteRuntime::advance_completed_restoration(
  self : NativeRemoteRuntime,
  owner : NativeRemoteRuntimeOwner,
  restore_output : (@journal.RecoveredSiteDispatch) -> NativeCompletedOutputRestoration,
) -> NativeCompletedRuntimeRestoration {
  if !completed_restoration_cleanup_current(owner) {
    return CompletedRuntimePending(StartAuthorizationRejected)
  }
  // Only this already-owned completion may reconcile cleanup progress. Normal
  // durable reconstruction stays strict, including terminal/material changes.
  let latest = match self.journal.require_completed_cleanup(owner.request) {
    Ok(value) => value
    Err(issue) => return CompletedRuntimePending(Journal(issue))
  }
  owner.record = latest
  // Physical identity stays pinned to the original saved obligation. The
  // record is refreshed above; no later observation may substitute a file.
  guard owner.restoration_observation is Some(recovered) else {
    return CompletedRuntimePending(CustodyRejected)
  }
  guard owner.restoration_current is Some(current) else {
    return CompletedRuntimePending(CustodyRejected)
  }
  if !@remote.remote_runtime_custody_holding_acquired(owner.custody) {
    let (_, _, _, bytes) = @remote.remote_managed_output_subject_retention(
      owner.subject.unwrap(),
    )
    guard @site.retain_site_holding(owner.registration.site, bytes)
      is Some(holding) else {
      return CompletedRuntimePending(CapacityRejected)
    }
    owner.holding = Some(holding)
    ignore(@remote.remote_runtime_custody_acquire_holding(owner.custody))
  }
  if !@remote.remote_runtime_custody_bundle_acquired(owner.custody) {
    match
      self.bundles.retain(
        owner.registration.runtime_bundle_cid,
        owner.bundle_hold_id,
        "dispatch",
      ) {
      Ok(_) =>
        ignore(@remote.remote_runtime_custody_acquire_bundle(owner.custody))
      Err(issue) => return CompletedRuntimePending(Bundle(issue))
    }
  }
  if !completed_restoration_cleanup_current(owner) {
    return CompletedRuntimePending(StartAuthorizationRejected)
  }
  // A rejected foreign adapter result is not the original output obligation.
  // Finish that callback before attaching any original cleanup-only handle.
  if !@remote.remote_runtime_custody_output_acquired(owner.custody) &&
    owner.restoration_cleanup is Some(cleanup) {
    if !cleanup() {
      return CompletedRuntimePending(CleanupPending("restoration-output"))
    }
    owner.restoration_cleanup = None
  }
  if @remote.dispatch_record_state_codes(latest)[2] != 0 ||
    !current() ||
    !completed_restoration_site_current(owner.registration.site, owner.request) ||
    owner.restoration_cleanup is Some(_) {
    if !@remote.remote_runtime_custody_output_acquired(owner.custody) {
      guard owner.restoration_cleanup_port is Some(port) else {
        return CompletedRuntimePending(StartAuthorizationRejected)
      }
      owner.restoration_cleanup = Some((port.restore)(recovered))
      ignore(@remote.remote_runtime_custody_acquire_output(owner.custody))
    }
    return self.finish_completed_cleanup_restoration(
      owner,
      CleanupPending("restoration-transition"),
    )
  }
  if owner.output is None {
    match restore_output(recovered) {
      RestoredCompletedOutput(output) => {
        if !restored_output_matches(owner, recovered, output) {
          owner.restoration_cleanup = Some(output.release)
          return CompletedRuntimePending(OutputRejected)
        }
        owner.output = Some(output)
        ignore(@remote.remote_runtime_custody_acquire_output(owner.custody))
      }
      CompletedOutputUnavailable(code, cleanup) => {
        owner.restoration_cleanup = Some(cleanup)
        ignore(@remote.remote_runtime_custody_acquire_output(owner.custody))
        return self.finish_completed_cleanup_restoration(
          owner,
          CompletedMaterialUnavailable(code),
        )
      }
    }
  }
  // Losing permission after the callback cannot expose the restored output.
  // Keep its exact release handle under independently verified cleanup custody.
  if !current() ||
    !completed_restoration_site_current(owner.registration.site, owner.request) {
    return self.finish_completed_cleanup_restoration(
      owner,
      CleanupPending("restoration-authority"),
    )
  }
  if !completed_restoration_cleanup_current(owner) {
    return CompletedRuntimePending(StartAuthorizationRejected)
  }
  let latest = match self.journal.require_completed_cleanup(owner.request) {
    Ok(value) => value
    Err(issue) => return CompletedRuntimePending(Journal(issue))
  }
  if !@remote.confirm_remote_runtime_completed_restoration(
      latest,
      owner.custody,
    ) {
    return self.finish_completed_cleanup_restoration(
      owner,
      CleanupPending("restoration-transition"),
    )
  }
  owner.record = latest
  owner.restoration_pending = false
  match native_remote_runtime_completion(owner) {
    Ok(value) => CompletedRuntimeReady(value)
    Err(issue) => CompletedRuntimePending(issue)
  }
}
