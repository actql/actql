///|
/// Finite resident consumer profile. The ordinary Native standard Host still
/// chooses and executes the checked suffix. Engine memory is explicitly set by
/// the Site operator; no dispatch can expand it or replace the Source mapping.
fn retained_consumer_configuration(
  source : @resident_host.ResidentSourceConfiguration,
  registry_body : String,
  values_body : String,
  engine_bytes : Int64,
) -> @resident_host.ResidentSourceComputeConfiguration? {
  guard @output.native_remote_standard_transfer_source_capacity(
      retained_consumer_input_limits(),
    )
    is Some(decoding) &&
    engine_bytes > 0L &&
    engine_bytes < source.ledger.execution_bytes - decoding.execution_bytes &&
    source.ledger.retained_bytes > decoding.retained_bytes else {
    return None
  }
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 10000,
    max_depth: 100,
    max_work: 100000,
  }
  Some({
    source: {
      ..source,
      // One reservation/holding for the bounded decoder and one for the
      // checked consumer. The operator's byte ceilings remain unchanged.
      ledger: { ..source.ledger, attempts: 2, holdings: 2, },
    },
    registry_body,
    values_body,
    dispatch: {
      input_entries: 100,
      input_name_bytes: 10000,
      candidate_work: 100,
      join_validation: { max_rows: 100, max_work: 1000, max_entries: 1000, },
      capacity: {
        contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
        max_rows: 100,
        max_value_bytes: 10000,
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
      guards: {
        max_work: 10000,
        max_bytes: 10000,
        max_nodes: 10000,
        max_depth: 100,
      },
      native_query: {
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
      native: {
        values: {
          max_work: 1000,
          max_bytes: 10000,
          max_nodes: 1000,
          max_depth: 20,
        },
        demand: {
          max_work: 1000,
          max_bytes: 10000,
          max_nodes: 1000,
          max_depth: 20,
        },
        physical: {
          max_rows: 100,
          max_cells: 1000,
          max_nodes: 1000,
          max_text_bytes: 10000,
        },
        retention: values,
        metadata_work: 1000,
        completion_entries: 100,
        completion_name_bytes: 1000,
      },
      transport: {
        max_bytes: 100000,
        max_nodes: 10000,
        max_columns: 10,
        max_rows: 100,
        max_text_bytes: 100000,
      },
    },
    estimates: [
      {
        local_rates: [
          {
            work_slots: [0, 1, 2, 3, 4],
            fixed_ms: Some(1000L),
            per_row_ms: Some(0L),
            per_wire_byte_ms: Some(0L),
            per_pair_ms: Some(0L),
          },
        ],
        native_rates: [
          {
            work_slots: [0, 1, 2, 3, 4, 5, 6, 7],
            fixed_ms: Some(10L),
            per_row_ms: Some(0L),
            per_wire_byte_ms: Some(0L),
            per_pair_ms: Some(0L),
          },
        ],
        // The chosen envelope includes the engine and bounded decoding scratch.
        native_capacity: {
          transfer_bytes: 100000L,
          retained_bytes: source.ledger.retained_bytes - decoding.retained_bytes,
          execution_bytes: source.ledger.execution_bytes -
          decoding.execution_bytes,
        },
        output_rows_per_mille: Some(1000),
      },
    ],
    search: {
      max_offers: 6,
      max_strategies: 8,
      max_work: 10000,
      max_revisions: 4,
    },
    imports: {
      max_rows: 100,
      max_cells: 40,
      max_parameters: 8,
      max_sql_bytes: 10000,
      max_batch_rows: 2,
    },
    transfer_bytes: 100000L,
    execution_bytes: engine_bytes,
    retained: None,
  })
}

///|
fn retained_consumer_input_limits() -> @output.NativeRemoteStandardTransferSourceLimits {
  {
    max_rows: 10,
    max_wire_bytes: 1000,
    max_read_bytes: 65536,
    max_entries: 100,
    max_name_bytes: 10000,
    values: {
      max_nodes: 10000,
      max_text_bytes: 100000,
      max_depth: 10,
      max_work: 200000,
    },
    wire: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
  }
}
