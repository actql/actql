///|
/// The selected configurations retain their original Native/Broad owner.
#export_name("clientProgramCapturedNativeConfiguration")
pub fn client_program_captured_native_configuration(
  setup : @duckdb_host.NativeHostConfiguration,
) -> @duckdb_host.CaptureConfiguration {
  @duckdb_host.native_capture_configuration(setup)
}

///|
#export_name("clientProgramCapturedBroadConfiguration")
pub fn client_program_captured_broad_configuration(
  setup : @duckdb_host.BroadHostConfiguration,
) -> @duckdb_host.CaptureConfiguration {
  @duckdb_host.broad_capture_configuration(setup)
}

///|
#export_name("clientProgramCapturedAcquisitionCapacity")
pub fn client_program_captured_acquisition_capacity(
  setup : @duckdb_host.CaptureConfiguration,
) -> Result[Array[Int64], @resources.LedgerIssue] {
  match @duckdb_host.configured_capture_capacity(setup) {
    Some(capacity) => Ok([capacity.retained_bytes, capacity.execution_bytes])
    None => Err(InvalidLimits)
  }
}

///|
#export_name("clientProgramInstalledDuckDBCaptureCapacity")
pub fn client_program_installed_duckdb_capture_capacity(
  selected : @duckdb_host.CaptureConfiguration,
) -> @client_local_host.ClientInstalledCaptureCapacity? {
  @client_local_host.installed_duckdb_capture_capacity(selected)
}

///|
#export_name("clientProgramInstalledRowCaptureCapacity")
pub fn client_program_installed_row_capture_capacity(
  selected : @client_row_source_host.RowAcquisition,
) -> @client_local_host.ClientInstalledCaptureCapacity? {
  @client_local_host.installed_row_capture_capacity(selected)
}

///|
#export_name("clientProgramInstalledPendingDuckDBCaptureCapacity")
pub fn client_program_installed_pending_duckdb_capture_capacity(
  pending : @client_local_host.ClientDuckDBCaptureCapacity,
) -> @client_local_host.ClientInstalledCaptureCapacity {
  @client_local_host.installed_pending_duckdb_capture_capacity(pending)
}

///|
#export_name("clientProgramPrepareMultiCapturedLocalInstalledLedger")
pub fn client_program_prepare_multi_captured_local_installed_ledger(
  prepared : @publication_host.PreparedClientProgram,
  capacities : Array[@client_local_host.ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  @client_local_host.prepare_multi_captured_local_installed_ledger(
    prepared, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
    values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramPrepareSerializationCapturedLedger")
pub fn client_program_prepare_serialization_captured_ledger(
  prepared : @publication_host.PreparedClientProgram,
  task : Int,
  capacity : @client_local_host.ClientInstalledCaptureCapacity,
  transport_bytes : Int64,
  transport_execution_bytes : Int64,
  prefix_retained_bytes : Int64,
  prefix_execution_bytes : Int64,
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  @client_local_host.prepare_serialization_captured_ledger(
    prepared, task, capacity, transport_bytes, transport_execution_bytes, prefix_retained_bytes,
    prefix_execution_bytes, installed_contracts, values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramPrepareMultiCapturedEffectInstalledLedger")
pub fn client_program_prepare_multi_captured_effect_installed_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  capacities : Array[@client_local_host.ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  @client_local_host.prepare_multi_captured_effect_installed_ledger(
    prepared, capacities, transport_bytes, transport_execution_bytes, installed_contracts,
    values_body, fragment_body, ordered_body,
  )
}

///|
/// Read the existing Run ledger for bounded installed-Host diagnostics.
#export_name("clientProgramMultiCapturedLedgerUsage")
pub fn client_program_multi_captured_ledger_usage(
  ledger : @resources.Ledger,
) -> Array[Int64] {
  @resources.ledger_usage_values(@resources.ledger_usage(ledger))
}

///|
#export_name("clientProgramPrepareMultiCapturedLocalLedger")
pub fn client_program_prepare_multi_captured_local_ledger(
  prepared : @publication_host.PreparedClientProgram,
  acquisitions : Array[@duckdb_host.NativeHostConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  @client_local_host.prepare_multi_captured_local_ledger(
    prepared, acquisitions, transport_bytes, transport_execution_bytes, installed_contracts,
    values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramOpenMultiCapturedLocalHost")
pub fn client_program_open_multi_captured_local_host(
  prepared : @publication_host.PreparedClientProgram,
  sources : Array[@query.CapturedInputSource],
  ledger : @resources.Ledger,
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  if sources.length() != 2 {
    return None
  }
  @client_local_host.open_multi_captured_local_host(
    prepared,
    [(0, sources[0]), (1, sources[1])],
    ledger,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    provider_factory=installed_client_family_providers,
  )
}

///|
/// The two checked captures keep their existing ledger while the selected
/// Local task writes its Relation output to the installed retained Store.
#export_name("clientProgramOpenMultiCapturedLocalRetainedHost")
pub fn client_program_open_multi_captured_local_retained_host(
  prepared : @publication_host.PreparedClientProgram,
  sources : Array[@query.CapturedInputSource],
  ledger : @resources.Ledger,
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  if sources.length() != 2 {
    return None
  }
  @client_local_host.open_multi_captured_local_retained_host(
    prepared,
    [(0, sources[0]), (1, sources[1])],
    ledger,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    provider_factory=installed_client_family_providers,
  )
}

///|
#export_name("clientProgramPrepareMultiCapturedEffectLocalLedger")
pub fn client_program_prepare_multi_captured_effect_local_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  acquisitions : Array[@duckdb_host.NativeHostConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  @client_local_host.prepare_multi_captured_effect_local_ledger(
    prepared, acquisitions, transport_bytes, transport_execution_bytes, installed_contracts,
    values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramOpenMultiCapturedLocalEffectHost")
pub fn client_program_open_multi_captured_local_effect_host(
  prepared : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  ledger : @resources.Ledger,
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> ClientLocalEffectHost? {
  if sources.length() != 2 {
    return None
  }
  open_client_local_effect_host(
    prepared,
    None,
    installed_contracts,
    values_body,
    1L,
    0L,
    0L,
    0L,
    fragment_body~,
    ordered_body~,
    captured_sources=[(0, sources[0]), (1, sources[1])],
    acquisition_ledger=Some(ledger),
  )
}

///|
#export_name("clientProgramPrepareMultiCapturedEffectAcquisitionLedger")
pub fn client_program_prepare_multi_captured_effect_acquisition_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  acquisitions : Array[@duckdb_host.CaptureConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  @client_local_host.prepare_multi_captured_effect_acquisition_ledger(
    prepared, acquisitions, transport_bytes, transport_execution_bytes, installed_contracts,
    values_body, fragment_body, ordered_body,
  )
}

///|
#export_name("clientProgramPrepareMultiCapturedLocalAcquisitionLedger")
pub fn client_program_prepare_multi_captured_local_acquisition_ledger(
  prepared : @publication_host.PreparedClientProgram,
  acquisitions : Array[@duckdb_host.CaptureConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : @client_local_host.ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  @client_local_host.prepare_multi_captured_local_acquisition_ledger(
    prepared, acquisitions, transport_bytes, transport_execution_bytes, installed_contracts,
    values_body, fragment_body, ordered_body,
  )
}
