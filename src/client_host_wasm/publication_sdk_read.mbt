///|
/// Project one selected SDK read original from the nominal Run and complete
/// stored chain. The current File/Store frame and six physical reader facts
/// remain the Host's responsibility. These bytes are not a grant or Store ACK.

///|
priv enum SDKReadExport {
  Original(Int, Int)
  Evidence(Int)
  Grant(Int)
  Decision
  DeliveryStorage
  DeliveryLookup
}

///|
#export_name("actql_publication_commit_export_produce_sdk_read_original")
pub fn produce_publication_sdk_read_original(
  nonce : Int64,
  handle : Int,
  input : Int,
  run : Int,
  current_configuration : Int,
  ordinal : Int,
  field : Int,
) -> Int {
  produce_sdk_read_field(
    nonce,
    handle,
    input,
    run,
    current_configuration,
    Original(ordinal, field),
  )
}

///|
/// Original evidence packet/key for the same physical Store. This performs
/// no insert, persistence acknowledgement, usage claim or Result read.
#export_name("actql_publication_commit_export_produce_sdk_read_evidence")
pub fn produce_publication_sdk_read_evidence(
  nonce : Int64,
  handle : Int,
  input : Int,
  run : Int,
  current_configuration : Int,
  field : Int,
) -> Int {
  produce_sdk_read_field(
    nonce,
    handle,
    input,
    run,
    current_configuration,
    Evidence(field),
  )
}

///|
/// Use the existing grant issuer after the trusted Store rereads the exact
/// original evidence. This is not persistence of this grant or a delivery.
#export_name("actql_publication_commit_export_produce_sdk_read_grant")
pub fn produce_publication_sdk_read_grant(
  nonce : Int64,
  handle : Int,
  input : Int,
  run : Int,
  current_configuration : Int,
  field : Int,
) -> Int {
  produce_sdk_read_field(
    nonce,
    handle,
    input,
    run,
    current_configuration,
    Grant(field),
  )
}

///|
/// Core decides first append versus retained evidence from the same trusted
/// Store. This proposal is not COMMIT acknowledgement or unknown-write retry.
#export_name("actql_publication_commit_export_produce_sdk_read_evidence_decision")
pub fn produce_publication_sdk_read_evidence_decision(
  nonce : Int64,
  handle : Int,
  input : Int,
  run : Int,
  current_configuration : Int,
) -> Int {
  produce_sdk_read_field(
    nonce,
    handle,
    input,
    run,
    current_configuration,
    Decision,
  )
}

///|
/// Original first-delivery CAS materials only, never usage ACK or payload.
#export_name("actql_publication_commit_export_produce_sdk_read_delivery_storage")
pub fn produce_publication_sdk_read_delivery_storage(
  nonce : Int64,
  handle : Int,
  input : Int,
  run : Int,
  current_configuration : Int,
) -> Int {
  produce_sdk_read_field(
    nonce,
    handle,
    input,
    run,
    current_configuration,
    DeliveryStorage,
  )
}

///|
/// Existing read-only delivery-attempt response from original Store metadata.
#export_name("actql_publication_commit_export_produce_sdk_delivery_lookup")
pub fn produce_publication_sdk_delivery_lookup(
  nonce : Int64,
  handle : Int,
  input : Int,
  run : Int,
  current_configuration : Int,
) -> Int {
  produce_sdk_read_field(
    nonce,
    handle,
    input,
    run,
    current_configuration,
    DeliveryLookup,
  )
}

///|
fn produce_sdk_read_field(
  nonce : Int64,
  handle : Int,
  input : Int,
  run : Int,
  current_configuration : Int,
  kind : SDKReadExport,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.commit_exports.get(handle) is Some(record) &&
    value.copies.get(input) is Some((slot, physical)) else {
    return -2
  }
  let (field, projection) = match kind {
    Original(ordinal, field) => {
      if ordinal < 0 || ordinal > 2 {
        return -3
      }
      (
        field,
        PublicationCommitExportProjection::SDKReadOriginal(
          input, run, ordinal, field,
        ),
      )
    }
    Evidence(field) =>
      (
        field,
        PublicationCommitExportProjection::SDKReadEvidence(input, run, field),
      )
    Grant(field) =>
      (
        field,
        PublicationCommitExportProjection::SDKReadGrant(input, run, field),
      )
    Decision =>
      (
        0,
        PublicationCommitExportProjection::SDKReadEvidenceDecision(input, run),
      )
    DeliveryStorage =>
      (0, PublicationCommitExportProjection::SDKReadDeliveryStorage(input, run))
    DeliveryLookup =>
      (0, PublicationCommitExportProjection::SDKReadDeliveryLookup(input, run))
  }
  if field < 0 || field > 1 {
    return -3
  }
  if record.output_closed {
    return -5
  }
  let context = match
    original_sdk_read_context(value, record, run, current_configuration) {
    Ok(context) => context
    Err(code) => return code
  }
  let current = context.current
  let sdk = context.sdk
  let finite = context.finite
  let source = context.source
  let commit = context.owner
  let view = context.view
  let result_name = context.result_name
  let format = context.format
  if record.projection is Some(original) && original != projection {
    return -33
  }
  if record.produced {
    if kind is DeliveryStorage && record.sdk_delivery_first is None {
      return -41
    }
    return 0
  }
  if record.invoked || record.pending {
    return -33
  }
  record.projection = Some(projection)
  record.invoked = true
  let borrow = match
    @buffers.borrow_buffer(value.pool, slot, () => {
      physical_reader_stop(physical, handle) == 0
    }) {
    Ok(borrow) => borrow
    Err(issue) => return issue_code(issue)
  }
  // The original buffer Owner returns this loan only after output cleanup.
  // Decode, capacity and projection failures retain this exact handle.
  record.state_borrow = Some(borrow)
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, [
      "result_name", "format", "attempt_id", "observed_at",
    ])
    is Ok(object) &&
    required_text(object, "result_name") == Some(result_name) &&
    required_text(object, "format") == Some(format) &&
    required_text(object, "attempt_id") is Some(attempt_id) &&
    required_text(object, "observed_at") is Some(observed_at) else {
    return -30
  }
  let current_check = context.check_current
  let mut first_delivery : @local_run.LocalSDKReadDeliveryPreparation? = None
  let text = match kind {
    Grant(_) => {
      let grant = match
        @local_run.issue_local_sdk_read_grant_for_source(
          source,
          current.account,
          finite,
          sdk.read,
          sdk.adoption_cid,
          commit,
          view,
          result_name,
          format,
          attempt_id,
          observed_at,
          8,
          (table, key) => sdk_run_journal_port(value, current, 1, table, key),
          current_check,
        ) {
        Ok(grant) => grant
        Err(Observation(code)) => return code
        Err(MissingEvidence) => return -37
        Err(ChangedEvidence) => return -32
        Err(Preparation(Preflight(_))) => return -35
        Err(Preparation(Codec(CapacityExceeded))) => return -4
        Err(Preparation(Expired)) => return -42
        Err(_) => return -32
      }
      if field == 0 {
        @publication.publication_contract_json(grant)
      } else {
        @publication.publication_contract_identity(grant)
      }
    }
    Decision => {
      let decision = match
        @local_run.prepare_local_sdk_read_evidence_for_source(
          source,
          current.account,
          finite,
          sdk.read,
          sdk.adoption_cid,
          commit,
          view,
          result_name,
          format,
          attempt_id,
          observed_at,
          8,
          (table, key) => sdk_run_journal_port(value, current, 1, table, key),
          current_check,
        ) {
        Ok(decision) => decision
        Err(Observation(code)) => return code
        Err(Preparation(Preflight(_))) => return -35
        Err(Preparation(Codec(CapacityExceeded))) => return -4
        Err(Preparation(Expired)) => return -42
        Err(_) => return -32
      }
      match @local_run.local_sdk_read_evidence_decision_wire(decision) {
        Ok(wire) => wire
        Err(Codec(CapacityExceeded)) => return -4
        Err(_) => return -32
      }
    }
    DeliveryStorage =>
      match
        @local_run.prepare_local_sdk_read_delivery_installation_for_source(
          source,
          current.account,
          finite,
          sdk.read,
          sdk.adoption_cid,
          commit,
          view,
          result_name,
          format,
          attempt_id,
          observed_at,
          8,
          (table, key) => sdk_run_journal_port(value, current, 1, table, key),
          current_check,
        ) {
        Ok((first, wire)) => {
          first_delivery = Some(first)
          wire
        }
        Err(Observation(code)) | Err(Store(Observation(code))) => return code
        Err(Store(Preparation(Preflight(_)))) => return -35
        Err(Store(Preparation(Codec(CapacityExceeded)))) => return -4
        Err(Store(Preparation(Expired))) => return -42
        Err(ExistingAttempt) => return -33
        Err(UnresolvedUsage) => return -41
        Err(Store(MissingEvidence)) => return -37
        Err(_) => return -32
      }
    DeliveryLookup =>
      match
        @local_run.local_sdk_read_delivery_lookup_wire_for_source(
          source,
          current.account,
          finite,
          sdk.read,
          sdk.adoption_cid,
          commit,
          view,
          result_name,
          format,
          attempt_id,
          8,
          (table, key) => sdk_run_journal_port(value, current, 1, table, key),
          current_check,
        ) {
        Ok(wire) => wire
        Err(Observation(code)) | Err(Store(Observation(code))) => return code
        Err(Store(Preparation(Preflight(_)))) => return -35
        Err(Store(Preparation(Codec(CapacityExceeded)))) => return -4
        Err(MissingOriginal) => return -41
        Err(_) => return -32
      }
    Original(_, _) | Evidence(_) => {
      let originals = match
        @local_run.prepare_local_sdk_read_originals_for_source(
          source,
          current.account,
          finite,
          sdk.read,
          sdk.adoption_cid,
          commit,
          view,
          result_name,
          format,
          attempt_id,
          observed_at,
          8,
        ) {
        Ok(originals) => originals
        Err(Preflight(_)) => return -35
        Err(Codec(CapacityExceeded)) => return -4
        Err(Expired) => return -42
        Err(_) => return -32
      }
      match kind {
        Original(ordinal, _) => {
          let (body, cid) = match
            @local_run.local_sdk_read_original(originals, ordinal) {
            Ok(pair) => pair
            Err(_) => return -32
          }
          if field == 0 {
            body
          } else {
            cid
          }
        }
        Evidence(_) => {
          let (key, packet) = match
            @local_run.local_sdk_read_evidence_packet(originals) {
            Ok(pair) => pair
            Err(Codec(CapacityExceeded)) => return -4
            Err(_) => return -32
          }
          if field == 0 {
            @utf8.decode(packet) catch {
              _ => return -30
            }
          } else {
            key
          }
        }
        Grant(_) | Decision | DeliveryStorage | DeliveryLookup => return -3
      }
    }
  }
  record.pending = true
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(text)),
  )
  record.pending = false
  if result == 0 {
    // Keep the actual first-issuance value under this original output/input
    // custody. Saved/Copied response bytes are not its constructor or permit.
    record.sdk_delivery_first = first_delivery
    record.produced = true
  }
  result
}
