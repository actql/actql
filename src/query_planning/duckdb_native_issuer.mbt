///|
/// Host-local two-receipt authority. The trusted transport verifier must bind
/// both actual SQL receipts to this exact attempt and one settled read view.
struct DuckDBNativeIssuer {
  _contract : QueryTwoReceiptContract
  requirement : QueryRequirement
  name : String
  attempts : IssuerCounter
  mut live : Bool
  mut transport_matches : (DuckDBNativeAttempt) -> Bool
}

///|
let duckdb_native_issuer_serial : IssuerCounter = { next: 0, }

///|
priv struct DuckDBNativeAuthority {
  issuer : DuckDBNativeIssuer
  number : String
  // Host-local discriminator, not a snapshot/content CID. The transport bridge
  // binds the one actual transaction to this preallocated attempt-owned name.
  read_view : String
}

///|
struct DuckDBNativeRecords {
  authority : DuckDBNativeAuthority
  measurement : DuckDBNativeMeasurement
  scope : String
  receipt_documents : Array[@encode.EncodedDocument]
  receipt_cids : Array[String]
  documents : Array[@encode.EncodedDocument]
  cids : Array[String]
  bytes : Int
  nodes : Int
}

///|
pub fn prepare_duckdb_native_issuer(
  contract : QueryTwoReceiptContract,
  requirement : QueryRequirement,
  process_nonce : String,
  max_nonce_chars : Int,
  transport_matches : (DuckDBNativeAttempt) -> Bool,
) -> Result[DuckDBNativeIssuer, DuckDBEvidenceIssue] {
  if max_nonce_chars < 0 {
    return Err(InvalidLimits)
  }
  if process_nonce.is_empty() || process_nonce.length() > max_nonce_chars {
    return Err(IdentifierLimit)
  }
  guard reserve_issuer_number(duckdb_native_issuer_serial) is Some(serial) else {
    return Err(IdentifierExhausted)
  }
  Ok({
    _contract: contract,
    requirement,
    name: process_nonce + "/duckdb-native-issuer/" + serial.to_string(),
    attempts: { next: 0, },
    live: true,
    transport_matches,
  })
}

///|
pub fn prepare_issued_duckdb_native_attempt(
  issuer : DuckDBNativeIssuer,
  choice : AcquisitionChoice,
  candidate : PreparedAcquisition[DuckDBNativePreparation],
  physical : @duckdb.PhysicalResultLimits,
  max_metadata_work : Int,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[DuckDBNativeAttempt, DuckDBEvidenceIssue] {
  if !issuer.live {
    return Err(IssuerClosed)
  }
  guard acquisition_choice_payload(choice, candidate) is Some(preparation) else {
    return Err(NotSelected)
  }
  if !physical_equal(issuer.requirement, preparation.requirement) {
    return Err(UnauthorizedAttempt)
  }
  let attempt = match
    prepare_duckdb_native_attempt(
      choice, candidate, physical, max_metadata_work, measurement,
    ) {
    Ok(value) => value
    Err(issue) => return Err(NativeAttempt(issue))
  }
  guard reserve_issuer_number(issuer.attempts) is Some(serial) else {
    abort_duckdb_native_attempt(attempt)
    return Err(IdentifierExhausted)
  }
  let number = serial.to_string()
  Ok({
    ..attempt,
    authority: Some({
      issuer,
      number,
      read_view: issuer.name + "/attempt/" + number + "/read-view/0",
    }),
  })
}

///|
pub fn close_duckdb_native_issuer(issuer : DuckDBNativeIssuer) -> Unit {
  issuer.live = false
  issuer.transport_matches = _ => false
}

///|
pub fn duckdb_native_attempt_identity(
  attempt : DuckDBNativeAttempt,
) -> (String, String, String)? {
  attempt.authority.map(value => {
    (value.issuer.name, value.number, value.read_view)
  })
}

///|
pub fn issue_duckdb_native_records(
  attempt : DuckDBNativeAttempt,
  max_retained_wire_bytes : Int,
  limits : QueryMaterialLimits,
) -> Result[DuckDBNativeRecords, DuckDBEvidenceIssue] {
  guard attempt.authority is Some(authority) else {
    return Err(UnauthorizedAttempt)
  }
  if !authority.issuer.live {
    return Err(IssuerClosed)
  }
  guard attempt.state is Measured(measurement) else { return Err(NotRetained) }
  if !physical_equal(
      authority.issuer.requirement,
      attempt.preparation.requirement,
    ) ||
    !duckdb_native_measurement_matches(measurement, attempt) {
    abort_duckdb_native_attempt(attempt)
    return Err(UnauthorizedAttempt)
  }
  if !(authority.issuer.transport_matches)(attempt) {
    abort_duckdb_native_attempt(attempt)
    return Err(UnverifiedTransport)
  }
  if max_retained_wire_bytes < 0 ||
    limits.max_work < 0 ||
    limits.max_fields < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let (_, scan_bytes, _, _) = @duckdb.native_receipt_digest(
    measurement.receipts,
    @duckdb.ValidationScan,
  )
  let (_, output_bytes, _, _) = @duckdb.native_receipt_digest(
    measurement.receipts,
    @duckdb.NativeResult,
  )
  // Both immutable receipt sets are retained. No output copy is constructed or
  // charged here; future materialization must account for its own capacity.
  if scan_bytes > max_retained_wire_bytes ||
    output_bytes > max_retained_wire_bytes - scan_bytes {
    abort_duckdb_native_attempt(attempt)
    return Err(Encoding(@encode.OutputLimit))
  }
  match build_native_records(authority, measurement, limits) {
    Ok(records) => {
      attempt.state = EvidenceIssued(records)
      Ok(records)
    }
    Err(issue) => {
      abort_duckdb_native_attempt(attempt)
      Err(issue)
    }
  }
}

///|
pub fn verify_duckdb_native_records(
  issuer : DuckDBNativeIssuer,
  attempt : DuckDBNativeAttempt,
  records : DuckDBNativeRecords,
) -> Result[Unit, DuckDBEvidenceIssue] {
  if !issuer.live {
    return Err(IssuerClosed)
  }
  guard attempt.authority is Some(authority) &&
    physical_equal(authority.issuer, issuer) &&
    physical_equal(records.authority, authority) else {
    return Err(UnauthorizedAttempt)
  }
  let issued = match attempt.state {
    EvidenceIssued(value) => value
    Captured(value) => value.records
    _ => return Err(ForeignRecords)
  }
  if !physical_equal(issued, records) ||
    !physical_equal(issuer.requirement, attempt.preparation.requirement) ||
    !duckdb_native_measurement_matches(records.measurement, attempt) {
    return Err(ForeignRecords)
  }
  if !(issuer.transport_matches)(attempt) {
    return Err(UnverifiedTransport)
  }
  Ok(())
}

///|
pub fn duckdb_native_record_at(
  records : DuckDBNativeRecords,
  index : Int,
) -> (@encode.EncodedDocument, String)? {
  guard records.documents.get(index) is Some(document) &&
    records.cids.get(index) is Some(cid) else {
    return None
  }
  Some((document, cid))
}

///|
pub fn duckdb_native_receipt_at(
  records : DuckDBNativeRecords,
  index : Int,
) -> (@encode.EncodedDocument, String)? {
  guard records.receipt_documents.get(index) is Some(document) &&
    records.receipt_cids.get(index) is Some(cid) else {
    return None
  }
  Some((document, cid))
}
