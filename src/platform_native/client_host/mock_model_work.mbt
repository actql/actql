///|
// Caller retention inside the existing Native Host, not another Model,
// Resource, Journal or cleanup owner. The installing caller funds this fixed
// control and retains it before attempting open; the original Model read
// consumer and its Scope remain responsible for every partial constructor.
struct NativeClientMockModelWork {
  capture : NativeLocalJournalCapture
  request : @host.ClientRequestIdentity
  compiled : @host.ClientCompiledRun
  definition : @publication.PublicationContract
  graph : @host.ClientInferPlanGraph
  provider_role : NativeClientModelWorkProvider
  _retained_provider : @model.ModelProvider
  _retained_limits : @infer.Limits
  _retained_observation_capacity : @execution.ExecutionCapacity
  principal : String
  namespace_id : String
  current_time : () -> String
  mut first_start : NativeClientWorkFirstStart?
  mut active : @infer.Execution?
  mut prepared : @model.ModelPreparedCallSet?
  mut admission : @host.ClientInferDispatchAdmission?
  mut scope : @publication.BoundModelInvocationScope?
  mut account : @authorization.AdmittedAccountConfiguration?
  mut observation_time : String?
  mut entry : @model.ModelCallEntry?
  mut entry_recording : Bool
  mut entry_recorded : Bool
  mut entry_not_recorded : Bool
  mut entry_issue : NativeLocalAdoptionIssue?
  mut settlement : NativeMockModelSettlement?
  mut effect_review : NativeMockEffectReview?
  mut publication_capacity : @model.OriginalModelPublicationCapacity?
  mut publication_retained : Int64
  mut publication_execution : Int64
  mut observation : @infer.ObservationIssuance?
  mut publication_inputs : (Array[String], Array[@publication.RunEvidenceValue])?
  mut local_scan : @execution.CompletedRelationIdentityScan?
  mut local_receipt : @execution.CompletedRelationExportReceipt?
  mut local_observation : @infer.LocalModelObservation?
  mut local_use : @infer.OutputUse?
  mut lookup_entries : Array[NativeMockLookupJournalEntry]?
  mut open_attempted : Bool
  mut advancing : Bool
  mut closing : Bool
  mut closed : Bool
}

///|
pub(all) enum NativeClientMockModelIssue {
  ForeignOriginal
  NotOpened
  CleanupPending
  Account(@authorization.AccountOutcome)
  Original(NativeLocalAdoptionIssue)
  Model(@infer.Issue)
  Binding(@infer.InvocationBindingIssue)
  Dispatch(@host.ClientInferDispatchIssue)
  Egress(@host.ClientInferEgressIssue)
  Evidence(@publication.RunEvidenceValueIssue)
  Capture(@model.ModelExecutionIssue)
  Store(@publication_store.NativePublicationStoreIssue)
  Transport(NativeClientModelHttpIssue)
  Start(NativeClientSourceWorkIssue)
  Review(NativeClientMockEffectReviewIssue)
  Encoding
}

///|
/// Fixed caller control only. This does not enter a read, open a new Ledger,
/// start input, issue a Run or authorize a provider. The caller retains it
/// before its first fallible original Model constructor.
pub fn prepare_native_client_mock_model_work(
  capture : NativeLocalJournalCapture,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @host.ClientInferPlanGraph,
  profile : @environment.ModelMockProfile,
  provider : @model.ModelProvider,
  limits : @infer.Limits,
  principal : String,
  namespace_id : String,
  current_time : () -> String,
) -> Result[NativeClientMockModelWork, NativeClientMockModelIssue] {
  if !@environment.model_mock_profile_current(profile) {
    return Err(ForeignOriginal)
  }
  prepare_native_client_model_work(
    capture,
    request,
    compiled,
    definition,
    graph,
    Mock(profile),
    provider,
    limits,
    principal,
    namespace_id,
    current_time,
  )
}

///|
fn prepare_native_client_model_work(
  capture : NativeLocalJournalCapture,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @host.ClientInferPlanGraph,
  provider_role : NativeClientModelWorkProvider,
  provider : @model.ModelProvider,
  limits : @infer.Limits,
  principal : String,
  namespace_id : String,
  current_time : () -> String,
) -> Result[NativeClientMockModelWork, NativeClientMockModelIssue] {
  if principal.is_empty() ||
    namespace_id.is_empty() ||
    @infer.check_original_composed_preparation(
      compiled,
      definition,
      graph.occurrence,
      graph,
    )
    is Err(_) {
    return Err(ForeignOriginal)
  }
  guard native_client_mock_model_observation_capacity(limits)
    is Some(observation_capacity) else {
    return Err(Encoding)
  }
  Ok({
    capture,
    request,
    compiled,
    definition,
    graph,
    provider_role,
    _retained_provider: provider,
    _retained_limits: limits,
    _retained_observation_capacity: observation_capacity,
    principal,
    namespace_id,
    current_time,
    first_start: None,
    active: None,
    prepared: None,
    admission: None,
    scope: None,
    account: None,
    observation_time: None,
    entry: None,
    entry_recording: false,
    entry_recorded: false,
    entry_not_recorded: false,
    entry_issue: None,
    settlement: None,
    effect_review: None,
    publication_capacity: None,
    publication_retained: 0L,
    publication_execution: 0L,
    observation: None,
    publication_inputs: None,
    local_scan: None,
    local_receipt: None,
    local_observation: None,
    local_use: None,
    lookup_entries: Some([]),
    open_attempted: false,
    advancing: false,
    closing: false,
    closed: false,
  })
}

///|
/// Claim the accepted original exactly once in its captured Journal Read.
/// The retained token, not a replay of durable flags, gates subsequent reads.
pub fn NativeClientMockModelWork::claim_start_in_original_read(
  self : Self,
  connection : String,
) -> Result[Unit, NativeClientMockModelIssue] {
  if self.first_start is Some(_) ||
    self.open_attempted ||
    self.closing ||
    self.closed {
    return Err(ForeignOriginal)
  }
  let result = self.capture.claim_effect_start_in_original_read(
    self.request,
    self.principal,
    connection,
    () => !self.closing && !self.closed,
    token => self.first_start = Some(token),
  )
  match result {
    Ok(value) => value.map_err(issue => Start(issue))
    Err(issue) => Err(Original(issue))
  }
}

///|
/// Check the original start and actual Source permission at each physical
/// boundary. No Source name, checked catalogue or retained token is an Allow.
pub fn NativeClientMockModelWork::require_source_in_original_read(
  self : Self,
  control_connection : String,
  source_connection : String,
  resource : String,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard self.first_start is Some(first) && !self.closing && !self.closed else {
    return Err(ForeignOriginal)
  }
  let result = self.capture.require_effect_source_in_original_read(
    first,
    self.request,
    self.principal,
    control_connection,
    source_connection,
    resource,
    () => !self.closing && !self.closed,
  )
  match result {
    Ok(value) => value.map_err(issue => Start(issue))
    Err(issue) => Err(Original(issue))
  }
}

///|
/// Observe this same accepted/started Run and its actual Account while the
/// caller has entered its captured Read. The bounded next Model step consumes
/// these originals without nesting filesystem/SQLite callbacks in Core. This
/// is an Account snapshot, never a cached Allow; dispatch still uses Core's
/// existing exact Task/Scope authorization owner. Refresh before every step.
pub fn NativeClientMockModelWork::observe_step_in_original_read(
  self : Self,
) -> Result[Unit, NativeClientMockModelIssue] {
  self.observe_model_step_in_original_read(physical=false)
}

///|
fn NativeClientMockModelWork::observe_model_step_in_original_read(
  self : Self,
  physical~ : Bool,
) -> Result[Unit, NativeClientMockModelIssue] {
  try {
    if self.closing ||
      self.closed ||
      self.advancing ||
      self.entry_issue is Some(_) {
      return Err(ForeignOriginal)
    }
    self.account = None
    self.observation_time = None
    // The clock may reenter. Observe the physical originals AFTER it returns.
    let at = (self.current_time)()
    if self.closing || self.closed || self.advancing {
      return Err(ForeignOriginal)
    }
    let account = mock_model_require(
      self.capture
      .with_current_adoption_material_in_original_read((
        host,
        material,
        operations,
      ) => {
        let record = match
          host.journal.retained(self.request, reads=Some(operations.reads)) {
          Ok(Some(value)) => value
          Ok(None) => return Err(Journal(CustodyLost))
          Err(issue) => return Err(Journal(issue))
        }
        if !record.dispatch_reserved ||
          !record.physical_start_claimed ||
          record.cancellation_requested ||
          record.checkpoint is Some(_) ||
          @publication.publication_contract_identity(record.definition) !=
          @publication.publication_contract_identity(self.definition) {
          return Err(Journal(ForeignRun))
        }
        let current = match
          @host.client_local_adopted_current_account(material, host.database) {
          Ok(value) => value
          Err(issue) => return Err(local_current_material_issue(issue))
        }
        if physical {
          host.journal
          .recheck_model_run_cut(self.request, operations.reads)
          .map_err(issue => NativeLocalAdoptionIssue::Journal(issue))
          .map(_ => current)
        } else {
          Ok(current)
        }
      })
      .map_err(issue => NativeClientMockModelIssue::Original(issue)),
    )
    if self.closing || self.closed || self.advancing {
      return Err(ForeignOriginal)
    }
    self.account = Some(account)
    self.observation_time = Some(at)
    Ok(())
  } catch {
    NativeMockModelStop(issue) => Err(issue)
  }
}

///|
/// Enter the already claimed same-Run read consumer. Every constructor stays
/// in the original Model frame. A failed open cannot start again or invent a
/// replacement read; its installing caller retires that same partial Scope.
pub fn NativeClientMockModelWork::open(
  self : Self,
  sequence : @execution.GeneratedSequence,
  consumer : @host.ClientModelReadConsumer,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  model_retained_bytes : Int64,
  model_execution_bytes : Int64,
  sources? : @host.ClientInferComposedSources? = None,
  input_body_read? : @host.ClientModelReadPreparation? = None,
  inputs? : Array[@compute_local.ManagedProviderInput] = [],
  prior_input_work? : Int64 = 0L,
  compiled_prefix? : Bool = false,
  compiled_suffix? : @execution.GeneratedSequence? = None,
) -> Result[Unit, NativeClientMockModelIssue] {
  try {
    if self.open_attempted ||
      self.closing ||
      self.closed ||
      self.advancing ||
      self.account is None ||
      self.observation_time is None {
      return Err(ForeignOriginal)
    }
    if prior_input_work < 0L ||
      prior_input_work > self._retained_limits.input.max_work.to_int64() {
      return Err(Model(@infer.Input(@local.InvalidLimits)))
    }
    self.open_attempted = true
    let (_, _, model_step) = @host.client_infer_occurrence_coordinates(
      self.graph.occurrence,
    )
    // Real producer ports consume exactly the checked pre-Model prefix. Keep
    // the full original for the later suffix; this view preserves its owner
    // and step coordinates and neither recompiles nor copies kernel contexts.
    let input_sequence = if compiled_prefix {
      guard sources is None &&
        @execution.generated_sequence_step_count(sequence) == model_step else {
        return Err(ForeignOriginal)
      }
      sequence
    } else if inputs.is_empty() {
      sequence
    } else {
      guard @execution.select_generated_sequence_prefix(
          sequence,
          model_step - 1,
        )
        is Some(prefix) else {
        return Err(Model(@infer.Input(@local.UnsupportedProgram)))
      }
      prefix
    }
    let active = mock_model_require(
      @infer.start_original_composed(
        self.graph.occurrence,
        self.graph,
        input_sequence,
        inputs,
        self._retained_provider,
        self._retained_limits,
        self.compiled,
        self.definition,
        consumer,
        read_retained_bytes,
        read_execution_bytes,
        model_retained_bytes,
        model_execution_bytes,
        sources~,
        input_body_read~,
        prior_input_work~,
      ).map_err(issue => NativeClientMockModelIssue::Model(issue)),
    )
    self.active = Some(active)
    guard @host.client_infer_occurrence_output_step(self.graph.occurrence)
      is Some(last) &&
      last >= model_step else {
      return Err(ForeignOriginal)
    }
    if last > model_step {
      // Ordinary deferred providers borrow the funded suffix lowered by
      // Request preparation. The existing Effect route still uses its whole
      // selected sequence. The Core checks exact owner and step coordinates.
      let suffix = if compiled_prefix {
        compiled_suffix
      } else {
        @execution.select_generated_sequence_range(
          sequence,
          model_step + 1,
          last,
        )
      }
      guard suffix is Some(suffix) else { return Err(ForeignOriginal) }
      mock_model_require(
        @infer.bind_compute_suffix(active, suffix).map_err(issue => {
          NativeClientMockModelIssue::Model(issue)
        }),
      )
    }
    if compiled_suffix is Some(_) && (!compiled_prefix || last == model_step) {
      return Err(ForeignOriginal)
    }
    mock_model_require(
      @infer.require_model_call_entry(active).map_err(issue => {
        NativeClientMockModelIssue::Binding(issue)
      }),
    )
    let execution = @host.client_infer_plan_graph_execution_contract(self.graph)
    let task = @environment.model_execution_task(execution)
    // The original installed Mock profile declares its actual local-only region
    // and no retention/training. Core combines this observation with ALL checked
    // source policies; the provider can never lower an unknown classification.
    let region = @environment.model_task_region_at(task, 0).unwrap_or("")
    let egress = match self.provider_role {
      Mock(profile) =>
        mock_model_require(
          @host.admit_client_infer_occurrence_egress(
            self.graph.occurrence,
            execution,
            () => {
              if self.closing ||
                !@environment.model_mock_profile_current(profile) {
                None
              } else {
                Some({
                  classification: @environment.Public,
                  region,
                  provider_retention: false,
                  training_use: false,
                })
              }
            },
          ).map_err(issue => NativeClientMockModelIssue::Egress(issue)),
        )
      PortableHttp(work) => {
        mock_model_require(work.bind_preflight(active))
        work.installation.run_policy.egress
      }
    }
    mock_model_require(
      @infer.bind_egress_admission(active, egress).map_err(issue => {
        NativeClientMockModelIssue::Model(issue)
      }),
    )
    Ok(())
  } catch {
    NativeMockModelStop(issue) => Err(issue)
  }
}

///|
fn NativeClientMockModelWork::current_step(
  self : Self,
) -> Result[
  (@authorization.AdmittedAccountConfiguration, String),
  @host.ClientInferDispatchIssue,
] {
  guard self.advancing &&
    !self.closing &&
    !self.closed &&
    self.account is Some(account) &&
    self.observation_time is Some(at) else {
    return Err(@host.ForeignRun)
  }
  Ok((account, at))
}

///|
// Mechanical emission of the existing scope contract. The existing Core sealer
// and bind_model_scope remain the only schema/identity/Run/slot validators.
fn native_mock_model_invocation_scope(
  definition : @publication.PublicationContract,
  prepared : @model.ModelPreparedCallSet,
  provider : @publication.RunEvidenceValue,
  boundary : @publication.ModelInvocationBoundary,
) -> Result[@publication.RunEvidenceValue, NativeClientMockModelIssue] {
  guard @model.prepared_model_input_artifact(prepared) is Some(input) &&
    @model.prepared_model_call_count(prepared) is Some(count) else {
    return Err(ForeignOriginal)
  }
  try {
    let writer = @encode.writer(16384, 1024, 20)
    @encode.begin_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-model-invocation-scope/0.1")
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(
      writer,
      @publication.publication_contract_identity(definition),
    )
    @encode.key(writer, "task_index")
    @encode.number_value(writer, boundary.task_index.to_double())
    @encode.key(writer, "strategy_revision")
    @encode.number_value(writer, boundary.strategy_revision.to_double())
    @encode.key(writer, "inference_barrier_cid")
    @encode.string_value(writer, boundary.inference_barrier_cid)
    @encode.key(writer, "input_artifact_cid")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(input),
    )
    @encode.key(writer, "model_call_slot_cids")
    @encode.begin_array(writer)
    for slot in 0..<count {
      guard @model.prepared_model_call_at(prepared, slot) is Some(call) else {
        return Err(ForeignOriginal)
      }
      @encode.string_value(
        writer,
        @publication.run_evidence_value_identity(call),
      )
    }
    @encode.end_array(writer)
    @encode.key(writer, "provider_binding_cid")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_identity(provider),
    )
    @encode.key(writer, "authorization_context")
    @encode.begin_object(writer)
    for
      (key, value) in [
        ("account_id", boundary.account_id),
        ("configuration_cid", boundary.configuration_cid),
        ("entry_id", boundary.entry_id),
        ("principal", boundary.principal),
        ("connection", boundary.connection),
        ("resource", boundary.resource),
        ("operation", "infer"),
        ("boundary", "activation"),
        ("context_cid", boundary.context_cid),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, value)
    }
    @encode.end_object(writer)
    @encode.end_object(writer)
    @publication.seal_run_evidence_value(
      "model_invocation_scope",
      @encode.finish(writer),
      16384,
      1024,
      20,
    ).map_err(issue => NativeClientMockModelIssue::Evidence(issue))
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn NativeClientMockModelWork::bind_prepared(
  self : Self,
  active : @infer.Execution,
  prepared : @model.ModelPreparedCallSet,
) -> Result[Unit, NativeClientMockModelIssue] {
  try {
    guard self.prepared is None &&
      self.admission is None &&
      self.account is Some(account) &&
      self.observation_time is Some(at) &&
      @infer.call_scope(active) is Some(call_scope) &&
      @host.client_infer_call_scope_unit_id(call_scope) is Some(unit_id) else {
      return Err(ForeignOriginal)
    }
    self.prepared = Some(prepared)
    let task = @environment.model_execution_task(
      @host.client_infer_plan_graph_execution_contract(self.graph),
    )
    let connection = @environment.model_task_connector(task)
    let resource = @environment.model_task_identity(task).2
    let outcome = @authorization.evaluate_account(account, {
      principal: self.principal,
      connection,
      resource,
      operation: "infer",
    })
    let entry = match outcome {
      @authorization.Allow(entry) => entry
      _ => return Err(Account(outcome))
    }
    let provider = match self.provider_role {
      Mock(profile) => {
        guard @environment.model_mock_profile_originals(profile)
          is Some(originals) else {
          return Err(ForeignOriginal)
        }
        mock_model_require(
          @host.issue_client_model_provider_binding(
            connection,
            originals.0,
            originals.2,
            originals.4,
          ).map_err(issue => NativeClientMockModelIssue::Evidence(issue)),
        )
      }
      PortableHttp(work) => work.installation.binding
    }
    guard @publication.model_provider_binding_configuration_cids(provider)
      is Some((revision_cid, contract_cid, configuration_cid)) else {
      return Err(ForeignOriginal)
    }
    let boundary : @publication.ModelInvocationBoundary = {
      unit_id,
      task_index: @host.client_infer_occurrence_coordinates(
        self.graph.occurrence,
      ).0.to_int64(),
      strategy_revision: 0L,
      inference_barrier_cid: @host.client_infer_plan_graph_barrier_cid(
        self.graph,
      ),
      account_id: account.account_id(),
      configuration_cid: account.configuration_cid(),
      entry_id: entry,
      principal: self.principal,
      connection,
      resource,
      context_cid: @publication.run_publication_execution_context(
        self.compiled.admission,
      ),
      installation_revision_cid: revision_cid,
      configuration_contract_cid: contract_cid,
      provider_configuration_cid: configuration_cid,
    }
    let scope = mock_model_require(
      native_mock_model_invocation_scope(
        self.definition,
        prepared,
        provider,
        boundary,
      ),
    )
    let bound = mock_model_require(
      @infer.bind_model_scope(active, prepared, scope, provider, boundary).map_err(issue => {
          NativeClientMockModelIssue::Binding(issue)
        },
      ),
    )
    self.scope = Some(bound)
    let admission = mock_model_require(
      @host.issue_client_infer_dispatch_admission(
        self.compiled,
        self.definition,
        account,
        self.principal,
        at,
        model_scope=Some(bound),
        observe_current=() => self.current_step(),
      ).map_err(issue => NativeClientMockModelIssue::Dispatch(issue)),
    )
    self.admission = Some(admission)
    mock_model_require(
      @infer.bind_model_entry_persistence(active, prepared, admission, entry => {
        if self.entry is Some(previous) {
          if physical_equal(previous, entry) {
            return @model.model_call_entry_persistence(entry, prepared, () => {
              self.entry_observation(entry, prepared)
            })
          }
          if !self.entry_recorded ||
            @model.model_call_entry_persistence_originals(
              previous, prepared, admission,
            )
            is Some(_) {
            return None
          }
        }
        self.entry = Some(entry)
        self.entry_recording = false
        self.entry_recorded = false
        self.entry_not_recorded = false
        self.entry_issue = None
        @model.model_call_entry_persistence(entry, prepared, () => {
          self.entry_observation(entry, prepared)
        })
      }).map_err(issue => NativeClientMockModelIssue::Binding(issue)),
    )
    if native_acceptance_enabled() &&
      !@infer.bind_model_observation(active, prepared, observed => {
        let (slot, attempt, event, _) = @model.model_physical_observation_facts(
          observed,
        )
        let tag = match event {
          "before_invoke" => 0
          "started" => 1
          "returned" => 2
          "failed" => 3
          "cancelled" => 4
          _ => -1
        }
        native_acceptance_identity(tag, slot, attempt)
      }) {
      native_acceptance_incomplete()
    }
    Ok(())
  } catch {
    NativeMockModelStop(issue) => Err(issue)
  }
}

///|
fn NativeClientMockModelWork::entry_observation(
  self : Self,
  entry : @model.ModelCallEntry,
  prepared : @model.ModelPreparedCallSet,
) -> @model.ModelEntryPersistenceObservation {
  guard self.entry is Some(original) && physical_equal(original, entry) else {
    return @model.Unknown
  }
  if self.entry_recorded {
    match @model.acknowledge_saved_model_call_entry(entry, prepared) {
      Some(acknowledgement) => @model.Saved(acknowledgement)
      None => @model.Unknown
    }
  } else if self.entry_not_recorded {
    @model.NotRecorded
  } else if self.entry_issue is Some(_) {
    @model.Unknown
  } else {
    @model.Pending
  }
}

///|
/// No Model frame is entered here. The caller enters the SAME captured Read
/// only after advance returned; no SQLite callback can suspend a Core stack.
/// Mark the original attempt before I/O and the known COMMIT before scope
/// return. A failed/ambiguous save cannot be attempted a second time.
pub fn NativeClientMockModelWork::persist_entry_in_original_read(
  self : Self,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.entry is Some(entry) &&
    self.prepared is Some(prepared) &&
    self.admission is Some(admission) &&
    !self.entry_recording &&
    !self.entry_recorded &&
    self.entry_issue is None else {
    return Err(ForeignOriginal)
  }
  self.account = None
  self.observation_time = None
  self.entry_recording = true
  if self.provider_role is PortableHttp(work) {
    if self.prepare_http_entry_in_original_read(
        work, entry, prepared, admission,
      )
      is Err(issue) {
      // No persistence call has run. Keep the transport cleanup with its
      // original Runtime and make the same Entry's refusal observable.
      self.entry_not_recorded = true
      return Err(issue)
    }
  }
  match self.persist_model_entry_original(prepared, admission, entry) {
    Ok(_) => {
      self.entry_recorded = true
      Ok(())
    }
    Err(issue) => {
      self.entry_issue = Some(issue)
      Err(Original(issue))
    }
  }
}

///|
pub fn NativeClientMockModelWork::needs_entry_persistence(self : Self) -> Bool {
  !self.closing &&
  !self.closed &&
  !self.advancing &&
  self.entry is Some(_) &&
  !self.entry_recording &&
  !self.entry_recorded &&
  self.entry_issue is None
}

///|
/// Borrow only this already opened component for its SAME configured Local
/// family. This neither opens a read nor reissues a Model execution/permission.
pub fn NativeClientMockModelWork::borrow_opened_original_model(
  self : Self,
) -> Result[@infer.Execution, NativeClientMockModelIssue] {
  guard !self.closing &&
    !self.closed &&
    self.open_attempted &&
    self.active is Some(active) else {
    return Err(NotOpened)
  }
  Ok(active)
}

///|
// Core advances and outer physical steps borrow the same bounded observation.
// Neither can use it after the step returns, even when the step failed.
fn[T] NativeClientMockModelWork::with_observed_step(
  self : Self,
  step : (@infer.Execution) -> Result[T, NativeClientMockModelIssue],
) -> Result[T, NativeClientMockModelIssue] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.account is Some(_) &&
    self.observation_time is Some(_) &&
    self.settlement is None &&
    self.active is Some(active) else {
    return Err(NotOpened)
  }
  self.advancing = true
  defer self.release_observed_step()
  step(active)
}

///|
fn NativeClientMockModelWork::release_observed_step(self : Self) -> Unit {
  self.advancing = false
  self.account = None
  self.observation_time = None
}

///|
/// One bounded Core work batch. Actual Entry persistence and acknowledgement
/// remain on opposite sides of this original Model step.
pub fn NativeClientMockModelWork::advance(
  self : Self,
) -> Result[@infer.Poll, NativeClientMockModelIssue] {
  self.with_observed_step(active => {
    @infer.advance(active, 31)
    .map_err(issue => NativeClientMockModelIssue::Model(issue))
    .bind(result => self.bind_observed_call_set(active).map(_ => result))
  })
}

///|
// The Local driver owns Core's advance. These two ports borrow the same
// Work's Account snapshot only for that one original, synchronous step.
pub fn NativeClientMockModelWork::enter_managed_model_step(
  self : Self,
  active : @infer.Execution,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard !self.closing &&
    !self.closed &&
    !self.advancing &&
    self.account is Some(_) &&
    self.observation_time is Some(_) &&
    self.settlement is None &&
    self.active is Some(original) &&
    physical_equal(original, active) else {
    return Err(ForeignOriginal)
  }
  self.advancing = true
  Ok(())
}

///|
pub fn NativeClientMockModelWork::leave_managed_model_step(
  self : Self,
  active : @infer.Execution,
  advanced : Bool,
) -> Result[Unit, NativeClientMockModelIssue] {
  guard self.advancing &&
    self.active is Some(original) &&
    physical_equal(original, active) else {
    return Err(ForeignOriginal)
  }
  defer self.release_observed_step()
  if advanced {
    self.bind_observed_call_set(active)
  } else {
    Ok(())
  }
}

///|
fn NativeClientMockModelWork::bind_observed_call_set(
  self : Self,
  active : @infer.Execution,
) -> Result[Unit, NativeClientMockModelIssue] {
  if self.prepared is None && @infer.prepared_call_set(active) is Some(prepared) {
    self.bind_prepared(active, prepared)
  } else {
    Ok(())
  }
}

///|
fn[T] NativeClientMockModelWork::with_observed_http_step(
  self : Self,
  call : NativeClientModelHttpCall,
  step : () -> Result[T, NativeClientModelHttpIssue],
) -> Result[T, NativeClientMockModelIssue] {
  self
  .observe_model_step_in_original_read(physical=true)
  .bind(_ => {
    self.with_observed_step(_ => {
      guard physical_equal(call.capture, self.capture) &&
        self.entry_recorded &&
        self.entry is Some(entry) &&
        call.original is Some(original) &&
        original.entry is Some(entered) &&
        physical_equal(entered, entry) &&
        self.prepared is Some(prepared) &&
        @model.prepared_model_request(prepared, call.request.slot)
        is Some(request) &&
        physical_equal(request, call.request) else {
        return Err(ForeignOriginal)
      }
      step().map_err(issue => Transport(issue))
    })
  })
}

///|
/// Preserve other Model waits. A portable response wait must find the
/// retained transport for this exact consumed Entry before advancing again.
pub fn NativeClientMockModelWork::entered_model_http_call(
  self : Self,
  runtime : NativeLocalPackagedRuntime?,
) -> Result[NativeClientModelHttpCall?, NativeClientMockModelIssue] {
  guard self.prepared is Some(prepared) &&
    @model.prepared_model_awaits_portable_http(prepared) else {
    return Ok(None)
  }
  guard !self.closing &&
    !self.closed &&
    self.entry_recorded &&
    self.entry is Some(entry) &&
    runtime is Some(runtime) &&
    runtime.model_http_load is Some(Ok(loaded)) &&
    !loaded.stopping else {
    return Err(ForeignOriginal)
  }
  let mut pending = loaded.calls
  while pending is Some(call) {
    if physical_equal(call.capture, self.capture) &&
      call.original is Some(original) &&
      original.entry is Some(entered) &&
      physical_equal(entry, entered) {
      return Ok(pending)
    }
    pending = call.next_in_runtime
  }
  Err(ForeignOriginal)
}

///|
/// One bounded readiness step on the exact consumed Entry, after its durable
/// acknowledgement. True means that this Call has a complete HTTP response
/// and its Client has returned. Store confirmation is a separate step.
pub fn NativeClientMockModelWork::drive_http_in_original_read(
  self : Self,
  call : NativeClientModelHttpCall,
) -> Result[Bool, NativeClientMockModelIssue] {
  self.with_observed_http_step(call, () => {
    call
    .drive_in_original_read()
    .map(_ => call.response is Some(_) && call.client is None)
  })
}

///|
/// Retain the returned child on the original command before saving it. The
/// response facts and durable Run identity both come from this exact Work.
pub fn NativeClientMockModelWork::prepare_http_raw_in_original_read(
  self : Self,
  call : NativeClientModelHttpCall,
  store : @publication_store.Store,
) -> Result[NativeClientModelRawCapture, NativeClientMockModelIssue] {
  guard self.provider_role is PortableHttp(configured) &&
    physical_equal(configured.store, store) else {
    return Err(ForeignOriginal)
  }
  self.with_observed_http_step(call, () => {
    guard self.observation_time is Some(at) else {
      return Err(NativeClientModelHttpIssue::ForeignOriginal)
    }
    call.prepare_raw_save_in_original_read(
      self.request,
      self.compiled,
      self.definition,
      self.namespace_id,
      store,
      at,
    )
  })
}

///|
/// Confirm the already retained Store child and decode its original response
/// under the same fresh observation. A refusal leaves the child with the caller.
pub fn NativeClientMockModelWork::save_http_raw_in_original_read(
  self : Self,
  call : NativeClientModelHttpCall,
  raw : NativeClientModelRawCapture,
) -> Result[Unit, NativeClientMockModelIssue] {
  self.with_observed_http_step(call, () => {
    guard !call.cancelled &&
      call.raw is Some(original) &&
      call.raw_store is Some(child) &&
      physical_equal(raw, child) &&
      physical_equal(raw.capture, self.capture) &&
      physical_equal(raw.view, original) else {
      return Err(NativeClientModelHttpIssue::ForeignOriginal)
    }
    raw
    .persist_in_original_read()
    .map_err(issue => NativeClientModelHttpIssue::RawStore(issue))
    .bind(_ => call.adopt_saved_chat(raw))
    .map(_ => call.raw_store = None)
  })
}

///|
/// Stop and retire only the original Model children. The caller separately
/// retires its Scope, Native frame, captured Read and SQLite/Store resources.
/// A Core cleanup ACK is not any of those physical acknowledgements.
pub fn NativeClientMockModelWork::close(
  self : Self,
) -> Result[Bool, NativeClientMockModelIssue] {
  try {
    if self.advancing {
      return Err(ForeignOriginal)
    }
    self.closing = true
    self.account = None
    self.observation_time = None
    match self.close_effect_review() {
      Err(issue) => return Err(issue)
      Ok(false) => return Ok(false)
      Ok(true) => ()
    }
    if self.lookup_entries is Some(entries) {
      for entry in entries {
        if (entry.attempted && !entry.recorded) ||
          (entry.page_attempted && !entry.page_recorded) {
          // The original Journal owns this unresolved write/return. A Model
          // close cannot turn ambiguous activation/adoption into no send.
          return Err(CleanupPending)
        }
      }
    }
    match self.active {
      None => {
        self.lookup_entries = None
        self.first_start = None
        self.closed = true
        Ok(true)
      }
      Some(active) => {
        if self.settlement is Some(saved) &&
          saved.store_complete &&
          saved.journal_recorded {
          // Actual Store confirmations and the known Journal COMMIT precede
          // this late custody observation. Finish that SAME settlement even
          // when a later Read return/stop sent the caller directly to cleanup.
          // This grants no dispatch, write or physical retirement; refusal
          // keeps the original settlement and its remaining cleanup duties.
          mock_model_require(self.acknowledge_saved_settlement())
        }
        // An exporter retains the original Model output use. Cancel and retire
        // that SAME child before attempting the Model's existing cleanup.
        if self.settlement is Some(saved) && saved.exporter is Some(exporter) {
          @model.cancel_model_capture_export(exporter) |> ignore
          let retired = mock_model_require(
            @model.cleanup_model_capture_export(exporter).map_err(issue => {
              NativeClientMockModelIssue::Capture(issue)
            }),
          )
          if !retired {
            return Ok(false)
          }
          saved.exporter = None
        }
        if self.settlement is Some(saved) &&
          (
            (saved.store_phase == ModelStoreEntered && !saved.store_complete) ||
            (saved.journal_attempted && !saved.journal_recorded)
          ) {
          // The same failed Store/Journal child owns unresolved persistence.
          // Model cancellation cannot acknowledge or discard either duty.
          return Err(CleanupPending)
        }
        if !mock_model_require(self.close_observation()) {
          return Ok(false)
        }
        @infer.cancel(active) |> ignore
        if !@infer.execution_stopped(active) {
          match @infer.advance_cancelled(active, 31) {
            Err(issue) | Ok(@infer.Failed(issue, ..)) =>
              return Err(Model(issue))
            Ok(_) => ()
          }
        }
        let closed = mock_model_require(
          @infer.cleanup(active).map_err(issue => {
            NativeClientMockModelIssue::Model(issue)
          }),
        )
        if closed {
          if self.provider_role is PortableHttp(work) {
            // Its Raw/current callbacks retain this Work. Cut the Work's
            // own edge only after the Model confirms retirement. Any pending
            // Store child still owns its exact registration and cleanup.
            work.registration = None
          }
          self.lookup_entries = None
          self.active = None
          self.prepared = None
          self.admission = None
          self.scope = None
          self.entry = None
          self.settlement = None
          self.first_start = None
          self.closed = true
        }
        Ok(closed)
      }
    }
  } catch {
    NativeMockModelStop(issue) => Err(issue)
  }
}

///|
priv suberror NativeMockModelStop {
  NativeMockModelStop(NativeClientMockModelIssue)
}

///|
fn[T] mock_model_require(
  value : Result[T, NativeClientMockModelIssue],
) -> T raise NativeMockModelStop {
  match value {
    Ok(value) => value
    Err(issue) => raise NativeMockModelStop(issue)
  }
}

///|
/// Fixed caller record and its returned Result only. Provider, Graph, profile
/// and numeric Limits are retained references, never copies or grants. Admit
/// this through the SAME Request before preparing this existing Native Work.
pub fn native_client_mock_model_work_construction() -> @execution.PreparationRepresentationUnits {
  {
    // Include the selected provider arm and explicit pre-entry refusal bit.
    record_headers: 13L,
    reference_slots: 57L,
    scalar_words: 20L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
}
