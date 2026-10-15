///|
// A private assembly value, not another Run/normalization/cleanup Owner. All
// members originate from the same first physical prepared computation.
priv struct LocalEffectFirstCompilation {
  request : @run_host.ClientRequestIdentity
  allowed : @run_host.ClientEffectAllowedRun
  definition : @publication.PublicationContract
  issued : @run_host.ClientEffectIssuedNormalizationMaterials
  materials : @run_host.ClientEffectRunMaterials
  bound : @run_host.PreparedClientEffectRun
}

///|
// A retained acceptance requires lookup, never another compilation or start.
priv enum LocalEffectStartPreparation {
  RetainedEffectSubmission
  NewEffectCompilation(LocalEffectFirstCompilation)
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
// Preserve the existing Open(issue, cleanup) variant intact. Converting this
// error to a CLI string would lose the failed acquisition's retry handle.
priv enum LocalEffectSourcePrefixIssue {
  ForeignPreparation
  Admission(@local_host.NativeClientSubmittedEffectMaterialsIssue)
  Work(@local_host.NativeClientSourceWorkIssue)
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
      @run_host.issue_prepared_client_effect_local_update_normalization(
        prepared,
      )
    _ => stop("LocalEffectNormalizationProfileNotInstalled")
  }
  let normalization = normalization_result.unwrap_or_else(() => {
    stop("LocalOriginalNormalizationNotInstalled")
  })
  let manifests = @run_host.admit_client_compilation_manifests(
    @compiler_environment.compiler_grammar_manifest_wire(),
    @compiler_environment.compiler_barrier_contract_manifest_wire(),
    10000,
    1000,
    20,
  ).unwrap_or_else(() => stop("LocalCompilerManifestUnavailable"))
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
  ).unwrap_or_else(() => stop("LocalEffectCompilationNotReady"))
  let allowed = @run_host.issue_client_effect_allowed_run(
    compilation, scope, configuration_cid, until,
  ).unwrap_or_else(() => stop("LocalEffectRunNotReady"))
  let definition = @run_host.issue_client_effect_run_definition(
    allowed, namespace_id, request_id, now, until,
  ).unwrap_or_else(() => stop("LocalEffectRunDefinitionNotReady"))
  let request = local_effect_request_identity(preparation, scope, request_id)
  let issued = @run_host.issue_prepared_client_effect_normalization_materials(
    allowed,
    definition,
    normalization,
    request=Some(request),
  ).unwrap_or_else(() => stop("LocalEffectOriginalMaterialsUnavailable"))
  let materials = @run_host.bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).unwrap_or_else(() => stop("LocalEffectOriginalMaterialsUnavailable"))
  // Retain the first nominal binding for the later dispatcher/capture join.
  // Rebinding equal contract bytes would create another checked Run owner.
  let bound = @run_host.bind_client_effect_compiled_run(
    prepared, allowed, definition,
  ).unwrap_or_else(() => stop("LocalEffectRunNotReady"))
  { request, allowed, definition, issued, materials, bound, }
}

///|
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
) -> LocalEffectStartPreparation raise ClientStop {
  local_effect_prepare_start_with_clocks(
    host, settings, crypto, preparation, reference, run, scope, local_utc_now,
    () => @env.now().to_double(),
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
) -> LocalEffectStartPreparation raise ClientStop {
  if !local_submit_allowed(host, settings, crypto, scope) {
    stop("LocalSubmissionAuthorizationDenied")
  }
  let request_id = @local_host.native_client_submission_request_id(reference)
  let request = local_effect_request_identity(preparation, scope, request_id)
  let observed_at = utc_now()
  // The existing Owner looks up this exact request before issuing a Policy.
  // A concurrent accepted request selects its saved original, not this clock.
  let (run, now) = match local_run_policy_binding(host, settings, crypto) {
    None => (installed, observed_at)
    Some(binding) =>
      match
        binding.prepare_submission_policy(
          reference, preparation, request, observed_at, epoch_now(),
        ) {
        Ok(Accepted(_)) => {
          if !local_submit_allowed(host, settings, crypto, scope) {
            stop("LocalSubmissionAuthorizationDenied")
          }
          return RetainedEffectSubmission
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
  let original = local_effect_first_compilation(
    preparation,
    scope,
    local_host_result(host.configuration()).configuration_cid(),
    run.namespace_id,
    request_id,
    now,
    run_text(retention, "available_until"),
  )
  // This existing Owner only checks the exact installed Values/normalization
  // profile. Its derived limits are not backing, a Ledger or a start permit.
  let values_supported = match run.source_free {
    Some(values) =>
      @local_values.client_effect_local_ledger_limits(
        original.materials.prepared,
        values.registry_body,
        values.values_body,
        values.fragment_body,
        values.ordered_body,
      ) is Some(_)
    None => false
  }
  if original.request != request ||
    (!values_supported &&
      !@source_owner.resident_effect_source_compute_shape_supported(
        original.bound,
      )) {
    stop("LocalEffectSourceExecutionProfileNotSupported")
  }
  if !local_submit_allowed(host, settings, crypto, scope) {
    stop("LocalSubmissionAuthorizationDenied")
  }
  NewEffectCompilation(original)
}

///|
// The finite Source prefix for the forthcoming trusted Local supplier assembly.
// The public CLI currently refuses before this seam, rather than accept an
// unusable Run and discard live acquisition/cleanup responsibility. The caller
// must retain both successful Work and failed-open cleanup handles.
fn local_effect_source_prefix(
  host : @local_host.NativeLocalHostConnection,
  settings : LocalHostSettings,
  crypto : @local_crypto.Library,
  reference : @local_host.NativeClientSubmissionReference,
  preparation : @local_host.NativeClientSubmittedPreparation,
  original : LocalEffectFirstCompilation,
  configuration : @source_owner.ResidentSourceComputeConfiguration,
  occurrence : String,
) -> Result[
  @local_host.NativeClientEffectSourceWork,
  LocalEffectSourcePrefixIssue,
] {
  guard @local_host.native_client_submitted_preparation(preparation)
    is EffectComputation(prepared) &&
    physical_equal(
      prepared,
      @run_host.client_effect_compilation_owner(original.allowed.compilation),
    ) else {
    return Err(ForeignPreparation)
  }
  match
    host.accept_submitted_effect_material_original(
      crypto,
      settings.principal,
      settings.connection,
      reference,
      preparation,
      original.request,
      original.allowed,
      original.definition,
      original.issued,
      @env.now().to_double(),
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Admission(issue))
  }
  host
  .open_effect_source_work(
    crypto,
    settings.principal,
    settings.connection,
    original.request,
    original.allowed,
    original.definition,
    original.materials,
    configuration,
    occurrence,
    local_utc_now,
  )
  .map_err(issue => Work(issue))
}
