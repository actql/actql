///|
// The original Project's bounded documents, not an installed Host or grant.
// The existing command Read owns their physical lifetime. The profile's
// nominal self-reference must retire before that Read can acknowledge close.
priv struct LocalProjectMockDeclarations {
  _retained_project : LocalProjectConfiguration
  profile : @run_host.ClientProjectProfileSelection
  mut model_profile : @compiler_environment.ModelMockProfile?
  models : Array[LocalProjectMockModelOriginal]
  mut model_started : Bool
  mut model_failure : LocalProjectMockModelIssue?
  mut model_retire_index : Int
  mut closing : Bool
  mut retired : Bool
  _retained_connections : @run_host.ClientProjectConnections
  _retained_catalog : @run_host.ClientProjectCatalog
  _retained_registry : @run_host.ClientProjectModelRegistry
  _retained_data_file : String
  _retained_tasks : Array[
    (
      @compiler_environment.PublicModelTaskDeclaration,
      @run_host.ClientProjectModelTaskSelection,
      String,
      String,
    ),
  ]
}

///|
fn LocalProjectMockDeclarations::retire(self : Self) -> Unit raise ClientStop {
  match self.retire_originals() {
    Ok(true) => ()
    Ok(false) => stop("LocalProjectMockCleanupPending")
    Err(_) => stop("LocalProjectMockCleanupPending")
  }
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
  let data_path = data_path.unwrap_or_else(() => stop("InvalidProjectBindings"))
  if data_path.has_suffix("/") {
    stop("InvalidProjectConfigurationPath")
  }
  // The Source payload is not Project declaration metadata. Retain only its
  // original locator; the same Request's admitted Source must open/read it
  // under its own checked payload bounds, currentness and physical custody.
  let data_file = local_project_absolute_path(project.directory, data_path)
  let tasks : Array[
    (
      @compiler_environment.PublicModelTaskDeclaration,
      @run_host.ClientProjectModelTaskSelection,
      String,
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
    let original_answer_path = answer_path.unwrap_or_else(() => {
      stop("InvalidProjectBindings")
    })
    let answers = match
      local_project_required_declaration(project, Some(original_answer_path)) {
      Ok(value) => value
      Err(original) => return Err(original)
    }
    tasks.push((task, selection, answers, original_answer_path))
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
    model_profile: None,
    models: [],
    model_started: false,
    model_failure: None,
    model_retire_index: 0,
    closing: false,
    retired: false,
    _retained_connections: connections,
    _retained_catalog: catalog,
    _retained_registry: registry,
    _retained_data_file: data_file,
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

///|
// Retention records in the existing command Project, not another resource or
// Provider owner. Installations, typed answers and the profile retain their
// original Common retirement protocols and cannot be reconstructed by CID.
priv struct LocalProjectMockModelOriginal {
  declaration : @compiler_environment.PublicModelTaskDeclaration
  mut normalized : @compiler_environment.NormalizedPublicModelTask?
  mut answers : @model.ModelMockAnswers?
  mut installation : @model.ModelMockInstallation?
}

///|
priv enum LocalProjectMockModelIssue {
  ForeignOriginal
  AlreadyPreparing
  Task(@compiler_environment.ModelTaskIssue)
  Answers(@model.ModelMockAnswerIssue)
  Installation(@model.ModelMockInstallationIssue)
}

///|
fn LocalProjectMockDeclarations::prepare_models(
  self : Self,
  task_limits : @compiler_environment.ModelTaskLimits,
  answer_limits : @model.ModelMockAnswerLimits,
  now : () -> String,
) -> Result[Unit, LocalProjectMockModelIssue] {
  if self.closing ||
    self.retired ||
    !@run_host.client_project_profile_matches(
      self.profile,
      Some(self._retained_project.metadata),
      self._retained_project.profile,
    ) {
    return Err(ForeignOriginal)
  }
  if self.model_failure is Some(original) {
    return Err(original)
  }
  if self.model_started {
    return Err(AlreadyPreparing)
  }
  self.model_started = true
  let profile = match
    @compiler_environment.install_model_mock_profile(task_limits) {
    Ok(value) => value
    Err(issue) => {
      self.model_failure = Some(Task(issue))
      return Err(Task(issue))
    }
  }
  // Retain every nominal cycle BEFORE the next fallible construction.
  self.model_profile = Some(profile)
  for (task, selection, wire, answer_path) in self._retained_tasks {
    if @run_host.client_project_model_task_selection_for(
        selection,
        self._retained_registry,
        task,
      )
      is None {
      self.model_failure = Some(ForeignOriginal)
      return Err(ForeignOriginal)
    }
    let entry : LocalProjectMockModelOriginal = {
      declaration: task,
      normalized: None,
      answers: None,
      installation: None,
    }
    self.models.push(entry)
    let format = if answer_path.has_suffix(".json") { "json" } else { "yaml" }
    let answers = match
      @model.read_model_mock_answer_document(task, wire, format, answer_limits) {
      Ok(value) => value
      Err(issue) => {
        self.model_failure = Some(Answers(issue))
        return Err(Answers(issue))
      }
    }
    entry.answers = Some(answers)
    let normalized = match
      @compiler_environment.normalize_public_mock_model_task(
        task, profile, task_limits,
      ) {
      Ok(value) => value
      Err(issue) => {
        self.model_failure = Some(Task(issue))
        return Err(Task(issue))
      }
    }
    entry.normalized = Some(normalized)
    let installation = match
      @model.install_original_model_mock(
        profile,
        entry.declaration,
        entry.normalized.unwrap(),
        entry.answers.unwrap(),
        now,
      ) {
      Ok(value) => value
      Err(issue) => {
        self.model_failure = Some(Installation(issue))
        return Err(Installation(issue))
      }
    }
    entry.installation = Some(installation)
  }
  Ok(())
}

///|
fn LocalProjectMockDeclarations::retire_originals(
  self : Self,
) -> Result[Bool, LocalProjectMockModelIssue] {
  if self.retired {
    return Ok(true)
  }
  self.closing = true
  while self.model_retire_index < self.models.length() {
    let entry = self.models[self.model_retire_index]
    if entry.installation is Some(original) {
      match @model.retire_original_model_mock(original) {
        Ok(true) => entry.installation = None
        Ok(false) => return Ok(false)
        Err(issue) => return Err(Installation(issue))
      }
    }
    if entry.answers is Some(original) {
      match @model.retire_model_mock_answers(original, entry.declaration) {
        Ok(_) => entry.answers = None
        Err(issue) => return Err(Answers(issue))
      }
    }
    entry.normalized = None
    self.model_retire_index += 1
  }
  if self.model_profile is Some(original) {
    if !@compiler_environment.retire_model_mock_profile(original) {
      return Err(ForeignOriginal)
    }
    self.model_profile = None
  }
  if @run_host.retire_client_project_profile(self.profile) is Err(_) {
    return Err(ForeignOriginal)
  }
  self.retired = true
  Ok(true)
}

///|
fn local_project_mock_answer_limits() -> @model.ModelMockAnswerLimits {
  let limits = local_project_mock_task_limits()
  {
    document: limits.bodies,
    values: {
      max_nodes: limits.contracts.max_nodes,
      max_depth: limits.contracts.max_depth,
      max_text_bytes: limits.contracts.max_text_bytes,
    },
    max_entries: limits.bodies.max_members,
    max_work: limits.max_work,
  }
}
