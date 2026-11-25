///|
// Resolve Task locators relative to the original registry, as the public
// Project contract requires. The bounded Reader remains authoritative for
// missing, symlinked, changed, oversized and physically unclosed files.
fn local_project_registry_document(
  project : LocalProjectConfiguration,
  registry_path : String,
  path : String,
) -> Result[String, @files.NativeBoundedTextFailure] raise ClientStop {
  let registry = local_project_absolute_path(project.directory, registry_path)
  let directory = local_product_selected_location(Some(registry), None).parent_path
  local_project_required_declaration({ ..project, directory, }, Some(path))
}

///|
// Both installed and Mock Task declarations retain the exact registry
// locator and Common's typed selection before a Provider is consulted.
fn local_project_read_selected_model_task(
  project : LocalProjectConfiguration,
  registry_path : String,
  registry : @run_host.ClientProjectModelRegistry,
  index : Int,
  limits : @compiler_environment.ModelTaskLimits,
  fund_document? : Bool = false,
) -> Result[
  (
    String,
    @compiler_environment.PublicModelTaskDeclaration,
    @run_host.ClientProjectModelTaskSelection,
  ),
  @files.NativeBoundedTextFailure,
] raise ClientStop {
  let (name, path) = registry
    .task_at(index)
    .unwrap_or_else(() => stop("InvalidProjectBindings"))
  let wire = match
    local_project_registry_document(project, registry_path, path) {
    Ok(value) => value
    Err(original) => return Err(original)
  }
  let format = if path.has_suffix(".json") { "json" } else { "yaml" }
  let construction = if fund_document {
    let extent = @compiler_environment.public_model_task_document_construction_extent(
      wire, format, limits,
    ).unwrap_or_else(() => stop("LocalCommandPreparationLayoutUnavailable"))
    let peak = local_project_model_extent_bytes(extent)
    // This original Read covers the complete synchronous constructor,
    // including its returned candidate, in its working window. The candidate
    // stays private until its retained inventory is admitted below.
    local_host_metadata_prepare(0L, peak)
    Some(peak)
  } else {
    None
  }
  let task = @compiler_environment.read_public_model_task_document(
    wire, format, limits,
  ).unwrap_or_else(() => stop("InvalidProjectBindings"))
  if construction is Some(peak) {
    let extent = @compiler_environment.public_model_task_declaration_retained_extent(
      task,
    ).unwrap_or_else(() => stop("LocalCommandPreparationLayoutUnavailable"))
    let retained = local_project_model_extent_bytes(extent)
    if retained > peak {
      stop("LocalCommandPreparationLayoutUnavailable")
    }
    // Admit the actual retained candidate before exposing its original. The
    // Read's working high-water remains with that same owner until close.
    local_host_metadata_prepare(retained, retained)
  }
  if @compiler_environment.public_model_task_declaration_identity(task).0 !=
    name {
    stop("InvalidProjectBindings")
  }
  let selection = @run_host.select_client_project_model_task(
    registry,
    task,
    limits.max_work,
  ).unwrap_or_else(() => stop("InvalidProjectBindings"))
  Ok((name, task, selection))
}

///|
// The selected document and closed provider selector stay on this Command's
// Project original. The installed configuration and Account are separate.
priv struct LocalProjectPortableModel {
  registry : @run_host.ClientProjectModelRegistry
  tasks : Array[
    (
      String,
      @compiler_environment.PublicModelTaskDeclaration,
      @run_host.ClientProjectModelTaskSelection,
    ),
  ]
  mut configurations : Array[@local_host.NativeModelHttpConfiguration]?
}

///|
fn local_project_model_extent_bytes(
  extent : @compiler_environment.RegistryConstructionExtent,
) -> Int64 raise ClientStop {
  local_host_metadata_price({
    record_headers: extent.record_headers,
    reference_slots: extent.reference_slots,
    scalar_words: extent.scalar_words,
    owned_utf16_units: extent.owned_utf16_units,
    owned_wire_bytes: extent.owned_wire_bytes,
  })
}

///|
fn local_project_model_fund_extent(
  extent : @compiler_environment.RegistryConstructionExtent,
) -> Unit raise ClientStop {
  let bytes = local_project_model_extent_bytes(extent)
  local_host_metadata_prepare(bytes, bytes)
}

///|
fn local_project_read_funded_model_registry(
  owner : LocalCommandPreparationOriginal,
  wire : String,
) -> @run_host.ClientProjectModelRegistry raise ClientStop {
  match
    @run_host.admit_funded_client_project_model_registry(
      wire,
      extent => {
        guard @execution.preparation_representation_cost(extent) is Some(bytes) else {
          return Err(CommandUnavailable)
        }
        owner.prepare_host_metadata(bytes, bytes)
      },
      _ => CommandApplication("InvalidProjectBindings"),
    ) {
    Ok(value) => value
    Err(issue) => {
      owner.retain_primary(issue)
      stop("InvalidProjectBindings")
    }
  }
}

///|
fn local_project_read_portable_model(
  project : LocalProjectConfiguration,
  path : String,
  registry : @run_host.ClientProjectModelRegistry,
) -> Result[LocalProjectPortableModel, @files.NativeBoundedTextFailure] raise ClientStop {
  let count = registry.task_count()
  if count <= 0 || count > @run_host.client_local_model_configuration_limit() {
    stop("LocalProjectBindingsUnavailable")
  }
  let slots = count.to_int64()
  let retained = local_host_metadata_price(
    local_host_metadata_units(4L + slots, 4L + 4L * slots, 4L, 0L),
  )
  local_host_metadata_prepare(retained, retained)
  let tasks = Array(capacity=count)
  for index in 0..<count {
    match
      local_project_read_selected_model_task(
        project,
        path,
        registry,
        index,
        local_project_mock_task_limits(),
        fund_document=true,
      ) {
      Err(issue) => return Err(issue)
      Ok(task) => tasks.push(task)
    }
  }
  Ok({ registry, tasks, configurations: None, })
}

///|
fn LocalProjectPortableModel::checked_environment(
  self : Self,
  original : LocalCommandPreparationOriginal,
  base : @checked.CheckEnvironment,
  capture : @local_host.NativeLocalJournalCapture,
  settings : LocalHostSettings,
) -> @checked.CheckEnvironment raise ClientStop {
  guard !original.closing &&
    !original.closed &&
    original.primary is None &&
    self.configurations is None &&
    settings.model_http_installations is Some(installed) else {
    stop("LocalProjectBindingsUnavailable")
  }
  let limits = local_project_mock_task_limits()
  let configurations = original.read_model_http_configurations(
    capture, installed, limits,
  )
  let slots = self.tasks.length().to_int64()
  let controls = local_host_metadata_price(
    local_host_metadata_units(10L + slots, 16L + 4L * slots, 10L, 0L),
  )
  local_host_metadata_prepare(controls, controls)
  let tasks = Array(capacity=self.tasks.length())
  let bindings = Array(capacity=self.tasks.length())
  for (name, declaration, selection) in self.tasks {
    guard @run_host.client_project_model_task_selection_for(
        selection,
        self.registry,
        declaration,
      )
      is Some((provider, _, _)) else {
      stop("LocalProjectBindingsUnavailable")
    }
    let mut declared = false
    for index in 0..<self.registry.provider_count() {
      if self.registry.provider_at(index)
        is Some((original_name, "openai", None)) &&
        original_name == provider {
        declared = true
        break
      }
    }
    // Only the protected installation selects the credential and route.
    if !declared {
      stop("LocalProjectBindingsUnavailable")
    }
    let mut selected = None
    for index, candidate in installed {
      if candidate.task_id == name && candidate.provider_id == provider {
        selected = Some(configurations[index])
        break
      }
    }
    guard selected is Some(configuration) else {
      stop("LocalProjectBindingsUnavailable")
    }
    let extent = @compiler_environment.public_model_task_normalization_construction_extent(
      declaration, limits,
    ).unwrap_or_else(() => stop("LocalCommandPreparationLayoutUnavailable"))
    let defaults = configuration.provider_defaults()
    let (resolution, _) = @run_host.client_model_provider_defaults_resolution_extents(
      defaults,
      @compiler_environment.public_model_task_declaration_limits(declaration).1,
    )
    local_project_model_fund_extent(resolution)
    local_project_model_fund_extent(extent)
    guard @run_host.normalize_client_project_model_task(
        selection,
        self.registry,
        declaration,
        defaults,
        limits,
      )
      is Ok(task) &&
      configuration.matches_project_task(task) else {
      stop("LocalModelHttpInstallationRefused")
    }
    let (_, task_cid, _, _) = @compiler_environment.normalized_public_model_task_materials(
      task,
    )
    if !(capture.authorize_in_original_read({
        principal: settings.principal,
        connection: provider,
        resource: task_cid,
        operation: "infer",
      })
      is Ok(Allow(_))) {
      stop("LocalModelHttpAuthorizationDenied")
    }
    tasks.push(task)
    bindings.push(configuration)
  }
  let base_wire = @checked.checking_environment_wire(base)
  guard @run_host.client_project_model_environment_projection_inventory(
      base_wire, tasks,
    )
    is Some((projection_limits, projection_quote)) else {
    stop("LocalCommandPreparationLayoutUnavailable")
  }
  let bytes = local_host_metadata_price(projection_quote)
  local_host_metadata_prepare(bytes, bytes)
  guard @compiler_environment.project_public_model_task_environment(
      base_wire, tasks, projection_limits,
    )
    is Ok((body, cid, _)) else {
    stop("InvalidProjectBindings")
  }
  local_host_metadata_prepare(0L, local_host_metadata_entry_bytes)
  let read_quote = @run_host.client_project_model_environment_read_inventory(
    body,
  ).unwrap_or_else(() => stop("LocalCommandPreparationLayoutUnavailable"))
  let bytes = local_host_metadata_price(read_quote)
  local_host_metadata_prepare(bytes, bytes)
  guard @run_host.admit_client_check_environment_wire(body, cid) is Some(wire) &&
    @compiler_environment.model_tasks_admission_construction_extent(wire)
    is Some(task_quote) else {
    stop("InvalidLocalCheckEnvironment")
  }
  local_project_model_fund_extent(task_quote)
  local_project_model_fund_extent(
    @run_host.client_check_environment_wrapper_construction_extent(true),
  )
  guard @decode.open_object(@compiler_environment.host_policy(wire))
    is Ok(policy) &&
    @run_host.admit_client_check_environment_from_wire_with_numeric_profile_cid(
      wire,
      {
        text_time: @decode.lookup(policy, "text_time_evaluation") is Some(_),
        veca: false,
      },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
      @numeric.cid(@numeric.builtin_profile()),
    )
    is Some(environment) else {
    stop("InvalidLocalCheckEnvironment")
  }
  local_host_result(capture.check_current_in_original_read())
  self.configurations = Some(bindings)
  environment
}
