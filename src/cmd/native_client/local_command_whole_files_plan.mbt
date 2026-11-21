///|
// Borrow the listing already installed for this Project and checked resource.
// The Project retains the issuer; the existing Work retains the physical Read.
fn local_command_file_listing(
  original : LocalProjectMockDeclarations,
  connector : String,
  resource : String,
) -> (
  LocalProjectMockSourceDeclaration,
  @row_file.NativeRelationFileListingProvider,
  LocalProjectMockFileBinding,
)? {
  guard !original.closing &&
    !original.retired &&
    original.file_sources is Some(sources) else {
    return None
  }
  for source in sources {
    let declaration = source._retained_original
    if declaration._retained_connection == connector &&
      source.references.known is Some(_) {
      for (provider, binding) in source._retained_listings {
        if binding.listing.resource == resource {
          return Some((declaration, provider, binding))
        }
      }
    }
  }
  None
}

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
    let source_input = @sourceviews.mode_input(
      @sourceviews.source_acquisition_mode(source),
    )
    let target = @sourceviews.declaration(source_input)
    let (declaration, provider, selection, limits, listing) = if @compiler_environment.source_request_file_listing(
        @sourceviews.selected_contract(source_input),
      )
      is Some(_) {
      guard local_command_file_listing(
          original,
          target.connector,
          target.resource,
        )
        is Some((declaration, listing, binding)) else {
        stop("LocalSourceInputSelectionUnavailable")
      }
      (
        declaration,
        binding._retained_provider,
        binding._retained_selection,
        binding._retained_limits,
        Some(listing),
      )
    } else {
      let (declaration, row) = local_command_file_row(
        original,
        target.connector,
        target.resource,
      )
      (declaration, row.provider, row._retained_selection, row.limits, None)
    }
    let page = limits.page
    let provider_capacity = match listing {
      Some(value) => value.capacity()
      None => provider.capacity()
    }
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
        Some(provider_capacity),
      ).map_err(issue => CommandBusinessQueryCapture(issue)),
      "LocalSourceWholeCapacityUnavailable",
    )
    capacities.push(capacity)
    sources.push({
      declaration: declaration._retained_declaration,
      capacity,
      provider,
      selection,
      limits,
      listing,
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
