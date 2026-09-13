///|
// Fixed public-checker conformance setup, not a product Host entry.
struct IssuedNativeFixture {
  issuer : @planning.DuckDBNativeIssuer
  attempt : @planning.DuckDBNativeAttempt
  scan : @duckdb.NativeScan
  requirement : @planning.QueryRequirement
  mut port : @duckdb.NativeReceiptPort?
  mut observation : @planning.DuckDBNativeObservation?
}

///|
#export_name("issuedNativeCreate")
pub fn issued_native_create(
  environment_json : String,
  environment_cid : String,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  query_json : String,
  evidence_json : String,
  two_receipt_json : String,
  output_rows : Int,
  verify : (@planning.DuckDBNativeAttempt) -> Bool,
) -> IssuedNativeFixture {
  try {
    let (preparation, _) = issued_fixture_preparation(
      environment_json, environment_cid, registry_json, values_json, fragment_json,
      output_rows,
    )
    let requirement = @planning.duckdb_query_requirement(preparation)
    let registry = @planning.prepare_capability_registry(
      [{ name: "duckdb", acquisition: true, fixed_compute: true, }],
      1,
      6,
    ).unwrap()
    let candidate = @planning.duckdb_native_candidate(
      @planning.capability_registration_at(registry, 0).unwrap(),
      preparation,
      [
        {
          work_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
          milliseconds: Some(10L),
        },
      ],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      100,
    ).unwrap()
    guard @planning.choose_acquisition_candidate(
        registry,
        requirement,
        [@planning.prepared_acquisition_candidate(candidate)],
        None,
        100,
      ).unwrap()
      is Proposed(choice) else {
      abort("native fixture choice")
    }
    let dependencies = @planning.admit_query_evidence_contracts(
      fixture_contract(query_json),
      fixture_contract(evidence_json),
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    ).unwrap()
    let contract = @planning.admit_query_two_receipt_contract(
      dependencies,
      fixture_contract(two_receipt_json),
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    ).unwrap()
    let issuer = @planning.prepare_duckdb_native_issuer(
      contract, requirement, "real-node-native-fixture", 100, verify,
    ).unwrap()
    let attempt = @planning.prepare_issued_duckdb_native_attempt(
      issuer,
      choice,
      candidate,
      {
        max_rows: 100,
        max_cells: 1000,
        max_nodes: 1000,
        max_text_bytes: 10000,
      },
      10000,
      issued_native_measure_limits(),
    ).unwrap()
    {
      issuer,
      attempt,
      requirement,
      scan: @planning.duckdb_native_preparation_scan(
        @planning.duckdb_native_attempt_preparation(attempt),
      ),
      port: None,
      observation: None,
    }
  } catch {
    _ => abort("fixed checked native setup")
  }
}

///|
fn issued_native_measure_limits() -> @execution.FixedInputGuardMeasureLimits {
  { max_work: 100000, max_bytes: 100000, max_nodes: 10000, max_depth: 100, }
}

///|
#export_name("issuedNativeAttempt")
pub fn issued_native_attempt(
  value : IssuedNativeFixture,
) -> @planning.DuckDBNativeAttempt {
  value.attempt
}

///|
#export_name("issuedNativeSql")
pub fn issued_native_sql(value : IssuedNativeFixture, kind : Int) -> String {
  match kind {
    0 => @duckdb.native_scan_metadata_sql(value.scan)
    1 => @duckdb.native_scan_sql(value.scan)
    _ => @duckdb.native_query_sql(@duckdb.native_scan_query(value.scan))
  }
}

///|
#export_name("issuedNativeParameter")
pub fn issued_native_parameter(
  value : IssuedNativeFixture,
  index : Int,
) -> String {
  try {
    let parameter = if index < 2 {
      @duckdb.native_scan_metadata_parameter(value.scan, index).unwrap()
    } else {
      @duckdb.native_query_parameter(@duckdb.native_scan_query(value.scan))
    }
    let writer = @encode.writer(1000, 100, 10)
    @duckdb.emit_physical_parameter(parameter, writer)
    @encode.finish(writer)
  } catch {
    _ => abort("fixed native parameter")
  }
}

///|
#export_name("issuedNativeMetadata")
pub fn issued_native_metadata(
  value : IssuedNativeFixture,
  rows : Int,
  names : String,
  data : String,
) -> Bool {
  @planning.admit_duckdb_native_metadata(
    value.attempt,
    rows,
    fields(names),
    columns(data),
  )
  is Ok(_)
}

///|
#export_name("issuedNativeBegin")
pub fn issued_native_begin(
  value : IssuedNativeFixture,
  native : Bool,
  names : String,
) -> Bool {
  let role : @duckdb.NativeReceiptRole = if native {
    NativeResult
  } else {
    ValidationScan
  }
  match
    @planning.begin_duckdb_native_receipt(value.attempt, role, fields(names)) {
    Ok(port) => {
      value.port = Some(port)
      true
    }
    Err(_) => false
  }
}

///|
#export_name("issuedNativeAccept")
pub fn issued_native_accept(
  value : IssuedNativeFixture,
  rows : Int,
  data : String,
) -> Bool {
  guard value.port is Some(port) else { return false }
  @planning.accept_duckdb_native_chunk(value.attempt, port, rows, columns(data))
  is Ok(_)
}

///|
#export_name("issuedNativeFinish")
pub fn issued_native_finish(value : IssuedNativeFixture) -> Bool {
  guard value.port is Some(port) else { return false }
  value.port = None
  @planning.finish_duckdb_native_receipt(value.attempt, port) is Ok(_)
}

///|
#export_name("issuedNativeComplete")
pub fn issued_native_complete(
  value : IssuedNativeFixture,
  artifact_bytes : Int,
) -> Bool {
  guard @planning.complete_duckdb_native_capture(value.issuer, value.attempt, {
      demand: issued_native_measure_limits(),
      receipts: {
        max_columns: 10,
        max_order_work: 10000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
      max_received_rows: 100,
      max_received_bytes: 100000,
      max_retained_wire_bytes: 100000,
      records: {
        max_work: 1000000,
        max_fields: 100,
        max_parameters: 100,
        max_bytes: 1000000,
        max_nodes: 100000,
        max_depth: 100,
      },
      capture: { max_bytes: artifact_bytes, max_nodes: 100000, max_depth: 100, },
    })
    is Ok(observation) else {
    return false
  }
  value.observation = Some(observation)
  true
}

///|
#export_name("issuedNativeObservation")
pub fn issued_native_observation(
  value : IssuedNativeFixture,
) -> @planning.DuckDBNativeObservation {
  value.observation.unwrap()
}

///|
#export_name("issuedNativeDocument")
pub fn issued_native_document(value : IssuedNativeFixture) -> String {
  match value.observation {
    Some(observation) =>
      @encode.document_text(
        @planning.duckdb_native_observation_document(observation),
      )
    None => "null"
  }
}

///|
#export_name("issuedNativeVerify")
pub fn issued_native_verify(value : IssuedNativeFixture) -> Bool {
  guard value.observation is Some(observation) else { return false }
  @planning.verify_duckdb_native_observation(
    value.issuer,
    value.attempt,
    observation,
  )
  is Ok(_)
}

///|
#export_name("issuedNativeAbort")
pub fn issued_native_abort(value : IssuedNativeFixture) -> Unit {
  @planning.abort_duckdb_native_attempt(value.attempt)
}

///|
#export_name("issuedNativeClose")
pub fn issued_native_close(value : IssuedNativeFixture) -> Unit {
  @planning.close_duckdb_native_issuer(value.issuer)
}

///|
#export_name("issuedNativeRequirement")
pub fn issued_native_requirement(value : IssuedNativeFixture) -> String {
  @encode.document_text(@planning.query_requirement_document(value.requirement))
}

///|
#export_name("issuedNativeIds")
pub fn issued_native_ids(value : IssuedNativeFixture) -> String {
  let (issuer, attempt, view) = @planning.duckdb_native_attempt_identity(
    value.attempt,
  ).unwrap()
  [issuer, attempt, view].to_json().stringify()
}
