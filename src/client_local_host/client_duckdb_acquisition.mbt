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
/// A checked pending-source budget, independent of AcquisitionChoice. The
/// componentwise maximum covers both installed realizations, while
/// the opaque owner binds the budget to the original checked requirement.
struct ClientDuckDBCaptureCapacity {
  requirement : @planning.QueryRequirement
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
/// Prepare capacity before read approval without choosing Native or Broad.
/// Both installed realizations are bounded conservatively, including paths
/// the later selector may exclude. No estimate, preference, candidate choice,
/// permit or read is manufactured, and eligibility remains the selector's job.
pub fn prepare_client_duckdb_capture_capacity(
  requirement : @planning.QueryRequirement,
  database_schema : String,
  table : String,
  query_contract_body : String,
  evidence_contract_body : String,
  two_receipt_contract_body : String,
) -> Result[ClientDuckDBCaptureCapacity, ClientDuckDBAcquisitionIssue] {
  match
    prepare_client_duckdb_acquisition_parts(
      requirement, database_schema, table, query_contract_body, evidence_contract_body,
      two_receipt_contract_body,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard @duckdb_host.prepared_native_capacity(client_duckdb_native_limits())
    is Some(native) else {
    return Err(Preparation)
  }
  guard @duckdb_host.prepared_broad_capacity(
      requirement,
      client_duckdb_broad_limits(),
    )
    is Some(broad) else {
    return Err(Preparation)
  }
  let retained_bytes = if native.retained_bytes > broad.retained_bytes {
    native.retained_bytes
  } else {
    broad.retained_bytes
  }
  let execution_bytes = if native.execution_bytes > broad.execution_bytes {
    native.execution_bytes
  } else {
    broad.execution_bytes
  }
  Ok({ requirement, retained_bytes, execution_bytes, })
}

///|
pub fn client_duckdb_capture_capacity_values(
  capacity : ClientDuckDBCaptureCapacity,
) -> Array[Int64] {
  [capacity.retained_bytes, capacity.execution_bytes]
}

///|
/// Requirement identity is a capacity/custody binding, never read authority.
pub fn client_duckdb_capture_capacity_matches_requirement(
  capacity : ClientDuckDBCaptureCapacity,
  requirement : @planning.QueryRequirement,
) -> Bool {
  @planning.query_requirement_cid(capacity.requirement) ==
  @planning.query_requirement_cid(requirement)
}

///|
/// Before an approved read starts, check its real selected configuration
/// against the pending budget already used by the shared Run ledger.
pub fn client_duckdb_capture_capacity_accepts(
  envelope : ClientDuckDBCaptureCapacity,
  selected : @duckdb_host.CaptureConfiguration,
) -> Bool {
  if !client_duckdb_capture_capacity_matches_requirement(
      envelope,
      @duckdb_host.configured_capture_requirement(selected),
    ) {
    return false
  }
  guard @duckdb_host.configured_capture_capacity(selected) is Some(capacity) else {
    return false
  }
  capacity.retained_bytes >= 0L &&
  capacity.execution_bytes >= 0L &&
  capacity.retained_bytes <= envelope.retained_bytes &&
  capacity.execution_bytes <= envelope.execution_bytes
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
  @duckdb_host.configure_native_host(
    receipts,
    requirement,
    choice,
    candidate,
    client_duckdb_native_limits(),
  )
}

///|
fn client_duckdb_native_limits() -> @duckdb_host.NativeHostLimits {
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 100000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
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
  }
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
  @duckdb_host.configure_broad_host(
    contracts,
    requirement,
    choice,
    candidate,
    client_duckdb_broad_limits(),
  )
}

///|
fn client_duckdb_broad_limits() -> @duckdb_host.BroadHostLimits {
  let values : @execution.ValueLimits = {
    max_nodes: 10000,
    max_text_bytes: 100000,
    max_depth: 100,
    max_work: 1000000,
  }
  {
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
  }
}
