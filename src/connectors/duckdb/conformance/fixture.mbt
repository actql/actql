// This package constructs only fixed test data using public checked entrances.
// It exports no completion constructor, issuer, arbitrary owner or storage access.

///|
#export_name("demandUsage")
pub fn demand_usage(value : @duckdb.NativeReceiving) -> String {
  let measured = match
    @duckdb.measure_native_demand(value, {
      max_work: 1000,
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 10,
    }) {
    Ok(value) => value
    Err(_) => return "null"
  }
  let usage = @duckdb.native_demand_usage(measured)
  try {
    let writer = @encode.writer(1000, 100, 4)
    @encode.begin_array(writer)
    for
      number in [
        usage.rows.to_int64(),
        usage.field_bytes,
        usage.true_rows.to_int64(),
        usage.false_rows.to_int64(),
        usage.null_rows.to_int64(),
        usage.predicate_bytes,
      ] {
      @encode.number_value(writer, number.to_double())
    }
    match usage.rhs_bytes {
      Some(bytes) => @encode.number_value(writer, bytes.to_double())
      None => @encode.null_value(writer)
    }
    @encode.end_array(writer)
    @encode.finish(writer)
  } catch {
    _ => abort("fixture demand usage")
  }
}

///|
#export_name("receiptIdentities")
pub fn receipt_identities(value : @duckdb.NativeReceiving) -> String {
  let receipts = match
    @duckdb.identify_native_receipts(
      value,
      {
        max_columns: 10,
        max_order_work: 1000,
        max_bytes: 100000,
        max_nodes: 1000,
        max_depth: 10,
      },
      100,
      100000,
    ) {
    Ok(receipts) => receipts
    Err(_) => return "null"
  }
  try {
    let writer = @encode.writer(1000, 100, 4)
    @encode.begin_array(writer)
    for role in [@duckdb.ValidationScan, @duckdb.NativeResult] {
      let (cid, bytes, nodes, rows) = @duckdb.native_receipt_digest(
        receipts, role,
      )
      @encode.begin_array(writer)
      @encode.string_value(writer, cid)
      for number in [bytes, nodes, rows] {
        @encode.number_value(writer, number.to_double())
      }
      @encode.end_array(writer)
    }
    @encode.end_array(writer)
    @encode.finish(writer)
  } catch {
    _ => abort("fixture receipt identities")
  }
}

///|
fn cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 100000,
      max_nodes: 10000,
      max_depth: 20,
    }).unwrap(),
    {
      max_nodes: 10000,
      max_depth: 20,
      max_string_bytes: 100000,
      max_total_string_bytes: 100000,
    },
  ).unwrap()
}

///|
#export_name("create")
pub fn create() -> @duckdb.NativeReceiving {
  create_guarded(10000, 100, 1000)
}

///|
#export_name("createGuarded")
pub fn create_guarded(
  value_bytes : Int,
  output_rows : Int,
  nodes : Int,
) -> @duckdb.NativeReceiving {
  let schema = @schema.from_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(@contract.NumberType, nullable=false),
      ),
      (
        @schema.Unqualified("amount"),
        @contract.primitive(@contract.NumberType, nullable=true),
      ),
    ],
    max_fields=2,
    max_name_bytes=100,
  ).unwrap()
  let pipeline = @pipeline.check(
    cursor("[{\"filter\":\"id > 1\"},{\"select\":[\"id\"]}]"),
    [("source", schema)],
    None,
    None,
    {
      max_steps: 2,
      max_work: 10000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let owner = @lower.bind_parameters(
    @lower.prepare(pipeline, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let query = @duckdb.compile_native_filter_select(owner, "main", "records", {
    max_entries: 100,
    max_sql_bytes: 10000,
    expressions: {
      max_nodes: 1000,
      max_work: 10000,
      max_depth: 100,
      max_literal_nodes: 1000,
      max_literal_text_bytes: 10000,
    },
  }).unwrap()
  @duckdb.prepare_native_receiving(
    @duckdb.prepare_native_scan(query, 2, 1000).unwrap(),
    { max_rows: 100, max_cells: 200, max_nodes: 200, max_text_bytes: 10000, },
    1000,
    { max_value_bytes: value_bytes, max_output_rows: output_rows, },
    { max_work: 10000, max_bytes: 100000, max_nodes: nodes, max_depth: 10, },
  ).unwrap()
}

///|
#export_name("sql")
pub fn sql(value : @duckdb.NativeReceiving, kind : Int) -> String {
  let scan = @duckdb.native_receiving_scan(value)
  match kind {
    0 => @duckdb.native_scan_metadata_sql(scan)
    1 => @duckdb.native_scan_sql(scan)
    _ => @duckdb.native_query_sql(@duckdb.native_scan_query(scan))
  }
}

///|
#export_name("parameter")
pub fn parameter(
  value : @duckdb.NativeReceiving,
  kind : Int,
  index : Int,
) -> String {
  let scan = @duckdb.native_receiving_scan(value)
  let parameter = if kind == 0 {
    @duckdb.native_scan_metadata_parameter(scan, index).unwrap()
  } else {
    @duckdb.native_query_parameter(@duckdb.native_scan_query(scan))
  }
  try {
    let writer = @encode.writer(1000, 100, 10)
    @duckdb.emit_physical_parameter(parameter, writer)
    @encode.finish(writer)
  } catch {
    _ => abort("fixture parameter")
  }
}

///|
fn fields(text : String) -> Array[(String, @duckdb.PhysicalType)] {
  let list = cursor(text)
  let result = []
  for i in 0..<@decode.array_length(list).unwrap() {
    let object = @decode.closed_object(@decode.element_at(list, i).unwrap(), [
      "name", "type",
    ]).unwrap()
    result.push(
      (
        @decode.text(@decode.required(object, "name").unwrap()).unwrap(),
        @duckdb.decode_physical_type(@decode.required(object, "type").unwrap()).unwrap(),
      ),
    )
  }
  result
}

///|
fn columns(text : String) -> Array[@decode.Cursor] {
  // Only the fixed fixture unwraps. Product Host callers retain the typed issue.
  @duckdb.decode_transport_columns(text, {
    max_bytes: 100000,
    max_nodes: 10000,
    max_columns: 100,
    max_rows: 10000,
    max_text_bytes: 100000,
  }).unwrap()
}

///|
#export_name("metadata")
pub fn metadata(
  value : @duckdb.NativeReceiving,
  count : Int,
  names : String,
  data : String,
) -> Bool {
  @duckdb.admit_native_table_metadata(
    value,
    count,
    fields(names),
    columns(data),
  )
  is Ok(_)
}

///|
#export_name("begin")
pub fn begin(
  value : @duckdb.NativeReceiving,
  role : Int,
  names : String,
) -> @duckdb.NativeReceiptPort {
  @duckdb.begin_native_receipt(
    value,
    if role == 0 {
      ValidationScan
    } else {
      NativeResult
    },
    fields(names),
  ).unwrap()
}

///|
#export_name("accept")
pub fn accept(
  value : @duckdb.NativeReceiving,
  port : @duckdb.NativeReceiptPort,
  count : Int,
  data : String,
) -> Bool {
  @duckdb.accept_native_receipt_chunk(value, port, count, columns(data))
  is Ok(_)
}

///|
#export_name("finish")
pub fn finish(
  value : @duckdb.NativeReceiving,
  port : @duckdb.NativeReceiptPort,
) -> Bool {
  @duckdb.finish_native_receipt(value, port) is Ok(_)
}

///|
#export_name("ready")
pub fn ready(value : @duckdb.NativeReceiving) -> Bool {
  @duckdb.native_receiving_has_both(value)
}

///|
#export_name("cancel")
pub fn cancel(value : @duckdb.NativeReceiving) -> Unit {
  @duckdb.abort_native_receiving(value)
}
