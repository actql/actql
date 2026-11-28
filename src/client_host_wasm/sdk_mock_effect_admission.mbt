///|
// The Project's checked publication and complete Plan must belong to this
// installed SDK configuration. Keep the nominal Plan, including its original
// selected file, on the Request.
fn sdk_mock_effect_plan(
  value : Instance,
  preparation : StoredPreparation,
  configuration : StoredRunConfiguration,
) -> (StoredMockProjectCheck, StoredMockProjectEffectPlan)? {
  guard preparation.kind == RETAINED_MOCK_REQUEST_KIND &&
    configuration.sdk is Some(_) &&
    preparation.project_request is Some(held) &&
    held.target_check_input is None &&
    held.submission is Some(_) &&
    held.effect_plan is Some(effect) &&
    effect.ready &&
    mock_project_request_configuration(value, preparation.environment)
    is Some((original_configuration, check)) &&
    physical_equal(configuration, original_configuration) &&
    check.runtime_cid is Some(_) else {
    return None
  }
  Some((check, effect))
}

///|
// Select the Run that may use this Plan for first journal construction. This
// step makes no Store write and never reserves a Source or a physical start.
// The Request remains the Plan and preparation capacity owner.
fn prepare_sdk_mock_effect(
  value : Instance,
  handle : Int,
  run : StoredRun,
  preparation : StoredPreparation,
  configuration : StoredRunConfiguration,
  submission : Int,
  observation : StoredSubmissionProjection,
) -> Int {
  guard sdk_mock_effect_plan(value, preparation, configuration)
    is Some((check, effect)) &&
    preparation.project_request is Some(held) &&
    held.submission is Some((original_handle, original_snapshot)) &&
    original_handle == submission &&
    run.restoration is None &&
    observation.append_plan is Ready(@host.Retained(snapshot)) &&
    physical_equal(snapshot, original_snapshot) else {
    return -35
  }
  guard effect.sdk_run is None || effect.sdk_run == Some(handle) else {
    return -33
  }
  let current = mock_project_effect_plan_current(value, check, effect)
  if current != 0 {
    return current
  }
  match
    retained_project_request_snapshot(
      value,
      preparation,
      check.configuration,
      configuration,
    ) {
    Ok((original, observed)) if original == submission &&
      physical_equal(observed, snapshot) => ()
    Ok(_) => return -35
    Err(code) => return code
  }
  let retained = @host.client_saved_submission_record(snapshot)
  guard @host.client_submission_reference_matches_request(
      retained.reference,
      effect.request,
    ) &&
    @authorization.bind_dispatch_authorization(
      configuration.account,
      configuration.tuple,
      @authorization.Activation,
      @host.client_request_program_cid(effect.request),
      configuration.context_cid,
    )
    is Ok(_) else {
    return -32
  }
  let (run_id, now, at) = match
    sdk_first_run_clock(value, run, retained.reference) {
    Err(code) => return code
    Ok(clock) => clock
  }
  match
    @host.read_client_retained_run_journal(
      effect.request,
      (table, key) => sdk_run_journal_port(value, configuration, 1, table, key),
      submission_append_run_inspection,
      -31,
    ) {
    Ok(None) => ()
    Ok(Some(_)) => return -35
    Err(issue) => return sdk_run_append_issue(issue)
  }
  match run_configuration_current(value, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  guard value.runs.get(handle) is Some(original_run) &&
    physical_equal(run, original_run) &&
    sdk_mock_effect_plan(value, preparation, configuration)
    is Some((original_check, original_effect)) &&
    physical_equal(check, original_check) &&
    physical_equal(effect, original_effect) &&
    value.submissions.get(submission) is Some(original_observation) &&
    physical_equal(observation, original_observation) &&
    !observation.output_closed &&
    observation.append_plan is Ready(@host.Retained(still)) &&
    physical_equal(snapshot, still) else {
    return -9
  }
  let current = mock_project_effect_plan_current(value, check, effect)
  if current != 0 {
    return current
  }
  if run.invoked {
    return if effect.sdk_run == Some(handle) &&
      run.sdk_submission == Some(submission) &&
      effect.journal is Some(_) {
      0
    } else {
      -33
    }
  }
  guard held.parent is Some(parent) &&
    held.access is Some(access) &&
    configuration.sdk is Some(sdk) else {
    return -23
  }
  if effect.sdk_run is Some(_) {
    return -33
  }
  run.invoked = true
  run.sdk_submission = Some(submission)
  effect.sdk_run = Some(handle)
  let (compilation, normalization) = match
    @local_host.construct_request_first_effect_compilation(
      parent,
      preparation.slot,
      effect.plan,
    ) {
    Err(issue) => return mock_project_request_issue(issue)
    Ok(value) => value
  }
  let prepared = @host.client_effect_compilation_owner(compilation)
  let (materials, retention) = match
    @local_host.construct_request_effect_materials(
      parent,
      preparation.slot,
      prepared,
      fund => {
        issue_sdk_mock_effect_materials(
          configuration,
          sdk,
          effect.request,
          compilation,
          normalization,
          run_id,
          at,
          fund,
        )
      },
    ) {
    Err(Preparation(issue)) => return mock_project_request_issue(issue)
    Err(_) => return -34
    Ok(value) => value
  }
  match run_configuration_current(value, configuration) {
    Err(code) => return code
    Ok(_) => ()
  }
  match
    @local_host.complete_request_effect_preparation(
      parent,
      preparation.slot,
      effect.plan,
    ) {
    Err(issue) => return mock_project_request_issue(issue)
    Ok(_) => ()
  }
  match
    @local_host.fund_platform_vm_request_effect_plan(
      parent,
      preparation.slot,
      access,
    ) {
    Err(issue) => return mock_project_request_backing_issue(issue)
    Ok(_) => ()
  }
  match @local_host.borrow_request_effect_preparation(parent) {
    Err(issue) => mock_project_request_issue(issue)
    Ok(plan) => {
      effect.journal = Some({
        plan,
        materials,
        retention,
        now,
        material_reserved: false,
      })
      0
    }
  }
}

///|
priv struct StoredMockEffectJournal {
  plan : @resources.PreparationBodyBorrow[
    @local_host.ClientInstalledEffectManagedPlan,
  ]
  materials : @host.ClientEffectRunMaterials
  retention : @publication.PublicationContract
  now : Double
  mut material_reserved : Bool
}

///|
fn issue_sdk_mock_effect_materials(
  configuration : StoredRunConfiguration,
  sdk : StoredSDKRunConfiguration,
  request : @host.ClientRequestIdentity,
  compilation : @host.ClientEffectCompilation,
  normalization : @host.ClientEffectNormalization,
  run_id : String,
  at : String,
  before_body : (String, Int, Int, Int) -> Bool,
) -> Result[
  (@host.ClientEffectRunMaterials, @publication.PublicationContract),
  @host.ClientEffectRunMaterialsIssue,
] {
  guard fund_sdk_first_run_definition(configuration, run_id, before_body) else {
    return Err(Input(MaterialsConstructionRefused("run_definition_read")))
  }
  guard @host.issue_client_local_run_retention_policy(sdk.profile, at)
    is Ok(retention) &&
    @publication.result_retention_available_until(retention) is Ok(until) &&
    @host.issue_client_effect_allowed_run(
      compilation,
      configuration.context_cid,
      configuration.policy_cid,
      until,
    )
    is Ok(allowed) &&
    @host.issue_client_effect_run_definition(
      allowed,
      configuration.run_namespace,
      run_id,
      at,
      until,
    )
    is Ok(definition) else {
    return Err(Input(MaterialsMalformed))
  }
  let issued = match
    @host.issue_prepared_client_effect_normalization_materials(
      allowed,
      definition,
      normalization,
      request=Some(request),
      before_body=Some(before_body),
    ) {
    Err(issue) => return Err(issue)
    Ok(issued) => issued
  }
  @host.bind_prepared_client_effect_original_materials(
    allowed,
    definition,
    issued,
    request=Some(request),
  ).map(materials => (materials, retention))
}
