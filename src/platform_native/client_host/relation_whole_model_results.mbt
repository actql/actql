///|
/// The selected Native Model consumer keeps the adopted retention and the
/// first source-bearing Model's original Read. Each receiver accepts only its
/// own view of the already issued producer Result.
pub(all) struct NativeWholeModelResults {
  scope : @host.ClientModelReadScope
  retention : @publication.PublicationContract
  retain : (Int, NativeWholeModelResultInputs) -> Bool
}

///|
pub type NativeWholeModelResultInputs = Array[
  (
    Int,
    @host.ClientWholeLocalResultArtifact,
    @host.ClientWholeLocalResultManifest,
  ),
]

///|
priv struct NativeWholeModelProducer {
  unit : Int
  pins : @strategy.CapturedCompletedUnitResults
  results : Array[@local.LocalWholeUnitResultExport]
  mut issued : (
    Array[@host.ClientWholeLocalResultArtifact],
    @host.ClientWholeLocalResultManifest,
  )?
}

///|
// All Local consumers have returned before this closes the shared views.
// There is no new attempt, storage transaction or public Result here.
fn retire_native_whole_model_producer(
  value : Ref[NativeWholeModelProducer?],
) -> Bool {
  guard value.val is Some(producer) else { return true }
  producer.issued = None
  for result in producer.results {
    result.close()
  }
  producer.results.clear()
  producer.results.shrink_to_fit()
  if !@strategy.release_captured_completed_unit_results(producer.pins) {
    return false
  }
  value.val = None
  true
}

///|
// Keep the first typed backing/currentness refusal for the outer File Work.
// Retained bodies accumulate; a finished synchronous constructor contributes
// only its retained extent to the next phase, in addition to the prior Work.
fn NativeClientRelationFileWork::whole_model_producer_funding(
  self : Self,
  managed : @local.ClientInstalledManagedRun,
  failure : Ref[NativeClientSourceWorkIssue?],
  initial : @execution.ExecutionCapacity,
) -> ((@execution.ExecutionCapacity) -> Bool)? {
  guard @local.installed_managed_preparation_admission_original(
      managed,
      self.prepared,
      self.start.request,
    )
    is Some(admission) else {
    return None
  }
  let ledger = @strategy.captured_dag_ledger(self.run)
  let (base_r, base_e) = match
    @resources.prepared_run_native_capacity(admission, self.prepared, ledger) {
    Ok(value) => value
    Err(issue) => {
      failure.val = Some(InstalledRun(@local.Resource(issue)))
      return None
    }
  }
  let controls = @execution.execution_capacity_retained_bytes(initial)
  guard @execution.checked_preparation_add_product(base_r, controls, 1L)
    is Some(initial_r) &&
    @execution.checked_preparation_add_product(
      base_e,
      @execution.execution_capacity_execution_bytes(initial),
      1L,
    )
    is Some(initial_e) else {
    return None
  }
  match
    @resources.grow_prepared_run_native_work_capacity(
      admission,
      self.prepared,
      ledger,
      initial_r,
      initial_e,
    ) {
    Err(issue) => {
      failure.val = Some(InstalledRun(@local.Resource(issue)))
      return None
    }
    Ok(_) => ()
  }
  let held = Ref(controls)
  let peak = Ref(initial_e)
  Some(capacity => {
    if failure.val is Some(_) {
      return false
    }
    match self.require_current() {
      Err(issue) => {
        failure.val = Some(issue)
        return false
      }
      Ok(_) => ()
    }
    guard @execution.checked_preparation_add_product(
        held.val,
        @execution.execution_capacity_retained_bytes(capacity),
        1L,
      )
      is Some(next) &&
      @execution.checked_preparation_add_product(base_r, next, 1L)
      is Some(retained) &&
      @execution.checked_preparation_add_product(base_e, held.val, 1L)
      is Some(previous) &&
      @execution.checked_preparation_add_product(
        previous,
        @execution.execution_capacity_execution_bytes(capacity),
        1L,
      )
      is Some(executing) else {
      failure.val = Some(Configuration)
      return false
    }
    let executing = Int64::max(peak.val, executing)
    match
      @resources.grow_prepared_run_native_work_capacity(
        admission,
        self.prepared,
        ledger,
        retained,
        executing,
      ) {
      Err(issue) => {
        failure.val = Some(InstalledRun(@local.Resource(issue)))
        return false
      }
      Ok(_) => ()
    }
    held.val = next
    peak.val = executing
    match self.require_current() {
      Err(issue) => {
        failure.val = Some(issue)
        false
      }
      Ok(_) => true
    }
  })
}

///|
fn native_whole_result_controls(
  tasks : Int,
  sources : Int,
  results : Int,
  imports : Int64,
) -> @execution.ExecutionCapacity? {
  let tasks = tasks.to_int64()
  let sources = sources.to_int64()
  let results = results.to_int64()
  // The Local next-task observation, exact pin and export wrappers,
  // retained vectors and Scope inputs coexist with the Source and Manifest.
  guard @execution.checked_preparation_add_product(
      sources + results,
      imports,
      1L,
    )
    is Some(items) &&
    @execution.checked_preparation_add_product(32L + tasks, items, 16L)
    is Some(headers) &&
    @execution.checked_preparation_add_product(56L + 3L * tasks, items, 36L)
    is Some(references) &&
    @execution.checked_preparation_add_product(36L + tasks, items, 24L)
    is Some(words) &&
    @execution.preparation_representation_cost({
      record_headers: headers,
      reference_slots: references,
      scalar_words: words,
      owned_utf16_units: 71L * (2L + sources + 2L * results),
      owned_wire_bytes: 0L,
    })
    is Some(bytes) else {
    return None
  }
  @execution.execution_capacity(bytes, bytes)
}

///|
fn NativeClientRelationFileWork::issue_whole_model_producer(
  self : Self,
  managed : @local.ClientInstalledManagedRun,
  selected : @local.LocalWholeTaskPreparation,
  configuration : NativeWholeModelResults,
  sources : @host.ClientInferComposedSources,
  unit : Int,
  count : Int,
  cached : Ref[NativeWholeModelProducer?],
  quantum : Int,
  max_rounds : Int,
  fund : (@execution.ExecutionCapacity) -> Bool,
) -> Result[NativeWholeModelProducer, NativeClientSourceWorkIssue] {
  guard cached.val is None &&
    @strategy.pin_captured_completed_unit_results(self.run, unit, count, 100000)
    is Ok(pins) else {
    return Err(FileWorkSourceBinding)
  }
  let producer : NativeWholeModelProducer = {
    unit,
    pins,
    results: Array(capacity=count),
    issued: None,
  }
  // Record the root before any publication or conversion callback can fail.
  cached.val = Some(producer)
  let original_cid = @publication.publication_contract_identity(self.definition)
  let fund_body = (
    name : String,
    geometry : @encode.EncodingConstructionGeometry,
  ) => {
    @local.installed_effect_imported_model_evidence_body_capacity(
      name, geometry, original_cid, 0L,
    )
    .map(fund)
    .unwrap_or(false)
  }
  let fund_sources = (length : Int) => {
    length > 0 && self.require_current() is Ok(_)
  }
  let invocation = match
    @host.prepare_client_whole_local_unit_invocation(
      configuration.scope,
      self.definition,
      self.start.request,
      self.run,
      pins,
      sources,
      unit,
      65536,
      8192,
      64,
      fund_sources,
      fund_body,
    ) {
    Ok(value) => value
    Err(_) => return Err(FileWorkSourceBinding)
  }
  let publication = match
    @host.prepare_client_whole_local_unit_publication(
      invocation,
      configuration.retention,
      65536,
      8192,
      64,
      fund_sources,
      fund_body,
    ) {
    Ok(value) => value
    Err(_) => return Err(FileWorkSourceBinding)
  }
  let artifacts = Array(capacity=count)
  for index in 0..<count {
    let result = match
      @local.prepare_local_whole_unit_result_export(
        selected,
        managed,
        self.prepared,
        self.start.request,
        unit,
        pins,
        index,
        quantum,
        max_rounds,
        fund,
      ) {
      Ok(value) => value
      Err(issue) => return Err(WholeModelProducerExport(issue))
    }
    producer.results.push(result)
    guard result.handoff() is Some(handoff) else {
      return Err(FileWorkSourceBinding)
    }
    match
      @host.issue_client_whole_local_result_artifact(
        publication,
        index,
        handoff,
        100000,
        65536,
        8192,
        64,
        () => self.require_current() is Ok(_),
        fund_body,
      ) {
      Ok(value) => artifacts.push(value)
      Err(_) => return Err(FileWorkSourceBinding)
    }
  }
  let manifest = match
    @host.issue_client_whole_local_result_manifest(
      publication,
      artifacts,
      65536,
      8192,
      64,
      length => length == count && self.require_current() is Ok(_),
      shape => fund_body("local_manifest", shape),
    ) {
    Ok(value) => value
    Err(_) => return Err(FileWorkSourceBinding)
  }
  producer.issued = Some((artifacts, manifest))
  Ok(producer)
}

///|
fn NativeClientRelationFileWork::stage_whole_model_results(
  self : Self,
  managed : @local.ClientInstalledManagedRun,
  task : Int,
  selected : @local.LocalWholeTaskPreparation,
  plans : Array[@host.ClientInferPlanGraph],
  sources : Array[@host.ClientInferComposedSources],
  configuration : NativeWholeModelResults,
  cached : Ref[NativeWholeModelProducer?],
  quantum : Int,
  max_rounds : Int,
  max_entries : Int,
  funding : (@execution.ExecutionCapacity) -> Bool,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  guard @local.local_whole_task_preparation_matches(selected, self.run, task) &&
    self.require_current() is Ok(_) else {
    return Err(OriginalRunNotCurrent)
  }
  let mut matching = None
  for plan in plans {
    if @host.client_infer_occurrence_coordinates(plan.occurrence).0 == task {
      if matching is Some(_) {
        return Err(FileWorkSourceBinding)
      }
      matching = Some(plan)
    }
  }
  guard matching is Some(plan) else { return Ok(()) }
  let count = @host.client_infer_occurrence_result_import_count(plan.occurrence)
  if count == 0 {
    return Ok(())
  }
  let graph = @strategy.captured_dag_graph(self.run)
  guard @host.client_infer_occurrence_result_import_at(plan.occurrence, 0)
    is Some((unit, _)) &&
    unit >= 0 &&
    @checked.unit_publication_count(@strategy.graph_program(graph), unit)
    is Some(result_count) &&
    result_count > 0 &&
    result_count <= max_entries else {
    return Err(FileWorkSourceBinding)
  }
  for index in 1..<count {
    guard @host.client_infer_occurrence_result_import_at(plan.occurrence, index)
      is Some((same, _)) &&
      same == unit else {
      return Err(FileWorkSourceBinding)
    }
  }
  let producer = match cached.val {
    Some(value) if value.unit == unit => value
    Some(_) => return Err(FileWorkSourceBinding)
    None =>
      match
        self.issue_whole_model_producer(
          managed,
          selected,
          configuration,
          sources[0],
          unit,
          result_count,
          cached,
          quantum,
          max_rounds,
          funding,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
  }
  guard producer.issued is Some((artifacts, manifest)) else {
    return Err(FileWorkSourceBinding)
  }
  let selected_results : NativeWholeModelResultInputs = Array(capacity=count)
  for index in 0..<count {
    let mut matched = None
    for result_index, original in producer.results {
      guard original.handoff() is Some(handoff) &&
        @strategy.captured_completed_unit_result_export_original(
          handoff,
          producer.pins,
          result_index,
        )
        is Some((port, _)) else {
        return Err(FileWorkSourceBinding)
      }
      if @host.client_infer_whole_result_input_edge(
          plan.occurrence,
          index,
          self.run,
          port,
        )
        is Some(edge) {
        guard matched is None else { return Err(FileWorkSourceBinding) }
        matched = Some((result_index, edge, handoff))
      }
    }
    guard matched is Some((result_index, edge, handoff)) &&
      @strategy.retain_captured_completed_unit_result_input(
        handoff, edge, max_entries, 65536,
      )
      is Ok(_) else {
      return Err(FileWorkSourceBinding)
    }
    selected_results.push((index, artifacts[result_index], manifest))
  }
  self
  .require_current()
  .bind(_ => {
    if !(configuration.retain)(task, selected_results) {
      return Err(FileWorkSourceBinding)
    }
    self.require_current()
  })
}
