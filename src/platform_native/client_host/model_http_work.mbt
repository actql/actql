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
priv struct NativeClientModelHttpWork {
  installation : NativeModelHttpInstallation
  store : @publication_store.Store
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
  store : @publication_store.Store,
  limits : @infer.Limits,
  principal : String,
  namespace_id : String,
  current_time : () -> String,
) -> Result[NativeClientMockModelWork, NativeClientMockModelIssue] {
  let execution = @host.client_infer_plan_graph_execution_contract(graph)
  let policy = installation.run_policy
  guard physical_equal(installation.capture, capture) &&
    installation.originals_for(execution) is Some((provider, _, _)) &&
    limits.model.max_items > 0 &&
    @host.client_compiled_run_infer_observation_policy(compiled)
    is Some(data_cid) &&
    @publication.captured_effect_dependency_body_cid(policy.raw.data) ==
    data_cid else {
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
    @execution.preparation_representation_cost(controls) is Some(bytes) else {
    return Err(Original(ConfigurationLimit))
  }
  // The Work and its slot array survive the Read/Compute scope switches.
  // Fund both on this exact installed original before either is allocated.
  let (_, _, _, array_header, pointer) = @bootstrap.native_managed_value_layout()
  guard array_header > 0L &&
    pointer > 0L &&
    @execution.checked_preparation_add_product(
      array_header,
      pointer,
      limits.model.max_items.to_int64(),
    )
    is Some(slot_bytes) else {
    return Err(Original(ConfigurationLimit))
  }
  match
    capture.fund_model_http_material_in_original_read(
      bytes,
      Int64::max(slot_bytes, bytes - slot_bytes),
    ) {
    Err(issue) => return Err(Transport(issue))
    Ok(_) => ()
  }
  let role = PortableHttp({
    installation,
    store,
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
  let policy = self.installation.run_policy
  @infer.bind_quantity_capacity(active, policy.quantities)
  .bind(_ => {
    @infer.bind_physical_preflight(active, request => {
      let slot = request.slot
      if slot < 0 || slot >= self.plans.length() || self.plans[slot] is Some(_) {
        return Err(@model.RequestIdentity)
      }
      self.installation.start_model_http_preflight(
        request,
        policy.quantities.per_attempt,
        policy.max_projection_frames,
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
  let store = match self.store.custody_location() {
    Ok((authority, _, _)) => authority
    Err(issue) => return Err(Store(issue))
  }
  let raw = self.installation.run_policy.raw
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
        let policy = work.installation.run_policy
        self.capture
        .prepare_model_http_call_in_original_read(
          policy.ca_path,
          policy.connect_timeout_ms,
          policy.operation_timeout_ms,
          plan,
          registration,
          policy.credential_expires_at,
        )
        .map_err(issue => Transport(issue))
        .map(_ => work.plans[slot] = None)
      })
    })
  })
}
