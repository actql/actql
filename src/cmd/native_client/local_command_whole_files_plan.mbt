///|
// The complete-input branch is selected from the SAME checked Request before
// Query construction. Preserve each original stage/input; no task/index
// equality, Query failure fallback, Source reparse or new permission exists.
fn[I] prepare_local_native_whole_files_request_module(
  control : LocalCommandPreparationOriginal,
  parent : @local_values.ClientRequestPreparation[I],
  input : I,
  prepared : @run_host.PreparedClientProgram,
  request : @run_host.ClientRequestIdentity,
  original : LocalProjectMockDeclarations,
  contracts : @local_values.ClientInstalledSequenceContracts,
  assets : @run_host.ClientLocalProductAssets,
) -> LocalCommandFileSources raise ClientStop {
  let (direct, originals) = local_command_query_preparation_result(
    control,
    @local_values.reserve_request_whole_source_construction(
      parent, input, request,
    ).map_err(issue => CommandBusinessQueryPlan(issue)),
    "LocalSourceWholeConstructionUnavailable",
  )
  let sources : Array[@local_host.NativeRelationFileWholeSource] = []
  let capacities : Array[@local_values.ClientInstalledWholeSourceCapacity] = []
  let transport : Array[Int64] = []
  let executing : Array[Int64] = []
  for index in 0..<originals.length() {
    let source = originals[index]
    guard @run_host.client_direct_acquisition_occurrence_at(direct, index)
      is Some((stage, source_index, _)) &&
      @run_host.client_source_acquisition_matches_program(
        prepared, stage, source_index, source,
      ) else {
      stop("LocalSourceInputSelectionUnavailable")
    }
    let target = @sourceviews.declaration(
      @sourceviews.mode_input(@sourceviews.source_acquisition_mode(source)),
    )
    let (declaration, row) = local_command_file_row(
      original,
      target.connector,
      target.resource,
    )
    let page = row.limits.page
    let capacity = local_command_query_preparation_result(
      control,
      @local_values.prepare_installed_whole_source_capacity(
        prepared,
        source,
        declaration._retained_declaration,
        contracts,
        @local_values.installed_row_input_policy(
          page.max_rows,
          page.max_bytes,
          page.max_nodes,
          page.max_depth,
          page.max_rows,
        ),
        Some(row.provider.capacity()),
      ).map_err(issue => CommandBusinessQueryCapture(issue)),
      "LocalSourceWholeCapacityUnavailable",
    )
    capacities.push(capacity)
    sources.push({
      declaration: declaration._retained_declaration,
      capacity,
      provider: row.provider,
      selection: row._retained_selection,
      limits: row.limits,
    })
    transport.push(page.max_bytes.to_int64())
    executing.push(page.max_bytes.to_int64())
  }
  let plan = local_command_query_preparation_result(
    control,
    @local_values.prepare_installed_managed_whole_sources_plan(
      prepared,
      request,
      capacities,
      transport,
      executing,
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      retained_output=false,
      provider_factory=native_request_provider_factory,
      runtime_admission=true,
    ).map_err(issue => CommandBusinessQueryCapture(issue)),
    "LocalSourceWholePlanUnavailable",
  )
  let limits = local_command_query_preparation_result(
    control,
    @local_values.request_program_compilation_limits(parent, input).map_err(issue => {
      CommandBusinessQueryPlan(issue)
    }),
    "LocalCompilerLimitsUnavailable",
  )
  local_command_query_preparation_result(
    control,
    @local_values.prepare_request_capture_module_body(
      parent,
      input,
      plan,
      manifests=native_request_manifests,
      compilation_limits=limits,
      provider_factory=native_request_provider_factory,
    ).map_err(issue => CommandBusinessQueryPlan(issue)),
    "LocalModulePreparationUnavailable",
  )
  WholeSet(sources)
}
