///|
/// A trusted Site mapping from a checked logical Source to a preconfigured
/// read-only database. This is not decoded from Program or Run materials.
struct NativeReadOnlySourceBinding {
  source_ref : String
  source_contract_cid : String
  path : String
  memory_bytes : Int64
}

///|
pub(all) enum NativeReadOnlySourceIssue {
  InvalidConfiguration
  ForeignSource
  Database(@native_duckdb.NativeDuckDBIssue)
  AcquisitionHost(@duckdb_host.NativeHostIssue)
}

///|
/// Provision the physical mapping from Site-owned configuration. The
/// configured Source includes the Catalog-selected contract, not a caller's
/// replacement Source identity. No physical I/O happens at preparation.
pub fn prepare_native_read_only_source_binding(
  trusted_source : @duckdb_host.NativeHostConfiguration,
  database_path : String,
  memory_bytes : Int64,
) -> Result[NativeReadOnlySourceBinding, NativeReadOnlySourceIssue] {
  if database_path.is_empty() ||
    database_path.length() > 4096 ||
    memory_bytes < 1L {
    return Err(InvalidConfiguration)
  }
  let (source_ref, source_contract_cid) = @duckdb_host.configured_native_host_source(
    trusted_source,
  )
  Ok({ source_ref, source_contract_cid, path: database_path, memory_bytes, })
}

///|
/// Reject an unconfigured logical Source before opening its physical file.
/// The existing acquisition runtime owns queries, completion and close;
/// this boundary only resolves the Site's path and enforces read-only open.
pub fn open_native_read_only_source_acquisition(
  binding : NativeReadOnlySourceBinding,
  setup : @duckdb_host.NativeHostConfiguration,
  library : @native_duckdb.Library,
  nonce : String,
) -> Result[NativeAcquisitionRuntime, NativeReadOnlySourceIssue] {
  let source = @duckdb_host.configured_native_host_source(setup)
  if source.0 != binding.source_ref || source.1 != binding.source_contract_cid {
    return Err(ForeignSource)
  }
  let database = match
    library.open_database(
      {
        ..@native_duckdb.restricted_open_limits(binding.memory_bytes),
        read_only: true,
      },
      path=binding.path,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Database(issue))
  }
  start_native_acquisition_runtime(setup, nonce, database).map_err(issue => {
    AcquisitionHost(issue)
  })
}
