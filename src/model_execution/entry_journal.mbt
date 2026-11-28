///|
pub(all) enum ModelCallEntryJournalIssue {
  ForeignOriginal
  Limit
  Encoding
}

///|
/// Bound the existing durable Call Entry body before allocating a writer.
/// Callers fund the writer and UTF-8 output together in their original Read.
pub fn model_call_entry_journal_bound(
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  call : @publication.RunEvidenceValue,
  attempt : @publication.RunEvidenceValue,
  authority : @publication.RunEvidenceValue,
  maximum : Int64,
) -> Int? {
  // Fixed syntax and the longest slot spelling. Every escaped UTF-16 unit
  // of a borrowed field occupies at most six bytes in the existing writer.
  let fixed = "{\"attempt\":\"\",\"authority\":\"\",\"call\":\"\",\"request_scope_cid\":\"\",\"run_definition_cid\":\"\",\"slot\":2147483647,\"version\":\"actql-native-model-call-original/0.1\"}"
    .length()
    .to_int64()
  let units = @publication.run_evidence_value_json(call).length().to_int64() +
    @publication.run_evidence_value_json(attempt).length().to_int64() +
    @publication.run_evidence_value_json(authority).length().to_int64() +
    @publication_host.client_request_scope_cid(request).length().to_int64() +
    @publication.publication_contract_identity(definition).length().to_int64()
  guard @relation.checked_preparation_add_product(fixed, units, 6L)
    is Some(bound) &&
    bound > 0L &&
    bound < 2147483519L &&
    bound <= maximum else {
    return None
  }
  Some(bound.to_int())
}

///|
/// Emit journal data from borrowed original evidence. The Host owns the
/// current Run and original transaction. Encoding does not acknowledge it.
pub fn encode_model_call_entry_journal(
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  slot : Int,
  call : @publication.RunEvidenceValue,
  attempt : @publication.RunEvidenceValue,
  authority : @publication.RunEvidenceValue,
  maximum : Int,
) -> Result[Bytes, ModelCallEntryJournalIssue] {
  try {
    let writer = @encode.writer(maximum, 16, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "attempt")
    @encode.string_value(writer, @publication.run_evidence_value_json(attempt))
    @encode.key(writer, "authority")
    @encode.string_value(
      writer,
      @publication.run_evidence_value_json(authority),
    )
    @encode.key(writer, "call")
    @encode.string_value(writer, @publication.run_evidence_value_json(call))
    @encode.key(writer, "request_scope_cid")
    @encode.string_value(
      writer,
      @publication_host.client_request_scope_cid(request),
    )
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(
      writer,
      @publication.publication_contract_identity(definition),
    )
    @encode.key(writer, "slot")
    @encode.number_value(writer, slot.to_double())
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-native-model-call-original/0.1")
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(Limit)
    _ => Err(Encoding)
  }
}

///|
/// Same pending Entry and its already funded canonical journal bytes.
/// This does not represent a write, saved acknowledgement or send permit.
pub struct ModelCallEntryJournalProjection {
  priv entry : ModelCallEntry
  body : Bytes
}

///|
/// Construct the body from the original Entry, never from a separately
/// supplied slot or evidence packet. The caller retains the original Run
/// request and funds the writer and projection for its full borrowed life.
pub fn project_model_call_entry_journal(
  entry : ModelCallEntry,
  prepared : ModelPreparedCallSet,
  admission : @publication_host.ClientInferDispatchAdmission,
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  maximum : Int,
) -> Result[ModelCallEntryJournalProjection, ModelCallEntryJournalIssue] {
  guard model_call_entry_persistence_owned(entry, prepared) &&
    physical_equal(entry.admission, admission) &&
    prepared.scope is Some(_) &&
    !entry.send_started &&
    @publication_host.client_infer_dispatch_run_cid(admission) ==
    @publication.publication_contract_identity(definition) else {
    return Err(ForeignOriginal)
  }
  match
    encode_model_call_entry_journal(
      request,
      definition,
      entry.slot,
      entry.trace.call,
      entry.trace.attempt,
      entry.trace.authority,
      maximum,
    ) {
    Ok(body) => Ok({ entry, body, })
    Err(issue) => Err(issue)
  }
}

///|
/// Check the physical row while the Host still owns its original Store
/// observation. The Host can acknowledge the Entry only after the read
/// closes successfully. This never acknowledges or starts transport.
pub fn model_call_entry_journal_matches_saved(
  projection : ModelCallEntryJournalProjection,
  entry : ModelCallEntry,
  prepared : ModelPreparedCallSet,
  row : @publication_host.ClientJournalPhysicalRow,
) -> Bool {
  physical_equal(projection.entry, entry) &&
  model_call_entry_persistence_owned(entry, prepared) &&
  !entry.send_started &&
  row.revision == 0L &&
  row.key == @publication.run_evidence_value_identity(entry.trace.attempt) &&
  row.body == projection.body
}

///|
/// Encode the existing local settlement index from already admitted leaves.
/// Callers keep authentication and Store confirmation on their original Read.
pub fn encode_model_call_settlement_journal(
  request : @publication_host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  slot : Int,
  scope_cid : String,
  slot_cid : String,
  attempt_cid : String,
  authority : String,
  binding : String,
  entry_digest : String,
  leaves : Array[@publication.RunEvidenceValue],
  maximum : Int,
) -> Result[Bytes, ModelCallEntryJournalIssue] {
  try {
    let writer = @encode.writer(maximum, 48, 4)
    @encode.begin_object(writer)
    @encode.key(writer, "attempt_cid")
    @encode.string_value(writer, attempt_cid)
    @encode.key(writer, "entry_digest")
    @encode.string_value(writer, entry_digest)
    @encode.key(writer, "request_scope_cid")
    @encode.string_value(
      writer,
      @publication_host.client_request_scope_cid(request),
    )
    @encode.key(writer, "run_definition_cid")
    @encode.string_value(
      writer,
      @publication.publication_contract_identity(definition),
    )
    @encode.key(writer, "scope_cid")
    @encode.string_value(writer, scope_cid)
    @encode.key(writer, "store_binding")
    @encode.string_value(writer, binding)
    @encode.key(writer, "version")
    @encode.string_value(
      writer, "actql-native-model-call-settlement-original/0.1",
    )
    @encode.key(writer, "slot")
    @encode.number_value(writer, slot.to_double())
    @encode.key(writer, "evidence")
    @encode.begin_array(writer)
    for original in leaves {
      let role = @publication.run_evidence_value_name(original)
      guard @publication.model_scoped_private_holding_cid(
          definition, authority, scope_cid, slot_cid, attempt_cid, 1, "settled",
          role,
        )
        is Some(holding) else {
        return Err(ForeignOriginal)
      }
      @encode.begin_object(writer)
      @encode.key(writer, "cid")
      @encode.string_value(
        writer,
        @publication.run_evidence_value_identity(original),
      )
      @encode.key(writer, "holding_cid")
      @encode.string_value(writer, holding)
      @encode.key(writer, "role")
      @encode.string_value(writer, role)
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    @encode.OutputLimit => Err(Limit)
    _ => Err(Encoding)
  }
}
