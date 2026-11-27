///|
// The fixed Native acceptance recorder emits only the first binding refusal.
// The existing typed error, retained work and original cleanup still return.
priv enum NativeWholeModelBindingStage {
  ProducerOutput
  ProducerTerminal
  ProducerInvocation
  ProducerSelection
  ProducerCompletion
  SourceInvocation
  ProducerPublication
  ProducerArtifact
  ProducerManifest
  ReceiverSelection
  ReceiverReader
  ReceiverRetain
}

///|
extern "C" fn native_model_dependency_failure(
  stage : Int,
  reason : Int,
) -> Unit = "actql_native_model_dependency_failure"

///|
fn native_whole_model_binding_issue(
  stage : NativeWholeModelBindingStage,
  reason? : Int = 0,
) -> NativeClientSourceWorkIssue {
  let number = match stage {
    ProducerOutput => 1
    ProducerTerminal => 2
    ProducerInvocation => 3
    ProducerSelection => 4
    ProducerCompletion => 5
    SourceInvocation => 6
    ProducerPublication => 7
    ProducerArtifact => 8
    ProducerManifest => 9
    ReceiverSelection => 10
    ReceiverReader => 11
    ReceiverRetain => 12
  }
  native_model_dependency_failure(number, reason)
  FileWorkSourceBinding
}

///|
fn native_whole_model_invocation_reason(
  issue : @host.ClientEffectLocalInvocationIssue,
) -> Int {
  match issue {
    MissingUnit => 1
    NotSourceFree => 2
    ForeignCapturedInput => 3
    MissingCapturedInput => 4
    ForeignSourceObservation => 5
    IncompleteResultImports => 6
    ForeignResultImport => 7
    Encoding => 8
  }
}

///|
/// The selected Native Model consumer keeps the adopted retention and the
/// exact selected Model Reads and completed outputs. Each receiver accepts only its
/// own view of the already issued producer Result.
pub(all) struct NativeWholeModelResults {
  scope : (Int) -> @host.ClientModelReadScope?
  completed : (Int) -> @infer.OutputUse?
  retention : @publication.PublicationContract
  retain : (Int, NativeWholeModelResultInputs) -> Bool
}

///|
pub type NativeWholeModelResultInputs = Array[
  (
    Int,
    @host.ClientWholeLocalResultArtifact,
    @host.ClientWholeLocalResultManifest,
    Int,
    @execution.ProducerRead,
  ),
]

///|
priv struct NativeWholeModelProducer {
  pins : @strategy.CapturedCompletedUnitResults
  results : Array[@local.LocalWholeUnitResultExport]
  mut outcome : @execution.CompletedRelationExportReceipt?
  mut issued : (
    Array[@host.ClientWholeLocalResultArtifact],
    @host.ClientWholeLocalResultManifest,
  )?
}

///|
// All Local consumers have returned before this closes the shared views.
// There is no new attempt, storage transaction or public Result here.
fn retire_native_whole_model_producers(
  values : FixedArray[NativeWholeModelProducer?],
) -> Bool {
  // Checked imports only point to earlier Units. Retire each borrower before
  // releasing the earlier producer whose Manifest it can still reference.
  for index = values.length() - 1; index >= 0; index = index - 1 {
    guard values[index] is Some(producer) else { continue }
    producer.issued = None
    if producer.outcome is Some(receipt) {
      @execution.cancel_completed_relation_export_receipt(receipt)
      producer.outcome = None
    }
    for result in producer.results {
      result.close()
    }
    producer.results.clear()
    producer.results.shrink_to_fit()
    if !@strategy.release_captured_completed_unit_results(producer.pins) {
      return false
    }
    values[index] = None
  }
  true
}

///|
priv struct NativeWholeModelProducerFunding {
  retain : (@execution.ExecutionCapacity) -> Bool
  cover : (@execution.ExecutionCapacity) -> Bool
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
) -> NativeWholeModelProducerFunding? {
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
  let retained_peak = Ref(initial_r)
  let execution_peak = Ref(initial_e)
  let reserve = (capacity, keep) => {
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
    let retained = Int64::max(retained_peak.val, retained)
    let executing = Int64::max(execution_peak.val, executing)
    if retained > retained_peak.val || executing > execution_peak.val {
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
    }
    if keep {
      held.val = next
    }
    retained_peak.val = retained
    execution_peak.val = executing
    match self.require_current() {
      Err(issue) => {
        failure.val = Some(issue)
        false
      }
      Ok(_) => true
    }
  }
  Some({
    retain: value => reserve(value, true),
    cover: value => reserve(value, false),
  })
}

///|
fn native_whole_result_controls(
  tasks : Int,
  sources : Int,
  units : Int,
  imports : Int64,
) -> @execution.ExecutionCapacity? {
  let tasks = tasks.to_int64()
  let sources = sources.to_int64()
  let units = units.to_int64()
  // The Local next-task observation, exact pin and export wrappers,
  // retained vectors and Scope inputs coexist with the Source and Manifest.
  // Each import also carries the task input position and the exact staged
  // Read. The retained and completed Scope variants each reserve a Reader
  // reference for dependent Model inputs.
  guard @execution.checked_preparation_add_product(sources, imports, 1L)
    is Some(items) &&
    @execution.checked_preparation_add_product(
      32L + tasks + imports,
      items,
      16L,
    )
    is Some(headers) &&
    @execution.checked_preparation_add_product(
      56L + 3L * tasks + 4L * imports,
      items,
      36L,
    )
    is Some(references) &&
    @execution.checked_preparation_add_product(
      36L + tasks + 2L * imports,
      items,
      24L,
    )
    is Some(words) &&
    @execution.preparation_representation_cost({
      record_headers: headers,
      reference_slots: references + units,
      scalar_words: words,
      owned_utf16_units: 71L * (2L + sources),
      owned_wire_bytes: 0L,
    })
    is Some(bytes) else {
    return None
  }
  @execution.execution_capacity(bytes, bytes)
}

///|
fn native_whole_producer_controls(count : Int) -> @execution.ExecutionCapacity? {
  let count = count.to_int64()
  @execution.preparation_representation_cost({
    record_headers: 2L + 16L * count,
    reference_slots: 9L + 36L * count,
    scalar_words: 4L + 24L * count,
    owned_utf16_units: 142L * count,
    owned_wire_bytes: 0L,
  }).bind(bytes => @execution.execution_capacity(bytes, bytes))
}

///|
fn NativeClientRelationFileWork::whole_model_outcome(
  self : Self,
  producer : NativeWholeModelProducer,
  held : @infer.OutputUse,
  plan : @host.ClientInferPlanGraph,
  quantum : Int,
  max_rounds : Int,
  funding : NativeWholeModelProducerFunding,
) -> Result[
  @execution.CompletedRelationExportReceipt,
  NativeClientSourceWorkIssue,
] {
  guard @infer.preconsumer_model_unit_identity_start_capacity(
      held,
      self.compiled,
      self.definition,
      plan,
      retain_body=false,
    )
    is Some(start) &&
    (funding.cover)(start) else {
    return Err(FileWorkControlQuote)
  }
  let scan = match
    @infer.start_preconsumer_model_unit_identity(
      held,
      self.compiled,
      self.definition,
      plan,
      retain_body=false,
    ) {
    Ok(value) => value
    Err(issue) => return Err(WholeModelOutcomeExport(issue))
  }
  defer @execution.cancel_completed_relation_identity_scan(scan) |> ignore
  for _ in 0..<max_rounds {
    guard @execution.completed_relation_identity_scan_next_construction_capacity(
        scan,
      )
      is Some(frame) &&
      (funding.cover)(frame) else {
      return Err(FileWorkControlQuote)
    }
    let finished = match
      @execution.advance_completed_relation_identity_scan(
        scan,
        quantum,
        construction_capacity=Some(frame),
      ) {
      Ok((value, _)) => value
      Err(issue) => return Err(WholeModelOutcomeExport(issue))
    }
    if finished {
      guard @execution.completed_relation_identity_scan_next_construction_capacity(
          scan,
        )
        is Some(finish) &&
        (funding.cover)(finish) else {
        return Err(FileWorkControlQuote)
      }
      let receipt = match
        @execution.finish_completed_relation_identity_scan(scan) {
        Ok(value) => value
        Err(issue) => return Err(WholeModelOutcomeExport(issue))
      }
      producer.outcome = Some(receipt)
      guard @execution.completed_relation_export_retained_capacity(receipt)
        is Some(capacity) &&
        (funding.retain)(capacity) else {
        return Err(FileWorkControlQuote)
      }
      return Ok(receipt)
    }
  }
  Err(WholeModelOutcomeExport(NotFinished))
}

///|
fn NativeClientRelationFileWork::materialize_whole_model_invocation(
  self : Self,
  producer : NativeWholeModelProducer,
  held : @infer.OutputUse,
  plan : @host.ClientInferPlanGraph,
  scope : @host.ClientModelReadScope,
  quantum : Int,
  max_rounds : Int,
  funding : NativeWholeModelProducerFunding,
  fund_original : (Int) -> Bool,
  fund_body : (String, @encode.EncodingConstructionGeometry) -> Bool,
) -> Result[@host.ClientWholeLocalUnitInvocation, NativeClientSourceWorkIssue] {
  guard @infer.borrow_original_live_host_output(
      held,
      self.compiled,
      self.definition,
      plan,
    )
    is Some((output, _)) else {
    return Err(native_whole_model_binding_issue(ProducerOutput))
  }
  let (task, unit, _) = @host.client_infer_occurrence_coordinates(
    plan.occurrence,
  )
  let mut selected = None
  for index, result in producer.results {
    guard result.handoff() is Some(handoff) else {
      return Err(native_whole_model_binding_issue(ProducerTerminal))
    }
    if @strategy.captured_completed_unit_result_export_matches_output(
        handoff,
        self.run,
        unit,
        task,
        output,
      ) {
      selected = Some((index, handoff))
      break
    }
  }
  guard selected is Some((index, handoff)) else {
    return Err(native_whole_model_binding_issue(ProducerTerminal))
  }
  self
  .whole_model_outcome(producer, held, plan, quantum, max_rounds, funding)
  .bind(receipt => {
    @infer.issue_original_whole_model_unit_invocation(
      held,
      self.compiled,
      self.definition,
      plan,
      scope,
      self.start.request,
      self.run,
      producer.pins,
      index,
      handoff,
      receipt,
      65536,
      8192,
      64,
      funding.retain,
      fund_original,
      fund_body,
    ).map_err(issue => {
      native_whole_model_binding_issue(
        ProducerInvocation,
        reason=native_whole_model_invocation_reason(issue),
      )
    })
  })
}

///|
fn NativeClientRelationFileWork::issue_whole_model_producer(
  self : Self,
  managed : @local.ClientInstalledManagedRun,
  selected : @local.LocalWholeTaskPreparation,
  configuration : NativeWholeModelResults,
  plans : Array[@host.ClientInferPlanGraph],
  sources : @host.ClientInferComposedSources,
  receiver : Int,
  unit : Int,
  count : Int,
  cached : FixedArray[NativeWholeModelProducer?],
  quantum : Int,
  max_rounds : Int,
  funding : NativeWholeModelProducerFunding,
) -> Result[NativeWholeModelProducer, NativeClientSourceWorkIssue] {
  let mut modeled = None
  for index, plan in plans {
    if @host.client_infer_occurrence_coordinates(plan.occurrence).1 == unit {
      guard modeled is None else {
        return Err(native_whole_model_binding_issue(ProducerSelection))
      }
      modeled = Some(index)
    }
  }
  guard cached[unit] is None &&
    (configuration.scope)(modeled.unwrap_or(receiver)) is Some(scope) &&
    native_whole_producer_controls(count) is Some(controls) &&
    (funding.retain)(controls) &&
    @strategy.pin_captured_completed_unit_results(self.run, unit, count, 100000)
    is Ok(pins) else {
    return Err(native_whole_model_binding_issue(ProducerSelection))
  }
  let producer : NativeWholeModelProducer = {
    pins,
    results: Array(capacity=count),
    outcome: None,
    issued: None,
  }
  // Record the root before any publication or conversion callback can fail.
  cached[unit] = Some(producer)
  let prepare_export = index => {
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
      funding.retain,
    )
    .map(value => {
      producer.results.push(value)
      value
    })
    .map_err(issue => WholeModelProducerExport(issue))
  }
  let original_cid = @publication.publication_contract_identity(self.definition)
  let workspace : Ref[Int64?] = Ref(None)
  let fund_body = (name, geometry) => {
    @local.installed_effect_imported_model_evidence_body_capacity(
      name,
      geometry,
      original_cid,
      workspace.val.unwrap_or(0L),
    )
    .map(funding.retain)
    .unwrap_or(false)
  }
  let fund_sources = (length : Int) => {
    if length <= 0 || self.require_current() is Err(_) {
      return false
    }
    if modeled is Some(_) && workspace.val is None {
      // Each original scope is drawn from this same bounded Source inventory.
      // Price duplicate scope entries as well as the canonical output keys.
      let entries = Int64::min(8192L, length.to_int64() * length.to_int64()).to_int()
      guard @local.installed_effect_imported_model_evidence_frame_capacity(
          length.to_int64(),
          entries,
          64,
        )
        is Some(frame) &&
        (funding.retain)(frame) else {
        return false
      }
      workspace.val = Some(
        @execution.execution_capacity_execution_bytes(frame) -
        @execution.execution_capacity_retained_bytes(frame),
      )
    }
    true
  }
  let invocation = match modeled {
    None =>
      @host.prepare_client_whole_local_unit_invocation(
        scope,
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
      ).map_err(_ => native_whole_model_binding_issue(SourceInvocation))
    Some(model) => {
      guard (configuration.completed)(model) is Some(held) else {
        return Err(native_whole_model_binding_issue(ProducerCompletion))
      }
      // The actual terminal export supplies the one checked Model occurrence
      // required by the shared issuer. Each declared view is constructed once.
      for index in 0..<count {
        match prepare_export(index) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
      self.materialize_whole_model_invocation(
        producer,
        held,
        plans[model],
        scope,
        quantum,
        max_rounds,
        funding,
        fund_sources,
        fund_body,
      )
    }
  }
  let invocation = match invocation {
    Ok(value) => value
    Err(issue) => return Err(issue)
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
    Err(_) => return Err(native_whole_model_binding_issue(ProducerPublication))
  }
  workspace.val = None
  let artifacts = Array(capacity=count)
  for index in 0..<count {
    let result = match producer.results.get(index) {
      Some(value) => value
      None =>
        match prepare_export(index) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
    }
    guard result.handoff() is Some(handoff) else {
      return Err(native_whole_model_binding_issue(ProducerArtifact))
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
      Err(_) => return Err(native_whole_model_binding_issue(ProducerArtifact))
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
    Err(_) => return Err(native_whole_model_binding_issue(ProducerManifest))
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
  cached : FixedArray[NativeWholeModelProducer?],
  quantum : Int,
  max_rounds : Int,
  max_entries : Int,
  funding : NativeWholeModelProducerFunding,
) -> Result[Unit, NativeClientSourceWorkIssue] {
  guard @local.local_whole_task_preparation_matches(selected, self.run, task) &&
    self.require_current() is Ok(_) else {
    return Err(OriginalRunNotCurrent)
  }
  let mut matching = None
  for receiver, plan in plans {
    if @host.client_infer_occurrence_coordinates(plan.occurrence).0 == task {
      if matching is Some(_) {
        return Err(native_whole_model_binding_issue(ReceiverSelection))
      }
      matching = Some((receiver, plan))
    }
  }
  guard matching is Some((receiver, plan)) else { return Ok(()) }
  let count = @host.client_infer_occurrence_result_import_count(plan.occurrence)
  if count == 0 {
    return Ok(())
  }
  let graph = @strategy.captured_dag_graph(self.run)
  let program = @strategy.graph_program(graph)
  let selected_results : NativeWholeModelResultInputs = Array(capacity=count)
  for index in 0..<count {
    guard @host.client_infer_occurrence_result_import_at(plan.occurrence, index)
      is Some((unit, _)) &&
      unit >= 0 &&
      unit < cached.length() else {
      return Err(native_whole_model_binding_issue(ReceiverSelection))
    }
    let producer = match cached[unit] {
      Some(value) => value
      None => {
        guard @checked.unit_publication_count(program, unit)
          is Some(result_count) &&
          result_count > 0 &&
          result_count <= max_entries else {
          return Err(native_whole_model_binding_issue(ReceiverSelection))
        }
        match
          self.issue_whole_model_producer(
            managed,
            selected,
            configuration,
            plans,
            sources[receiver],
            receiver,
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
    }
    guard producer.issued is Some((artifacts, manifest)) else {
      return Err(native_whole_model_binding_issue(ReceiverReader))
    }
    let mut matched = None
    for result_index, original in producer.results {
      guard original.handoff() is Some(handoff) &&
        @strategy.captured_completed_unit_result_export_original(
          handoff,
          producer.pins,
          result_index,
        )
        is Some((port, _)) else {
        return Err(native_whole_model_binding_issue(ReceiverReader))
      }
      if @host.client_infer_whole_result_input_edge(
          plan.occurrence,
          index,
          self.run,
          port,
        )
        is Some(edge) {
        guard matched is None else {
          return Err(native_whole_model_binding_issue(ReceiverReader))
        }
        matched = Some((result_index, edge, handoff))
      }
    }
    guard matched is Some((result_index, edge, handoff)) &&
      @strategy.retain_captured_completed_unit_result_input(
        handoff, edge, max_entries, 65536,
      )
      is Ok((position, read)) else {
      return Err(native_whole_model_binding_issue(ReceiverReader))
    }
    selected_results.push(
      (index, artifacts[result_index], manifest, position, read),
    )
  }
  self
  .require_current()
  .bind(_ => {
    if !(configuration.retain)(task, selected_results) {
      return Err(native_whole_model_binding_issue(ReceiverRetain))
    }
    self.require_current()
  })
}
