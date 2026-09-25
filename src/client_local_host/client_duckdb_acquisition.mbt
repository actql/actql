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
/// The trusted Host supplies the physical table and file grant separately;
/// Program text cannot select a local file or replace evidence contracts.
pub fn prepare_client_duckdb_acquisition(
  requirement : @planning.QueryRequirement,
  database_schema : String,
  table : String,
  query_contract_body : String,
  evidence_contract_body : String,
  two_receipt_contract_body : String,
) -> Result[
  @duckdb_host.NativeHostConfiguration,
  ClientDuckDBAcquisitionIssue,
] {
  if database_schema != "main" || table != "records" {
    return Err(InvalidSource)
  }
  let query_contract = @identity.from_json(
    @json.parse(query_contract_body), 10000, 100, 100000,
  ) catch { _ => return Err(InvalidContracts) }
  let evidence_contract = @identity.from_json(
    @json.parse(evidence_contract_body), 10000, 100, 100000,
  ) catch { _ => return Err(InvalidContracts) }
  let two_receipt_contract = @identity.from_json(
    @json.parse(two_receipt_contract_body), 10000, 100, 100000,
  ) catch { _ => return Err(InvalidContracts) }
  let contracts = match @planning.admit_query_evidence_contracts(
      query_contract,
      evidence_contract,
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidContracts)
  }
  let receipts = match @planning.admit_query_two_receipt_contract(
      contracts,
      two_receipt_contract,
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidContracts)
  }
  let preparation = match @duckdb_query.prepare_duckdb_query(
      requirement, database_schema, table, 10,
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
  let registry = match @connector.prepare_capability_registry(
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
  guard @connector.capability_registration_at(registry, 0)
    is Some(registration) else {
    return Err(Registration)
  }
  let candidate = match @duckdb_query.duckdb_native_candidate(
      registration,
      preparation,
      [
        {
          work_slots: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10],
          milliseconds: Some(10L),
        },
      ],
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
      None,
      100,
    ) is Ok(@planning.Proposed(choice)) else {
    return Err(Selection)
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  Ok(@duckdb_host.configure_native_host(
    receipts,
    requirement,
    choice,
    candidate,
    {
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
    },
  ))
}
