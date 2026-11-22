///|
/// The original Host-selected model. The selector is a Task reference and
/// the model ID and API mode identify the resolved implementation.
pub(all) struct ResolvedStructuredModel {
  selector : String
  model_id : String
  api_mode : String
} derive(Eq, Debug)

///|
/// Typed support for structured generation on one installed Provider and one
/// resolved model. This declaration grants no transport, budget or authority.
pub struct StructuredModelCapability {
  priv provider : ModelProvider
  priv resolved : ResolvedStructuredModel
  priv adapter_supports : Bool
  priv model_supports : Bool
}

///|
pub(all) enum StructuredModelCapabilityIssue {
  InvalidRegistration
  ChangedSelection
  UnsupportedAdapter
  UnsupportedModel
  ProviderAdmission(ModelProviderAdmissionIssue)
} derive(Eq, Debug)

///|
/// The capability-aware route retains the same nominal declaration and the
/// existing Provider admission. Legacy and Mock admissions have no new field.
pub struct AdmittedStructuredModelProvider {
  priv capability : StructuredModelCapability
  priv original : AdmittedModelProvider
}

///|
pub fn register_structured_model_capability(
  provider : ModelProvider,
  resolved : ResolvedStructuredModel,
  adapter_supports : Bool,
  model_supports : Bool,
) -> Result[StructuredModelCapability, StructuredModelCapabilityIssue] {
  if !(provider.invocation is AsynchronousPhysical) ||
    resolved.selector.is_empty() ||
    resolved.model_id.is_empty() ||
    resolved.api_mode.is_empty() {
    return Err(InvalidRegistration)
  }
  Ok({ provider, resolved, adapter_supports, model_supports, })
}

///|
pub fn admit_structured_model_provider(
  capability : StructuredModelCapability,
  selected : ResolvedStructuredModel,
  execution : @environment.ModelExecutionContract,
  dependencies : @environment.SingleAttemptModelDependencies,
  validate : (@environment.ModelTaskContract, @environment.ModelDependency) -> Bool,
) -> Result[AdmittedStructuredModelProvider, StructuredModelCapabilityIssue] {
  let task = @environment.model_execution_task(execution)
  if capability.resolved != selected ||
    @environment.model_task_model_selector(task) != selected.selector {
    return Err(ChangedSelection)
  }
  if !capability.adapter_supports ||
    @environment.model_task_kind(task) != @environment.StructuredGenerate {
    return Err(UnsupportedAdapter)
  }
  if !capability.model_supports {
    return Err(UnsupportedModel)
  }
  match
    admit_model_provider(capability.provider, execution, dependencies, validate) {
    Ok(original) => Ok({ capability, original, })
    Err(issue) => Err(ProviderAdmission(issue))
  }
}

///|
/// Read the Provider with the exact capability selected by the original
/// admission. A replacement registry declaration cannot supply this fact.
pub fn admitted_structured_model_provider_for(
  value : AdmittedStructuredModelProvider,
  current : StructuredModelCapability,
  selected : ResolvedStructuredModel,
  execution : @environment.ModelExecutionContract,
) -> ModelProvider? {
  if !physical_equal(value.capability, current) || current.resolved != selected {
    return None
  }
  admitted_model_provider_for(value.original, execution)
}
