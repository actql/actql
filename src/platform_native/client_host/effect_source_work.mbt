///|
/// The original accepted Effect Run connected to the same Native acquisition,
/// Compute and cleanup Owner as ordinary Source work. It is not a second Run,
/// scheduler, approval Owner, capture receipt or Provider permission.
struct NativeClientEffectSourceWork {
  journal : NativeClientRunJournal
  request : @host.ClientRequestIdentity
  owner : @resident.ResidentSourceCompute
  materials : @host.ClientEffectRunMaterials
  allowed : @host.ClientEffectAllowedRun
  definition : @publication.PublicationContract
  current_time : () -> String
  current_authorization : () -> Bool
  capture_started_at : String
  capture_completed_at : String
  first_start : NativeClientWorkFirstStart
}

///|
fn claim_native_client_effect_work_start(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  current_authorization : () -> Bool,
) -> Result[
  (@host.PreparedClientEffectRun, NativeClientWorkFirstStart),
  NativeClientSourceWorkIssue,
] {
  if !current_authorization() {
    return Err(AuthorizationDenied)
  }
  let prepared = @host.client_effect_compilation_owner(allowed.compilation)
  let bound = match
    @host.bind_client_effect_compiled_run(prepared, allowed, definition) {
    Ok(value) => value
    Err(issue) => return Err(Work(EffectRun(issue)))
  }
  if @host.prepared_client_effect_request_scope(prepared, request) is Err(_) {
    return Err(Journal(ChangedIntent))
  }
  match journal.lookup(request, true) {
    Ok(Retained(record)) if @publication.publication_contract_identity(
        record.definition,
      ) ==
      @publication.publication_contract_identity(definition) =>
      // This original was cancelled before this start attempt. Refuse before
      // reserving dispatch so reconciliation cannot mutate its saved intent.
      if record.cancellation_requested {
        return Err(NeedsOriginalReconciliation)
      }
    Ok(Retained(_)) => return Err(Journal(ForeignRun))
    Ok(UnresolvedHistory) => return Err(Journal(CustodyLost))
    Err(issue) => return Err(Journal(issue))
  }
  match
    claim_native_client_retained_work_first_start(
      journal, request, current_authorization,
    ) {
    Ok(start) => Ok((bound, start))
    Err(issue) => Err(issue)
  }
}

///|
/// Open only an already accepted original Effect Run. Configuration remains
/// Host-owned and must be the selected original mapping; this adapter does not
/// install configuration or grants. A prior physical claim cannot be retried,
/// including after failure or lost reply. Recovery uses the original Owner.
pub fn open_native_client_effect_source_work(
  journal : NativeClientRunJournal,
  request : @host.ClientRequestIdentity,
  allowed : @host.ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  materials : @host.ClientEffectRunMaterials,
  configuration : @resident.ResidentSourceComputeConfiguration,
  occurrence : String,
  current_time : () -> String,
  current_authorization : () -> Bool,
  observe? : (@resident.ResidentSourceComputeEvent) -> Bool,
) -> Result[NativeClientEffectSourceWork, NativeClientSourceWorkIssue] {
  if !current_authorization() {
    return Err(AuthorizationDenied)
  }
  let prepared = @host.client_effect_compilation_owner(allowed.compilation)
  // Carry the original admitted material, including absent or retained
  // normalization custody. Never synthesize a replacement material projection.
  if !physical_equal(materials.prepared, prepared) ||
    !physical_equal(materials.compilation, allowed.compilation) ||
    !physical_equal(materials.allowed, allowed) ||
    materials.request != Some(request) ||
    @publication.publication_contract_identity(materials.run_definition) !=
    @publication.publication_contract_identity(definition) ||
    @host.bind_client_effect_compiled_run(
      materials.prepared,
      materials.allowed,
      materials.run_definition,
    )
    is Err(_) {
    return Err(Work(ForeignEffectMaterials))
  }
  if materials.normalization is Some(_) &&
    @host.restore_client_effect_run_normalization(materials) is Err(_) {
    return Err(Work(ForeignEffectMaterials))
  }
  let checked = match
    @host.bind_client_effect_compiled_run(prepared, allowed, definition) {
    Ok(value) => value
    Err(issue) => return Err(Work(EffectRun(issue)))
  }
  if !@resident.resident_effect_source_compute_shape_supported(checked) {
    return Err(Work(UnsupportedGraph))
  }
  // Observe time before the final original-claim guard. A clock callback may
  // itself accept cancellation and must never bypass that guard.
  let capture_started_at = current_time()
  if !@host.client_effect_run_start_current(
      allowed, definition, capture_started_at,
    ) {
    return Err(OriginalRunNotCurrent)
  }
  let (bound, first_start) = match
    claim_native_client_effect_work_start(
      journal, request, allowed, definition, current_authorization,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    @resident.open_resident_effect_source_compute(
      bound,
      configuration,
      occurrence,
      materials~,
      observe=native_client_work_observer(
        journal,
        request,
        () => {
          @host.client_effect_run_start_current(
            allowed,
            definition,
            current_time(),
          ) &&
          current_authorization()
        },
        observe,
      ),
    ) {
    Ok(owner) =>
      Ok({
        journal,
        request,
        owner,
        materials,
        allowed,
        definition,
        current_time,
        current_authorization,
        capture_started_at,
        capture_completed_at: current_time(),
        first_start,
      })
    Err((issue, cleanup)) => Err(Open(issue, cleanup))
  }
}

///|
fn NativeClientEffectSourceWork::require_current(
  self : NativeClientEffectSourceWork,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  if !(self.current_authorization)() {
    return Err(AuthorizationDenied)
  }
  let now = (self.current_time)()
  // Time observation may itself revoke authority or accept cancellation.
  if !(self.current_authorization)() {
    return Err(AuthorizationDenied)
  }
  if !@host.client_effect_run_start_current(self.allowed, self.definition, now) {
    return Err(OriginalRunNotCurrent)
  }
  require_native_client_work_current(
    self.journal,
    self.request,
    self.current_authorization,
  )
}

///|
// The observation grant assembly requires this original operational witness,
// not a reconstructed CID. Post-Checkpoint evidence/cleanup keep their existing
// paths; this preparation check does not redefine their authorization.
fn NativeClientEffectSourceWork::require_preparation_start(
  self : NativeClientEffectSourceWork,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  match self.require_current() {
    Ok(_) =>
      self.first_start.require_current(
        self.journal,
        self.request,
        self.current_authorization,
      )
    Err(issue) => Err(issue)
  }
}

///|
pub fn NativeClientEffectSourceWork::execute_task(
  self : NativeClientEffectSourceWork,
  task : Int,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  match self.require_current() {
    Ok(_) => {
      // Once the original journal owns a Checkpoint, physical continuation
      // belongs to its existing resume/reconciliation Owner. A live input
      // borrow remains available for evidence/cleanup, not another task start.
      match self.journal.lookup(self.request, true) {
        Ok(Retained(record)) if record.checkpoint is None => ()
        Ok(_) => return Err(NeedsOriginalReconciliation)
        Err(issue) => return Err(Journal(issue))
      }
      self.owner.execute_task(task).map(_ => ()).map_err(issue => Work(issue))
    }
    Err(issue) => Err(issue)
  }
}

///|
/// Borrow the original physical Owner for existing capture/Preview APIs.
/// The Host retains every returned pin and output according to those Owners;
/// this observation neither transfers ownership nor authorizes Provider I/O.
pub fn NativeClientEffectSourceWork::owner_for_capture(
  self : NativeClientEffectSourceWork,
) -> Result[@resident.ResidentSourceCompute, NativeClientSourceWorkIssue] {
  match self.require_current() {
    Ok(_) if self.owner.effect_run() is Some(_) => Ok(self.owner)
    Ok(_) => Err(Work(Unavailable))
    Err(issue) => Err(issue)
  }
}

///|
/// Checked Named Result bytes remain private until ordinary publication and
/// current read authorization; exporting them is not Effect completion.
pub fn NativeClientEffectSourceWork::prepare_result_export(
  self : NativeClientEffectSourceWork,
  limits : @host.PublicationOutputExportLimits,
) -> Result[@host.PublicationOutputExport, NativeClientSourceWorkIssue] {
  match self.require_current() {
    Ok(_) =>
      self.owner.prepare_result_export(limits).map_err(issue => Work(issue))
    Err(issue) => Err(issue)
  }
}

///|
pub fn NativeClientEffectSourceWork::usage(
  self : NativeClientEffectSourceWork,
) -> @resources.LedgerUsage {
  self.owner.usage()
}

///|
/// Cleanup retains the same retryable Owner even after authority loss. A
/// successful physical close is not cancellation acceptance or Run terminality.
pub fn NativeClientEffectSourceWork::close(
  self : NativeClientEffectSourceWork,
) -> Bool {
  self.owner.close()
}
