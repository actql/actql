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
