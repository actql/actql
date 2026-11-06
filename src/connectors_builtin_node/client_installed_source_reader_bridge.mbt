///|
/// Original installed JSON reader representation DATA. Core admission remains
/// at the existing same-acquisition provider RowRun and actual parent Ledger.
#export_name("clientProgramInstalledSourceReaderPolicy")
pub fn client_program_installed_source_reader_policy() -> Array[Int] {
  @client_local_host.installed_source_reader_policy()
}

///|
#export_name("clientProgramInstalledJsonSourceReaderCapacity")
pub fn client_program_installed_json_source_reader_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
) -> @execution.ExecutionCapacity? {
  @client_local_host.installed_json_source_reader_capacity(
    limits, columns, secret_bytes,
  )
}

///|
/// Project the existing common native-reader composition. The supplied domain
/// quote is the original provider constructor, not a numeric allowance or a
/// permission. Its caller keeps that same quote on the bound Source Reader.
#export_name("clientProgramInstalledNativeSourceReaderCapacity")
pub fn client_program_installed_native_source_reader_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  native : @execution.ExecutionCapacity?,
) -> @execution.ExecutionCapacity? {
  @client_local_host.installed_native_source_reader_capacity(
    limits, columns, secret_bytes, native,
  )
}

///|
#export_name("clientProgramInstalledJsonSourceReaderProfile")
pub fn client_program_installed_json_source_reader_profile(
  metadata_responses : Int,
  origin_units : Int,
) -> Array[Int]? {
  @client_local_host.installed_json_source_reader_profile(
    metadata_responses, origin_units,
  )
}

///|
#export_name("clientProgramInstalledGmailThreadReaderCapacity")
pub fn client_program_installed_gmail_thread_reader_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  list_pages : Int,
  mailbox_bytes : Int,
) -> @execution.ExecutionCapacity? {
  @client_local_host.installed_gmail_thread_reader_capacity(
    limits, columns, secret_bytes, list_pages, mailbox_bytes,
  )
}

///|
#export_name("clientProgramInstalledSlackSourceReaderCapacity")
pub fn client_program_installed_slack_source_reader_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  protocol_pages : Int,
) -> @execution.ExecutionCapacity? {
  @client_local_host.installed_slack_source_reader_capacity(
    limits, columns, secret_bytes, protocol_pages,
  )
}

///|
#export_name("clientProgramInstalledJsonSourceReaderCapacityWithRequest")
pub fn client_program_installed_json_source_reader_capacity_with_request(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  request : @execution.ExecutionCapacity?,
) -> @execution.ExecutionCapacity? {
  @client_local_host.installed_json_source_reader_capacity_with_request(
    limits, columns, secret_bytes, request,
  )
}

///|
#export_name("clientProgramInstalledPreservingJsonSourceReaderCapacityWithRequest")
pub fn client_program_installed_preserving_json_source_reader_capacity_with_request(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  request : @execution.ExecutionCapacity?,
) -> @execution.ExecutionCapacity? {
  @client_local_host.installed_preserving_json_source_reader_capacity_with_request(
    limits, columns, secret_bytes, request,
  )
}

///|
/// Original installed Salesforce limits, not Run admission or a replacement
/// schema. The native domain owns its Describe/recovery/typed query constructors;
/// the shared Reader owns response custody, original binding and cleanup.
#export_name("clientProgramInstalledSalesforceSourceReaderCapacity")
pub fn client_program_installed_salesforce_source_reader_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  describe : Array[Int],
  max_observation_bytes : Int,
  binding_units : Int,
  resource_units : Int,
  query_pages : Int,
  api_units : Int,
  soql_units : Int,
) -> @execution.ExecutionCapacity? {
  installed_salesforce_reader_capacity(
    limits,
    columns,
    secret_bytes,
    describe,
    max_observation_bytes,
    binding_units,
    resource_units,
    query_pages,
    api_units,
    soql_units,
    None,
  )
}

///|
/// Initial controls (zero) or the largest actual owned response extent.
/// Only constructor DATA is narrowed: original response/parser rejection
/// limits stay unchanged. The same RowRun must grow before any projection.
#export_name("clientProgramInstalledSalesforceSourceReaderResponseCapacity")
pub fn client_program_installed_salesforce_source_reader_response_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  describe : Array[Int],
  max_observation_bytes : Int,
  binding_units : Int,
  resource_units : Int,
  query_pages : Int,
  api_units : Int,
  soql_units : Int,
  response_bytes : Int,
) -> @execution.ExecutionCapacity? {
  installed_salesforce_reader_capacity(
    limits,
    columns,
    secret_bytes,
    describe,
    max_observation_bytes,
    binding_units,
    resource_units,
    query_pages,
    api_units,
    soql_units,
    Some(response_bytes),
  )
}

///|
fn installed_salesforce_reader_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  describe : Array[Int],
  max_observation_bytes : Int,
  binding_units : Int,
  resource_units : Int,
  query_pages : Int,
  api_units : Int,
  soql_units : Int,
  response_bytes : Int?,
) -> @execution.ExecutionCapacity? {
  if limits.length() != 16 ||
    describe.length() != 5 ||
    query_pages < 1 ||
    query_pages > 2147483647 - 2 ||
    limits[6] != query_pages + 2 {
    return None
  }
  let bytes = match response_bytes {
    None => Int::max(limits[0], describe[0])
    Some(value) => {
      if value < 0 || value > Int::max(limits[0], describe[0]) {
        return None
      }
      // Even empty/invalid bodies retain the initial refusal constructors.
      Int::max(1, value)
    }
  }
  let query_bytes = Int::min(limits[0], bytes)
  let describe_bytes = Int::min(describe[0], bytes)
  let native = @salesforce_host.native_read_construction_capacity(
    {
      max_bytes: describe_bytes,
      max_nodes: if response_bytes is None {
        describe[1]
      } else {
        Int::min(describe[1], describe_bytes)
      },
      max_depth: describe[2],
      max_fields: describe[3],
      max_name_units: describe[4],
    },
    {
      max_bytes: query_bytes,
      max_nodes: if response_bytes is None {
        limits[2]
      } else {
        Int::min(limits[2], query_bytes)
      },
      max_depth: limits[3],
      max_rows: limits[4],
      max_locator_units: limits[8],
    },
    max_observation_bytes,
    binding_units,
    resource_units,
    columns,
    query_pages,
    api_units,
    soql_units,
  )
  let capacity = @client_local_host.installed_native_source_reader_capacity(
    limits, columns, secret_bytes, native,
  )
  if response_bytes is None {
    return capacity
  }
  // Original provider response-capacity method/state, captured RowRun callback
  // and its fixed aliases:2H13R2W. The synchronous quote/Result/byte-growth
  // argument and failure carriers peak at24H64R24W; no body/tree is copied.
  let controls = @execution.preparation_execution_capacity({
    retained: {
      record_headers: 2L,
      reference_slots: 13L,
      scalar_words: 2L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    workspace: {
      record_headers: 24L,
      reference_slots: 64L,
      scalar_words: 24L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    },
    retained_nodes: 0L,
    workspace_nodes: 0L,
    retained_bytes: 0L,
    workspace_bytes: 0L,
  })
  guard capacity is Some(capacity) && controls is Some(controls) else {
    return None
  }
  @execution.add_execution_capacity(capacity, controls)
}

///|
/// This is the existing reader's next constructor DATA, not admission or a
/// replacement query. The QueryRead retains its original preflight before any
/// fallible quote; only its same body/path can later consume that parser.
#export_name("clientProgramInstalledSalesforceCurrentResponseCapacity")
pub fn client_program_installed_salesforce_current_response_capacity(
  limits : Array[Int],
  columns : Int,
  secret_bytes : Int,
  describe : Array[Int],
  max_observation_bytes : Int,
  binding_units : Int,
  resource_units : Int,
  query_pages : Int,
  api_units : Int,
  soql_units : Int,
  metadata_bytes : Int,
  read : @salesforce_catalog.QueryRead?,
  path : String,
  body : Bytes?,
  received_bytes : Int64,
  received_responses : Int,
) -> Result[@execution.ExecutionCapacity, @salesforce_catalog.QueryReadIssue] {
  if limits.length() != 16 ||
    describe.length() != 5 ||
    metadata_bytes < 0 ||
    metadata_bytes > describe[0] ||
    query_pages < 1 ||
    query_pages > 2147483645 ||
    limits[6] != query_pages + 2 {
    return Err(InvalidLimits)
  }
  let (geometry, value_nodes, query_columns) = match (read, body) {
    (Some(read), Some(body)) => {
      let geometry = match
        @salesforce_catalog.prepare_query_read_response(read, path, body) {
        Ok(geometry) => geometry
        Err(issue) => return Err(issue)
      }
      (
        Some(geometry),
        Some(
          @salesforce_catalog.query_read_response_value_node_bound(
            read, geometry,
          ),
        ),
        @salesforce_catalog.query_read_response_columns(read),
      )
    }
    (Some(_), None) => return Err(InvalidLimits)
    (None, _) => (None, None, columns)
  }
  let describe_geometry = match (read, body) {
    (None, Some(body)) =>
      installed_salesforce_describe_source_geometry(body, describe)
    _ => None
  }
  let metadata = Int::max(1, metadata_bytes)
  let query_bytes = geometry.map(g => Int::max(1, g.input_bytes)).unwrap_or(1)
  let native = @salesforce_host.native_read_construction_capacity(
    {
      max_bytes: metadata,
      max_nodes: Int::min(describe[1], metadata),
      max_depth: describe[2],
      max_fields: describe[3],
      max_name_units: describe[4],
    },
    {
      max_bytes: query_bytes,
      max_nodes: if geometry is Some(_) {
        limits[2]
      } else {
        1
      },
      max_depth: limits[3],
      max_rows: limits[4],
      max_locator_units: limits[8],
    },
    max_observation_bytes,
    binding_units,
    resource_units,
    query_columns,
    query_pages,
    api_units,
    soql_units,
    query_geometry=geometry,
    describe_geometry~,
    value_nodes=if geometry is Some(_) { value_nodes } else { Some(1) },
  )
  guard @client_local_host.installed_native_source_reader_capacity(
      limits,
      columns,
      secret_bytes,
      native,
      received=Some((received_bytes, received_responses)),
    )
    is Some(reader) else {
    return Err(InvalidLimits)
  }
  // Existing callback/peak carrier plus original query/metadata scalar slots.
  // Current DTO, two projected quantity tuples, Result/Option/error paths and
  // coordinate-maximum composition coexist only during this synchronous cut.
  guard @encode.hash_writer_live_key_inventory(0, 0) is Some(hash) else {
    return Err(InvalidLimits)
  }
  guard @execution.preparation_execution_capacity({
      retained: {
        record_headers: 6L,
        reference_slots: 24L,
        scalar_words: 4L,
        owned_utf16_units: 128L,
        owned_wire_bytes: 0L,
      },
      workspace: {
        record_headers: 32L + hash.record_headers,
        reference_slots: 88L + hash.reference_slots,
        scalar_words: 40L + hash.scalar_words,
        owned_utf16_units: hash.owned_utf16_units,
        owned_wire_bytes: hash.owned_wire_bytes,
      },
      retained_nodes: 0L,
      workspace_nodes: 0L,
      retained_bytes: 0L,
      workspace_bytes: 0L,
    })
    is Some(controls) &&
    @execution.add_execution_capacity(reader, controls) is Some(capacity) else {
    return Err(InvalidLimits)
  }
  Ok(capacity)
}

///|
// The shared Reader already retains the SAME received body and funds the
// next decoded Source String/preflight controls BEFORE calling this quote
// (installed_native_source_reader_capacity). Scan syntax only, with the exact
// existing parser limits; no Catalog, field/type admission or provider I/O.
// Only the current parser/index workspace uses this geometry. On refusal,
// keep the former complete envelope and original metadata consumer/error path.
fn installed_salesforce_describe_source_geometry(
  body : Bytes,
  limits : Array[Int],
) -> @source.JsonSourceGeometry? {
  @salesforce_host.named_describe_response_geometry(body, {
    max_bytes: limits[0],
    max_nodes: limits[1],
    max_depth: limits[2],
    max_fields: limits[3],
    max_name_units: limits[4],
  })
}
