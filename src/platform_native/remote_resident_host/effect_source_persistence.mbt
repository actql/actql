///|
pub(all) enum ResidentEffectSourcePersistenceIssue {
  ForeignInput
  Unavailable
  ReceiptMismatch
  Custody(ResidentEffectSourceCustodyIssue)
  Native(ResidentSourceComputeIssue)
  Export(@execution.CompletedExportIssue)
}

///|
/// A failed or uncertain seal keeps the original writer. A pre-seal failure
/// cancels only this operation's export/writer; failed cleanup keeps that writer
/// as well. The custody owner and its reservation remain until confirmed cleanup.
pub(all) struct ResidentEffectSourcePersistenceFailure {
  issue : ResidentEffectSourcePersistenceIssue
  custody : ResidentEffectSourceCustody?
  writer : @publication_store.PayloadWriter?
  cleanup_issue : @publication_store.NativePublicationStoreIssue?
}

///|
/// Persist the exact already-computed Native input through the existing output
/// export and payload Store owners. This does not execute a task, grant approval
/// or restore an encrypted Preview. A sealed retry confirms the original bytes.
pub fn ResidentSourceCompute::persist_effect_source_payload(
  self : ResidentSourceCompute,
  store : @publication_store.Store,
  materials : @host.ClientEffectRunMaterials,
  inputs : @strategy.CapturedEffectInputs,
  member_index : Int,
  artifact : @host.ClientEffectLocalResultArtifact,
  source : @publication.CapturedEffectSourceArtifact,
  request : @payload.PublicationPayloadRequest,
  local_result : Int,
  limits : @host.PublicationOutputExportLimits,
) -> Result[ResidentEffectSourceCustody, ResidentEffectSourcePersistenceFailure] {
  if !@strategy.captured_effect_local_result_matches_member(
      inputs, local_result, member_index,
    ) {
    return Err({
      issue: ForeignInput,
      custody: None,
      writer: None,
      cleanup_issue: None,
    })
  }
  let custody = match
    self.retain_effect_source_custody(
      store, materials, inputs, member_index, artifact, source, request,
    ) {
    Ok(value) => value
    Err(failure) =>
      return Err({
        issue: Custody(failure.issue),
        custody: failure.custody,
        writer: None,
        cleanup_issue: None,
      })
  }
  let reject = (issue : ResidentEffectSourcePersistenceIssue) => {
    Err({ issue, custody: Some(custody), writer: None, cleanup_issue: None, })
  }
  match custody.confirm_payload() {
    Ok(_) => return Ok(custody)
    Err(Store(RecoveryRequired)) => ()
    Err(issue) => return reject(Custody(issue))
  }
  if !custody.current() {
    return reject(Unavailable)
  }
  // Keep the raw writer locally across the post-allocation authority check.
  // Even failed cancellation persistence must not lose this recovery handle.
  let writer = match custody.custody.begin_payload() {
    Ok(value) => value
    Err(ExistingPayload) =>
      // Another admitted writer may have sealed this exact payload. Never
      // replace it or export again merely because allocation raced.
      return match custody.confirm_payload() {
        Ok(_) => Ok(custody)
        Err(issue) => reject(Custody(issue))
      }
    Err(issue) => return reject(Custody(Store(issue)))
  }
  let preparation : Ref[@execution.CompletedResultRelationExportPreparation?] = Ref(
    None,
  )
  let stream : Ref[@execution.CompletedOutputExport?] = Ref(None)
  let receipt : Ref[@execution.CompletedRelationExportReceipt?] = Ref(None)
  let close_export = () => {
    if receipt.val is Some(value) {
      @execution.cancel_completed_relation_export_receipt(value)
    }
    if stream.val is Some(value) {
      @execution.cancel_completed_output_export(value)
    }
    if preparation.val is Some(value) {
      @execution.cancel_completed_result_relation_export(value) |> ignore
    }
  }
  let fail_before_seal = (issue : ResidentEffectSourcePersistenceIssue) => {
    close_export()
    match writer.cancel() {
      Ok(_) => reject(issue)
      Err(cleanup_issue) =>
        Err({
          issue,
          custody: Some(custody),
          writer: Some(writer),
          cleanup_issue: Some(cleanup_issue),
        })
    }
  }
  if !custody.current() {
    return fail_before_seal(Unavailable)
  }
  let exported = match
    self.prepare_effect_result_export(inputs, local_result, limits) {
    Ok(value) => value
    Err(issue) => return fail_before_seal(Native(issue))
  }
  let prepared = @strategy.captured_effect_local_result_export_preparation(
    exported,
  )
  preparation.val = Some(prepared)
  while true {
    if !custody.current() {
      return fail_before_seal(Unavailable)
    }
    match @execution.advance_completed_result_relation_export(prepared, 16) {
      Ok((true, _)) => break
      Ok(_) => continue
      Err(issue) => return fail_before_seal(Export(issue))
    }
  }
  let output = match
    @execution.finish_completed_result_relation_export_preparation(prepared) {
    Ok(value) => value
    Err(issue) => return fail_before_seal(Export(issue))
  }
  stream.val = Some(output)
  while true {
    if !custody.current() {
      return fail_before_seal(Unavailable)
    }
    match @execution.next_completed_output_export(output) {
      Ok(Some(chunk)) =>
        match writer.append(@utf8.encode(chunk)) {
          Ok(_) => ()
          Err(issue) => return fail_before_seal(Custody(Store(issue)))
        }
      Ok(None) => break
      Err(issue) => return fail_before_seal(Export(issue))
    }
  }
  let (completed, tail) = match
    @execution.finish_completed_relation_export(output) {
    Ok(value) => value
    Err(issue) => return fail_before_seal(Export(issue))
  }
  receipt.val = Some(completed)
  if !custody.current() {
    return fail_before_seal(Unavailable)
  }
  match writer.append(@utf8.encode(tail)) {
    Ok(_) => ()
    Err(issue) => return fail_before_seal(Custody(Store(issue)))
  }
  let (digest, bytes, _, _) = @execution.output_stream_identity(
    @execution.completed_relation_export_content(completed),
  )
  if !@strategy.captured_effect_local_result_export_matches_receipt(
      inputs, exported, completed,
    ) ||
    digest != custody.digest ||
    bytes.to_int64() != custody.bytes ||
    @execution.logical_relation_cid(
      @execution.completed_relation_export_identity(completed),
    ) !=
    @payload.publication_payload_request_logical_relation(request) ||
    @execution.relation_schema_cid(
      @execution.completed_relation_export_schema_identity(completed),
    ) !=
    @payload.publication_payload_request_schema(request) ||
    @execution.completed_relation_export_measurement(completed).row_count.to_int64() !=
    @payload.publication_payload_request_row_count(request) {
    return fail_before_seal(ReceiptMismatch)
  }
  if !custody.current() {
    return fail_before_seal(Unavailable)
  }
  // Once sealing starts, a persistence failure can have a physical sealed
  // outcome. Keep the same writer/custody; do not erase it or re-export.
  let sealed = writer.seal()
  close_export()
  match sealed {
    Ok(_) => ()
    Err(issue) =>
      return Err({
        issue: Custody(Store(issue)),
        custody: Some(custody),
        writer: Some(writer),
        cleanup_issue: None,
      })
  }
  match custody.confirm_payload() {
    Ok(_) => Ok(custody)
    Err(issue) => reject(Custody(issue))
  }
}
