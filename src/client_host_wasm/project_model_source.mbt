///|
// The retained Model claim selects one Local CSV. Its Source transfer and
// later Compute belong to the same physical start and adopted Request.
priv struct StoredPortableModelFileWork {
  compute_handle : Int
  compute : StoredNativeCompute
  selected : StoredPortableModelFile
  runtime : StoredPortableModelRun
  adopted : @local_host.ClientInstalledManagedRun
  model : @local_host.ClientInstalledManagedModelPlan
  source : StoredSDKWholeSourceTransfer
  mut sealing : Bool
  mut evidence_capacity : (@resources.Ledger, @resources.CapacityReservation)?
}

///|
priv struct StoredPortableModelSourceEvidence {
  selection : @host.ClientInferComposedSources
  source : @publication.RunEvidenceValue
  logical : @publication.RunEvidenceValue
  identity : @query.CapturedSourceRelationIdentity
}

///|
fn portable_model_file_source_current(
  value : Instance,
  start : Int,
) -> Result[(StoredPhysicalStart, StoredPortableModelFileWork), Int] {
  guard value.physical_starts.get(start) is Some(custody) &&
    custody.invoked &&
    custody.outcome is Some(Ok(_)) &&
    custody.file_managed is None &&
    custody.model_file is Some(work) &&
    custody.sdk_step is Some(step) &&
    value.runs.get(custody.run) is Some(run) &&
    run.configuration == custody.current_configuration &&
    run.outcome is Some(Ok(plan)) &&
    run.restoration is None &&
    value.computes.get(work.compute_handle) is Some(compute) &&
    physical_equal(compute, work.compute) &&
    compute.origin is SourceFree(original_run, original_start) &&
    original_run == custody.run &&
    original_start == start &&
    !compute.closing &&
    compute.current_configuration == Some(run.configuration) &&
    value.preparations.get(run.preparation)
      is Some({ project_request: Some({ model_run: Some(runtime), .. }), .. } as preparation) &&
    physical_equal(runtime, work.runtime) &&
    runtime.adopted is Some(adopted) &&
    physical_equal(adopted, work.adopted) &&
    physical_equal(runtime.request, @local_run.local_run_request(plan)) &&
    physical_equal(runtime.compiled, @local_run.local_run_compiled(plan)) &&
    physical_equal(runtime.definition, @local_run.local_run_definition(plan)) &&
    value.run_configurations.get(run.configuration) is Some(configuration) &&
    project_request_configuration(value, preparation.environment)
      is Some((selected, check)) &&
    physical_equal(selected, configuration) &&
    configuration.local_project == Some(check.project) &&
    check.local_file is Some(checker) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    current.account is Some(account) else {
    return Err(-2)
  }
  if value.closing || value.runtime_closing { return Err(-5) }
  match run_configuration_current(value, configuration) {
    Err(code) => return Err(code)
    Ok(_) => ()
  }
  let claim = validate_sdk_start_claim(value, step, plan)
  if claim != 0 { return Err(claim) }
  if !work.selected.selection.read_current(checker, account, configuration.tuple.principal) {
    return Err(-20)
  }
  guard value.physical_starts.get(start) is Some(actual) &&
    physical_equal(actual, custody) &&
    actual.model_file is Some(retained) &&
    physical_equal(retained, work) &&
    value.computes.get(work.compute_handle) is Some(same_compute) &&
    physical_equal(same_compute, compute) &&
    !compute.closing else {
    return Err(-2)
  }
  Ok((custody, work))
}

///|
fn advance_original_portable_model_file_source(
  value : Instance,
  handle : Int,
  record : StoredOriginalMetadata,
  start : Int,
  occurrence : Int,
  wire : Bytes,
) -> Int {
  if occurrence != 0 { return -20 }
  let (custody, work) = match portable_model_file_source_current(value, start) {
    Ok(original) => original
    Err(code) => return code
  }
  if !record.invoked {
    let child = match reserve_sdk_whole_source_capture(
        value, handle, record, start, occurrence, wire, work.source,
        work.runtime.compiled, work.runtime.definition,
      ) {
      Ok(child) => child
      Err(code) => return code
    }
    let opened = open_sdk_local_csv_rows(
      work.source, work.adopted, work.runtime.compiled.owner, work.runtime.request,
      child, work.selected.selection, handle,
    )
    if opened != 0 { return opened }
  }
  guard work.source.capture == Some(handle) &&
    record.project is Some(FileCapture(child)) &&
    child.start == start &&
    child.occurrence == occurrence else {
    return -33
  }
  advance_sdk_whole_source_rows(value, handle, record, child, work.source, () => {
    match portable_model_file_source_current(value, start) {
      Err(code) => code
      Ok((active, current)) =>
        if physical_equal(active, custody) && physical_equal(current, work) {
          0
        } else {
          -9
        }
    }
  })
}

///|
fn seal_original_portable_model_file_source(
  value : Instance,
  start : Int,
  at : String,
  record : StoredOriginalMetadata,
) -> Int {
  let (custody, work) = match portable_model_file_source_current(value, start) {
    Ok(original) => original
    Err(code) => return code
  }
  guard !work.sealing &&
    work.evidence_capacity is None &&
    work.runtime.sources is None &&
    work.compute.host is None &&
    work.compute.outcome is None &&
    custody.outcome is Some(Ok(start_proof)) &&
    value.runs.get(custody.run) is Some({ outcome: Some(Ok(plan)), .. }) &&
    work.source.capture is Some(handle) &&
    value.original_metadata.get(handle) is Some({ project: Some(FileCapture(child)), produced: true, output_closed: false, .. }) &&
    child.start == start &&
    child.captured is Some(capture) &&
    child.identity is Some(identity) &&
    child.acquisition is Some(acquisition) &&
    @row_host.row_capture_source(capture) is Ok(input) &&
    work.runtime.members is [task] &&
    @query.captured_source_relation_identity_matches_source(identity, input) else {
    return -35
  }
  if !@publication.run_publication_start_current(
      @host.client_compiled_run_admission(work.runtime.compiled),
      work.runtime.definition,
      at,
    ) {
    return -32
  }
  work.sealing = true
  let host = match @local_run.configure_local_whole_source_model_compute(
      plan, start_proof, work.adopted, work.model, input,
    ) {
    Ok(host) => host
    Err(issue) => {
      work.compute.outcome = Some(Err(issue))
      return -32
    }
  }
  // From here the existing Compute close owns the configured DAG.
  work.compute.host = Some(host)
  let run = @local_run.local_compute_run(host)
  let graph = @strategy.captured_dag_graph(run)
  let prepared = @local_run.local_run_prepared(plan)
  let request = work.runtime.request
  let declared = work.selected.selection.source_acquisition()
  let facts = @row_host.row_input_acquisition_facts(acquisition)
  let scope = @host.client_request_authority_scope_cid(request)
  guard @local_host.installed_managed_source_occurrence(work.adopted, prepared, request, 0)
    is Ok((_, _, producer)) &&
    @row_host.row_input_acquisition_matches_source(acquisition, declared) &&
    sdk_file_invocation_capacity(graph, facts.source_ref, facts.data_classification, child.started_at, at)
      is Some((retained, scratch)) else {
    return -35
  }
  let ledger = @strategy.captured_dag_ledger(run)
  let capacity = match @resources.reserve_capacity(ledger, retained, scratch) {
    Ok(value) => value
    Err(_) => return -4
  }
  work.evidence_capacity = Some((ledger, capacity))
  guard @host.issue_captured_whole_source_input_logical(graph, input, identity, declared, task=producer)
      is Ok(logical) else {
    return -31
  }
  let evidence = match @row_host.issue_row_input_source_evidence(
      acquisition, capture, identity, logical, scope, facts.source_data_policy_cid, at,
    ) {
    Ok(evidence) => evidence
    Err(issue) => return mock_effect_capture_issue(issue)
  }
  guard @host.admit_client_infer_composed_whole_sources(
      task.graph.occurrence, [input], [identity], [declared], [logical], [evidence],
      scope, child.started_at, at,
    ) is Ok(sources) &&
    @host.client_infer_composed_whole_sources_match_run(sources, run) &&
    portable_model_file_source_current(value, start) is Ok((active, retained_work)) &&
    physical_equal(active, custody) &&
    physical_equal(retained_work, work) else {
    return -32
  }
  let activated = match @local_run.bind_local_compute_start(host, start_proof) {
    Ok(owner) => owner
    Err(issue) => {
      work.compute.outcome = Some(Err(issue))
      return -32
    }
  }
  if @resources.shrink_capacity_reservation(ledger, capacity, retained, 0L) is Err(_) {
    return -4
  }
  work.runtime.sources = Some({ selection: sources, source: evidence, logical, identity })
  let code = status(@buffers.supply_buffer_output(value.pool, record.slot, b""))
  if code == 0 {
    work.compute.start = Some(activated)
    work.compute.outcome = Some(Ok(()))
    record.produced = true
  }
  code
}

///|
fn retire_portable_model_file_source(custody : StoredPhysicalStart) -> Int {
  guard custody.model_file is Some(work) else { return 0 }
  if work.source.csv_read is Some(_) { return -9 }
  if work.evidence_capacity is Some((ledger, capacity)) {
    if @resources.settle_capacity(ledger, capacity) is Err(_) { return -4 }
    work.evidence_capacity = None
  }
  work.runtime.sources = None
  custody.model_file = None
  0
}
