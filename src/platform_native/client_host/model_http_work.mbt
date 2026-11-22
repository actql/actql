///|
priv enum NativeClientModelWorkProvider {
  Mock(@environment.ModelMockProfile)
  PortableHttp(NativeClientModelHttpWork)
}

///|
/// Already admitted originals for the same Run's raw response custody.
pub(all) struct NativeClientModelHttpRawOriginals {
  retention : @publication.CapturedEffectDependencyBody
  metadata : @publication.CapturedEffectDependencyBody
  clock : @publication.CapturedEffectDependencyBody
  data : @publication.CapturedEffectDependencyBody
  available_until : String
  delete_by : String
  extension_ceiling_at : String
  metadata_delete_by : String
}

///|
/// Bounded operations on the installed transport. An instance alone cannot
/// issue a Call or replace the original source egress admission.
pub(all) struct NativeClientModelHttpRunConfiguration {
  egress : @host.ClientInferEgressAdmission
  quantities : @model.ModelQuantityCapacity
  store : @publication_store.Store
  raw : NativeClientModelHttpRawOriginals
  ca_path : String
  connect_timeout_ms : Int
  operation_timeout_ms : Int
  credential_expires_at : Int64
  max_projection_frames : Int
}

///|
priv struct NativeClientModelHttpWork {
  installation : NativeModelHttpInstallation
  configuration : NativeClientModelHttpRunConfiguration
  plans : Array[NativeClientModelHttpPlan?]
  mut registration : @host.ClientModelRawCaptureRegistration?
}

///|
/// Reuse the original Native Work for a trusted installed HTTP provider.
/// The constructor reserves its extra controls before retaining the slot
/// index. The existing Model owns preflight buffers and physical limits.
pub fn prepare_native_client_model_http_work(
  capture : NativeLocalJournalCapture,
  request : @host.ClientRequestIdentity,
  compiled : @host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @host.ClientInferPlanGraph,
  installation : NativeModelHttpInstallation,
  configuration : NativeClientModelHttpRunConfiguration,
  limits : @infer.Limits,
  principal : String,
  namespace_id : String,
  current_time : () -> String,
  prepare : (@execution.PreparationRepresentationUnits) -> Bool,
) -> Result[NativeClientMockModelWork, NativeClientMockModelIssue] {
  let execution = @host.client_infer_plan_graph_execution_contract(graph)
  guard physical_equal(installation.capture, capture) &&
    installation.originals_for(execution) is Some((provider, _, _)) &&
    limits.model.max_items > 0 &&
    configuration.max_projection_frames > 0 &&
    configuration.credential_expires_at > 0L &&
    configuration.connect_timeout_ms > 0 &&
    configuration.operation_timeout_ms >= configuration.connect_timeout_ms &&
    !configuration.ca_path.is_empty() &&
    configuration.ca_path.length() <= 4096 &&
    !configuration.ca_path.contains("\u{0}") else {
    return Err(ForeignOriginal)
  }
  guard @execution.preparation_array_representation(
      1L,
      limits.model.max_items.to_int64(),
      true,
    )
    is Some(array) &&
    @execution.compose_preparation_representation([
      native_client_mock_model_work_construction(),
      {
        ..array,
        record_headers: array.record_headers + 1L,
        reference_slots: array.reference_slots + 4L,
      },
    ])
    is Some(controls) &&
    prepare(controls) else {
    return Err(Original(ConfigurationLimit))
  }
  let role = PortableHttp({
    installation,
    configuration,
    plans: Array::make(limits.model.max_items, None),
    registration: None,
  })
  prepare_native_client_model_work(
    capture, request, compiled, definition, graph, role, provider, limits, principal,
    namespace_id, current_time,
  )
}

///|
fn NativeClientModelHttpWork::bind_preflight(
  self : Self,
  active : @infer.Execution,
) -> Result[Unit, NativeClientMockModelIssue] {
  @infer.bind_quantity_capacity(active, self.configuration.quantities)
  .bind(_ => {
    @infer.bind_physical_preflight(active, request => {
      let slot = request.slot
      if slot < 0 || slot >= self.plans.length() || self.plans[slot] is Some(_) {
        return Err(@model.RequestIdentity)
      }
      self.installation.start_model_http_preflight(
        request,
        self.configuration.quantities.per_attempt,
        self.configuration.max_projection_frames,
        plan => self.plans[slot] = Some(plan),
      )
    })
  })
  .map_err(issue => NativeClientMockModelIssue::Model(issue))
}

///|
fn NativeClientModelHttpWork::raw_registration(
  self : Self,
  owner : NativeClientMockModelWork,
  scope : @publication.BoundModelInvocationScope,
  dispatch : @host.ClientInferDispatchAdmission,
  account : @authorization.AdmittedAccountConfiguration,
  at : String,
) -> Result[@host.ClientModelRawCaptureRegistration, NativeClientMockModelIssue] {
  if self.registration is Some(value) {
    return Ok(value)
  }
  let store = match self.configuration.store.custody_location() {
    Ok((authority, _, _)) => authority
    Err(issue) => return Err(Store(issue))
  }
  let raw = self.configuration.raw
  let response = self.installation.response
  let profile = self.installation.profile
  let policy = match
    @host.issue_client_model_raw_capture_policy(
      dispatch,
      scope,
      response,
      profile,
      None,
      store,
      raw.retention,
      raw.metadata,
      raw.clock,
      raw.data,
      at,
      raw.available_until,
      raw.delete_by,
      raw.extension_ceiling_at,
      raw.metadata_delete_by,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Transport(RawPolicy(issue)))
  }
  @host.register_client_model_raw_capture(
    dispatch,
    scope,
    policy,
    response,
    profile,
    None,
    account,
    at,
    store,
    () => !owner.closing && !owner.closed,
    () => {
      owner
      .current_step()
      .map_err(issue => {
        match issue {
          @host.ForeignRun => @host.ClientModelRawCaptureIssue::ForeignRun
          _ => @host.UnavailableSelection
        }
      })
    },
  )
  .map(value => {
    self.registration = Some(value)
    value
  })
  .map_err(issue => Transport(RawPolicy(issue)))
}

///|
fn NativeClientMockModelWork::prepare_http_entry_in_original_read(
  self : Self,
  work : NativeClientModelHttpWork,
  entry : @model.ModelCallEntry,
  prepared : @model.ModelPreparedCallSet,
  dispatch : @host.ClientInferDispatchAdmission,
) -> Result[Unit, NativeClientMockModelIssue] {
  self
  .observe_model_step_in_original_read(physical=true)
  .bind(_ => {
    self.with_observed_step(_ => {
      guard self.account is Some(account) &&
        self.observation_time is Some(at) &&
        self.scope is Some(scope) &&
        @model.model_call_entry_persistence_originals(entry, prepared, dispatch)
        is Some((_, slot, _, _, _, original_scope)) &&
        physical_equal(scope, original_scope) &&
        work.plans.get(slot) is Some(Some(plan)) &&
        @model.prepared_model_request(prepared, slot) is Some(request) &&
        physical_equal(plan.request, request) else {
        return Err(ForeignOriginal)
      }
      work
      .raw_registration(self, scope, dispatch, account, at)
      .bind(registration => {
        let configuration = work.configuration
        self.capture
        .prepare_model_http_call_in_original_read(
          configuration.ca_path,
          configuration.connect_timeout_ms,
          configuration.operation_timeout_ms,
          plan,
          registration,
          configuration.credential_expires_at,
        )
        .map_err(issue => Transport(issue))
        .map(_ => work.plans[slot] = None)
      })
    })
  })
}
