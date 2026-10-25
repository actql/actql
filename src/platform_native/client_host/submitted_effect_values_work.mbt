///|
/// The existing Work plus its authenticated accepted Submission/material join.
/// This facade owns no Run state, authority, key, backing, packet or cleanup.
struct NativeClientSubmittedEffectValuesWork {
  work : NativeClientEffectValuesWork
  binding : NativeSubmittedEffectValuesBinding
}

///|
pub(all) enum NativeClientSubmittedEffectValuesWorkIssue {
  Original(NativeClientSubmittedEffectMaterialsIssue)
  Work(NativeClientEffectValuesWorkIssue)
}

///|
struct NativeClientSubmittedEffectValuesWorkFailure {
  issue : NativeClientSubmittedEffectValuesWorkIssue
  cleanup : () -> Bool
  mut cleaned : Bool
}

///|
pub fn native_client_submitted_effect_values_work_failure_issue(
  failure : NativeClientSubmittedEffectValuesWorkFailure,
) -> NativeClientSubmittedEffectValuesWorkIssue {
  failure.issue
}

///|
pub fn NativeClientSubmittedEffectValuesWorkFailure::close(
  self : NativeClientSubmittedEffectValuesWorkFailure,
) -> Bool {
  if !self.cleaned {
    self.cleaned = (self.cleanup)()
  }
  self.cleaned
}

///|
fn submitted_effect_values_failure(
  issue : NativeClientSubmittedEffectValuesWorkIssue,
  cleanup? : () -> Bool = () => true,
) -> NativeClientSubmittedEffectValuesWorkFailure {
  { issue, cleanup, cleaned: false, }
}

///|
// References to the same original Host/request/material, never copied policy
// or an Allow cache. last_issue transports only the most recent failed guard
// through the existing private Bool guard; it grants no retry or authority.
priv struct NativeSubmittedEffectValuesBinding {
  authority : NativeLocalPolicyAuthority
  reference : NativeClientSubmissionReference
  request : @host.ClientRequestIdentity
  materials : @host.ClientEffectRunMaterials
  epoch_clock : () -> Double
  last_issue : Ref[NativeClientSubmittedEffectValuesWorkIssue?]
}

///|
fn NativeSubmittedEffectValuesBinding::require_current(
  self : NativeSubmittedEffectValuesBinding,
) -> Result[Unit, NativeClientSubmittedEffectValuesWorkIssue] {
  self.last_issue.val = None
  let host = self.authority.host
  let result = (fn() -> Result[Unit, NativeClientSubmittedEffectValuesWorkIssue] {
    if !self.authority.current_for(host.journal, self.request) {
      return Err(Work(AuthorizationDenied))
    }
    let now = (self.epoch_clock)()
    // The epoch clock callback may revoke adoption/current or close the Work.
    // The existing reader checks current RunRead before and after both original
    // lookups, independently of Submit. It authenticates the retained reference,
    // intent/request/Run, packet HMAC/canonical bytes and exact materials CID.
    let original = check_local_effect_capture_binding(
      host,
      self.authority.crypto,
      self.authority.principal,
      self.authority.connection,
      self.reference,
      self.request,
      host.journal,
      self.materials,
      self.materials.run_definition,
      now,
    )
    // Always observe terminal Submit, including after an original refusal.
    // Preserve the original reader's refusal priority; neither branch may
    // produce a successful result after terminal Submit revocation.
    let submit_current = self.authority.current_for(host.journal, self.request)
    submitted_effect_values_current_result(original, submit_current)
  })()
  if result is Err(issue) {
    self.last_issue.val = Some(issue)
  }
  result
}

///|
// Pure refusal combination only, never a public authority or permission port.
fn submitted_effect_values_current_result(
  original : Result[Unit, NativeClientSubmittedEffectMaterialsIssue],
  submit_current : Bool,
) -> Result[Unit, NativeClientSubmittedEffectValuesWorkIssue] {
  match original {
    Err(issue) => Err(Original(issue))
    Ok(_) if !submit_current => Err(Work(AuthorizationDenied))
    Ok(_) => Ok(())
  }
}

///|
fn NativeSubmittedEffectValuesBinding::work_issue(
  self : NativeSubmittedEffectValuesBinding,
  issue : NativeClientEffectValuesWorkIssue,
) -> NativeClientSubmittedEffectValuesWorkIssue {
  self.last_issue.val.unwrap_or_else(() => Work(issue))
}

///|
/// Enter only through the original accepted packet and the same first opaque
/// Run binding. Current RunRead authenticates those originals; current Submit
/// separately guards the existing journal claim and Compute. Missing accepted
/// custody is never retained after the fact or reconstructed by this method.
/// Clocks are the trusted installed Host's existing UTC/epoch ports. These
/// inputs do not issue authority or extend any original lifetime.
pub fn NativeLocalHostConnection::open_submitted_effect_values_work(
  self : NativeLocalHostConnection,
  crypto : @crypto.Library,
  principal : String,
  connection : String,
  reference : NativeClientSubmissionReference,
  request : @host.ClientRequestIdentity,
  materials : @host.ClientEffectRunMaterials,
  bound : @host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  installed_contracts : @local.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  current_time : () -> String,
  current_epoch_clock : () -> Double,
) -> Result[
  NativeClientSubmittedEffectValuesWork,
  NativeClientSubmittedEffectValuesWorkFailure,
] {
  let authority = match
    native_local_policy_authority(
      self,
      crypto,
      principal,
      connection,
      request,
      None,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(submitted_effect_values_failure(Work(Journal(issue))))
  }
  let binding : NativeSubmittedEffectValuesBinding = {
    authority,
    reference,
    request,
    materials,
    epoch_clock: current_epoch_clock,
    last_issue: Ref(None),
  }
  match binding.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(submitted_effect_values_failure(issue))
  }
  let work = match
    open_native_client_effect_values_work(
      self.journal,
      request,
      materials,
      bound,
      captured,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      finalization_quantum,
      max_finalization_rounds,
      current_time,
      () => binding.require_current() is Ok(_),
    ) {
    Ok(value) => value
    Err(failure) =>
      return Err(
        submitted_effect_values_failure(
          binding.work_issue(
            native_client_effect_values_work_failure_issue(failure),
          ),
          cleanup=() => failure.close(),
        ),
      )
  }
  match binding.require_current() {
    Ok(_) => ()
    Err(issue) =>
      return Err(
        submitted_effect_values_failure(issue, cleanup=() => work.close()),
      )
  }
  // No callback follows this local lifetime check. An original read callback
  // may have retired the existing Work without changing its public identities.
  if work.closed || work.execution.material() is None {
    return Err(
      submitted_effect_values_failure(Work(Unavailable), cleanup=() => {
        work.close()
      }),
    )
  }
  Ok({ work, binding, })
}

///|
/// The same opaque Run only. Existing capture/evidence/Checkpoint/reviewer and
/// Provider Owners still decide every later read, approval and physical effect.
pub fn NativeClientSubmittedEffectValuesWork::run_for_capture(
  self : NativeClientSubmittedEffectValuesWork,
) -> Result[
  @strategy.CapturedEffectRunDAG,
  NativeClientSubmittedEffectValuesWorkIssue,
] {
  if self.work.closed {
    return Err(Work(Unavailable))
  }
  match self.binding.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let captured = match self.work.run_for_capture() {
    Ok(value) => value
    Err(issue) => return Err(self.binding.work_issue(issue))
  }
  match self.binding.require_current() {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  if self.work.closed || self.work.execution.material() is None {
    return Err(Work(Unavailable))
  }
  Ok(captured)
}

///|
pub fn NativeClientSubmittedEffectValuesWork::usage(
  self : NativeClientSubmittedEffectValuesWork,
) -> @resources.LedgerUsage {
  self.work.usage()
}

///|
/// Delegate the original cleanup carrier without requiring renewed read/submit
/// or changing a durable claim. False retains the same responsibility.
pub fn NativeClientSubmittedEffectValuesWork::close(
  self : NativeClientSubmittedEffectValuesWork,
) -> Bool {
  self.work.close()
}
