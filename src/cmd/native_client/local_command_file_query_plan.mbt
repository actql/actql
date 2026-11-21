///|
// Exact original Project target, not an Account/permission merge. This private
// selector runs under the same backed Query construction frontier.
fn local_command_file_row(
  original : LocalProjectMockDeclarations,
  connector : String,
  resource : String,
) -> (LocalProjectMockSourceDeclaration, LocalProjectMockRowBinding) raise ClientStop {
  if original.closing || original.retired {
    stop("LocalSourceInputSelectionUnavailable")
  }
  for declaration in original.sources {
    if declaration._retained_connection == connector {
      for row in declaration._retained_rows {
        if row.view.resource == resource {
          return (declaration, row)
        }
      }
    }
  }
  stop("LocalSourceInputSelectionUnavailable")
}

///|
// Preserve the actual typed primary before its stable public stage projection.
// No Source body, credential, path or opaque original is stringified here.
fn[T] local_command_query_preparation_result(
  control : LocalCommandPreparationOriginal,
  result : Result[T, LocalCommandPreparationIssue],
  message : String,
) -> T raise ClientStop {
  match result {
    Ok(value) => value
    Err(issue) => {
      control.retain_primary(issue)
      stop(message)
    }
  }
}

///|
fn[I] prepare_local_native_file_request_module(
  control : LocalCommandPreparationOriginal,
  parent : @local_values.ClientRequestPreparation[I],
  input : I,
  prepared : @run_host.PreparedClientProgram,
  request : @run_host.ClientRequestIdentity,
  original : LocalProjectMockDeclarations,
  contracts : @local_values.ClientInstalledSequenceContracts,
  assets : @run_host.ClientLocalProductAssets,
  bodies : (String, String)?,
) -> (
  @local_values.ClientInstalledWholeSourceCapacity?,
  LocalCommandFileSources,
) raise ClientStop {
  let count = @run_host.prepared_client_acquisition_count(prepared)
  if count != 1 {
    let route = @local_values.select_installed_source_input(
      prepared, request, 0, 0,
    ).unwrap_or_else(() => stop("LocalSourceInputSelectionUnavailable"))
    if route is @sourceviews.WholeInputRoute(_) {
      return (
        None,
        prepare_local_native_whole_files_request_module(
          control, parent, input, prepared, request, original, contracts, assets,
        ),
      )
    }
  }
  if count == 1 {
    let route = @local_values.select_installed_source_input(
      prepared, request, 0, 0,
    ).unwrap_or_else(() => stop("LocalSourceInputSelectionUnavailable"))
    if route is @sourceviews.WholeInputRoute(source) {
      let source_input = @sourceviews.mode_input(
        @sourceviews.source_acquisition_mode(source),
      )
      let subject = @sourceviews.declaration(source_input)
      // A lone typed listing uses the ordered Whole planner as a JOIN does.
      // The catalog check itself borrows the original before that Plan quote.
      if @compiler_environment.source_request_file_listing(
          @sourceviews.selected_contract(source_input),
        )
        is Some(_) {
        return (
          None,
          prepare_local_native_whole_files_request_module(
            control, parent, input, prepared, request, original, contracts, assets,
          ),
        )
      }
      let (declaration, row) = local_command_file_row(
        original,
        subject.connector,
        subject.resource,
      )
      let capacity = prepare_local_native_whole_file_request_module(
        parent,
        input,
        prepared,
        request,
        declaration._retained_declaration,
        row,
        contracts,
        assets,
      )
      return (Some(capacity), Whole(declaration, row))
    }
  }
  guard bodies is Some((query, evidence)) else {
    stop("LocalQueryContractsNotInstalled")
  }
  let (protocols, direct) = local_command_query_preparation_result(
    control,
    @local_values.admit_request_query_acquisition_contracts(
      parent, input, query, evidence,
    ).map_err(issue => CommandBusinessQueryPlan(issue)),
    "LocalSourceContractsUnavailable",
  )
  if @run_host.client_direct_acquisition_occurrence_count(direct) != count {
    stop("LocalSourceInputSelectionUnavailable")
  }
  let sources : Array[@local_host.NativeRelationFileQuerySource] = []
  let capacities : Array[@local_values.ClientInstalledCaptureCapacity] = []
  let transport : Array[Int64] = []
  let executing : Array[Int64] = []
  for index in 0..<count {
    guard @run_host.client_direct_acquisition_occurrence_at(direct, index)
      is Some((stage, input_index, task)) &&
      task == index &&
      @run_host.client_direct_acquisition_occurrence_subject(direct, index)
      is Some(subject) else {
      stop("LocalSourceInputSelectionUnavailable")
    }
    let target = @sourceviews.declaration(subject.source)
    let (declaration, row) = local_command_file_row(
      original,
      target.connector,
      target.resource,
    )
    let requirement = local_command_query_preparation_result(
      control,
      @local_values.prepare_local_query_requirement(
        prepared,
        stage,
        input_index,
        contracts,
        assets.values,
        Some(assets.fragment),
        assets.ordered,
      ).map_err(issue => CommandBusinessQueryRequirement(issue)),
      "LocalSourceRequirementUnavailable",
    )
    let selected = local_command_query_preparation_result(
      control,
      @row_host.prepare_row_source(
        requirement,
        declaration._retained_declaration,
      ).map_err(issue => CommandBusinessQueryRow(@row_host.Source(issue))),
      "LocalSourceInputSelectionUnavailable",
    )
    let acquisition = local_command_query_preparation_result(
      control,
      @row_host.prepare_declared_row_acquisition_with_contracts(
        selected,
        declaration._retained_declaration.connector_registration,
        protocols,
      ).map_err(issue => CommandBusinessQueryRow(issue)),
      "LocalSourceAcquisitionUnavailable",
    )
    let capacity = @local_values.installed_provider_row_capture_capacity(
      acquisition,
      Some(row.provider.capacity()),
    ).unwrap_or_else(() => stop("LocalSourceCapacityUnavailable"))
    sources.push({
      declaration: declaration._retained_declaration,
      acquisition,
      provider: row.provider,
      selection: row._retained_selection,
      limits: row.limits,
    })
    capacities.push(capacity)
    transport.push(row.limits.page.max_bytes.to_int64())
    executing.push(row.limits.page.max_bytes.to_int64())
  }
  let plan = local_command_query_preparation_result(
    control,
    @local_values.prepare_installed_managed_capture_plan(
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
    "LocalSourcePlanUnavailable",
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
  (None, Query(sources))
}
