///|
// Host-selected originals only. This configuration projection opens no library,
// database, Run or grant and does not select or execute a strategy.
priv struct LocalSourceInstallation {
  source_ref : String
  library_path : String
  database_file : String
  configuration : (@duckdb.Library, String) -> @source_owner.ResidentSourceComputeConfiguration
}

///|
fn source_setting(
  object : @decode.ObjectView,
  name : String,
) -> @decode.Cursor raise ClientStop {
  @decode.lookup(object, name).unwrap_or_else(() => {
    stop("InvalidLocalSourceInstallation")
  })
}

///|
fn source_object(
  object : @decode.ObjectView,
  name : String,
  keys : Array[String],
) -> @decode.ObjectView raise ClientStop {
  @decode.closed_object(source_setting(object, name), keys).unwrap_or_else(() => {
    stop("InvalidLocalSourceInstallation")
  })
}

///|
fn source_integer(
  object : @decode.ObjectView,
  name : String,
  maximum? : Int64 = 2147483647L,
) -> Int64 raise ClientStop {
  guard @decode.safe_integer(source_setting(object, name)) is Ok(value) &&
    value >= 0L &&
    value <= maximum else {
    stop("InvalidLocalSourceLimits")
  }
  value
}

///|
fn source_count(
  object : @decode.ObjectView,
  name : String,
) -> Int raise ClientStop {
  source_integer(object, name).to_int()
}

///|
fn source_bytes(
  object : @decode.ObjectView,
  name : String,
) -> Int64 raise ClientStop {
  source_integer(object, name, maximum=536870912L)
}

///|
fn source_text(
  object : @decode.ObjectView,
  name : String,
) -> String raise ClientStop {
  guard @decode.text(source_setting(object, name)) is Ok(value) &&
    !value.is_empty() else {
    stop("InvalidLocalSourceInstallation")
  }
  value
}

///|
fn source_cid(
  object : @decode.ObjectView,
  name : String,
) -> String raise ClientStop {
  let value = source_text(object, name)
  if value.length() != 71 || !value.has_prefix("sha256:") {
    stop("InvalidLocalSourceInstallation")
  }
  for index in 7..<71 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      stop("InvalidLocalSourceInstallation")
    }
  }
  value
}

///|
fn source_value_limits(
  object : @decode.ObjectView,
) -> @execution.ValueLimits raise ClientStop {
  {
    max_nodes: source_count(object, "max_nodes"),
    max_text_bytes: source_count(object, "max_text_bytes"),
    max_depth: source_count(object, "max_depth"),
    max_work: source_count(object, "max_work"),
  }
}

///|
fn source_rates(
  cursor : @decode.Cursor,
) -> Array[@cost.WorkRate] raise ClientStop {
  guard @decode.elements(cursor) is Ok(elements) else {
    stop("InvalidLocalSourceInstallation")
  }
  elements.map(element => {
    let object = @decode.closed_object(element, [
      "work_slots", "fixed_ms", "per_row_ms", "per_wire_byte_ms", "per_pair_ms",
    ]).unwrap_or_else(() => stop("InvalidLocalSourceInstallation"))
    guard @decode.elements(source_setting(object, "work_slots")) is Ok(slots) &&
      slots.length() <= 8 else {
      stop("InvalidLocalSourceInstallation")
    }
    let numbers : Array[Int] = []
    for slot in slots {
      guard @decode.safe_integer(slot) is Ok(value) &&
        value >= 0L &&
        value < 8L &&
        !numbers.contains(value.to_int()) else {
        stop("InvalidLocalSourceInstallation")
      }
      numbers.push(value.to_int())
    }
    let coefficient = fn(name : String) -> Int64? raise ClientStop {
      match @decode.lookup(object, name) {
        None => None
        Some(value) if @decode.is_null(value) => None
        Some(_) => Some(source_integer(object, name, maximum=9007199254740991L))
      }
    }
    {
      work_slots: numbers,
      fixed_ms: coefficient("fixed_ms"),
      per_row_ms: coefficient("per_row_ms"),
      per_wire_byte_ms: coefficient("per_wire_byte_ms"),
      per_pair_ms: coefficient("per_pair_ms"),
    }
  })
}

///|
fn source_dispatch_limits(
  object : @decode.ObjectView,
) -> @dispatch.TaskDispatchLimits raise ClientStop {
  let capacity = source_object(object, "capacity", [
    "contract_cid", "max_rows", "max_value_bytes",
  ])
  let execution = source_object(object, "local_execution", [
    "rows", "max_work", "max_frames",
  ])
  let rows = source_object(execution, "rows", [
    "max_rows", "metadata_entries", "retained_entries", "operation_entries", "input_values",
    "output_values",
  ])
  let value_keys = ["max_nodes", "max_text_bytes", "max_depth", "max_work"]
  let guards = source_object(object, "guards", [
    "max_work", "max_bytes", "max_nodes", "max_depth",
  ])
  let query = source_object(object, "native_query", [
    "max_entries", "max_sql_bytes", "expressions",
  ])
  let expressions = source_object(query, "expressions", [
    "max_nodes", "max_work", "max_depth", "max_literal_nodes", "max_literal_text_bytes",
  ])
  let join = source_object(object, "join_validation", [
    "max_rows", "max_work", "max_entries",
  ])
  let native = source_object(object, "native", [
    "values", "demand", "physical", "retention", "metadata_work", "completion_entries",
    "completion_name_bytes",
  ])
  let wire_keys = ["max_work", "max_bytes", "max_nodes", "max_depth"]
  let values = source_object(native, "values", wire_keys)
  let demand = source_object(native, "demand", wire_keys)
  let physical = source_object(native, "physical", [
    "max_rows", "max_cells", "max_nodes", "max_text_bytes",
  ])
  let transport = source_object(object, "transport", [
    "max_bytes", "max_nodes", "max_columns", "max_rows", "max_text_bytes",
  ])
  {
    input_entries: source_count(object, "input_entries"),
    input_name_bytes: source_count(object, "input_name_bytes"),
    candidate_work: source_count(object, "candidate_work"),
    capacity: {
      contract_cid: source_cid(capacity, "contract_cid"),
      max_rows: source_count(capacity, "max_rows"),
      max_value_bytes: source_count(capacity, "max_value_bytes"),
      common_fragment: None,
    },
    local_execution: {
      rows: {
        max_rows: source_count(rows, "max_rows"),
        metadata_entries: source_count(rows, "metadata_entries"),
        retained_entries: source_count(rows, "retained_entries"),
        operation_entries: source_count(rows, "operation_entries"),
        input_values: source_value_limits(
          source_object(rows, "input_values", value_keys),
        ),
        output_values: source_value_limits(
          source_object(rows, "output_values", value_keys),
        ),
      },
      max_work: source_count(execution, "max_work"),
      max_frames: source_count(execution, "max_frames"),
    },
    guards: {
      max_work: source_count(guards, "max_work"),
      max_bytes: source_count(guards, "max_bytes"),
      max_nodes: source_count(guards, "max_nodes"),
      max_depth: source_count(guards, "max_depth"),
    },
    native_query: {
      max_entries: source_count(query, "max_entries"),
      max_sql_bytes: source_count(query, "max_sql_bytes"),
      expressions: {
        max_nodes: source_count(expressions, "max_nodes"),
        max_work: source_count(expressions, "max_work"),
        max_depth: source_count(expressions, "max_depth"),
        max_literal_nodes: source_count(expressions, "max_literal_nodes"),
        max_literal_text_bytes: source_count(
          expressions, "max_literal_text_bytes",
        ),
      },
    },
    join_validation: {
      max_rows: source_count(join, "max_rows"),
      max_work: source_count(join, "max_work"),
      max_entries: source_count(join, "max_entries"),
    },
    native: {
      values: {
        max_work: source_count(values, "max_work"),
        max_bytes: source_count(values, "max_bytes"),
        max_nodes: source_count(values, "max_nodes"),
        max_depth: source_count(values, "max_depth"),
      },
      demand: {
        max_work: source_count(demand, "max_work"),
        max_bytes: source_count(demand, "max_bytes"),
        max_nodes: source_count(demand, "max_nodes"),
        max_depth: source_count(demand, "max_depth"),
      },
      physical: {
        max_rows: source_count(physical, "max_rows"),
        max_cells: source_count(physical, "max_cells"),
        max_nodes: source_count(physical, "max_nodes"),
        max_text_bytes: source_count(physical, "max_text_bytes"),
      },
      retention: source_value_limits(
        source_object(native, "retention", value_keys),
      ),
      metadata_work: source_count(native, "metadata_work"),
      completion_entries: source_count(native, "completion_entries"),
      completion_name_bytes: source_count(native, "completion_name_bytes"),
    },
    transport: {
      max_bytes: source_count(transport, "max_bytes"),
      max_nodes: source_count(transport, "max_nodes"),
      max_columns: source_count(transport, "max_columns"),
      max_rows: source_count(transport, "max_rows"),
      max_text_bytes: source_count(transport, "max_text_bytes"),
    },
  }
}

///|
fn local_source_installation_cursor(
  body : String,
) -> @decode.Cursor raise ClientStop {
  let root = local_host_settings_object(
    local_host_settings_cursor(body, max_input_bytes=65536, max_nodes=8192),
    ["version", "native"],
    0,
    "InvalidLocalSourceInstallation",
  )
  if source_text(root, "version") != "actql-config/0.1" {
    stop("InvalidLocalSourceInstallation")
  }
  let native = local_host_settings_object(
    source_setting(root, "native"),
    ["source"],
    1,
    "InvalidLocalSourceInstallation",
  )
  source_setting(native, "source")
}

///|
// The operator-selected configuration retains declarations and a payload
// locator. The original Run Read still has to admit the Source and open it.
fn local_declared_file_source_installation(
  source : @decode.Cursor,
) -> (
  @run_host.ClientProjectConnections,
  @run_host.ClientProjectCatalog,
  String,
)? raise ClientStop {
  let invalid = "InvalidLocalDeclaredFileSourceInstallation"
  let count = @decode.object_length(source).unwrap_or_else(() => stop(invalid))
  // The resident Source's closed object has fifteen fields. Inspect the
  // discriminator on the original index without constructing a second map.
  if count > 15 {
    stop(invalid)
  }
  let fields = @shape.scale_collection_construction_extent(
    @decode.indexed_field_construction_extent(),
    count.to_int64(),
  ).unwrap_or_else(() => stop("LocalCommandPreparationLayoutUnavailable"))
  let selection = local_host_metadata_price(
    local_host_metadata_units(
      fields.record_headers + 6L,
      fields.reference_slots + 10L,
      fields.scalar_words + 8L,
      0L,
    ),
  )
  local_host_metadata_prepare(0L, selection)
  let mut kind = None
  for index in 0..<count {
    if @decode.field_at(source, index) is Some(("kind", value)) {
      kind = Some(value)
      break
    }
  }
  guard kind is Some(kind) else { return None }
  if @decode.text(kind) != Ok("declared_file") {
    stop(invalid)
  }
  let selected = local_host_settings_object(
    source,
    ["kind", "connections", "catalog", "data_file"],
    2,
    invalid,
  )
  let connections_wire = source_text(selected, "connections")
  let catalog_wire = source_text(selected, "catalog")
  let data_file = source_text(selected, "data_file")
  guard @scalar.admit_utf8_length(data_file, 4096) is Ok(_) &&
    local_declared_file_source_path(data_file) else {
    stop("InvalidLocalSourceLocation")
  }
  guard @run_host.client_project_connections_admission_construction_inventory(
      connections_wire,
    )
    is Some(connections_cost) &&
    @run_host.client_project_catalog_admission_construction_inventory(
      catalog_wire,
    )
    is Some(catalog_cost) &&
    @execution.compose_preparation_representation([
      connections_cost,
      catalog_cost,
      local_host_metadata_units(5L, 9L, 2L, 0L),
    ])
    is Some(inventory) else {
    stop("LocalCommandPreparationLayoutUnavailable")
  }
  let prepared = local_host_metadata_price(inventory)
  local_host_metadata_prepare(prepared, prepared)
  let connections = @run_host.admit_client_project_connections(connections_wire).unwrap_or_else(() => {
      stop(invalid)
    },
  )
  let catalog = @run_host.admit_client_project_catalog(catalog_wire).unwrap_or_else(() => {
      stop(invalid)
    },
  )
  Some((connections, catalog, data_file))
}

///|
fn local_declared_file_source_path(path : String) -> Bool {
  if !path.has_prefix("/") || path.length() < 2 {
    return false
  }
  let mut segment = 1
  for index in 1..<(path.length() + 1) {
    if index == path.length() || path[index] == '/' {
      let length = index - segment
      if length == 0 ||
        (length == 1 && path[segment] == '.') ||
        (length == 2 && path[segment] == '.' && path[segment + 1] == '.') {
        return false
      }
      segment = index + 1
    } else if path[index] == '\u{0000}' {
      return false
    }
  }
  true
}

///|
fn local_prepare_source_installation(
  body : String,
) -> (
  @run_host.ClientProjectConnections,
  @run_host.ClientProjectCatalog,
  String,
)? raise ClientStop {
  let source = local_source_installation_cursor(body)
  let declared = local_declared_file_source_installation(source)
  if declared is None {
    ignore(local_resident_source_installation(source))
  }
  declared
}

///|
fn local_source_installation(
  body : String,
) -> LocalSourceInstallation raise ClientStop {
  let source = local_source_installation_cursor(body)
  if local_declared_file_source_installation(source) is Some(_) {
    stop("LocalDeclaredFileSourceBindingRequired")
  }
  local_resident_source_installation(source)
}

///|
fn local_resident_source_installation(
  source : @decode.Cursor,
) -> LocalSourceInstallation raise ClientStop {
  let source = @decode.closed_object(source, [
    "source_ref", "source_contract_cid", "duckdb_library", "database_file", "memory_bytes",
    "schema", "table", "contracts", "ledger", "dispatch", "estimates", "search",
    "imports", "transfer_bytes", "execution_bytes",
  ]).unwrap_or_else(() => stop("InvalidLocalSourceInstallation"))
  let source_ref = source_text(source, "source_ref")
  let source_contract_cid = source_cid(source, "source_contract_cid")
  let library_path = source_text(source, "duckdb_library")
  let database_file = source_text(source, "database_file")
  if database_file.length() > 128 ||
    database_file == "." ||
    database_file == ".." ||
    database_file.contains("/") ||
    database_file.contains("\\") ||
    database_file.contains("\u{0000}") {
    stop("InvalidLocalSourceLocation")
  }
  let schema = source_text(source, "schema")
  let table = source_text(source, "table")
  let memory = source_bytes(source, "memory_bytes")
  let contracts = source_object(source, "contracts", [
    "query", "evidence", "two_receipt", "fragment", "registry", "values",
  ])
  let query = source_text(contracts, "query")
  let evidence = source_text(contracts, "evidence")
  let two_receipt = source_text(contracts, "two_receipt")
  let fragment = source_text(contracts, "fragment")
  let registry = source_text(contracts, "registry")
  let values = source_text(contracts, "values")
  let ledger = source_object(source, "ledger", [
    "planning_work", "attempts", "holdings", "transfer_bytes", "retained_bytes",
    "execution_bytes",
  ])
  let planning_work = source_count(ledger, "planning_work")
  let attempts = source_count(ledger, "attempts")
  let holdings = source_count(ledger, "holdings")
  let transfer = source_bytes(ledger, "transfer_bytes")
  let retained = source_bytes(ledger, "retained_bytes")
  let execution = source_bytes(ledger, "execution_bytes")
  let dispatch = source_dispatch_limits(
    source_object(source, "dispatch", [
      "input_entries", "input_name_bytes", "candidate_work", "capacity", "local_execution",
      "guards", "native_query", "join_validation", "native", "transport",
    ]),
  )
  let profiles = @decode.elements(source_setting(source, "estimates")).unwrap_or_else(() => {
      stop("InvalidLocalSourceInstallation")
    },
  )
  let estimates : Array[@dispatch.DispatchEstimateProfile] = profiles.map(profile => {
    let profile = @decode.closed_object(profile, [
      "local_rates", "native_rates", "native_capacity", "output_rows_per_mille",
    ]).unwrap_or_else(() => stop("InvalidLocalSourceInstallation"))
    let capacity = source_object(profile, "native_capacity", [
      "transfer_bytes", "retained_bytes", "execution_bytes",
    ])
    let ratio = @decode.lookup(profile, "output_rows_per_mille")
    let ratio = match ratio {
      None => None
      Some(value) if @decode.is_null(value) => None
      Some(_) =>
        Some(
          source_integer(profile, "output_rows_per_mille", maximum=1000L).to_int(),
        )
    }
    {
      local_rates: source_rates(source_setting(profile, "local_rates")),
      native_rates: source_rates(source_setting(profile, "native_rates")),
      native_capacity: {
        transfer_bytes: source_bytes(capacity, "transfer_bytes"),
        retained_bytes: source_bytes(capacity, "retained_bytes"),
        execution_bytes: source_bytes(capacity, "execution_bytes"),
      },
      output_rows_per_mille: ratio,
    }
  })
  let search = source_object(source, "search", [
    "max_offers", "max_strategies", "max_work", "max_revisions",
  ])
  let offers = source_count(search, "max_offers")
  let strategies = source_count(search, "max_strategies")
  let work = source_count(search, "max_work")
  let revisions = source_count(search, "max_revisions")
  let imports = source_object(source, "imports", [
    "max_rows", "max_cells", "max_parameters", "max_sql_bytes", "max_batch_rows",
  ])
  let rows = source_count(imports, "max_rows")
  let cells = source_count(imports, "max_cells")
  let parameters = source_count(imports, "max_parameters")
  let sql = source_count(imports, "max_sql_bytes")
  let batch = source_count(imports, "max_batch_rows")
  let transfer_bytes = source_bytes(source, "transfer_bytes")
  let execution_bytes = source_bytes(source, "execution_bytes")
  let installed_contracts = @local_values.prepare_installed_sequence_contracts(
    registry,
    values,
    Some(fragment),
    None,
  ).unwrap_or_else(() => stop("InvalidLocalSourceInstalledContracts"))
  {
    source_ref,
    library_path,
    database_file,
    configuration: (library, database_path) => {
      source: {
        source_ref,
        source_contract_cid,
        library,
        database_path,
        retained_output_root: None,
        memory_bytes: memory,
        database_schema: schema,
        table,
        query_contract_body: query,
        evidence_contract_body: evidence,
        two_receipt_contract_body: two_receipt,
        fragment_contract_body: fragment,
        ledger: {
          planning_work,
          attempts,
          holdings,
          transfer_bytes: transfer,
          retained_bytes: retained,
          execution_bytes: execution,
        },
      },
      installed_contracts,
      values_body: values,
      dispatch,
      estimates,
      search: {
        max_offers: offers,
        max_strategies: strategies,
        max_work: work,
        max_revisions: revisions,
      },
      imports: {
        max_rows: rows,
        max_cells: cells,
        max_parameters: parameters,
        max_sql_bytes: sql,
        max_batch_rows: batch,
      },
      transfer_bytes,
      execution_bytes,
      retained: None,
    },
  }
}
