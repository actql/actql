///|
/// Per-Result facts that are not shared by the complete Run publication.
/// Array position is the checked Program Result occurrence; names are never
/// accepted from the caller.
pub(all) struct NativeCapturedResultPublicationContext {
  retention : @publication.PublicationContract
  computation_contract_cid : String
  input_relation_cids : Array[String]
  scope_cid : String
  effective_data_policy_cid : String
  store_authority_cid : String
  material_generation_cid : String
  max_payload_bytes : Int64
}

///|
pub(all) enum NativeCapturedRunPublicationPrimaryIssue {
  InvalidCapturedRun
  TerminalInvocation(@local.ClientClosedValuesPreparationIssue)
  TerminalResult(@publication_host.ClientResultTransformationIssue)
  TerminalWorkLimit
  Export(@publication_host.PublicationOutputExportIssue)
  Publication(NativeRunPublicationIssue)
  Output(Int, NativePublicationOutputIssue)
  Assembly(NativeRunPublicationAssemblyIssue)
}

///|
pub(all) struct NativeCapturedRunCleanupFailure {
  result : Int
  issue : @store.NativePublicationStoreIssue
}

///|
/// Preparation failures preserve the primary failure separately from every
/// failed physical reclamation. The Store remains the cleanup owner for any
/// failure reported here.
pub(all) enum NativeCapturedRunPublicationPreparationIssue {
  Prepare(NativeCapturedRunPublicationPrimaryIssue)
  PrepareCleanup(
    NativeCapturedRunPublicationPrimaryIssue,
    Array[NativeCapturedRunCleanupFailure]
  )
}

///|
pub(all) enum NativeCapturedRunPublicationCancellationIssue {
  PublicationCommitted
  Cleanup(Array[NativeCapturedRunCleanupFailure])
}

///|
/// Retryable owner for one fully persisted, not-yet-committed Run
/// publication. A commit failure does not discard the exact occurrence or
/// its payload custody; callers can retry commit or explicitly cancel.
struct NativePreparedCapturedRunPublication {
  service : NativeRunPublicationService
  evidence : NativeEffectFreePublicationEvidence
  intent : NativeRunPublicationIntent
  occurrence : NativeRunPublicationOccurrence
  preparation : NativeRunPublicationPreparation
  capture : @local.ClientProgramCapture?
  material_generation_cids : Array[String]
  reclaimed : Array[Bool]
  mut committed : NativeRunPublicationResult?
  mut cancelled : Bool
}

///|
fn reclaim_captured_outputs(
  service : NativeRunPublicationService,
  contexts : Array[NativeCapturedResultPublicationContext],
  count : Int,
) -> Array[NativeCapturedRunCleanupFailure] {
  let failures : Array[NativeCapturedRunCleanupFailure] = []
  for result in 0..<count {
    match
      service.store.reclaim_payload(contexts[result].material_generation_cid) {
      Ok(_) => ()
      Err(issue) => failures.push({ result, issue, })
    }
  }
  failures
}

///|
fn preparation_failure(
  service : NativeRunPublicationService,
  contexts : Array[NativeCapturedResultPublicationContext],
  persisted : Int,
  primary : NativeCapturedRunPublicationPrimaryIssue,
) -> NativeCapturedRunPublicationPreparationIssue {
  let cleanup = reclaim_captured_outputs(service, contexts, persisted)
  if cleanup.is_empty() {
    Prepare(primary)
  } else {
    PrepareCleanup(primary, cleanup)
  }
}

///|
/// Persist all and only the Named Results declared by the captured checked
/// Program. Payloads remain private until `commit` installs the formal public
/// index. Any preparation failure attempts every independent reclamation and
/// reports unresolved Store custody without weakening the primary cause.
pub fn prepare_captured_effect_free_run_publication_native(
  service : NativeRunPublicationService,
  run : @strategy.CapturedDAG,
  context : NativeEffectFreeRunContext,
  results : Array[NativeCapturedResultPublicationContext],
  intent : NativeRunPublicationIntent,
  occurrence : NativeRunPublicationOccurrence,
  export_limits : @publication_host.PublicationOutputExportLimits,
  converted_outputs? : Array[@execution.CompletedOutput?],
) -> Result[
  NativePreparedCapturedRunPublication,
  NativeCapturedRunPublicationPreparationIssue,
] {
  let graph = @strategy.captured_dag_graph(run)
  let result_count = @strategy.graph_result_count(graph)
  if result_count < 1 || results.length() != result_count {
    return Err(Prepare(InvalidCapturedRun))
  }
  let exports = match
    @publication_host.prepare_all_captured_result_publication_exports(
      run,
      export_limits,
      converted_outputs?,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Prepare(Export(issue)))
  }
  prepare_exported_effect_free_run_publication_native(
    service, run, context, exports, results, intent, occurrence,
  )
}

///|
/// Persist already re-admitted checked Result exports through the same Run
/// publication Owner. This is used when a managed physical output needs its
/// existing publication bridge; it does not reinterpret raw rows or invent
/// completion. The caller retains each bridge until this call returns.
/// Every export is consumed or cancelled here. Store cleanup remains owned by
/// the same preparation result, including failure and unknown commit paths.
pub fn prepare_exported_effect_free_run_publication_native(
  service : NativeRunPublicationService,
  run : @strategy.CapturedDAG,
  context : NativeEffectFreeRunContext,
  exports : Array[@publication_host.PublicationOutputExport],
  results : Array[NativeCapturedResultPublicationContext],
  intent : NativeRunPublicationIntent,
  occurrence : NativeRunPublicationOccurrence,
  publication? : @local.ClientProgramPublication? = None,
) -> Result[
  NativePreparedCapturedRunPublication,
  NativeCapturedRunPublicationPreparationIssue,
] {
  prepare_exported_effect_free_original_graph(
    service,
    @strategy.captured_dag_graph(run),
    context,
    exports,
    results,
    intent,
    occurrence,
    publication~,
  )
}

///|
fn prepare_exported_effect_free_original_graph(
  service : NativeRunPublicationService,
  graph : @checked_strategy.CheckedDAG,
  context : NativeEffectFreeRunContext,
  exports : Array[@publication_host.PublicationOutputExport],
  results : Array[NativeCapturedResultPublicationContext],
  intent : NativeRunPublicationIntent,
  occurrence : NativeRunPublicationOccurrence,
  publication? : @local.ClientProgramPublication? = None,
  content? : Array[@publication.BoundContentGeneration] = [],
  work_remaining? : Ref[Int]? = None,
) -> Result[
  NativePreparedCapturedRunPublication,
  NativeCapturedRunPublicationPreparationIssue,
] {
  if exports.is_empty() ||
    results.length() != exports.length() ||
    exports.length() != @strategy.graph_result_count(graph) {
    for output in exports {
      output.cancel()
    }
    return Err(Prepare(InvalidCapturedRun))
  }
  let definitions : Array[@publication.PublicationContract] = []
  for output in exports {
    match output.definition() {
      Ok(value) => definitions.push(value)
      Err(issue) => {
        for pending in exports {
          pending.cancel()
        }
        return Err(Prepare(Export(issue)))
      }
    }
  }
  // The bridge route must cover all original Named Results in their checked
  // order, just like the ordinary captured-output route. Equal counts alone
  // cannot substitute a Result from another Program or omit a named output.
  for index, definition in definitions {
    let expected = @strategy.graph_result_name(graph, index).bind(name => {
      @publication.prepare_result_definition(
        @strategy.graph_program_definition_cid(graph),
        name,
      ).to_option()
    })
    guard expected is Some(expected) &&
      @publication.publication_contract_identity(definition) ==
      @publication.publication_contract_identity(
        @publication.result_definition_contract(expected),
      ) else {
      for output in exports {
        output.cancel()
      }
      return Err(Prepare(InvalidCapturedRun))
    }
  }
  let preparation = match
    prepare_effect_free_run_publication_native(
      service,
      context.run_definition,
      definitions,
      intent,
      occurrence,
    ) {
    Ok(value) => value
    Err(issue) => {
      for output in exports {
        output.cancel()
      }
      return Err(Prepare(Publication(issue)))
    }
  }
  let attempt = preparation.publication_attempt()
  let published : Array[NativePublishedOutput] = []
  for result, output in exports {
    let selected = results[result]
    match
      persist_publication_output_native(
        service.store,
        output,
        {
          run_definition: context.run_definition,
          invocation: context.invocation,
          retention: selected.retention,
          publication_attempt: attempt,
          computation_contract_cid: selected.computation_contract_cid,
          input_relation_cids: selected.input_relation_cids,
          scope_cid: selected.scope_cid,
          effective_data_policy_cid: selected.effective_data_policy_cid,
          authority_scope_cid: intent.authority_scope_cid,
          store_authority_cid: selected.store_authority_cid,
          material_generation_cid: selected.material_generation_cid,
          max_payload_bytes: selected.max_payload_bytes,
        },
        service.max_wire_bytes,
        service.max_nodes,
        service.max_depth,
        publication~,
        work_remaining~,
      ) {
      Ok(value) => published.push(value)
      Err(issue) => {
        let first_pending = result + 1
        for pending in first_pending..<exports.length() {
          exports[pending].cancel()
        }
        return Err(
          preparation_failure(
            service,
            results,
            published.length(),
            Output(result, issue),
          ),
        )
      }
    }
  }
  let (evidence, capture) = match
    assemble_native_effect_free_publication_owned(
      context,
      published,
      service.max_wire_bytes,
      service.max_nodes,
      service.max_depth,
      publication~,
      content~,
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        preparation_failure(
          service,
          results,
          published.length(),
          Assembly(issue),
        ),
      )
  }
  Ok({
    service,
    evidence,
    intent,
    occurrence,
    preparation,
    capture,
    material_generation_cids: results.map(result => {
      result.material_generation_cid
    }),
    reclaimed: Array::make(results.length(), false),
    committed: None,
    cancelled: false,
  })
}

///|
/// Commit the exact prepared chain. Retrying this method reconciles the same
/// occurrence and never creates a second publication attempt.
pub fn NativePreparedCapturedRunPublication::commit(
  self : NativePreparedCapturedRunPublication,
) -> Result[NativeRunPublicationResult, NativeRunPublicationIssue] {
  if self.cancelled {
    return Err(InvalidConfiguration)
  }
  match self.committed {
    Some(value) => Ok(value)
    None =>
      match
        commit_prepared_effect_free_run_publication_native(
          self.service,
          self.evidence,
          self.intent,
          self.occurrence,
          self.preparation,
          capture=self.capture,
        ) {
        Ok(value) => {
          self.committed = Some(value)
          Ok(value)
        }
        Err(issue) => Err(issue)
      }
  }
}

///|
/// Reclaim every private payload when the caller abandons a prepared
/// publication. Independent failures are all attempted and remain retryable.
pub fn NativePreparedCapturedRunPublication::cancel(
  self : NativePreparedCapturedRunPublication,
) -> Result[Bool, NativeCapturedRunPublicationCancellationIssue] {
  if self.committed is Some(_) {
    return Err(PublicationCommitted)
  }
  if self.cancelled {
    return Ok(true)
  }
  let failures : Array[NativeCapturedRunCleanupFailure] = []
  for result, material_generation_cid in self.material_generation_cids {
    if self.reclaimed[result] {
      continue
    }
    match self.service.store.reclaim_payload(material_generation_cid) {
      Ok(_) => self.reclaimed[result] = true
      Err(issue) => failures.push({ result, issue, })
    }
  }
  if failures.is_empty() {
    self.cancelled = true
    Ok(true)
  } else {
    Err(Cleanup(failures))
  }
}

///|
/// Non-Result evidence of the already admitted source-free Content Run. Its
/// observation and invocation are issued from the original generation below.
pub(all) struct NativeTerminalSerializationRunContext {
  definition : @publication.PublicationContract
  normalization_journal : @publication.RunEvidenceValue
  binding_names : Array[String]
  binding_digests : Array[String]
  authoring : @publication.RunEvidenceValue
}

///|
/// Build a named Result view using the same checked transformation/export as
/// the installed Content driver. The view consumes the remaining Run work.
fn prepare_native_terminal_result(
  prepared : @publication_host.PreparedClientProgram,
  output : @execution.CompletedOutput,
  index : Int,
  limits : @publication_host.PublicationOutputExportLimits,
  remaining : Ref[Int],
) -> Result[
  @publication_host.PublicationOutputExport,
  NativeCapturedRunPublicationPrimaryIssue,
] {
  let selection = match
    @publication_host.prepare_client_result_transformation(
      prepared,
      index,
      limits.schema.max_bytes,
      limits.schema.max_nodes,
      limits.schema.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(TerminalResult(issue))
  }
  let cursor = match
    @publication_host.start_client_result_transformation(
      selection, output, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(TerminalResult(issue))
  }
  defer cursor.cancel() |> ignore
  let mut done = false
  while !done {
    if remaining.val <= 0 {
      return Err(TerminalWorkLimit)
    }
    let granted = Int::min(32, remaining.val)
    let (ready, work, issue) = cursor.advance_progress(granted)
    if work < 0 || work > granted || (!ready && issue is None && work == 0) {
      return Err(TerminalWorkLimit)
    }
    remaining.val -= work
    if issue is Some(cause) {
      return Err(TerminalResult(cause))
    }
    done = ready
  }
  cursor.finish().map_err(issue => TerminalResult(issue))
}

///|
/// A generated Content row is not a captured DAG. Use the original checked
/// graph and the adopted terminal Run's live generation to enter the same
/// private Result/Receipt/Store path as other effect-free publications.
pub fn prepare_native_terminal_serialization_publication(
  service : NativeRunPublicationService,
  owner : @local.ClientInstalledManagedRun,
  request : @publication_host.ClientRequestIdentity,
  prepared : @publication_host.PreparedClientProgram,
  compiled : @publication_host.ClientCompiledRun,
  generation : @publication_host.ClientSerializationGeneration,
  context : NativeTerminalSerializationRunContext,
  results : Array[NativeCapturedResultPublicationContext],
  intent : NativeRunPublicationIntent,
  occurrence : NativeRunPublicationOccurrence,
  demand : @local.ClientSerializationOutputDemand,
  work_remaining : Int,
) -> Result[
  NativePreparedCapturedRunPublication,
  NativeCapturedRunPublicationPreparationIssue,
] {
  guard demand.result_limits is Some(limits) &&
    service.client_request is Some(original) &&
    physical_equal(original, request) &&
    @publication_host.client_compiled_run_matches(compiled, prepared) &&
    @publication_host.client_serialization_generation_output_for(
      generation, compiled,
    )
    is Some(output) else {
    return Err(Prepare(InvalidCapturedRun))
  }
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = @strategy.graph_result_count(graph)
  if count < 1 || results.length() != count {
    return Err(Prepare(InvalidCapturedRun))
  }
  let (observation, invocation, content) = match
    @local.issue_program_terminal_serialization_invocation(
      owner,
      request,
      compiled,
      context.definition,
      generation,
      demand,
      service.max_wire_bytes,
      service.max_nodes,
      service.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Prepare(TerminalInvocation(issue)))
  }
  guard @publication.bound_content_generation_location(content)
    is Some((store, _)) &&
    store == intent.publication_target_cid &&
    intent.authority_scope_cid ==
    @publication_host.client_request_authority_scope_cid(request) &&
    @publication.bound_content_generation_input_relation_cid(content)
    is Some(input_cid) &&
    @publication_host.client_compiled_run_serialization_policy_body(compiled)
    is Some(policy) else {
    return Err(Prepare(InvalidCapturedRun))
  }
  let policy_cid = @publication.captured_effect_dependency_body_cid(policy)
  let definition_cid = @publication.publication_contract_identity(
    context.definition,
  )
  let plan_cid = @publication.publication_contract_identity(
    @publication_host.client_compiled_run_plan(compiled),
  )
  for result in results {
    if result.input_relation_cids != [input_cid] ||
      result.effective_data_policy_cid != policy_cid ||
      result.scope_cid != definition_cid ||
      result.store_authority_cid != store ||
      result.computation_contract_cid != plan_cid {
      return Err(Prepare(InvalidCapturedRun))
    }
  }
  let exports : Array[@publication_host.PublicationOutputExport] = []
  let remaining = Ref(work_remaining)
  for index in 0..<count {
    match
      prepare_native_terminal_result(prepared, output, index, limits, remaining) {
      Ok(value) => exports.push(value)
      Err(issue) => {
        for pending in exports {
          pending.cancel()
        }
        return Err(Prepare(issue))
      }
    }
  }
  prepare_exported_effect_free_original_graph(
    service,
    graph,
    {
      admission: @publication_host.client_compiled_run_admission(compiled),
      run_definition: context.definition,
      observation,
      invocation,
      normalization_journal: context.normalization_journal,
      binding_names: context.binding_names,
      binding_digests: context.binding_digests,
      source_evidence: [],
      model_evidence: [],
      barrier_attempt_receipt_cids: [],
      source_advances: [],
      authoring: context.authoring,
    },
    exports,
    results,
    intent,
    occurrence,
    content=[content],
    work_remaining=Some(remaining),
  )
}
