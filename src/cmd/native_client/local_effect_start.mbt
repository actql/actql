///|
// Only actual CLI outcomes: an accepted original can be observed, or successful
// preflight still lacks the installed authority supplier and must refuse.
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
  _retained_sources : Array[LocalProjectMockEffectSourceInput]
}

///|
fn local_effect_request_identity(
  preparation : @local_host.NativeClientSubmittedPreparation,
  scope : String,
  request_id : String,
) -> @run_host.ClientRequestIdentity raise ClientStop {
  guard @local_host.native_client_submitted_preparation(preparation)
    is EffectComputation(prepared) else {
    stop("LocalEffectPreparationRequired")
  }
  @run_host.prepare_client_effect_request_identity(
    prepared,
    scope,
    request_id,
    @run_host.source_free_caller_input_intent_cid(),
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
  request? : @run_host.ClientRequestIdentity? = None,
  source_inputs? : Array[LocalProjectMockEffectSourceInput] = [],
) -> LocalEffectFirstCompilation raise ClientStop {
  guard @local_host.native_client_submitted_preparation(preparation)
    is EffectComputation(prepared) else {
    stop("LocalEffectPreparationRequired")
  }
  // Select only from the original checked header. Each existing issuer audits
  // its own closed profile; a kind string is not a completion-free proof.
  let headers = @checked.effect_program_static_headers(
    @run_host.prepared_client_effect_computation_candidate(prepared),
  )
  guard @syntax.effect_header_count(headers) == 1 &&
    @syntax.effect_header_at(headers, 0) is Some(header) else {
    stop("LocalEffectNormalizationProfileNotInstalled")
  }
  let normalization_result = match @syntax.effect_header_kind(header) {
    "create" => @run_host.issue_prepared_client_effect_normalization(prepared)
    "update" =>
      @run_host.issue_prepared_client_effect_selected_normalization(prepared)
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
  { request, allowed, definition, issued, _retained_sources: source_inputs, }
}

///|
// AlreadyAccepted means only authenticated retained acceptance requiring lookup.
// AuthoritySupplierUnavailable records completed preflight, never admission or
// a retry permit; other unsupported/refused conditions still raise.
// Called by the actual CLI Effect preparation branch. It has no journal accept,
// physical Source open, approval, grant issuance or Provider side effect.
fn local_effect_prepare_start(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  preparation : @local_host.NativeClientSubmittedPreparation,
  reference : @local_host.NativeClientSubmissionReference,
  run : LocalRunInstallation,
  scope : String,
  business? : LocalCommandBusinessPreparation? = None,
) -> LocalEffectPreflightStatus raise ClientStop {
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
) -> LocalEffectPreflightStatus raise ClientStop {
  if !local_submit_allowed(host, settings, crypto, scope) {
    stop("LocalSubmissionAuthorizationDenied")
  }
  let request_id = @local_host.native_client_submission_request_id(reference)
  let request = local_effect_request_identity(preparation, scope, request_id)
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
          if !local_submit_allowed(host, settings, crypto, scope) {
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
  if original.request != request ||
    (
      !values_supported &&
      !@source_owner.resident_effect_source_compute_shape_supported(bound)
    ) {
    stop("LocalEffectSourceExecutionProfileNotSupported")
  }
  if !local_submit_allowed(host, settings, crypto, scope) {
    stop("LocalSubmissionAuthorizationDenied")
  }
  AuthoritySupplierUnavailable
}
