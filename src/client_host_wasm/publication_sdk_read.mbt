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
    value.publications.get(record.publication) is Some(parent) &&
    value.runs.get(run) is Some(original_run) &&
    original_run.finite_policy is Some(finite) &&
    value.run_configurations.get(original_run.configuration)
    is Some(original_configuration) &&
    original_configuration.sdk is Some(sdk) &&
    value.run_configurations.get(current_configuration) is Some(current) &&
    current.sdk is Some(current_sdk) &&
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
  }
  if field < 0 || field > 1 {
    return -3
  }
  if record.closing ||
    record.output_closed ||
    parent.observation_closing ||
    parent.lookup_closing {
    return -5
  }
  // Current metadata never replaces the original selection or finite packet.
  // Its adoption and Store must still be those of this original Run.
  if current_sdk.adoption_cid != sdk.adoption_cid ||
    current_sdk.store_authority_cid != sdk.store_authority_cid ||
    @publication.local_sdk_result_read_selection_cid(current_sdk.read) !=
    @publication.local_sdk_result_read_selection_cid(sdk.read) {
    return -32
  }
  let code = validate_publication_run(
    nonce,
    record.publication,
    run,
    current_configuration,
  )
  if code != 0 {
    return code
  }
  let (commit, view) = match
    publication_commit_export_view(value, parent, current.account) {
    Ok(original) => original
    Err(code) => return code
  }
  guard value.publication_preflights.get(parent.preflight)
    is Some({ closing: false, preflight: Some(preflight), .. }) &&
    parent.observation_checked &&
    !parent.observation_failed &&
    parent.observation_index is Some(index) &&
    parent.observation_publisher is Some(publisher) else {
    return -32
  }
  let (principal, connection, _, result_name, format, _, _) = @publication.local_sdk_result_read_selection_parameters(
    sdk.read,
  )
  if principal != current.tuple.principal ||
    connection != current.tuple.connection {
    return -32
  }
  if @local_run.validate_local_preflight_result_read_current(
      preflight,
      current.account,
      result_name,
    )
    is Err(_) {
    return -35
  }
  let auth = publication_observation_publisher(
    value,
    parent,
    publisher,
    current_configuration,
    Some(index),
  )
  if auth != 0 {
    return auth
  }
  // The callback may change current authority. Cached returns have the same
  // current/independent read gates as new output; no prior Allow is reused.
  match run_configuration_current(value, current) {
    Err(code) => return code
    Ok(_) => ()
  }
  if @local_run.validate_local_preflight_result_read_current(
      preflight,
      current.account,
      result_name,
    )
    is Err(_) {
    return -35
  }
  if record.projection is Some(original) && original != projection {
    return -33
  }
  if record.produced {
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
  let current_check = () => {
    match run_configuration_current(value, current) {
      Err(code) => return Err(code)
      Ok(_) => ()
    }
    let auth = publication_observation_publisher(
      value,
      parent,
      publisher,
      current_configuration,
      Some(index),
    )
    if auth != 0 {
      return Err(auth)
    }
    run_configuration_current(value, current)
  }
  let text = match kind {
    Grant(_) => {
      let grant = match
        @local_run.issue_local_sdk_read_grant_from_store(
          preflight,
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
        @local_run.prepare_local_sdk_read_evidence_from_store(
          preflight,
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
        @local_run.prepare_local_sdk_read_delivery_storage_from_store(
          preflight,
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
        Ok(wire) => wire
        Err(Observation(code)) | Err(Store(Observation(code))) => return code
        Err(Store(Preparation(Preflight(_)))) => return -35
        Err(Store(Preparation(Codec(CapacityExceeded)))) => return -4
        Err(Store(Preparation(Expired))) => return -42
        Err(ExistingAttempt) => return -33
        Err(UnresolvedUsage) => return -41
        Err(Store(MissingEvidence)) => return -37
        Err(_) => return -32
      }
    Original(_, _) | Evidence(_) => {
      let originals = match
        @local_run.prepare_local_sdk_read_originals(
          preflight,
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
        Grant(_) | Decision | DeliveryStorage => return -3
      }
    }
  }
  record.pending = true
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(text)),
  )
  record.pending = false
  if result == 0 {
    record.produced = true
  }
  result
}
