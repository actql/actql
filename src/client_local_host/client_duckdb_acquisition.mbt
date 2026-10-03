///|
pub(all) enum ClientDuckDBAcquisitionIssue {
  InvalidSource
  InvalidContracts
  Preparation
  Registration
  Candidate
  Selection
}

///|
/// Bind one checked source requirement to the installed DuckDB realization.
/// This single-candidate API has exactly one implementation; its explicit singleton Host
/// preference needs no duration estimate and makes no cheapest-route claim.
/// The trusted Host supplies the physical table and file grant separately;
/// Program text cannot select a local file or replace evidence contracts.
fn prepare_client_duckdb_acquisition_parts(
  requirement : @planning.QueryRequirement,
  database_schema : String,
  table : String,
  query_contract_body : String,
  evidence_contract_body : String,
  two_receipt_contract_body : String,
) -> Result[
  (
    @planning.QueryEvidenceContracts,
    @planning.QueryTwoReceiptContract,
    @duckdb_query.DuckDBQueryPreparation,
    @connector.CapabilityRegistry,
  ),
  ClientDuckDBAcquisitionIssue,
] {
  if database_schema.is_empty() || table.is_empty() {
    return Err(InvalidSource)
  }
  let query_contract = @identity.from_json(
    @json.parse(query_contract_body),
    10000,
    100,
    100000,
  ) catch {
    _ => return Err(InvalidContracts)
  }
  let evidence_contract = @identity.from_json(
    @json.parse(evidence_contract_body),
    10000,
    100,
    100000,
  ) catch {
    _ => return Err(InvalidContracts)
  }
  let two_receipt_contract = @identity.from_json(
    @json.parse(two_receipt_contract_body),
    10000,
    100,
    100000,
  ) catch {
    _ => return Err(InvalidContracts)
  }
  let contracts = match
    @planning.admit_query_evidence_contracts(
      query_contract,
      evidence_contract,
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidContracts)
  }
  let receipts = match
    @planning.admit_query_two_receipt_contract(
      contracts,
      two_receipt_contract,
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidContracts)
  }
  let preparation = match
    @duckdb_query.prepare_duckdb_query(
      requirement,
      database_schema,
      table,
      10,
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
    ) {
    Ok(value) => value
    Err(_) => return Err(Preparation)
  }
  let registry = match
    @connector.prepare_capability_registry(
      [
        {
          name: "duckdb",
          acquisition: true,
          fixed_compute: true,
          effect: false,
        },
      ],
      1,
      6,
    ) {
    Ok(value) => value
    Err(_) => return Err(Registration)
  }
  Ok((contracts, receipts, preparation, registry))
}

///|
pub fn prepare_client_duckdb_acquisition(
  requirement : @planning.QueryRequirement,
  database_schema : String,
  table : String,
  query_contract_body : String,
  evidence_contract_body : String,
  two_receipt_contract_body : String,
) -> Result[@duckdb_host.NativeHostConfiguration, ClientDuckDBAcquisitionIssue] {
  let (_, receipts, preparation, registry) = match
    prepare_client_duckdb_acquisition_parts(
      requirement, database_schema, table, query_contract_body, evidence_contract_body,
      two_receipt_contract_body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @duckdb_host.prepare_native_source_evidence_context(requirement)
    is Ok(context) &&
    @duckdb_host.source_evidence_context_supports(
      context,
      @planning.query_two_receipt_contract_cid(receipts),
    ) else {
    return Err(Candidate)
  }
  guard @connector.capability_registration_at(registry, 0) is Some(registration) else {
    return Err(Registration)
  }
  let candidate = match
    @duckdb_query.duckdb_native_candidate(
      registration,
      preparation,
      [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10], milliseconds: None, }],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      100,
    ) {
    Ok(value) => value
    Err(_) => return Err(Candidate)
  }
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(candidate)],
      Some([0]),
      100,
    )
    is Ok(@planning.Proposed(choice)) else {
    return Err(Selection)
  }
  Ok(configure_client_duckdb_native(requirement, receipts, choice, candidate))
}

///|
fn configure_client_duckdb_native(
  requirement : @planning.QueryRequirement,
  receipts : @planning.QueryTwoReceiptContract,
  choice : @planning.AcquisitionChoice,
  candidate : @planning.PreparedAcquisition[
    @duckdb_query.DuckDBNativePreparation,
  ],
) -> @duckdb_host.NativeHostConfiguration {
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  @duckdb_host.configure_native_host(receipts, requirement, choice, candidate, {
    physical: {
      max_rows: 100,
      max_cells: 1000,
      max_nodes: 1000,
      max_text_bytes: 10000,
    },
    metadata_work: 10000,
    measurement,
    completion: {
      demand: measurement,
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
    transport: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_columns: 10,
      max_rows: 100,
      max_text_bytes: 100000,
    },
  })
}

///|
/// Prepare the existing bounded broad-receipt realization before any I/O.
/// This is selection material, not an execution-time retry or read grant.
pub fn prepare_client_duckdb_broad_acquisition(
  requirement : @planning.QueryRequirement,
  database_schema : String,
  table : String,
  query_contract_body : String,
  evidence_contract_body : String,
  two_receipt_contract_body : String,
) -> Result[@duckdb_host.BroadHostConfiguration, ClientDuckDBAcquisitionIssue] {
  guard @duckdb_host.prepare_native_source_evidence_context(requirement)
    is Ok(context) &&
    @duckdb_host.source_evidence_context_supports(
      context,
      @planning.query_evidence_contract_identity(),
    ) else {
    return Err(InvalidContracts)
  }
  let (contracts, _, preparation, registry) = match
    prepare_client_duckdb_acquisition_parts(
      requirement, database_schema, table, query_contract_body, evidence_contract_body,
      two_receipt_contract_body,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @connector.capability_registration_at(registry, 0) is Some(registration) else {
    return Err(Registration)
  }
  let candidate = match
    @duckdb_query.duckdb_broad_candidate(
      registration,
      preparation,
      [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: None, }],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      100,
    ) {
    Ok(value) => value
    Err(_) => return Err(Candidate)
  }
  guard @planning.choose_acquisition_candidate(
      registry,
      requirement,
      [@planning.prepared_acquisition_candidate(candidate)],
      Some([0]),
      100,
    )
    is Ok(@planning.Proposed(choice)) else {
    return Err(Selection)
  }
  Ok(configure_client_duckdb_broad(requirement, contracts, choice, candidate))
}

///|
fn configure_client_duckdb_broad(
  requirement : @planning.QueryRequirement,
  contracts : @planning.QueryEvidenceContracts,
  choice : @planning.AcquisitionChoice,
  candidate : @planning.PreparedAcquisition[
    @duckdb_query.DuckDBQueryPreparation,
  ],
) -> @duckdb_host.BroadHostConfiguration {
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 100000,
    max_depth: 100,
    max_work: 1000000,
  }
  @duckdb_host.configure_broad_host(contracts, requirement, choice, candidate, {
    physical: {
      max_rows: 100,
      max_cells: 1000,
      max_nodes: 1000,
      max_text_bytes: 10000,
    },
    metadata_work: 10000,
    retention: values,
    completion: {
      execution: {
        rows: {
          max_rows: 100,
          metadata_entries: 10000,
          retained_entries: 10000,
          operation_entries: 10000,
          input_values: values,
          output_values: values,
        },
        max_work: 1000000,
        max_frames: 10000,
      },
      guards: {
        max_work: 100000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
      retention: {
        received_wire_bytes: 100000,
        retained_wire_bytes: 100000,
        measurement: {
          max_columns: 10,
          max_order_work: 10000,
          max_bytes: 100000,
          max_nodes: 10000,
          max_depth: 100,
        },
      },
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
    transport: {
      max_bytes: 100000,
      max_nodes: 10000,
      max_columns: 10,
      max_rows: 100,
      max_text_bytes: 100000,
    },
  })
}
