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
  if limits.length() != 16 ||
    describe.length() != 5 ||
    query_pages < 1 ||
    query_pages > 2147483647 - 2 ||
    limits[6] != query_pages + 2 {
    return None
  }
  let native = @salesforce_catalog.native_read_construction_capacity(
    {
      max_bytes: describe[0],
      max_nodes: describe[1],
      max_depth: describe[2],
      max_fields: describe[3],
      max_name_units: describe[4],
    },
    {
      max_bytes: limits[0],
      max_nodes: limits[2],
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
  @client_local_host.installed_native_source_reader_capacity(
    limits, columns, secret_bytes, native,
  )
}
