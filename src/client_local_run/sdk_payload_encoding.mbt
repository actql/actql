///|
/// Transport aggregation of the existing framing, serialization and sink
/// Owners. It makes no authorization, Run, recovery or durable Store decision.
struct LocalSDKPayloadEncoding {
  frames : @publication.DurableResultRowFrames
  serializer : @publication.ResultDeliverySerializer
  sink : @publication.DeliverySinkProgress
  source_hash : @sha.Hasher
  materials : @publication.ObservedResultReadMaterials
  first : LocalSDKReadDeliveryPreparation
  max_bytes : Int
  mut prefix : String?
  mut issue : LocalSDKPayloadEncodingIssue?
  mut terminal : LocalSDKDeliveryTerminal?
}

///|
pub(all) enum LocalSDKPayloadEncodingIssue {
  Frames(@publication.DurableResultRowFrameIssue)
  Serialization(@publication.DeliverySerializationIssue)
  Sink(@publication.DeliverySinkProgressIssue)
  ContentMismatch
  CapacityExceeded
  HashFailure
  Receipt(@publication.DeliveryIssuanceIssue)
} derive(Eq, Debug)

///|
/// The caller keeps the genuine first preparation/current/physical loans and
/// has already reserved codec workspace. Construction is not byte permission.
fn prepare_local_sdk_payload_encoding(
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  first : LocalSDKReadDeliveryPreparation,
  codecs : (
    @publication.DurableResultRowFrames,
    @publication.ResultDeliverySerializer,
  ),
  result_name : String,
  max_results : Int,
  max_bytes : Int,
) -> Result[LocalSDKPayloadEncoding, LocalSDKPayloadEncodingIssue] {
  if max_bytes < 1 ||
    !@publication.result_read_grant_allows_bytes(first.grant, max_bytes) {
    return Err(CapacityExceeded)
  }
  let materials = match
    owner.observed_result_read_materials(view, result_name, max_results) {
    Ok(value) => value
    Err(_) => return Err(ContentMismatch)
  }
  let prefix = match @publication.begin_result_delivery(codecs.1) {
    Ok(value) => value
    Err(issue) => return Err(Serialization(issue))
  }
  let sink = match
    @publication.prepare_delivery_sink_progress(max_bytes.to_int64()) {
    Ok(value) => value
    Err(issue) => return Err(Sink(issue))
  }
  Ok({
    frames: codecs.0,
    serializer: codecs.1,
    sink,
    source_hash: @sha.hasher(),
    materials,
    first,
    max_bytes,
    prefix: Some(prefix),
    issue: None,
    terminal: None,
  })
}

///|
pub(all) enum LocalSDKPayloadPreparationIssue[E] {
  Codecs(LocalSDKReadPayloadCodecIssue[E])
  Encoding(LocalSDKPayloadEncodingIssue)
}

///|
/// Only the original validated selection/schema can create this encoder. A
/// caller cannot pair an arbitrary serializer with a retained attempt and
/// thereby issue a receipt for a different serialization contract.
pub fn[E] prepare_local_sdk_payload_encoding_for_source(
  source : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  finite : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  first : LocalSDKReadDeliveryPreparation,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
  max_row_bytes : Int,
  input_chunk_bytes : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[LocalSDKPayloadEncoding, LocalSDKPayloadPreparationIssue[E]] {
  let codecs = match
    prepare_local_sdk_read_payload_codecs_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, first,
      result_name, format, attempt_id, observed_at, max_results, max_row_bytes, input_chunk_bytes,
      read, current,
    ) {
    Ok(codecs) => codecs
    Err(issue) => return Err(Codecs(issue))
  }
  let (_, _, _, _, _, max_bytes, _) = @publication.local_sdk_result_read_selection_parameters(
    selection,
  )
  prepare_local_sdk_payload_encoding(
    owner, view, first, codecs, result_name, max_results, max_bytes,
  ).map_err(issue => Encoding(issue))
}

///|
/// Reuse original evidence/availability/current Owners around actual byte
/// disclosure. Recomputing the same grant body does not renew or install it.
pub fn[E] validate_local_sdk_payload_encoding_source_current(
  source : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  finite : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  first : LocalSDKReadDeliveryPreparation,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[Unit, LocalSDKReadPayloadCodecIssue[E]] {
  let saved = match
    observe_local_sdk_read_delivery_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, max_results, read, current,
    ) {
    Ok(saved) => saved
    Err(issue) => return Err(Original(issue))
  }
  if !sdk_read_payload_original_matches(first, saved) {
    return Err(ChangedOriginal)
  }
  let grant = match
    issue_local_sdk_read_grant_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, observed_at, max_results, read, current,
    ) {
    Ok(grant) => grant
    Err(issue) => return Err(Store(issue))
  }
  if @publication.publication_contract_json(grant) !=
    @publication.publication_contract_json(first.grant) {
    return Err(ChangedOriginal)
  }
  // A current callback can change the saved usage/head after observation.
  // Revalidate the original streaming attempt without constructing new codecs.
  let final_saved = match
    observe_local_sdk_read_delivery_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, max_results, read, current,
    ) {
    Ok(saved) => saved
    Err(issue) => return Err(Original(issue))
  }
  if !sdk_read_payload_original_matches(first, final_saved) {
    return Err(ChangedOriginal)
  }
  Ok(())
}

///|
fn local_sdk_payload_feed(
  value : LocalSDKPayloadEncoding,
  chunk : Bytes,
  eof : Bool,
) -> Result[Bytes, LocalSDKPayloadEncodingIssue] {
  match value.sink.prepare_next() {
    Ok(_) => ()
    Err(issue) => return Err(Sink(issue))
  }
  let rows = match
    @publication.feed_durable_result_row_frames(value.frames, chunk) {
    Ok(rows) => rows
    Err(issue) => return Err(Frames(issue))
  }
  @sha.update(value.source_hash, chunk) catch {
    _ => return Err(HashFailure)
  }
  let builder = StringBuilder()
  let mut bytes = 0
  if value.prefix is Some(prefix) {
    bytes = @utf8.encode(prefix).length()
    if bytes > value.max_bytes {
      return Err(CapacityExceeded)
    }
    builder.write_string(prefix)
    value.prefix = None
  }
  for row in rows {
    let encoded = match
      @publication.next_result_delivery_row(value.serializer, row) {
      Ok(value) => value
      Err(issue) => return Err(Serialization(issue))
    }
    let count = @utf8.encode(encoded).length()
    if count > value.max_bytes - bytes {
      return Err(CapacityExceeded)
    }
    bytes += count
    builder.write_string(encoded)
  }
  if eof {
    let summary = match
      @publication.finish_durable_result_row_frames(value.frames) {
      Ok(value) => value
      Err(issue) => return Err(Frames(issue))
    }
    let digest = @sha.finish_hex(value.source_hash) catch {
      _ => return Err(HashFailure)
    }
    if summary.bytes.to_int64() != value.materials.read.byte_count ||
      summary.rows.to_int64() != value.materials.read.row_count ||
      digest != value.materials.read.physical_sha256 {
      return Err(ContentMismatch)
    }
    let suffix = match @publication.finish_result_delivery(value.serializer) {
      Ok(value) => value
      Err(issue) => return Err(Serialization(issue))
    }
    if @utf8.encode(suffix).length() > value.max_bytes - bytes {
      return Err(CapacityExceeded)
    }
    builder.write_string(suffix)
  }
  let encoded = @utf8.encode(builder.to_string())
  match value.sink.offer(encoded, eof) {
    Ok(_) => Ok(encoded)
    Err(issue) => Err(Sink(issue))
  }
}

///|
/// Supply bounded physical bytes, never parse or serialize them in Python.
/// The source digest/row count remain distinct from confirmed egress bytes.
pub fn LocalSDKPayloadEncoding::feed(
  self : LocalSDKPayloadEncoding,
  chunk : Bytes,
  eof : Bool,
) -> Result[Bytes, LocalSDKPayloadEncodingIssue] {
  if self.issue is Some(issue) {
    return Err(issue)
  }
  let result = local_sdk_payload_feed(self, chunk, eof)
  match result {
    // These refusals precede all framing/hash advancement. Keep the existing
    // outstanding chunk confirmable; never turn a protocol refusal into lost
    // progress or re-read the supplied physical bytes.
    Err(Sink(DeliverySinkChunkOutstanding)) | Err(Sink(DeliverySinkClosed)) =>
      ()
    Err(issue) => self.issue = Some(issue)
    Ok(_) => ()
  }
  result
}

///|
/// Reject outstanding sink custody before a physical supplier advances its
/// descriptor. This is backpressure, not an enduring read permission.
pub fn LocalSDKPayloadEncoding::prepare_input(
  self : LocalSDKPayloadEncoding,
) -> Result[Unit, LocalSDKPayloadEncodingIssue] {
  if self.issue is Some(issue) {
    return Err(issue)
  }
  self.sink.prepare_next().map_err(issue => Sink(issue))
}

///|
/// Only the physical sink confirms this original outstanding output. Merely
/// producing/copying bytes, EOF or a serializer finish cannot call this for it.
pub fn LocalSDKPayloadEncoding::confirm_chunk(
  self : LocalSDKPayloadEncoding,
) -> Result[Int64, LocalSDKPayloadEncodingIssue] {
  if self.issue is Some(issue) {
    return Err(issue)
  }
  self.sink.confirm_chunk().map_err(issue => Sink(issue))
}

///|
/// The ABI caller has proven the same produced output has zero bytes. Observe
/// existing cumulative progress without fabricating a physical sink ACK.
pub fn LocalSDKPayloadEncoding::observe_empty_output(
  self : LocalSDKPayloadEncoding,
) -> Result[Int64, LocalSDKPayloadEncodingIssue] {
  if self.issue is Some(issue) {
    return Err(issue)
  }
  self.sink.observe_empty_output().map_err(issue => Sink(issue))
}

///|
/// Explicit sink completion issues the existing receipt from actual confirmed
/// bytes. The receipt is not durable until the original Store accepts it; no
/// Run state, index, generation or candidate is issued/changed here.
pub fn LocalSDKPayloadEncoding::confirm_finished(
  self : LocalSDKPayloadEncoding,
) -> Result[@publication.PublicationContract, LocalSDKPayloadEncodingIssue] {
  if self.issue is Some(issue) {
    return Err(issue)
  }
  let summary = match self.sink.confirm_finished() {
    Ok(value) => value
    Err(issue) => return Err(Sink(issue))
  }
  if summary.confirmed_bytes > self.max_bytes.to_int64() {
    return Err(CapacityExceeded)
  }
  @publication.issue_result_delivery_receipt(
    self.materials.index,
    self.materials.manifest,
    self.first.grant,
    self.first.attempt,
    summary.confirmed_bytes.to_int(),
    summary.delivered_sha256[7:].to_owned(),
    65536,
    8192,
    64,
  ).map_err(issue => Receipt(issue))
}

///|
/// Stop this row codec only. Physical reader stop, sink failure/exposure and
/// Store cleanup remain their original Owners, never inferred from cancellation.
pub fn LocalSDKPayloadEncoding::cancel_frames(
  self : LocalSDKPayloadEncoding,
) -> Unit {
  @publication.cancel_durable_result_row_frames(self.frames)
  self.issue = Some(Frames(DurableRowFrameClosed))
}

///|
/// Existing live-run entry preserves its original preflight/current checks.
pub fn[E] prepare_local_sdk_payload_encoding_from_store(
  preflight : LocalPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  finite : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  first : LocalSDKReadDeliveryPreparation,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
  max_row_bytes : Int,
  input_chunk_bytes : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[LocalSDKPayloadEncoding, LocalSDKPayloadPreparationIssue[E]] {
  prepare_local_sdk_payload_encoding_for_source(
    live_sdk_read_source(preflight),
    account,
    finite,
    selection,
    host_adoption_cid,
    owner,
    view,
    first,
    result_name,
    format,
    attempt_id,
    observed_at,
    max_results,
    max_row_bytes,
    input_chunk_bytes,
    read,
    current,
  )
}

///|
/// Existing live-run entry preserves its original preflight/current checks.
pub fn[E] validate_local_sdk_payload_encoding_current(
  preflight : LocalPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  finite : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  first : LocalSDKReadDeliveryPreparation,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[Unit, LocalSDKReadPayloadCodecIssue[E]] {
  validate_local_sdk_payload_encoding_source_current(
    live_sdk_read_source(preflight),
    account,
    finite,
    selection,
    host_adoption_cid,
    owner,
    view,
    first,
    result_name,
    format,
    attempt_id,
    observed_at,
    max_results,
    read,
    current,
  )
}
