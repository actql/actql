///|
/// Physical output facts produced by one registered native implementation.
/// The common runtime derives the exact holding, subject, and evidence from
/// these facts; an executor cannot supply an arbitrary authority CID.
pub(all) struct NativeRemoteOutputFacts {
  material_generation : String
  managed_profile_cid : String
  result_schema_cid : String
  logical_view_cid : String
  representation_codec_cid : String
  physical_manifest : @manifest.PhysicalManifest
  row_count : Int
  retained_bytes : Int64
  measurement : @remote.RemoteManagedOutputMeasurement
}

///|
/// One physical output owner. The release callback performs only physical
/// cleanup and reports whether it was confirmed. Release eligibility remains
/// in the common runtime progression.
struct NativeRemoteOutput {
  facts : NativeRemoteOutputFacts
  open_reader : () -> Result[NativeRemotePhysicalReader, String]
  open_manifest_reader : () -> Result[
    NativeRemotePhysicalManifestReader,
    String,
  ]
  release : () -> Bool
}

///|
/// One bounded physical read result. The common runtime rejects a physical
/// adapter that returns more bytes than the admitted request size.
pub(all) struct NativeRemoteOutputChunk {
  bytes : Bytes
  eof : Bool
}

///|
/// Environment-owned output access. These callbacks only perform and report
/// physical I/O; the common runtime owns reader pins and release eligibility.
struct NativeRemotePhysicalReader {
  next : (Int) -> Result[NativeRemoteOutputChunk, String]
  finish : () -> Result[Unit, String]
  close : () -> Result[Unit, String]
}

///|
/// Environment-owned access preserving exact physical manifest boundaries.
/// The common runtime verifies every returned chunk before it can be used by
/// a Transfer. The physical implementation only performs and reports I/O.
struct NativeRemotePhysicalManifestReader {
  next : (Int) -> Result[Bytes, String]
  finish : () -> Result[Unit, String]
  close : () -> Result[Unit, String]
}

///|
/// One common-owned read pin for an exact retained remote output.
struct NativeRemoteOutputReader {
  owner : NativeRemoteRuntimeOwner
  physical : NativeRemotePhysicalReader
  max_chunk_bytes : Int
  mut eof : Bool
  mut closed : Bool
}

///|
/// One verified physical manifest chunk from an exact retained output.
pub(all) struct NativeRemoteOutputManifestChunk {
  index : Int
  bytes : Bytes
}

///|
/// A common-owned manifest reader pin. Unlike the general consumer reader,
/// this reader preserves physical chunk boundaries needed by Transfer.
struct NativeRemoteOutputManifestReader {
  owner : NativeRemoteRuntimeOwner
  physical : NativeRemotePhysicalManifestReader
  manifest : @manifest.PhysicalManifest
  max_chunk_bytes : Int
  mut index : Int
  mut closed : Bool
}

///|
/// A physical failure observation. A returned failure is not itself proof
/// that native access stopped. The retry callback may only report a confirmed
/// stop; it cannot choose settlement or release transitions.
struct NativeRemotePhysicalFailure {
  code : String
  cancelled : Bool
  stop_required : Bool
  mut stop_confirmed : Bool
  retry_stop : () -> Bool
}

///|
pub(all) enum NativeRemotePhysicalExecution {
  NativeRemoteOutputReady(NativeRemoteOutput)
  NativeRemoteExecutionFailed(NativeRemotePhysicalFailure)
}

///|
struct NativeRemoteRuntimeRegistration {
  site : @site.ExecutionSite
  active_runtime : @bundle.NativeActiveRuntimeBinding
  runtime_bundle_cid : String
  capability : @remote.RemoteExecutionCapability
  issuer : @remote.RemoteEvidenceIssuer
  key : String
  supports : (@remote.DispatchRequest) -> Bool
  execute : (
    @remote.DispatchRequest,
    @remote.RemoteInputBinding,
    @remote.RemoteDispatchBudget,
  ) -> NativeRemotePhysicalExecution
}

///|
/// One preinstalled executable checked task. Runtime bundle activation and
/// Connector capability remain separate admission requirements; this binding
/// prevents a Connector-wide callback from accepting an arbitrary task name.
struct NativeRemoteTaskExecutor {
  key : String
  execute : (
    @remote.DispatchRequest,
    @remote.RemoteInputBinding,
    @remote.RemoteDispatchBudget,
  ) -> NativeRemotePhysicalExecution
}

///|
priv struct NativeRemoteRuntimeOwner {
  request : @remote.DispatchRequest
  binding : @remote.RemoteInputBinding
  record : @remote.DispatchRecord
  registration : NativeRemoteRuntimeRegistration
  custody : @remote.RemoteRuntimeCustody
  bundle_hold_id : String
  mut operation : @site.SiteOperation?
  mut output : NativeRemoteOutput?
  mut holding : @site.SiteHolding?
  mut holding_evidence_cid : String?
  mut physical_failure : NativeRemotePhysicalFailure?
  mut evidence : @remote.RemoteExecutionEvidence?
  mut subject : @remote.RemoteManagedOutputSubject?
  mut measurement : @remote.RemoteManagedOutputMeasurement?
  mut active_readers : Int
}

///|
struct NativeRemoteRuntime {
  journal : @journal.Journal
  bundles : @bundle.NativeRuntimeBundleStore
  registrations : Map[String, NativeRemoteRuntimeRegistration]
  process_holds : Map[String, Bool]
  budgets : Map[String, @remote.RemoteDispatchBudget]
  admitting : Map[String, Bool]
  owners : Map[String, NativeRemoteRuntimeOwner]
  pending_cleanup : Map[String, NativeRemoteRuntimeOwner]
  mut closed : Bool
}

///|
pub(all) struct NativeRemoteRuntimeCompletion {
  dispatch_request_cid : String
  evidence_cid : String
  subject_cid : String
  measurement_cid : String
  revision : Int
  state : Array[Int]
}

///|
pub(all) enum NativeRemoteRuntimeIssue {
  Closed
  InvalidConfiguration
  RegistrationCollision
  RuntimeUnsupported
  BudgetUnsupported
  SiteUnavailable
  CapacityRejected
  AcceptanceUnconfirmed
  DispatchAlreadyStarted
  OperationRejected
  HoldingRejected
  SettlementRejected
  CustodyRejected
  OutputRejected
  OutputReaderUnavailable
  OutputReaderClosed
  OutputReaderIncomplete
  OutputReaderChunkExceeded
  OutputReaderPhysical(String)
  Physical(String)
  CleanupPending(String)
  Protocol(@remote.DispatchIssue)
  Journal(@journal.NativeRemoteJournalIssue)
  Bundle(@bundle.NativeRuntimeBundleStoreIssue)
}

///|
fn readmit_native_remote_output_manifest(
  manifest : @manifest.PhysicalManifest,
) -> @manifest.PhysicalManifest? {
  let chunks = manifest.chunks
  match
    @manifest.admit(
      "actql-managed-physical-manifest/0.1",
      manifest.schema_contract_cid,
      manifest.view_contract_cid,
      manifest.codec_contract_cid,
      manifest.row_count,
      chunks.map(chunk => chunk.cid),
      chunks.map(chunk => chunk.byte_length),
      chunks.map(chunk => chunk.row_count),
      chunks.length(),
      manifest.metadata_bytes,
      manifest.referenced_bytes,
    ) {
    Ok(value) =>
      if @manifest.manifest_cid(value) == @manifest.manifest_cid(manifest) {
        Some(value)
      } else {
        None
      }
    Err(_) => None
  }
}

///|
pub fn prepare_native_remote_output(
  facts : NativeRemoteOutputFacts,
  open_reader : () -> Result[NativeRemotePhysicalReader, String],
  open_manifest_reader : () -> Result[
    NativeRemotePhysicalManifestReader,
    String,
  ],
  release : () -> Bool,
) -> Result[NativeRemotePhysicalExecution, NativeRemoteRuntimeIssue] {
  let manifest = facts.physical_manifest
  guard readmit_native_remote_output_manifest(manifest)
    is Some(admitted_manifest) else {
    return Err(OutputRejected)
  }
  if admitted_manifest.schema_contract_cid != facts.result_schema_cid ||
    admitted_manifest.view_contract_cid != facts.logical_view_cid ||
    admitted_manifest.codec_contract_cid != facts.representation_codec_cid ||
    admitted_manifest.row_count != facts.row_count ||
    admitted_manifest.referenced_bytes != facts.retained_bytes {
    return Err(OutputRejected)
  }
  let measurement_cid = @remote.remote_managed_output_measurement_cid(
    facts.measurement,
  )
  match
    @remote.prepare_remote_managed_output_subject(
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      facts.material_generation,
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      facts.managed_profile_cid,
      facts.result_schema_cid,
      facts.logical_view_cid,
      facts.representation_codec_cid,
      @manifest.manifest_cid(admitted_manifest),
      measurement_cid,
      facts.row_count,
      facts.retained_bytes,
    ) {
    Ok(_) =>
      Ok(
        NativeRemoteOutputReady({
          facts: { ..facts, physical_manifest: admitted_manifest, },
          open_reader,
          open_manifest_reader,
          release,
        }),
      )
    Err(_) => Err(OutputRejected)
  }
}

///|
/// Wrap environment-owned physical output operations for common runtime use.
/// The callbacks must not make lifecycle or accounting decisions.
pub fn prepare_native_remote_physical_reader(
  next : (Int) -> Result[NativeRemoteOutputChunk, String],
  finish : () -> Result[Unit, String],
  close : () -> Result[Unit, String],
) -> NativeRemotePhysicalReader {
  { next, finish, close, }
}

///|
/// Wrap environment-owned physical manifest access for common verification.
/// The callback must return the complete chunk at the requested index; it may
/// not reinterpret the manifest or choose a different chunking scheme.
pub fn prepare_native_remote_physical_manifest_reader(
  next : (Int) -> Result[Bytes, String],
  finish : () -> Result[Unit, String],
  close : () -> Result[Unit, String],
) -> NativeRemotePhysicalManifestReader {
  { next, finish, close, }
}

///|
pub fn prepare_native_remote_failure(
  code : String,
  cancelled : Bool,
  stop_required : Bool,
  stop_confirmed : Bool,
  retry_stop : () -> Bool,
) -> Result[NativeRemotePhysicalExecution, NativeRemoteRuntimeIssue] {
  if code.is_empty() || (stop_required && stop_confirmed) {
    return Err(InvalidConfiguration)
  }
  Ok(
    NativeRemoteExecutionFailed({
      code,
      cancelled,
      stop_required,
      stop_confirmed: !stop_required || stop_confirmed,
      retry_stop,
    }),
  )
}

///|
fn scope_key(scope : Array[String]) -> String {
  scope.join("\u0000")
}

///|
fn install_native_remote_runtime_scope(
  site : @site.ExecutionSite,
  active_runtime : @bundle.NativeActiveRuntimeBinding,
  connector_registration : String,
  connector_revision : String,
  strategy_revision : String,
  operation_capability_cid : String,
  issuer_capability_cid : String,
  execute : (
    @remote.DispatchRequest,
    @remote.RemoteInputBinding,
    @remote.RemoteDispatchBudget,
  ) -> NativeRemotePhysicalExecution,
) -> Result[NativeRemoteRuntimeRegistration, NativeRemoteRuntimeIssue] {
  let runtime_bundle_cid = @bundle.native_active_runtime_bundle_cid(
    active_runtime,
  )
  let capability = match
    @remote.register_remote_execution_capability(
      site, runtime_bundle_cid, connector_registration, connector_revision, strategy_revision,
      operation_capability_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let issuer = match
    @remote.register_remote_evidence_issuer(
      site,
      runtime_bundle_cid,
      connector_registration,
      connector_revision,
      strategy_revision,
      @remote.remote_managed_output_evidence_kind(),
      issuer_capability_cid,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  let scope = match
    @remote.remote_managed_runtime_registration_scope(capability, issuer) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  Ok({
    site,
    active_runtime,
    runtime_bundle_cid,
    capability,
    issuer,
    key: scope_key(scope),
    supports: _request => true,
    execute,
  })
}

///|
/// Bind one executable implementation to the exact checked Run definition and
/// task key supplied by its installed runtime bundle. This performs no I/O and
/// grants no Site or evidence authority.
pub fn install_native_remote_task_executor(
  run_definition_cid : String,
  task_key : String,
  execute : (
    @remote.DispatchRequest,
    @remote.RemoteInputBinding,
    @remote.RemoteDispatchBudget,
  ) -> NativeRemotePhysicalExecution,
) -> Result[NativeRemoteTaskExecutor, NativeRemoteRuntimeIssue] {
  if task_key.is_empty() ||
    !run_definition_cid.has_prefix("sha256:") ||
    run_definition_cid.length() != 71 {
    return Err(InvalidConfiguration)
  }
  Ok({ key: run_definition_cid + "\u0000" + task_key, execute, })
}

///|
/// Install a Connector registration whose physical executor selection is
/// bounded by an exact task registry. Unsupported tasks are rejected before
/// durable acceptance, capacity acquisition, or physical execution.
pub fn install_native_remote_runtime_registry_registration(
  site : @site.ExecutionSite,
  active_runtime : @bundle.NativeActiveRuntimeBinding,
  operation_capability_cid : String,
  issuer_capability_cid : String,
  executors : Array[NativeRemoteTaskExecutor],
) -> Result[NativeRemoteRuntimeRegistration, NativeRemoteRuntimeIssue] {
  if executors.is_empty() {
    return Err(InvalidConfiguration)
  }
  let installed : Map[String, NativeRemoteTaskExecutor] = Map([])
  for executor in executors {
    if installed.contains(executor.key) {
      return Err(RegistrationCollision)
    }
    installed[executor.key] = executor
  }
  let (connector_registration, connector_revision, strategy_revision) = @bundle.native_active_runtime_connector_scope(
    active_runtime,
  )
  let registration = match
    install_native_remote_runtime_scope(
      site,
      active_runtime,
      connector_registration,
      connector_revision,
      strategy_revision,
      operation_capability_cid,
      issuer_capability_cid,
      (request, binding, budget) => {
        let (run_definition_cid, task_key) = @remote.dispatch_request_task_scope(
          request,
        )
        guard installed.get(run_definition_cid + "\u0000" + task_key)
          is Some(executor) else {
          return NativeRemoteExecutionFailed({
            code: "unregistered-task",
            cancelled: false,
            stop_required: false,
            stop_confirmed: true,
            retry_stop: () => true,
          })
        }
        (executor.execute)(request, binding, budget)
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    ..registration,
    supports: request => {
      let (run_definition_cid, task_key) = @remote.dispatch_request_task_scope(
        request,
      )
      installed.contains(run_definition_cid + "\u0000" + task_key)
    },
  })
}

///|
/// Open one runtime from already acquired component bindings. On success this
/// runtime owns every distinct process holding in the registrations. Callers
/// must not install the same binding into another live runtime. `close`
/// releases those holdings only after all physical execution and output
/// owners have closed; an open failure leaves them with the caller.
pub fn open_native_remote_runtime(
  journal : @journal.Journal,
  bundles : @bundle.NativeRuntimeBundleStore,
  registrations : Array[NativeRemoteRuntimeRegistration],
  budgets : Array[@remote.RemoteDispatchBudget],
) -> Result[NativeRemoteRuntime, NativeRemoteRuntimeIssue] {
  let installed : Map[String, NativeRemoteRuntimeRegistration] = Map([])
  let process_holds : Map[String, Bool] = Map([])
  for registration in registrations {
    if installed.contains(registration.key) {
      return Err(RegistrationCollision)
    }
    match bundles.verify_active_component_binding(registration.active_runtime) {
      Ok(_) => ()
      Err(issue) => return Err(Bundle(issue))
    }
    let process_hold_id = @bundle.native_active_runtime_process_hold_id(
      registration.active_runtime,
    )
    process_holds[process_hold_id] = false
    installed[registration.key] = registration
  }
  let provisioned : Map[String, @remote.RemoteDispatchBudget] = Map([])
  for budget in budgets {
    let key = @remote.remote_dispatch_budget_cid(budget)
    if provisioned.contains(key) {
      return Err(RegistrationCollision)
    }
    provisioned[key] = budget
  }
  Ok({
    journal,
    bundles,
    registrations: installed,
    process_holds,
    budgets: provisioned,
    admitting: Map([]),
    owners: Map([]),
    pending_cleanup: Map([]),
    closed: false,
  })
}

///|
fn NativeRemoteRuntime::registration_for(
  self : NativeRemoteRuntime,
  request : @remote.DispatchRequest,
) -> NativeRemoteRuntimeRegistration? {
  self.registrations.get(
    scope_key(@remote.dispatch_request_execution_scope(request)),
  )
}

///|
fn NativeRemoteRuntime::budget_for(
  self : NativeRemoteRuntime,
  request : @remote.DispatchRequest,
) -> @remote.RemoteDispatchBudget? {
  self.budgets.get(@remote.dispatch_request_budget_cid(request))
}

///|
fn NativeRemoteRuntimeOwner::settle_operation(
  self : NativeRemoteRuntimeOwner,
) -> Result[Unit, NativeRemoteRuntimeIssue] {
  if @remote.remote_runtime_custody_operation_settled(self.custody) {
    return Ok(())
  }
  if !@remote.remote_runtime_custody_operation_acquired(self.custody) {
    return Ok(())
  }
  guard self.operation is Some(operation) else {
    return Err(SettlementRejected)
  }
  if !@site.settle_site_operation(operation) {
    return Err(SettlementRejected)
  }
  if !@remote.remote_runtime_custody_settle_operation(self.custody) {
    return Err(CustodyRejected)
  }
  Ok(())
}

///|
fn NativeRemoteRuntime::commit_step(
  self : NativeRemoteRuntime,
  step : @remote.RemoteRuntimeStep,
) -> Result[Unit, NativeRemoteRuntimeIssue] {
  let transition = match @remote.remote_runtime_step_transition(step) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match self.journal.commit_transition(transition) {
    Ok(_) => Ok(())
    Err(issue) => Err(Journal(issue))
  }
}

///|
fn NativeRemoteRuntime::apply_failure_plan(
  self : NativeRemoteRuntime,
  owner : NativeRemoteRuntimeOwner,
) -> Result[Unit, NativeRemoteRuntimeIssue] {
  let step = match
    @remote.prepare_owned_remote_runtime_failure(owner.record, owner.custody) {
    Ok(value) => value
    Err(issue) => return Err(Protocol(issue))
  }
  match @remote.remote_runtime_step_action_code(step) {
    1 => self.commit_step(step)
    2 => {
      match owner.settle_operation() {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      self.commit_step(step)
    }
    _ => Err(Protocol(@remote.InvalidTransition))
  }
}

///|
fn NativeRemoteRuntime::retain_failed_owner(
  self : NativeRemoteRuntime,
  identity : String,
  owner : NativeRemoteRuntimeOwner,
  issue : NativeRemoteRuntimeIssue,
  cancelled : Bool,
  stop_required : Bool,
  stop_confirmed : Bool,
) -> NativeRemoteRuntimeIssue {
  ignore(self.owners.remove(identity))
  if !@remote.remote_runtime_custody_record_failure(
      owner.custody,
      cancelled,
      stop_required,
      stop_confirmed,
    ) {
    self.pending_cleanup[identity] = owner
    return CustodyRejected
  }
  self.pending_cleanup[identity] = owner
  match self.apply_failure_plan(owner) {
    Ok(_) => issue
    Err(persistence) => persistence
  }
}

///|
fn NativeRemoteRuntime::reclaim_owner_resources(
  self : NativeRemoteRuntime,
  owner : NativeRemoteRuntimeOwner,
) -> Result[Unit, NativeRemoteRuntimeIssue] {
  if @remote.remote_runtime_custody_output_acquired(owner.custody) &&
    !@remote.remote_runtime_custody_output_released(owner.custody) {
    if owner.active_readers != 0 {
      return Err(CleanupPending("output-readers"))
    }
    guard owner.output is Some(output) else { return Err(CustodyRejected) }
    if !(output.release)() {
      return Err(CleanupPending("output"))
    }
    if !@remote.remote_runtime_custody_release_output(owner.custody) {
      return Err(CustodyRejected)
    }
  }
  if @remote.remote_runtime_custody_holding_acquired(owner.custody) &&
    !@remote.remote_runtime_custody_holding_released(owner.custody) {
    guard owner.holding is Some(holding) else { return Err(CustodyRejected) }
    if !@site.release_site_holding(holding) {
      return Err(CleanupPending("holding"))
    }
    if !@remote.remote_runtime_custody_release_holding(owner.custody) {
      return Err(CustodyRejected)
    }
  }
  if @remote.remote_runtime_custody_bundle_acquired(owner.custody) &&
    !@remote.remote_runtime_custody_bundle_released(owner.custody) {
    match self.bundles.release(owner.bundle_hold_id) {
      Ok(true) => ()
      Ok(false) => return Err(CleanupPending("bundle"))
      Err(issue) => return Err(Bundle(issue))
    }
    if !@remote.remote_runtime_custody_release_bundle(owner.custody) {
      return Err(CustodyRejected)
    }
  }
  Ok(())
}

///|
fn NativeRemoteRuntime::drive_cleanup(
  self : NativeRemoteRuntime,
  owner : NativeRemoteRuntimeOwner,
  retry_stop : Bool,
) -> Result[Bool, NativeRemoteRuntimeIssue] {
  if @remote.remote_runtime_custody_stop_pending(owner.custody) {
    guard owner.physical_failure is Some(failure) else {
      return Err(CleanupPending("stop"))
    }
    if retry_stop && (failure.retry_stop)() {
      failure.stop_confirmed = true
      if !@remote.remote_runtime_custody_confirm_stop(owner.custody) {
        return Err(CustodyRejected)
      }
    }
    if @remote.remote_runtime_custody_stop_pending(owner.custody) {
      return Ok(false)
    }
  }
  while true {
    let step = match
      @remote.prepare_owned_remote_runtime_cleanup(owner.record, owner.custody) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    match @remote.remote_runtime_step_action_code(step) {
      0 => return Ok(false)
      1 =>
        match self.commit_step(step) {
          Ok(_) => continue
          Err(issue) => return Err(issue)
        }
      2 => {
        match owner.settle_operation() {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
        match self.commit_step(step) {
          Ok(_) => continue
          Err(issue) => return Err(issue)
        }
      }
      3 => {
        if owner.active_readers != 0 {
          return Ok(false)
        }
        match self.reclaim_owner_resources(owner) {
          Ok(_) => continue
          Err(issue) => {
            let unknown = match
              @remote.prepare_remote_runtime_reclaim_unknown(owner.record) {
              Ok(value) => value
              Err(protocol_issue) => return Err(Protocol(protocol_issue))
            }
            match self.commit_step(unknown) {
              Ok(_) => return Err(issue)
              Err(persistence) => return Err(persistence)
            }
          }
        }
      }
      4 => return Ok(true)
      _ => return Err(Protocol(@remote.InvalidTransition))
    }
  } nobreak {
    Err(Protocol(@remote.InvalidTransition))
  }
}

///|
fn native_remote_runtime_completion(
  owner : NativeRemoteRuntimeOwner,
) -> Result[NativeRemoteRuntimeCompletion, NativeRemoteRuntimeIssue] {
  guard owner.evidence is Some(evidence) else { return Err(OutputRejected) }
  guard owner.subject is Some(subject) else { return Err(OutputRejected) }
  guard owner.measurement is Some(measurement) else {
    return Err(OutputRejected)
  }
  Ok({
    dispatch_request_cid: @remote.dispatch_request_identity(owner.request),
    evidence_cid: @remote.remote_execution_evidence_cid(evidence),
    subject_cid: @remote.remote_managed_output_subject_cid(subject),
    measurement_cid: @remote.remote_managed_output_measurement_cid(measurement),
    revision: @remote.dispatch_record_revision(owner.record),
    state: @remote.dispatch_record_state_codes(owner.record),
  })
}

///|
fn NativeRemoteRuntime::run_success(
  self : NativeRemoteRuntime,
  owner : NativeRemoteRuntimeOwner,
  budget : @remote.RemoteDispatchBudget,
) -> Result[NativeRemoteRuntimeCompletion, NativeRemoteRuntimeIssue] {
  let identity = @remote.dispatch_request_identity(owner.request)
  let (retained_bytes, execution_bytes) = @remote.remote_dispatch_budget_capacity(
    budget,
  )
  while true {
    let action = match
      @remote.prepare_remote_runtime_success(owner.record, owner.custody) {
      Ok(value) => value
      Err(issue) =>
        return Err(
          self.retain_failed_owner(
            identity,
            owner,
            Protocol(issue),
            false,
            false,
            true,
          ),
        )
    }
    match action {
      @remote.RuntimeAcquireBundle => {
        match
          self.bundles.retain(
            owner.registration.runtime_bundle_cid,
            owner.bundle_hold_id,
            "dispatch",
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Bundle(issue))
        }
        if !@remote.remote_runtime_custody_acquire_bundle(owner.custody) {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              CustodyRejected,
              false,
              false,
              true,
            ),
          )
        }
        match self.bundles.verify(owner.registration.runtime_bundle_cid) {
          Ok(_) => continue
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Bundle(issue),
                false,
                false,
                true,
              ),
            )
        }
      }
      @remote.RuntimePersistProvisioning => {
        let transition = match
          @remote.prepare_begin_managed_provisioning(
            owner.record,
            owner.registration.capability,
            owner.registration.issuer,
          ) {
          Ok(value) => value
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Protocol(issue),
                false,
                false,
                true,
              ),
            )
        }
        match self.journal.commit_transition(transition) {
          Ok(_) => continue
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Journal(issue),
                false,
                false,
                true,
              ),
            )
        }
      }
      @remote.RuntimeAcquireOperation => {
        guard @site.start_site_operation(
            owner.registration.site,
            retained_bytes,
            execution_bytes,
          )
          is Some(operation) else {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              OperationRejected,
              false,
              false,
              true,
            ),
          )
        }
        owner.operation = Some(operation)
        if !@remote.remote_runtime_custody_acquire_operation(owner.custody) {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              CustodyRejected,
              false,
              false,
              true,
            ),
          )
        }
        continue
      }
      @remote.RuntimePersistRunning => {
        let transition = match
          @remote.prepare_begin_remote_execution(owner.record) {
          Ok(value) => value
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Protocol(issue),
                false,
                false,
                true,
              ),
            )
        }
        match self.journal.commit_transition(transition) {
          Ok(_) => continue
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Journal(issue),
                false,
                false,
                true,
              ),
            )
        }
      }
      @remote.RuntimeExecutePhysical =>
        match
          (owner.registration.execute)(owner.request, owner.binding, budget) {
          NativeRemoteOutputReady(output) => {
            owner.output = Some(output)
            if !@remote.remote_runtime_custody_acquire_output(owner.custody) {
              return Err(
                self.retain_failed_owner(
                  identity,
                  owner,
                  CustodyRejected,
                  false,
                  false,
                  true,
                ),
              )
            }
            if output.facts.retained_bytes > retained_bytes {
              return Err(
                self.retain_failed_owner(
                  identity,
                  owner,
                  OutputRejected,
                  false,
                  false,
                  true,
                ),
              )
            }
            continue
          }
          NativeRemoteExecutionFailed(failure) => {
            owner.physical_failure = Some(failure)
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Physical(failure.code),
                failure.cancelled,
                failure.stop_required,
                failure.stop_confirmed,
              ),
            )
          }
        }
      @remote.RuntimeAcquireHolding => {
        guard owner.operation is Some(operation) else {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              CustodyRejected,
              false,
              false,
              true,
            ),
          )
        }
        guard owner.output is Some(output) else {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              CustodyRejected,
              false,
              false,
              true,
            ),
          )
        }
        if !@site.site_operation_available(operation) {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              SiteUnavailable,
              false,
              false,
              true,
            ),
          )
        }
        guard @site.retain_site_operation_holding(
            operation,
            output.facts.retained_bytes,
          )
          is Some(holding) else {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              HoldingRejected,
              false,
              false,
              true,
            ),
          )
        }
        owner.holding = Some(holding)
        if !@remote.remote_runtime_custody_acquire_holding(owner.custody) {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              CustodyRejected,
              false,
              false,
              true,
            ),
          )
        }
        owner.holding_evidence_cid = match
          @remote.remote_output_holding_evidence_cid(
            owner.request,
            output.facts.material_generation,
            output.facts.retained_bytes,
          ) {
          Ok(value) => Some(value)
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Protocol(issue),
                false,
                false,
                true,
              ),
            )
        }
        continue
      }
      @remote.RuntimeSettleOperation =>
        match owner.settle_operation() {
          Ok(_) => continue
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity, owner, issue, false, false, true,
              ),
            )
        }
      @remote.RuntimePersistSettled => {
        let transition = match
          @remote.prepare_confirm_native_settled(owner.record) {
          Ok(value) => value
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Protocol(issue),
                false,
                false,
                true,
              ),
            )
        }
        match self.journal.commit_transition(transition) {
          Ok(_) => continue
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Journal(issue),
                false,
                false,
                true,
              ),
            )
        }
      }
      @remote.RuntimePersistRetained => {
        guard owner.output is Some(output) else {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              CustodyRejected,
              false,
              false,
              true,
            ),
          )
        }
        guard owner.holding_evidence_cid is Some(holding_evidence_cid) else {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              CustodyRejected,
              false,
              false,
              true,
            ),
          )
        }
        let transition = match
          @remote.prepare_retain_remote_output(
            owner.record,
            output.facts.material_generation,
            holding_evidence_cid,
          ) {
          Ok(value) => value
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Protocol(issue),
                false,
                false,
                true,
              ),
            )
        }
        self.owners[identity] = owner
        match self.journal.commit_transition(transition) {
          Ok(_) => continue
          Err(issue) => {
            ignore(self.owners.remove(identity))
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Journal(issue),
                false,
                false,
                true,
              ),
            )
          }
        }
      }
      @remote.RuntimePersistEvidence => {
        guard owner.output is Some(output) else {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              CustodyRejected,
              false,
              false,
              true,
            ),
          )
        }
        guard owner.holding_evidence_cid is Some(holding_evidence_cid) else {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              CustodyRejected,
              false,
              false,
              true,
            ),
          )
        }
        let measurement = output.facts.measurement
        let subject = match
          @remote.prepare_remote_managed_output_subject(
            identity,
            output.facts.material_generation,
            holding_evidence_cid,
            output.facts.managed_profile_cid,
            output.facts.result_schema_cid,
            output.facts.logical_view_cid,
            output.facts.representation_codec_cid,
            @manifest.manifest_cid(output.facts.physical_manifest),
            @remote.remote_managed_output_measurement_cid(measurement),
            output.facts.row_count,
            output.facts.retained_bytes,
          ) {
          Ok(value) => value
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Protocol(issue),
                false,
                false,
                true,
              ),
            )
        }
        if !@remote.remote_managed_output_subject_matches_measurement(
            subject, measurement,
          ) {
          return Err(
            self.retain_failed_owner(
              identity,
              owner,
              OutputRejected,
              false,
              false,
              true,
            ),
          )
        }
        let evidence = match
          @remote.issue_remote_managed_output_evidence(
            owner.registration.issuer,
            owner.record,
            subject,
          ) {
          Ok(value) => value
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Protocol(issue),
                false,
                false,
                true,
              ),
            )
        }
        let transition = match
          @remote.prepare_durable_execution_evidence(owner.record, evidence) {
          Ok(value) => value
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Protocol(issue),
                false,
                false,
                true,
              ),
            )
        }
        match
          self.journal.commit_evidence_transition(
            transition, evidence, subject, measurement,
          ) {
          Ok(_) => {
            owner.evidence = Some(evidence)
            owner.subject = Some(subject)
            owner.measurement = Some(measurement)
            continue
          }
          Err(issue) =>
            return Err(
              self.retain_failed_owner(
                identity,
                owner,
                Journal(issue),
                false,
                false,
                true,
              ),
            )
        }
      }
      @remote.RuntimeSuccessFinished =>
        return native_remote_runtime_completion(owner)
    }
  } nobreak {
    Err(Protocol(@remote.InvalidTransition))
  }
}

///|
/// Start one exact durable dispatch. The accepted record is persisted before
/// any registered executor is invoked. An existing nonterminal occurrence is
/// never converted into a second native execution.
pub fn NativeRemoteRuntime::start(
  self : NativeRemoteRuntime,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
) -> Result[NativeRemoteRuntimeCompletion, NativeRemoteRuntimeIssue] {
  self.start_after_acceptance(request, binding, _ => true)
}

///|
/// Start one exact durable dispatch after its accepted record has been
/// observed by the transport owner. The callback runs only after Site journal
/// admission and before any bundle, Site-operation, or physical-executor
/// acquisition. A rejected observation leaves the accepted record startable;
/// an exact retransmission may retry the observation without duplicating
/// native work.
pub fn NativeRemoteRuntime::start_after_acceptance(
  self : NativeRemoteRuntime,
  request : @remote.DispatchRequest,
  binding : @remote.RemoteInputBinding,
  observe_accepted : (@remote.DispatchRecord) -> Bool,
) -> Result[NativeRemoteRuntimeCompletion, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Err(Closed)
  }
  if !self.admitting.is_empty() {
    return Err(DispatchAlreadyStarted)
  }
  let identity = @remote.dispatch_request_identity(request)
  if self.pending_cleanup.contains(identity) {
    return Err(CleanupPending("dispatch"))
  }
  if !@remote.remote_input_binding_matches_dispatch(binding, request) {
    return Err(Protocol(@remote.DispatchIdentityMismatch))
  }
  match self.owners.get(identity) {
    Some(owner) => {
      self.admitting[identity] = true
      let observed = observe_accepted(owner.record)
      ignore(self.admitting.remove(identity))
      if self.closed {
        return Err(Closed)
      }
      if !observed {
        return Err(AcceptanceUnconfirmed)
      }
      guard self.owners.get(identity) is Some(current) else {
        return Err(DispatchAlreadyStarted)
      }
      return native_remote_runtime_completion(current)
    }
    None => ()
  }
  let registration = match self.registration_for(request) {
    Some(value) => value
    None => return Err(RuntimeUnsupported)
  }
  if !(registration.supports)(request) {
    return Err(RuntimeUnsupported)
  }
  let budget = match self.budget_for(request) {
    Some(value) => value
    None => return Err(BudgetUnsupported)
  }
  if !@site.site_available(registration.site) {
    return Err(SiteUnavailable)
  }
  let (retained_bytes, execution_bytes) = @remote.remote_dispatch_budget_capacity(
    budget,
  )
  if !@site.site_capacity_supports(
      registration.site,
      retained_bytes,
      execution_bytes,
    ) {
    return Err(CapacityRejected)
  }
  let active = match self.bundles.active() {
    Ok(value) => value
    Err(issue) => return Err(Bundle(issue))
  }
  guard active is Some(snapshot) else { return Err(RuntimeUnsupported) }
  if snapshot.runtime_bundle_cid != registration.runtime_bundle_cid {
    return Err(RuntimeUnsupported)
  }
  match
    self.bundles.verify_active_component_binding(registration.active_runtime) {
    Ok(_) => ()
    Err(issue) => return Err(Bundle(issue))
  }
  match self.bundles.verify(registration.runtime_bundle_cid) {
    Ok(_) => ()
    Err(issue) => return Err(Bundle(issue))
  }
  let record = match self.journal.accept(request) {
    Ok((_, value)) => value
    Err(issue) => return Err(Journal(issue))
  }
  if !@remote.dispatch_record_matches_request(record, request) {
    return Err(Protocol(@remote.DispatchIdentityMismatch))
  }
  if !@remote.remote_runtime_record_startable(record) {
    return Err(DispatchAlreadyStarted)
  }
  self.admitting[identity] = true
  let observed = observe_accepted(record)
  ignore(self.admitting.remove(identity))
  if !observed {
    return Err(AcceptanceUnconfirmed)
  }
  if self.closed {
    return Err(Closed)
  }
  if !@site.site_available(registration.site) {
    return Err(SiteUnavailable)
  }
  match
    self.bundles.verify_active_component_binding(registration.active_runtime) {
    Ok(_) => ()
    Err(issue) => return Err(Bundle(issue))
  }
  let record = match self.journal.require(request) {
    Ok(value) => value
    Err(issue) => return Err(Journal(issue))
  }
  if !@remote.dispatch_record_matches_request(record, request) ||
    !@remote.remote_runtime_record_startable(record) {
    return Err(DispatchAlreadyStarted)
  }
  let owner : NativeRemoteRuntimeOwner = {
    request,
    binding,
    record,
    registration,
    custody: @remote.create_remote_runtime_custody(),
    bundle_hold_id: "dispatch:" + identity,
    operation: None,
    output: None,
    holding: None,
    holding_evidence_cid: None,
    physical_failure: None,
    evidence: None,
    subject: None,
    measurement: None,
    active_readers: 0,
  }
  self.run_success(owner, budget)
}

///|
/// Open a bounded reader for the exact currently retained material. This is a
/// new consumer admission: a closed runtime or unavailable Site cannot grant
/// another pin, while already-open readers remain owned until physical close.
pub fn NativeRemoteRuntime::open_output_reader(
  self : NativeRemoteRuntime,
  request : @remote.DispatchRequest,
  material_generation : String,
  max_chunk_bytes : Int,
) -> Result[NativeRemoteOutputReader, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Err(Closed)
  }
  if max_chunk_bytes <= 0 || max_chunk_bytes > 1048576 {
    return Err(OutputReaderUnavailable)
  }
  let identity = @remote.dispatch_request_identity(request)
  guard self.owners.get(identity) is Some(owner) else {
    return Err(OutputReaderUnavailable)
  }
  if !@remote.dispatch_record_matches_request(owner.record, request) ||
    !@site.site_available(owner.registration.site) {
    return Err(OutputReaderUnavailable)
  }
  guard owner.output is Some(output) else {
    return Err(OutputReaderUnavailable)
  }
  if output.facts.material_generation != material_generation ||
    !@remote.remote_runtime_custody_output_acquired(owner.custody) ||
    @remote.remote_runtime_custody_output_released(owner.custody) ||
    !@remote.remote_runtime_custody_holding_acquired(owner.custody) ||
    @remote.remote_runtime_custody_holding_released(owner.custody) {
    return Err(OutputReaderUnavailable)
  }
  match native_remote_runtime_completion(owner) {
    Ok(_) => ()
    Err(_) => return Err(OutputReaderUnavailable)
  }
  let physical = match (output.open_reader)() {
    Ok(value) => value
    Err(issue) => return Err(OutputReaderPhysical(issue))
  }
  owner.active_readers += 1
  Ok({ owner, physical, max_chunk_bytes, eof: false, closed: false, })
}

///|
/// Open a manifest-preserving reader for an explicit Transfer occurrence.
/// Every admitted physical chunk must fit the caller's bounded buffer; this
/// operation never combines chunks or materializes the complete Result.
pub fn NativeRemoteRuntime::open_output_manifest_reader(
  self : NativeRemoteRuntime,
  request : @remote.DispatchRequest,
  material_generation : String,
  max_chunk_bytes : Int,
) -> Result[NativeRemoteOutputManifestReader, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Err(Closed)
  }
  if max_chunk_bytes <= 0 || max_chunk_bytes > 1048576 {
    return Err(OutputReaderUnavailable)
  }
  let identity = @remote.dispatch_request_identity(request)
  guard self.owners.get(identity) is Some(owner) else {
    return Err(OutputReaderUnavailable)
  }
  if !@remote.dispatch_record_matches_request(owner.record, request) ||
    !@site.site_available(owner.registration.site) {
    return Err(OutputReaderUnavailable)
  }
  guard owner.output is Some(output) else {
    return Err(OutputReaderUnavailable)
  }
  if output.facts.material_generation != material_generation ||
    !@remote.remote_runtime_custody_output_acquired(owner.custody) ||
    @remote.remote_runtime_custody_output_released(owner.custody) ||
    !@remote.remote_runtime_custody_holding_acquired(owner.custody) ||
    @remote.remote_runtime_custody_holding_released(owner.custody) {
    return Err(OutputReaderUnavailable)
  }
  guard readmit_native_remote_output_manifest(output.facts.physical_manifest)
    is Some(manifest) else {
    return Err(OutputRejected)
  }
  for chunk in manifest.chunks {
    if chunk.byte_length > max_chunk_bytes.to_int64() {
      return Err(OutputReaderChunkExceeded)
    }
  }
  match native_remote_runtime_completion(owner) {
    Ok(_) => ()
    Err(_) => return Err(OutputReaderUnavailable)
  }
  let physical = match (output.open_manifest_reader)() {
    Ok(value) => value
    Err(issue) => return Err(OutputReaderPhysical(issue))
  }
  owner.active_readers += 1
  Ok({ owner, physical, manifest, max_chunk_bytes, index: 0, closed: false, })
}

///|
/// Read and verify one complete physical manifest chunk in manifest order.
pub fn NativeRemoteOutputManifestReader::next(
  self : NativeRemoteOutputManifestReader,
) -> Result[NativeRemoteOutputManifestChunk?, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Err(OutputReaderClosed)
  }
  if self.index == self.manifest.chunks.length() {
    return Ok(None)
  }
  let index = self.index
  let expected = self.manifest.chunks[index]
  let bytes = match (self.physical.next)(index) {
    Ok(value) => value
    Err(issue) => return Err(OutputReaderPhysical(issue))
  }
  if bytes.length() > self.max_chunk_bytes ||
    bytes.length().to_int64() != expected.byte_length ||
    "sha256:" + @sha.hex(bytes) != expected.cid {
    return Err(OutputRejected)
  }
  self.index += 1
  Ok(Some({ index, bytes, }))
}

///|
/// Confirm that every manifest chunk was consumed and release the reader pin.
pub fn NativeRemoteOutputManifestReader::finish(
  self : NativeRemoteOutputManifestReader,
) -> Result[Bool, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Ok(false)
  }
  if self.index != self.manifest.chunks.length() {
    return Err(OutputReaderIncomplete)
  }
  match (self.physical.finish)() {
    Ok(_) => ()
    Err(issue) => return Err(OutputReaderPhysical(issue))
  }
  self.owner.active_readers -= 1
  self.closed = true
  Ok(true)
}

///|
/// Abort manifest access and release the pin only after physical stop.
pub fn NativeRemoteOutputManifestReader::close(
  self : NativeRemoteOutputManifestReader,
) -> Result[Bool, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Ok(false)
  }
  match (self.physical.close)() {
    Ok(_) => ()
    Err(issue) => return Err(OutputReaderPhysical(issue))
  }
  self.owner.active_readers -= 1
  self.closed = true
  Ok(true)
}

///|
pub fn NativeRemoteOutputManifestReader::physical_manifest(
  self : NativeRemoteOutputManifestReader,
) -> Result[@manifest.PhysicalManifest, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Err(OutputReaderClosed)
  }
  match readmit_native_remote_output_manifest(self.manifest) {
    Some(value) => Ok(value)
    None => Err(OutputRejected)
  }
}

///|
pub fn NativeRemoteOutputManifestReader::material_generation(
  self : NativeRemoteOutputManifestReader,
) -> Result[String, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Err(OutputReaderClosed)
  }
  guard self.owner.output is Some(output) else {
    return Err(OutputReaderUnavailable)
  }
  Ok(output.facts.material_generation)
}

///|
/// Read one bounded chunk. Physical errors and oversized adapter responses do
/// not release the reader pin; the caller must confirm finish or close.
pub fn NativeRemoteOutputReader::next(
  self : NativeRemoteOutputReader,
) -> Result[NativeRemoteOutputChunk, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Err(OutputReaderClosed)
  }
  if self.eof {
    return Err(OutputReaderIncomplete)
  }
  let chunk = match (self.physical.next)(self.max_chunk_bytes) {
    Ok(value) => value
    Err(issue) => return Err(OutputReaderPhysical(issue))
  }
  if chunk.bytes.length() > self.max_chunk_bytes {
    return Err(OutputReaderChunkExceeded)
  }
  if chunk.eof {
    self.eof = true
  }
  Ok(chunk)
}

///|
/// Return a fresh admitted snapshot of the exact physical manifest bound to
/// this live reader occurrence. The snapshot conveys no Transfer grant or
/// completion authority; it only prevents adapters from reconstructing the
/// physical source from detached strings.
pub fn NativeRemoteOutputReader::physical_manifest(
  self : NativeRemoteOutputReader,
) -> Result[@manifest.PhysicalManifest, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Err(OutputReaderClosed)
  }
  guard self.owner.output is Some(output) else {
    return Err(OutputReaderUnavailable)
  }
  match readmit_native_remote_output_manifest(output.facts.physical_manifest) {
    Some(value) => Ok(value)
    None => Err(OutputRejected)
  }
}

///|
/// Return the exact retained generation pinned by this reader occurrence.
pub fn NativeRemoteOutputReader::material_generation(
  self : NativeRemoteOutputReader,
) -> Result[String, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Err(OutputReaderClosed)
  }
  guard self.owner.output is Some(output) else {
    return Err(OutputReaderUnavailable)
  }
  Ok(output.facts.material_generation)
}

///|
/// Confirm complete physical consumption and release this reader pin once.
pub fn NativeRemoteOutputReader::finish(
  self : NativeRemoteOutputReader,
) -> Result[Bool, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Ok(false)
  }
  if !self.eof {
    return Err(OutputReaderIncomplete)
  }
  match (self.physical.finish)() {
    Ok(_) => ()
    Err(issue) => return Err(OutputReaderPhysical(issue))
  }
  self.owner.active_readers -= 1
  self.closed = true
  Ok(true)
}

///|
/// Abort a physical read and release its pin only after close is confirmed.
/// A failed close remains retryable on the same reader.
pub fn NativeRemoteOutputReader::close(
  self : NativeRemoteOutputReader,
) -> Result[Bool, NativeRemoteRuntimeIssue] {
  if self.closed {
    return Ok(false)
  }
  match (self.physical.close)() {
    Ok(_) => ()
    Err(issue) => return Err(OutputReaderPhysical(issue))
  }
  self.owner.active_readers -= 1
  self.closed = true
  Ok(true)
}

///|
/// Release one successfully retained output. A false result means there was
/// no live owner or an admitted reader still pins it; cleanup failures remain
/// retryable.
pub fn NativeRemoteRuntime::release(
  self : NativeRemoteRuntime,
  request : @remote.DispatchRequest,
) -> Result[Bool, NativeRemoteRuntimeIssue] {
  let identity = @remote.dispatch_request_identity(request)
  guard self.owners.get(identity) is Some(owner) else { return Ok(false) }
  match self.drive_cleanup(owner, false) {
    Ok(true) => {
      ignore(self.owners.remove(identity))
      Ok(true)
    }
    Ok(false) => Ok(false)
    Err(issue) => Err(issue)
  }
}

///|
/// Retry stop observation and cleanup for a failed occurrence. A false result
/// preserves the owner and all capacity while physical stop is unconfirmed.
pub fn NativeRemoteRuntime::cleanup(
  self : NativeRemoteRuntime,
  request : @remote.DispatchRequest,
) -> Result[Bool, NativeRemoteRuntimeIssue] {
  let identity = @remote.dispatch_request_identity(request)
  guard self.pending_cleanup.get(identity) is Some(owner) else {
    return Ok(false)
  }
  match self.drive_cleanup(owner, true) {
    Ok(true) => {
      ignore(self.pending_cleanup.remove(identity))
      Ok(true)
    }
    Ok(false) => Ok(false)
    Err(issue) => Err(issue)
  }
}

///|
pub fn NativeRemoteRuntime::cleanup_pending(self : NativeRemoteRuntime) -> Bool {
  !self.pending_cleanup.is_empty()
}

///|
/// Stop admission and attempt all known releases. Owners remain installed if
/// any stop, physical release, or durable transition is still unconfirmed.
pub fn NativeRemoteRuntime::close(
  self : NativeRemoteRuntime,
) -> Result[Bool, NativeRemoteRuntimeIssue] {
  let changed = !self.closed
  self.closed = true
  let mut failure : NativeRemoteRuntimeIssue? = None
  let owner_keys = self.owners.keys().to_array()
  for key in owner_keys {
    guard self.owners.get(key) is Some(owner) else { continue }
    match self.drive_cleanup(owner, false) {
      Ok(true) => ignore(self.owners.remove(key))
      Ok(false) => ()
      Err(issue) => if failure is None { failure = Some(issue) }
    }
  }
  let pending_keys = self.pending_cleanup.keys().to_array()
  for key in pending_keys {
    guard self.pending_cleanup.get(key) is Some(owner) else { continue }
    match self.drive_cleanup(owner, true) {
      Ok(true) => ignore(self.pending_cleanup.remove(key))
      Ok(false) => ()
      Err(issue) => if failure is None { failure = Some(issue) }
    }
  }
  if !self.admitting.is_empty() ||
    !self.owners.is_empty() ||
    !self.pending_cleanup.is_empty() {
    match failure {
      Some(issue) => Err(issue)
      None => Err(CleanupPending("runtime"))
    }
  } else {
    let mut released = false
    let hold_ids = self.process_holds.keys().to_array()
    for hold_id in hold_ids {
      guard self.process_holds.get(hold_id) is Some(false) else { continue }
      match self.bundles.release(hold_id) {
        Ok(true) => {
          self.process_holds[hold_id] = true
          released = true
        }
        Ok(false) => return Err(Bundle(@bundle.MissingBundle))
        Err(issue) => return Err(Bundle(issue))
      }
    }
    Ok(changed || released)
  }
}
