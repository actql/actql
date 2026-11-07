///|
// The original Project's bounded documents, not an installed Host or grant.
// The existing command Read owns their physical lifetime. The profile's
// nominal self-reference must retire before that Read can acknowledge close.
priv struct LocalProjectMockDeclarations {
  _retained_project : LocalProjectConfiguration
  profile : @run_host.ClientProjectProfileSelection
  _retained_connections : @run_host.ClientProjectConnections
  _retained_catalog : @run_host.ClientProjectCatalog
  _retained_registry : @run_host.ClientProjectModelRegistry
  _retained_data : String
  _retained_tasks : Array[
    (
      @compiler_environment.PublicModelTaskDeclaration,
      @run_host.ClientProjectModelTaskSelection,
      String,
    ),
  ]
}

///|
fn LocalProjectMockDeclarations::retire(self : Self) -> Unit raise ClientStop {
  @run_host.retire_client_project_profile(self.profile).unwrap_or_else(() => {
    stop("LocalProjectBindingsUnavailable")
  })
}

///|
fn local_project_required_declaration(
  project : LocalProjectConfiguration,
  path : String?,
) -> Result[String, @files.NativeBoundedTextFailure] raise ClientStop {
  match local_project_read_declaration(project, path) {
    Err(original) => Err(original)
    Ok(Some(wire)) => Ok(wire)
    Ok(None) => stop("InvalidProjectBindings")
  }
}

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
// Read and select original DATA through the existing Common owners. Limits
// belong to the selected caller; parsing this input installs no Source, Model,
// reviewer, Account or capacity. The caller retains a successful result before
// fallible assembly and retires it before its original command Read closes.
fn local_project_read_mock_declarations(
  project : LocalProjectConfiguration,
  task_limits : @compiler_environment.ModelTaskLimits,
) -> Result[LocalProjectMockDeclarations, @files.NativeBoundedTextFailure] raise ClientStop {
  if project.metadata.lock_file() is Some(_) {
    stop("LocalProjectBindingsUnavailable")
  }
  let profile = @run_host.select_client_project_profile(
    Some(project.metadata),
    project.profile,
    task_limits.max_work,
  ).unwrap_or_else(() => stop("InvalidProjectBindings"))
  let mut transferred = false
  defer (if !transferred {
    ignore(@run_host.retire_client_project_profile(profile))
  })
  guard profile.selected_profile() == Ok(Some("mock")) else {
    stop("LocalProjectBindingsUnavailable")
  }
  let connectors_wire = match
    local_project_required_declaration(
      project,
      project.metadata.connectors_file(),
    ) {
    Ok(value) => value
    Err(original) => return Err(original)
  }
  let connections = @run_host.admit_client_project_connections(connectors_wire).unwrap_or_else(() => {
      stop("InvalidProjectBindings")
    },
  )
  let registry_path = project.metadata
    .model_tasks_file()
    .unwrap_or_else(() => stop("InvalidProjectBindings"))
  let registry_wire = match
    local_project_required_declaration(project, Some(registry_path)) {
    Ok(value) => value
    Err(original) => return Err(original)
  }
  let registry = @run_host.admit_client_project_model_registry(registry_wire).unwrap_or_else(() => {
      stop("InvalidProjectBindings")
    },
  )
  let catalog_path = profile
    .mock_catalog_file()
    .unwrap_or_else(() => stop("InvalidProjectBindings"))
  let catalog_wire = match
    local_project_required_declaration(project, catalog_path) {
    Ok(value) => value
    Err(original) => return Err(original)
  }
  let catalog = @run_host.admit_client_project_catalog(catalog_wire).unwrap_or_else(() => {
      stop("InvalidProjectBindings")
    },
  )
  let data_path = profile
    .mock_data_file()
    .unwrap_or_else(() => stop("InvalidProjectBindings"))
  let data = match local_project_required_declaration(project, data_path) {
    Ok(value) => value
    Err(original) => return Err(original)
  }
  let tasks : Array[
    (
      @compiler_environment.PublicModelTaskDeclaration,
      @run_host.ClientProjectModelTaskSelection,
      String,
    ),
  ] = []
  for index in 0..<registry.task_count() {
    let (name, path) = registry
      .task_at(index)
      .unwrap_or_else(() => stop("InvalidProjectBindings"))
    let wire = match
      local_project_registry_document(project, registry_path, path) {
      Ok(value) => value
      Err(original) => return Err(original)
    }
    let format = if path.has_suffix(".json") { "json" } else { "yaml" }
    let task = @compiler_environment.read_public_model_task_document(
      wire, format, task_limits,
    ).unwrap_or_else(() => stop("InvalidProjectBindings"))
    if @compiler_environment.public_model_task_declaration_identity(task).0 !=
      name {
      stop("InvalidProjectBindings")
    }
    let selection = @run_host.select_client_project_model_task(
      registry,
      task,
      task_limits.max_work,
    ).unwrap_or_else(() => stop("InvalidProjectBindings"))
    let mut answer_path = None
    for
      answer_index in 0..<profile
      .mock_answer_count()
      .unwrap_or_else(() => stop("InvalidProjectBindings")) {
      let (answer_task, path) = profile
        .mock_answer_at(answer_index)
        .unwrap_or_else(() => stop("InvalidProjectBindings"))
        .unwrap_or_else(() => stop("InvalidProjectBindings"))
      if answer_task == name {
        answer_path = Some(path)
      }
    }
    let answers = match
      local_project_required_declaration(project, answer_path) {
      Ok(value) => value
      Err(original) => return Err(original)
    }
    tasks.push((task, selection, answers))
  }
  // Answer declarations without an original registered Task are not ignored.
  for
    index in 0..<profile
    .mock_answer_count()
    .unwrap_or_else(() => stop("InvalidProjectBindings")) {
    let (name, _) = profile
      .mock_answer_at(index)
      .unwrap_or_else(() => stop("InvalidProjectBindings"))
      .unwrap_or_else(() => stop("InvalidProjectBindings"))
    if !tasks.any(entry => {
        @compiler_environment.public_model_task_declaration_identity(entry.0).0 ==
        name
      }) {
      stop("InvalidProjectBindings")
    }
  }
  let result = {
    _retained_project: project,
    profile,
    _retained_connections: connections,
    _retained_catalog: catalog,
    _retained_registry: registry,
    _retained_data: data,
    _retained_tasks: tasks,
  }
  transferred = true
  Ok(result)
}

///|
// Native Project document intake policy. This retains the existing 64 KiB
// Reader bound and Common Project parser geometry; it is not a Run capacity
// quote, Model execution limit or authority to install these declarations.
fn local_project_mock_task_limits() -> @compiler_environment.ModelTaskLimits {
  {
    bodies: {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 16,
      max_members: 4096,
    },
    contracts: { max_nodes: 4096, max_depth: 16, max_text_bytes: 65536, },
    max_work: 1000000,
  }
}
