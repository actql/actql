///|
/// Conformance setup only. Actual capture stays opaque in the same process;
/// the transport asks the shared adapter for one parameter at a time.
struct OwnedFixedFixture {
  compute : @duckdb.FixedCompute
  local_binding : @planning.PreparedCompute[@execution.GeneratedSequence]
  local_choice : @planning.FixedComputeChoice
  mut receiving : @duckdb.FixedComputeReceiving?
  mut receipt : @duckdb.FixedComputeReceipt?
}

///|
#export_name("ownedFixedCreate")
pub fn owned_fixed_create(
  producer : IssuedNativeFixture,
  output : @execution.CompletedOutput,
  registry_json : String,
  values_json : String,
  fragment_json : String,
) -> OwnedFixedFixture {
  try {
    let owner = @duckdb.native_query_owner(
      @duckdb.native_scan_query(producer.scan),
    )
    let receiver = issued_fixture_consumer(
      owner,
      steps="[{\"filter\":\"id > 2\"},{\"select\":[\"id\"]}]",
    )
    let bound = @execution.bind_completed_input(receiver, 0, owner, output).unwrap()
    let read = @execution.prepare_producer_read(receiver, bound, 100, 10000).unwrap()
    let request = @planning.prepare_fixed_compute_request(read, {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 10000,
      common_fragment: None,
    }).unwrap()
    let registry = @planning.prepare_capability_registry(
      [
        { name: "local", acquisition: false, fixed_compute: true, },
        { name: "duckdb", acquisition: true, fixed_compute: true, },
      ],
      2,
      11,
    ).unwrap()
    let quantities : @planning.QueryQuantities = {
      transfer_bytes: None,
      retained_bytes: None,
      money_units: None,
    }
    let local_binding = @planning.local_fixed_compute_candidate(
      @planning.capability_registration_at(registry, 0).unwrap(),
      request,
      fixture_generated(
        receiver, registry_json, values_json, fragment_json, true,
      ),
      [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(20L), }],
      quantities,
      100,
    ).unwrap()
    let native = @planning.duckdb_fixed_compute_candidate(
      @planning.capability_registration_at(registry, 1).unwrap(),
      request,
      "owned_input",
      {
        max_entries: 100,
        max_sql_bytes: 10000,
        expressions: {
          max_nodes: 1000,
          max_work: 10000,
          max_depth: 100,
          max_literal_nodes: 1000,
          max_literal_text_bytes: 10000,
        },
      },
      [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(10L), }],
      quantities,
      100,
    ).unwrap()
    guard @planning.choose_fixed_compute_candidate(
        registry,
        request,
        [
          @planning.prepared_compute_candidate(local_binding),
          @planning.prepared_compute_candidate(native),
        ],
        None,
        100,
      ).unwrap()
      is Proposed(choice) else {
      abort("fixed candidate choice")
    }
    guard @planning.choose_fixed_compute_candidate(
        registry,
        request,
        [@planning.prepared_compute_candidate(local_binding)],
        None,
        100,
      ).unwrap()
      is Proposed(local_choice) else {
      abort("local reference choice")
    }
    {
      compute: @planning.fixed_compute_choice_payload(choice, native).unwrap(),
      local_binding,
      local_choice,
      receiving: None,
      receipt: None,
    }
  } catch {
    _ => abort("owned fixed conformance setup")
  }
}

///|
#export_name("ownedFixedRowCount")
pub fn owned_fixed_row_count(value : OwnedFixedFixture) -> Int {
  @execution.producer_read_row_count(
    @duckdb.fixed_import_input(@duckdb.fixed_compute_import(value.compute)),
  )
}

///|
#export_name("ownedFixedColumnCount")
pub fn owned_fixed_column_count(value : OwnedFixedFixture) -> Int {
  @duckdb.fixed_import_column_count(@duckdb.fixed_compute_import(value.compute))
}

///|
#export_name("ownedFixedSql")
pub fn owned_fixed_sql(value : OwnedFixedFixture, kind : Int) -> String {
  let imported = @duckdb.fixed_compute_import(value.compute)
  match kind {
    0 => @duckdb.fixed_import_create_sql(imported)
    1 => @duckdb.fixed_import_insert_sql(imported)
    2 => @duckdb.native_query_sql(@duckdb.fixed_compute_query(value.compute))
    _ => abort("fixed command selector")
  }
}

///|
#export_name("ownedFixedParameter")
pub fn owned_fixed_parameter(
  value : OwnedFixedFixture,
  row : Int,
  column : Int,
  predicate : Bool,
) -> String {
  let parameter = if predicate {
    @duckdb.native_query_parameter(@duckdb.fixed_compute_query(value.compute))
  } else {
    match
      @duckdb.fixed_import_parameter(
        @duckdb.fixed_compute_import(value.compute),
        row,
        column,
      ) {
      Ok(value) => value
      Err(_) => return "null"
    }
  }
  try {
    let writer = @encode.writer(10000, 100, 10)
    @duckdb.emit_physical_parameter(parameter, writer)
    @encode.finish(writer)
  } catch {
    _ => "null"
  }
}

///|
#export_name("ownedFixedBegin")
pub fn owned_fixed_begin(
  value : OwnedFixedFixture,
  names : String,
  max_rows : Int,
) -> Bool {
  if value.receiving is Some(_) {
    return false
  }
  match
    @duckdb.prepare_fixed_compute_receiving(
      value.compute,
      fields(names),
      { max_rows, max_cells: 1000, max_nodes: 1000, max_text_bytes: 10000, },
      {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 100,
        max_work: 100000,
      },
      10000,
    ) {
    Ok(receiving) => {
      value.receiving = Some(receiving)
      true
    }
    Err(_) => false
  }
}

///|
#export_name("ownedFixedAccept")
pub fn owned_fixed_accept(
  value : OwnedFixedFixture,
  rows : Int,
  data : String,
) -> Bool {
  guard value.receiving is Some(receiving) else { return false }
  @duckdb.receive_fixed_compute_chunk(receiving, rows, columns(data)) is Ok(_)
}

///|
#export_name("ownedFixedFinish")
pub fn owned_fixed_finish(value : OwnedFixedFixture) -> Bool {
  guard value.receiving is Some(receiving) else { return false }
  match @duckdb.finish_fixed_compute_receiving(receiving) {
    Ok(receipt) => {
      value.receipt = Some(receipt)
      true
    }
    Err(_) => false
  }
}

///|
#export_name("ownedFixedRows")
pub fn owned_fixed_rows(value : OwnedFixedFixture) -> String {
  guard value.receipt is Some(receipt) else { return "null" }
  guard @duckdb.fixed_compute_receipt_rows(receipt) is Some(rows) else {
    return "null"
  }
  try {
    let writer = @encode.writer(10000, 1000, 10)
    @encode.begin_array(writer)
    for row in 0..<@execution.admitted_output_row_count(rows) {
      guard @execution.admitted_output_cell(rows, row, 0)
        is Some(@admitted.Number(number)) else {
        return "null"
      }
      @encode.number_value(writer, number)
    }
    @encode.end_array(writer)
    @encode.finish(writer)
  } catch {
    _ => "null"
  }
}

///|
#export_name("ownedFixedLocalCid")
pub fn owned_fixed_local_cid(value : OwnedFixedFixture) -> String {
  guard @planning.execute_local_fixed_compute(
      value.local_choice,
      value.local_binding,
      issued_execution_limits(100),
    )
    is Ok(completed) else {
    return "null"
  }
  let output = @execution.completed_output(completed, Step(1)).unwrap()
  guard @execution.identify_completed_rows(output, {
      max_columns: 10,
      max_order_work: 10000,
      max_bytes: 100000,
      max_nodes: 10000,
      max_depth: 100,
    })
    is Ok(identity) else {
    return "null"
  }
  @execution.row_wire_cid(identity)
}

///|
#export_name("ownedFixedAbort")
pub fn owned_fixed_abort(value : OwnedFixedFixture) -> Unit {
  if value.receiving is Some(receiving) {
    @duckdb.abort_fixed_compute_receiving(receiving)
  }
  value.receipt = None
}
