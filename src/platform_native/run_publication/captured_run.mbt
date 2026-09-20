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
      run, export_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Prepare(Export(issue)))
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
  let evidence = match
    assemble_native_effect_free_publication(
      context,
      published,
      service.max_wire_bytes,
      service.max_nodes,
      service.max_depth,
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
