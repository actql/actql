///|
/// Original existing-Owner receipt and successor, not physical COMMIT ACK.
/// The first terminal time/body stays immutable across lost-response lookup.
struct LocalSDKDeliveryTerminal {
  first : LocalSDKReadDeliveryPreparation
  receipt : @publication.PublicationContract
  record : @publication.PublicationContract
  head_key : String
  original_head : Bytes
}

///|
pub(all) enum LocalSDKDeliveryTerminalIssue[E] {
  Current(LocalSDKReadPayloadCodecIssue[E])
  Observation(LocalSDKReadDeliveryObservationIssue[E])
  Query(E)
  Encoding(LocalSDKPayloadEncodingIssue)
  Issuance(@publication.DeliveryIssuanceIssue)
  ChangedOriginal
  MissingOriginal
  UnresolvedOriginal
  CapacityExceeded
  EncodingFailure
}

///|
/// Reuse sink completion and delivery issuance after the original streaming
/// head/current/availability are observed. Preparing these bytes makes no
/// Store mutation, durable acknowledgement or Run terminal transition.
pub fn[E] LocalSDKPayloadEncoding::prepare_terminal_for_source(
  self : LocalSDKPayloadEncoding,
  source : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  finite : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[LocalSDKDeliveryTerminal, LocalSDKDeliveryTerminalIssue[E]] {
  match
    validate_local_sdk_payload_encoding_source_current(
      source,
      account,
      finite,
      selection,
      host_adoption_cid,
      owner,
      view,
      self.first,
      result_name,
      format,
      attempt_id,
      observed_at,
      max_results,
      read,
      current,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Current(issue))
  }
  if self.terminal is Some(original) {
    // An unattempted cached proposal does not acquire a new terminal timestamp.
    // An attempted/unknown write uses observation, never this preparation path.
    return Ok(original)
  }
  let receipt = match self.confirm_finished() {
    Ok(receipt) => receipt
    Err(issue) => return Err(Encoding(issue))
  }
  let summary = match self.sink.confirm_finished() {
    Ok(summary) => summary
    Err(issue) => return Err(Encoding(Sink(issue)))
  }
  if summary.confirmed_bytes < 0L ||
    summary.confirmed_bytes > 65536L ||
    !summary.delivered_sha256.has_prefix("sha256:") {
    return Err(ChangedOriginal)
  }
  let record = match
    @publication.issue_delivery_record(
      self.first.attempt,
      Some(self.first.streaming),
      "succeeded",
      summary.confirmed_bytes.to_int(),
      "exact",
      None,
      Some(summary.delivered_sha256[7:].to_owned()),
      Some(receipt),
      None,
      observed_at,
      [],
      65536,
      8192,
      64,
    ) {
    Ok(record) => record
    Err(issue) => return Err(Issuance(issue))
  }
  match
    @publication.validate_delivery_success_evidence(
      self.first.attempt,
      receipt,
      record,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Issuance(issue))
  }
  let terminal : LocalSDKDeliveryTerminal = {
    first: self.first,
    receipt,
    record,
    head_key: @publication.publication_contract_identity(self.first.attempt),
    original_head: @utf8.encode(
      @publication.publication_contract_json(self.first.streaming),
    ),
  }
  self.terminal = Some(terminal)
  Ok(terminal)
}

///|
/// Typed proposal for one same-Store transaction. The trusted physical caller
/// fences original scope/epoch/reader facts, applies these three CAS writes and
/// treats an attempted COMMIT failure as Unknown. This packet is never ACK.
pub fn[E] LocalSDKDeliveryTerminal::storage_from_store(
  self : LocalSDKDeliveryTerminal,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[String, LocalSDKDeliveryTerminalIssue[E]] {
  match current() {
    Err(issue) => return Err(Query(issue))
    Ok(_) => ()
  }
  for contract in [self.receipt, self.record] {
    let key = @publication.publication_contract_identity(contract)
    match read("publication_contract", key) {
      Err(issue) => return Err(Query(issue))
      Ok(Some(_)) => return Err(UnresolvedOriginal)
      Ok(None) => ()
    }
  }
  match read("delivery_record_head", self.head_key) {
    Err(issue) => return Err(Query(issue))
    Ok(None) => return Err(MissingOriginal)
    Ok(Some(head)) =>
      if head.key != self.head_key ||
        head.revision != 0L ||
        head.body != self.original_head {
        return Err(ChangedOriginal)
      }
  }
  match current() {
    Err(issue) => return Err(Query(issue))
    Ok(_) => ()
  }
  try {
    let writer = @encode.writer(1048576, 64, 6)
    @encode.begin_array(writer)
    for
      (table, key, revision, body) in [
        (
          "publication_contract",
          @publication.publication_contract_identity(self.receipt),
          None,
          @publication.publication_contract_json(self.receipt),
        ),
        (
          "publication_contract",
          @publication.publication_contract_identity(self.record),
          None,
          @publication.publication_contract_json(self.record),
        ),
        (
          "delivery_record_head",
          self.head_key,
          Some(0L),
          @publication.publication_contract_json(self.record),
        ),
      ] {
      @encode.begin_object(writer)
      @encode.key(writer, "body")
      @encode.string_value(writer, body)
      @encode.key(writer, "key")
      @encode.string_value(writer, key)
      @encode.key(writer, "revision")
      match revision {
        None => @encode.null_value(writer)
        Some(revision) =>
          @encode.decimal_number_value(writer, revision.to_string())
      }
      @encode.key(writer, "table")
      @encode.string_value(writer, table)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    Ok(@encode.finish(writer))
  } catch {
    @encode.OutputLimit => Err(CapacityExceeded)
    _ => Err(EncodingFailure)
  }
}

///|
/// Validate only the actually saved successor/receipt through existing lookup
/// and success-evidence Owners. Query failure remains distinct from absence;
/// lookup grants no write retry, payload replay or execution permission.
pub fn[E] LocalSDKDeliveryTerminal::observe_for_source(
  self : LocalSDKDeliveryTerminal,
  source : LocalSDKReadSource,
  account : @authorization.AdmittedAccountConfiguration,
  finite : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  format : String,
  attempt_id : String,
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[Unit, LocalSDKDeliveryTerminalIssue[E]] {
  let saved = match
    observe_local_sdk_read_delivery_for_source(
      source, account, finite, selection, host_adoption_cid, owner, view, result_name,
      format, attempt_id, max_results, read, current,
    ) {
    Ok(saved) => saved
    Err(issue) => return Err(Observation(issue))
  }
  if @publication.publication_contract_json(saved.grant) !=
    @publication.publication_contract_json(self.first.grant) ||
    @publication.publication_contract_json(saved.attempt) !=
    @publication.publication_contract_json(self.first.attempt) {
    return Err(ChangedOriginal)
  }
  guard saved.receipt is Some(receipt) && saved.record is Some(record) else {
    return Err(UnresolvedOriginal)
  }
  if @publication.publication_contract_json(receipt) !=
    @publication.publication_contract_json(self.receipt) ||
    @publication.publication_contract_json(record) !=
    @publication.publication_contract_json(self.record) {
    return Err(ChangedOriginal)
  }
  match read("delivery_record_head", self.head_key) {
    Err(issue) => return Err(Query(issue))
    Ok(None) => return Err(MissingOriginal)
    Ok(Some(head)) =>
      if head.key != self.head_key ||
        head.revision != 1L ||
        head.body !=
        @utf8.encode(@publication.publication_contract_json(self.record)) {
        return Err(ChangedOriginal)
      }
  }
  match current() {
    Err(issue) => Err(Query(issue))
    Ok(_) => Ok(())
  }
}

///|
/// Existing live-run entry preserves its original preflight/current checks.
pub fn[E] LocalSDKPayloadEncoding::prepare_terminal_from_store(
  self : LocalSDKPayloadEncoding,
  preflight : LocalPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  finite : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  format : String,
  attempt_id : String,
  observed_at : String,
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[LocalSDKDeliveryTerminal, LocalSDKDeliveryTerminalIssue[E]] {
  self.prepare_terminal_for_source(
    live_sdk_read_source(preflight),
    account,
    finite,
    selection,
    host_adoption_cid,
    owner,
    view,
    result_name,
    format,
    attempt_id,
    observed_at,
    max_results,
    read,
    current,
  )
}

///|
/// Existing live-run entry preserves its original preflight/current checks.
pub fn[E] LocalSDKDeliveryTerminal::observe_from_store(
  self : LocalSDKDeliveryTerminal,
  preflight : LocalPublicationPreflight,
  account : @authorization.AdmittedAccountConfiguration,
  finite : @host.ClientLocalRunPolicyOriginal,
  selection : @publication.LocalSDKResultReadSelection,
  host_adoption_cid : String,
  owner : @publication.PublicationCommitPreparation,
  view : @publication.PublicationCommitReadView,
  result_name : String,
  format : String,
  attempt_id : String,
  max_results : Int,
  read : (String, String) -> Result[@host.ClientJournalPhysicalRow?, E],
  current : () -> Result[Unit, E],
) -> Result[Unit, LocalSDKDeliveryTerminalIssue[E]] {
  self.observe_for_source(
    live_sdk_read_source(preflight),
    account,
    finite,
    selection,
    host_adoption_cid,
    owner,
    view,
    result_name,
    format,
    attempt_id,
    max_results,
    read,
    current,
  )
}
