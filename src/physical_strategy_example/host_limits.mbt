///|
// Deliberately small, explicit application limits. Not global Host defaults.
fn measurement() -> @execution.FixedInputGuardMeasureLimits {
  { max_work: 100000, max_bytes: 100000, max_nodes: 10000, max_depth: 100, }
}

///|
fn native_query_limits() -> @duckdb.NativeQueryLimits {
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
  }
}

///|
fn transport() -> @duckdb.TransportColumnLimits {
  {
    max_bytes: 100000,
    max_nodes: 10000,
    max_columns: 10,
    max_rows: 100,
    max_text_bytes: 100000,
  }
}

///|
fn acquisition_limits() -> @dbhost.NativeHostLimits {
  {
    physical: {
      max_rows: 100,
      max_cells: 1000,
      max_nodes: 1000,
      max_text_bytes: 10000,
    },
    metadata_work: 10000,
    measurement: measurement(),
    completion: {
      demand: measurement(),
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
      capture: { max_bytes: 1000000, max_nodes: 100000, max_depth: 100, },
    },
    retention: {
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 100,
      max_work: 1000000,
    },
    output_rows: 100,
    output_entries: 100,
    output_name_bytes: 10000,
    transport: transport(),
  }
}

///|
fn dispatch_limits() -> @dbhost.TaskDispatchLimits {
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  {
    input_entries: 100,
    input_name_bytes: 10000,
    candidate_work: 100,
    capacity: {
      contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
      max_rows: 100,
      max_value_bytes: 1000,
      common_fragment: None,
    },
    local_execution: {
      rows: {
        max_rows: 100,
        metadata_entries: 10000,
        retained_entries: 10000,
        operation_entries: 10000,
        input_values: values,
        output_values: values,
      },
      max_work: 100000,
      max_frames: 100,
    },
    guards: measurement(),
    native_query: native_query_limits(),
    native: {
      values: measurement(),
      demand: measurement(),
      physical: {
        max_rows: 100,
        max_cells: 1000,
        max_nodes: 1000,
        max_text_bytes: 10000,
      },
      retention: {
        max_nodes: 10000,
        max_text_bytes: 10000,
        max_depth: 100,
        max_work: 100000,
      },
      metadata_work: 10000,
      completion_entries: 100,
      completion_name_bytes: 10000,
    },
    transport: transport(),
  }
}
