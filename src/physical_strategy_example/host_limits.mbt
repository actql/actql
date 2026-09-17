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
fn acquisition_limits(
  data? : DataProfile? = None,
) -> @acquisition_host.NativeHostLimits {
  let base : @acquisition_host.NativeHostLimits = {
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
  match data {
    None => base
    Some(data) =>
      {
        ..base,
        // Validation scan and selected output share one cumulative receiver.
        physical: profile_physical(data, data.source_rows + data.task_rows),
        // Schema matching is independent of row count; keep its budget bounded.
        metadata_work: 100000,
        // The two receipts share measurement usage, unlike a single retained
        // representation. Reserve their combined encoding budget before scan.
        measurement: {
          ..profile_measurement(data),
          max_bytes: data.wire_bytes * 2,
        },
        completion: {
          ..base.completion,
          demand: {
            ..profile_measurement(data),
            max_bytes: data.wire_bytes * 2,
          },
          receipts: {
            ..base.completion.receipts,
            max_columns: data.columns,
            max_bytes: data.wire_bytes * 2,
            max_nodes: data.value_nodes,
          },
          max_received_rows: data.source_rows + data.task_rows,
          max_received_bytes: data.wire_bytes * 2,
          max_retained_wire_bytes: data.wire_bytes * 2,
          records: { ..base.completion.records, max_fields: data.columns * 2, },
        },
        retention: profile_values(data),
        output_rows: data.source_rows,
        output_entries: profile_completion_entries(data),
        transport: profile_transport(data, data.source_rows),
      }
  }
}

///|
fn dispatch_limits(data? : DataProfile? = None) -> @dbhost.TaskDispatchLimits {
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  let base : @dbhost.TaskDispatchLimits = {
    input_entries: 100,
    input_name_bytes: 10000,
    candidate_work: 100,
    join_validation: { max_rows: 100, max_work: 10000, max_entries: 1000, },
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
  match data {
    None => base
    Some(data) =>
      {
        ..base,
        input_entries: data.entries,
        join_validation: {
          max_rows: data.task_rows,
          max_work: data.work,
          max_entries: data.entries,
        },
        capacity: {
          ..base.capacity,
          max_rows: data.task_rows,
          max_value_bytes: data.value_bytes,
        },
        local_execution: {
          ..base.local_execution,
          rows: {
            ..base.local_execution.rows,
            max_rows: data.task_rows,
            retained_entries: data.entries,
            operation_entries: data.entries,
            input_values: profile_values(data),
            output_values: profile_values(data),
          },
          max_work: data.work,
        },
        guards: profile_measurement(data),
        // Managed filter/select preparation inspects both the admitted input
        // and output views. The data profile's finite metadata allowance, not
        // the small example compiler default, bounds that work.
        native_query: { ..base.native_query, max_entries: data.entries, },
        native: {
          ..base.native,
          metadata_work: 100000,
          values: profile_measurement(data),
          demand: profile_measurement(data),
          physical: profile_physical(data, data.task_rows),
          retention: profile_values(data),
          completion_entries: profile_completion_entries(data),
        },
        transport: profile_transport(data, data.task_rows),
      }
  }
}
