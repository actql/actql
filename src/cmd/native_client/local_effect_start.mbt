///|
// Only actual CLI outcomes: an authenticated accepted original is observed
// through its existing lookup. A newly saved waiting checkpoint is still
// neither approval nor a completed mutation.
priv enum LocalEffectPreflightStatus {
  AlreadyAccepted
  AuthoritySupplierUnavailable
}

///|
// The actual preflight consumes all four original compiler outputs in its
// material and checked-Run bindings. This intermediate is not a future
// dispatcher, normalization, cleanup Owner, or public authority supplier.
priv struct LocalEffectFirstCompilation {
  request : @run_host.ClientRequestIdentity
  allowed : @run_host.ClientEffectAllowedRun
  definition : @publication.PublicationContract
  issued : @run_host.ClientEffectIssuedNormalizationMaterials
  model_compiled : @run_host.ClientCompiledRun?
  _retained_sources : Array[LocalProjectMockEffectSourceInput]
  _retained_models : Array[LocalProjectMockEffectModelInput]
}

///|
fn LocalEffectFirstCompilation::is_mock_values_create(self : Self) -> Bool {
  if !self._retained_models.is_empty() || !self._retained_sources.is_empty() {
    return false
  }
  let prepared = @run_host.client_effect_compilation_owner(
    self.allowed.compilation,
  )
  let candidate = @run_host.prepared_client_effect_computation_candidate(
    prepared,
  )
  let program = @checked.effect_program_static_checked_computation(candidate)
  let headers = @checked.effect_program_static_headers(candidate)
  @checked.unit_count(program) == 1 &&
  @checked.unit_result_import_count(program, 0) == Some(0) &&
  @checked.unit_import_cid_count(program, 0) == Some(0) &&
  @run_host.client_effect_direct_acquisition_count(prepared, 100000) is Ok(0) &&
  @run_host.prepared_client_effect_infer_count(prepared) == Some(0) &&
  @strategy.graph_source_free_inputs_complete(
    @strategy.checked_effect_computation_graph(
      @run_host.prepared_client_effect_computation_graph(prepared),
    ),
  ) &&
  @run_host.prepared_client_effect_serialization_occurrences(prepared).is_empty() &&
  @syntax.effect_header_count(headers) == 1 &&
  @syntax.effect_header_at(headers, 0) is Some(header) &&
  @syntax.effect_header_kind(header) == "create"
}

///|
fn local_effect_request_identity(
  preparation : @local_host.NativeClientSubmittedPreparation,
  scope : String,
  request_id : String,
  submitted_input_cid? : String? = None,
) -> @run_host.ClientRequestIdentity raise ClientStop {
  guard @local_host.native_client_submitted_preparation(preparation)
    is EffectComputation(prepared) else {
    stop("LocalEffectPreparationRequired")
  }
  // The Native Query checker already bound its exact authored Submission.
  // Its lowered Effect can use the existing material identity while a
  // Source-bound Effect still has to match the authored input CID.
  if submitted_input_cid is Some(expected) &&
    @local_host.native_client_submitted_preparation_lowered_effect_query(
      preparation,
    ) {
    if @local_host.native_client_submitted_preparation_intent_cid(preparation) !=
      expected {
      stop("LocalEffectRequestIdentityUnavailable")
    }
    let request = @run_host.prepare_client_original_effect_request_identity(
      prepared, scope, request_id,
    ).unwrap_or_else(() => stop("LocalEffectRequestIdentityUnavailable"))
    let input = @run_host.client_request_input_cid(request)
    if input != expected &&
      input != @run_host.source_free_caller_input_intent_cid() {
      stop("LocalEffectRequestIdentityUnavailable")
    }
    return request
  }
  @run_host.prepare_client_original_effect_request_identity(
    prepared,
    scope,
    request_id,
    submitted_input_cid~,
  ).unwrap_or_else(() => stop("LocalEffectRequestIdentityUnavailable"))
}

///|
fn local_effect_first_compilation(
  preparation : @local_host.NativeClientSubmittedPreparation,
  scope : String,
  configuration_cid : String,
  namespace_id : String,
  request_id : String,
  now : String,
  until : String,
  infers? : Array[@run_host.ClientInferPlanGraph] = [],
  models? : Array[LocalProjectMockEffectModelInput] = [],
  request? : @run_host.ClientRequestIdentity? = None,
  source_inputs? : Array[LocalProjectMockEffectSourceInput] = [],
) -> LocalEffectFirstCompilation raise ClientStop {
  guard @local_host.native_client_submitted_preparation(preparation)
    is EffectComputation(prepared) else {
    stop("LocalEffectPreparationRequired")
  }
  // The original file inputs are retained only by the admitted project Mock
  // entrance. One proof audits the entire checked Set, including a later DELETE.
  let allow_file_mutation = !source_inputs.is_empty() && models.is_empty()
  let headers = @checked.effect_program_static_headers(
    @run_host.prepared_client_effect_computation_candidate(prepared),
  )
  guard @syntax.effect_header_at(headers, 0) is Some(header) else {
    stop("LocalEffectNormalizationProfileNotInstalled")
  }
  let first_kind = @syntax.effect_header_kind(header)
  let normalization_result = match first_kind {
    "create" if @syntax.effect_header_count(headers) == 1 =>
      @run_host.issue_prepared_client_effect_normalization(prepared)
    "update" | "delete" | "upsert" if first_kind == "update" ||
      allow_file_mutation =>
      @run_host.issue_prepared_client_effect_selected_normalization(
        prepared,
        allow_source_completion=true,
        allow_file_mutation~,
      )
    _ => stop("LocalEffectNormalizationProfileNotInstalled")
  }
  let normalization = normalization_result.unwrap_or_else(() => {
    stop("LocalOriginalNormalizationNotInstalled")
  })
  // Reuse the same immutable installed manifests retained by Request Graph
  // construction. Do not admit identical compiler contracts again here.
  let manifests = native_request_manifests
  // Supply the genuine profile to the FIRST compiler invocation. Never upgrade
  // a previously compiled/accepted legacy Template during replay or recovery.
  let compilation = @run_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @run_host.client_standard_values_sequence_limits(),
    1000,
    1000,
    65536,
    8192,
    64,
    normalization=Some(normalization),
    infer=if infers.length() == 1 { Some(infers[0]) } else { None },
    infers=if infers.length() == 1 { [] } else { infers },
  ).unwrap_or_else(() => stop("LocalEffectCompilationNotReady"))
  let allowed = @run_host.issue_client_effect_allowed_run(
    compilation, scope, configuration_cid, until,
  ).unwrap_or_else(() => stop("LocalEffectRunNotReady"))
  let definition = @run_host.issue_client_effect_run_definition(
    allowed, namespace_id, request_id, now, until,
  ).unwrap_or_else(() => stop("LocalEffectRunDefinitionNotReady"))
  let request = match request {
    Some(original) => {
      if @run_host.prepared_client_effect_request_scope(prepared, original)
        is Err(_) {
        stop("LocalEffectRequestIdentityUnavailable")
      }
      original
    }
    None => local_effect_request_identity(preparation, scope, request_id)
  }
  let issued = @run_host.issue_prepared_client_effect_normalization_materials(
    allowed,
    definition,
    normalization,
    request=Some(request),
  ).unwrap_or_else(() => stop("LocalEffectOriginalMaterialsUnavailable"))
  // This returns a new checked component view, not a getter alias. Retain
  // it ONCE for the original Work, Plan and Model Scope to share later.
  let model_compiled = if infers.is_empty() {
    None
  } else {
    Some(
      @run_host.client_effect_allowed_infer_run(allowed).unwrap_or_else(() => {
        stop("LocalOriginalModelWorkUnavailable")
      }),
    )
  }
  {
    request,
    allowed,
    definition,
    issued,
    model_compiled,
    _retained_sources: source_inputs,
    _retained_models: models,
  }
}

///|
// AlreadyAccepted means only authenticated retained acceptance requiring lookup.
// AuthoritySupplierUnavailable records completed preflight, never admission or
// a retry permit; other unsupported/refused conditions still raise.
// Called by the actual CLI Effect preparation branch. The installed Native
// Model path accepts the same originals and captures its actual file Sources.
// Other profiles remain preflight-only. No branch issues approval or a grant.
fn local_effect_prepare_start(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  preparation : @local_host.NativeClientSubmittedPreparation,
  reference : @local_host.NativeClientSubmissionReference,
  submitted : @local_host.NativeClientSubmittedIntentRecord,
  run : LocalRunInstallation,
  scope : String,
  business? : LocalCommandBusinessPreparation? = None,
) -> LocalEffectPreflightStatus raise ClientStop {
  let submitted_cid = @run_host.client_submitted_intent_cid(
    @local_host.native_client_submitted_intent(submitted),
  )
  let submitted_reference = @local_host.native_client_submitted_intent_reference(
    submitted,
  )
  if submitted_cid !=
    @local_host.native_client_submitted_preparation_intent_cid(preparation) ||
    @local_host.native_client_submission_reference_wire(submitted_reference) !=
    @local_host.native_client_submission_reference_wire(reference) {
    stop("LocalEffectRequestIdentityUnavailable")
  }
  // Verify the selected Request before choosing its Effect material identity.
  // Direct setup has its own preparation from the same Submission.
  let submitted_input_cid = business.map(original => {
    if !physical_equal(original.preparation, preparation) ||
      @run_host.client_submitted_intent_cid(original.intent) != submitted_cid {
      stop("LocalEffectRequestIdentityUnavailable")
    }
    submitted_cid
  })
  local_effect_prepare_start_with_clocks(
    host,
    settings,
    crypto,
    preparation,
    reference,
    run,
    scope,
    local_utc_now,
    () => @env.now().to_double(),
    business~,
    submitted_input_cid~,
  )
}

///|
// Same trusted CLI clock ports, made explicit for controlled Source tests.
// No public option, new clock source or execution authority is introduced.
fn local_effect_prepare_start_with_clocks(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  preparation : @local_host.NativeClientSubmittedPreparation,
  reference : @local_host.NativeClientSubmissionReference,
  installed : LocalRunInstallation,
  scope : String,
  utc_now : () -> String,
  epoch_now : () -> Double,
  business? : LocalCommandBusinessPreparation? = None,
  submitted_input_cid? : String? = None,
) -> LocalEffectPreflightStatus raise ClientStop {
  if !local_submit_allowed(host, settings, crypto, scope, business~) {
    stop("LocalSubmissionAuthorizationDenied")
  }
  let request_id = @local_host.native_client_submission_request_id(reference)
  let request = local_effect_request_identity(
    preparation,
    scope,
    request_id,
    submitted_input_cid~,
  )
  let observed_at = utc_now()
  // The existing Owner looks up this exact request before issuing a Policy.
  // A concurrent accepted request selects its saved original, not this clock.
  let policy = local_run_policy_binding(host, settings, crypto, business~)
  let (run, now) = match policy {
    None => (installed, observed_at)
    Some(binding) =>
      match
        (match business {
          None =>
            binding.prepare_submission_policy(
              reference,
              preparation,
              request,
              observed_at,
              epoch_now(),
            )
          Some(original) =>
            local_business_policy_result(
              original,
              original.capture.prepare_run_policy_in_original_read(
                binding,
                reference,
                preparation,
                request,
                observed_at,
                epoch_now(),
              ),
            )
        }) {
        Ok(Accepted(_)) => {
          if !local_submit_allowed(host, settings, crypto, scope, business~) {
            stop("LocalSubmissionAuthorizationDenied")
          }
          return AlreadyAccepted
        }
        Ok(Pending(retention, issued_at)) =>
          ({ ..installed, retention, }, issued_at)
        Err(_) => stop("LocalRunPolicyPreparationUnavailable")
      }
  }
  if !@publication.result_retention_intervals_valid(run.retention) ||
    !(@publication.result_retention_interval_state(run.retention, now)
    is Ok("available")) {
    stop("LocalResultRetentionUnavailable")
  }
  let retention = @decode.open_object(
    local_input_cursor(@publication.publication_contract_json(run.retention)),
  ).unwrap_or_else(() => stop("InvalidLocalResultRetentionPolicy"))
  let configuration_cid = local_host_result(
    match business {
      None => host.configuration()
      Some(original) => original.capture.configuration_in_original_read()
    },
  ).configuration_cid()
  let original = match business {
    None =>
      local_effect_first_compilation(
        preparation,
        scope,
        configuration_cid,
        run.namespace_id,
        request_id,
        now,
        run_text(retention, "available_until"),
        request=Some(request),
      )
    Some(original) =>
      original.compile_effect_first(
        scope,
        configuration_cid,
        run.namespace_id,
        request_id,
        now,
        run_text(retention, "available_until"),
        request,
        utc_now,
      )
  }
  // These same original bindings are consumed by the actual preflight, in
  // material-before-checked-Run order. No future dispatcher carrier is returned.
  let materials = @run_host.bind_prepared_client_effect_original_materials(
    original.allowed,
    original.definition,
    original.issued,
    request=Some(original.request),
  ).unwrap_or_else(() => stop("LocalEffectOriginalMaterialsUnavailable"))
  let bound = @run_host.bind_client_effect_compiled_run(
    @run_host.client_effect_compilation_owner(original.allowed.compilation),
    original.allowed,
    original.definition,
  ).unwrap_or_else(() => stop("LocalEffectRunNotReady"))
  // This existing Owner only checks the exact installed Values/normalization
  // profile. Its derived limits are not backing, a Ledger or a start permit.
  let values_supported = match run.source_free {
    Some(values) =>
      @local_values.client_effect_local_ledger_limits(
        materials.prepared,
        values.installed_contracts,
        values.values_body,
        values.fragment_body,
        values.ordered_body,
      )
      is Some(_)
    None => false
  }
  if original.request != request {
    stop("LocalEffectSourceExecutionProfileNotSupported")
  }
  let native_mock = match business {
    Some(selected) if original._retained_models.length() == 1 ||
      (
        original._retained_models.is_empty() &&
        (
          !original._retained_sources.is_empty() ||
          (values_supported && original.is_mock_values_create())
        ) &&
        selected.original.project is Some(project) &&
        project.mock_declarations is Some(_)
      ) => {
      selected.prepare_mock_effect_plan(original, run)
      true
    }
    _ => false
  }
  if !values_supported &&
    !native_mock &&
    !@source_owner.resident_effect_source_compute_shape_supported(bound) {
    stop("LocalEffectSourceExecutionProfileNotSupported")
  }
  if !local_submit_allowed(host, settings, crypto, scope, business~) {
    stop("LocalSubmissionAuthorizationDenied")
  }
  if native_mock && business is Some(selected) && policy is Some(binding) {
    selected.capture_mock_effect_sources(
      reference,
      binding,
      run.retention,
      bound,
      now,
      epoch_now(),
      run,
    )
    if original._retained_models.is_empty() {
      selected.execute_direct_mock_effect(
        run.retention,
        native_mock_effect_record_bytes(run),
      )
    } else {
      selected.capture_mock_effect_content(run)
      selected.execute_mock_effect_model(run)
      selected.prepare_mock_effect_observation()
      selected.retain_mock_effect_host(bound)
      selected.prepare_mock_effect_local_observation()
      selected.prepare_mock_effect_proposals(
        run.retention,
        native_mock_effect_record_bytes(run),
      )
    }
    selected.observe_mock_effect_targets()
    selected.prepare_mock_effect_preview(run, binding)
    selected.prepare_mock_effect_computation(run)
    selected.persist_mock_effect_review(run)
    return AlreadyAccepted
  }
  AuthoritySupplierUnavailable
}
