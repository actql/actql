///|
/// Original project/Task DATA correspondence. Provider installation/currentness
/// and physical policy/funding remain with their existing Owners.
struct ClientProjectModelTaskSelection {
  registry : ClientProjectModelRegistry
  task : @environment.PublicModelTaskDeclaration
  task_file : String
  provider : String
  model : String?
  work : Int
}

///|
pub(all) enum ClientProjectModelTaskSelectionIssue {
  InvalidLimits
  WorkLimit
  TaskUnavailable
  ProviderUnavailable
  ForeignOriginal
  InvalidDefaults(@environment.ModelProviderDefaultsResolutionIssue)
} derive(Eq, Debug)

///|
/// Select the complete explicit pair or the original registry's default.
/// Check the registered task name and provider in the same retained registry;
/// no credential, configuration alias, filesystem or Provider is consulted.
pub fn select_client_project_model_task(
  registry : ClientProjectModelRegistry,
  task : @environment.PublicModelTaskDeclaration,
  max_work : Int,
) -> Result[
  ClientProjectModelTaskSelection,
  ClientProjectModelTaskSelectionIssue,
] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let name = @environment.public_model_task_declaration_identity(task).0
  let mut work = 0
  let mut task_file = None
  for (candidate, file) in registry.tasks {
    for amount in [1, candidate.length(), name.length()] {
      if amount > max_work - work {
        return Err(WorkLimit)
      }
      work += amount
    }
    if candidate == name {
      task_file = Some(file)
      break
    }
  }
  guard task_file is Some(task_file) else { return Err(TaskUnavailable) }
  let (provider, model) = match
    @environment.public_model_task_declaration_model(task) {
    Some((provider, model)) => (provider, Some(model))
    None =>
      match registry.default_provider {
        Some(provider) => (provider, None)
        None => return Err(ProviderUnavailable)
      }
  }
  for (candidate, _, _) in registry.providers {
    for amount in [1, candidate.length(), provider.length()] {
      if amount > max_work - work {
        return Err(WorkLimit)
      }
      work += amount
    }
    if candidate == provider {
      return Ok({ registry, task, task_file, provider, model, work, })
    }
  }
  Err(ProviderUnavailable)
}

///|
/// Project only through the exact originally checked pair. Equal separately
/// decoded registry/Task DATA does not replace these nominal originals.
pub fn client_project_model_task_selection_for(
  value : ClientProjectModelTaskSelection,
  registry : ClientProjectModelRegistry,
  task : @environment.PublicModelTaskDeclaration,
) -> (String, String?, String)? {
  if !physical_equal(value.registry, registry) ||
    !physical_equal(value.task, task) {
    None
  } else {
    Some((value.provider, value.model, value.task_file))
  }
}

///|
pub fn client_project_model_task_selection_usage(
  value : ClientProjectModelTaskSelection,
) -> Int {
  value.work
}

///|
/// Bind resolved generation to the same original registry/Task and provider
/// configuration. This is still DATA, never installation or dispatch authority.
pub fn resolve_client_project_model_task_defaults(
  selection : ClientProjectModelTaskSelection,
  registry : ClientProjectModelRegistry,
  task : @environment.PublicModelTaskDeclaration,
  defaults : ClientModelProviderDefaults,
  max_work : Int,
) -> Result[
  @environment.ResolvedModelProviderDefaults,
  ClientProjectModelTaskSelectionIssue,
] {
  if !physical_equal(selection.registry, registry) ||
    !physical_equal(selection.task, task) ||
    selection.provider != defaults.provider_id {
    return Err(ForeignOriginal)
  }
  let tokens = @environment.public_model_task_declaration_limits(task).1
  resolve_client_model_provider_defaults(
    defaults,
    selection.model,
    tokens,
    max_work,
  ).map_err(ClientProjectModelTaskSelectionIssue::InvalidDefaults)
}
