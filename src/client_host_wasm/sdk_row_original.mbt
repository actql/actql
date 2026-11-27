///|
// One pure validator result under the existing Run. It is never an inventory,
// Account/current observation, authorization, publication or physical-start ACK.
priv struct StoredSDKRunRowOriginal {
  key : String
  revision : Int64
  retention : Int64
  decoded : @host.ClientRunJournalRowOriginal
}

///|
// Charge the retained row/text/tuple and the existing bounded parser/encoder
// scratch before constructing the result. These are the decoder's selected
// limits, not new admission limits or a new Ledger/profile.
fn sdk_row_original_capacity(bytes : Int) -> (Int64, Int64)? {
  if bytes < 1 || bytes > 131072 {
    return None
  }
  let retained : @execution.PreparationRepresentationUnits = {
    record_headers: 64L,
    reference_slots: 128L,
    scalar_words: 64L,
    owned_utf16_units: 2L * bytes.to_int64() + 4096L + 65536L,
    owned_wire_bytes: bytes.to_int64(),
  }
  guard @decode.preserving_json_admission_construction_inventory(
      131072, 8192, 64,
    )
    is Some(parser) &&
    @encode.text_writer_construction_inventory(131072, 8192, 64) is Some(writer) else {
    return None
  }
  // Full miss: outer row, two saved compiler evidence values, bounded policy
  // and identity decoders. Accepted nested text is contained in this row.
  let scratch : @execution.PreparationRepresentationUnits = {
    record_headers: 6L * parser.record_headers + 6L * writer.record_headers,
    reference_slots: 6L * parser.reference_slots + 6L * writer.reference_slots,
    scalar_words: 6L * parser.scalar_words + 6L * writer.scalar_words,
    owned_utf16_units: 6L * parser.owned_utf16_units +
    6L * writer.owned_utf16_units,
    owned_wire_bytes: 6L * 131072L,
  }
  guard @execution.preparation_representation_cost(retained) is Some(retention) &&
    @execution.compose_preparation_representation([retained, scratch])
    is Some(total) &&
    @execution.preparation_representation_cost(total) is Some(execution) else {
    return None
  }
  Some((retention, execution))
}

///|
fn dispose_sdk_run_row_original(value : Instance, record : StoredRun) -> Int {
  record.sdk_row_original = None
  match record.sdk_row_capacity {
    None => 0
    Some(capacity) =>
      match @resources.settle_capacity(value.root, capacity) {
        Err(_) => -4
        Ok(_) => {
          record.sdk_row_capacity = None
          0
        }
      }
  }
}

///|
fn sdk_run_row_original(
  value : Instance,
  run : Int,
  row : @host.ClientJournalPhysicalRow,
) -> Result[@host.ClientRunJournalEncoding, Int] {
  guard value.runs.get(run) is Some(record) && record.outcome is Some(Ok(plan)) else {
    return Err(-2)
  }
  sdk_run_row_original_with_identity(
    value,
    record,
    @local_run.local_run_request(plan),
    @local_run.local_run_definition(plan),
    row,
  )
}

///|
fn sdk_run_row_original_with_identity(
  value : Instance,
  record : StoredRun,
  request : @host.ClientRequestIdentity,
  definition : @publication.PublicationContract,
  row : @host.ClientJournalPhysicalRow,
) -> Result[@host.ClientRunJournalEncoding, Int] {
  if row.key != @host.client_request_scope_cid(request) {
    // Every foreign inventory row keeps the original complete validator.
    return submission_run_row_original_with_identity(row, None)
  }
  if record.sdk_row_original is Some(original) &&
    original.key == row.key &&
    original.revision == row.revision &&
    @host.client_run_journal_row_original_matches(original.decoded, row.body) {
    guard record.sdk_row_capacity is Some(capacity) &&
      @resources.capacity_reservation_covers(
        value.root,
        capacity,
        original.retention,
        0L,
      ) else {
      return Err(-4)
    }
    return @host.decode_client_run_journal_row_with_observation_originals(
        row.body,
        original=Some(original.decoded),
      )
      .map(value => value.0)
      .map_err(_ => -31)
  }
  // Synchronous pure disposal. No other invocation can borrow this cell across
  // a guest call; physical work and current observations are never stored here.
  let disposed = dispose_sdk_run_row_original(value, record)
  if disposed != 0 {
    return Err(disposed)
  }
  guard sdk_row_original_capacity(row.body.length())
    is Some((retention, execution)) else {
    return Err(-31)
  }
  let capacity = match
    @resources.reserve_capacity(value.root, retention, execution) {
    Err(_) => return Err(-4)
    Ok(value) => value
  }
  // Keep the same token reachable even if a constructor traps or refuses.
  record.sdk_row_capacity = Some(capacity)
  let decoded = match
    @host.retain_client_run_journal_row_original(row.body, request, definition) {
    Ok(value) => value
    Err(_) => return Err(-31)
  }
  let encoding = match
    validate_sdk_run_row_decoded(
      @host.decode_client_run_journal_row_with_observation_originals(
        row.body,
        original=Some(decoded),
      ),
    ) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  // Do not promote another Run's valid pure codec result to this original.
  if @host.client_request_identity_relation(request, encoding.request) !=
    @host.SameRequest ||
    @publication.publication_contract_identity(encoding.definition) !=
    @publication.publication_contract_identity(definition) {
    return Err(-31)
  }
  // Temporary validation workspace has returned before publishing this pure
  // result. A failed shrink leaves only the original reachable reservation.
  match
    @resources.shrink_capacity_reservation(value.root, capacity, retention, 0L) {
    Err(_) => Err(-4)
    Ok(_) => {
      record.sdk_row_original = Some({
        key: row.key,
        revision: row.revision,
        retention,
        decoded,
      })
      Ok(encoding)
    }
  }
}

///|
fn sdk_run_row_inspection(
  value : Instance,
  run : Int,
  row : @host.ClientJournalPhysicalRow,
) -> Result[@host.ClientRunJournalInspection, Int] {
  sdk_run_row_original(value, run, row).map(record => {
    request: record.request,
    definition: record.definition,
    checkpoint: None,
    cancellation_head: record.cancellation_head,
    task_materials_cid: record.task_materials_cid,
  })
}

///|
fn sdk_run_row_codec_original(
  value : Instance,
  run : Int,
) -> @host.ClientRunJournalRowOriginal? {
  value.runs
  .get(run)
  .bind(record => record.sdk_row_original.map(original => original.decoded))
}
