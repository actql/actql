///|
/// Provider capability, not egress authority or an executed-attempt receipt.
/// Keep the exact selected provider and the exact checked dependencies alive.
pub struct AdmittedModelProvider {
  provider : ModelProvider
  execution : @environment.ModelExecutionContract
  dependencies : @environment.SingleAttemptModelDependencies
}

///|
pub(all) enum ModelProviderAdmissionIssue {
  ForeignDependencies
  ForeignProvider
  UnsupportedPrompt
} derive(Eq, Debug)

///|
/// Only a Host-installed provider may interpret its prompt payload. A valid
/// canonical value is not executable merely because its envelope was admitted.
pub fn admit_model_provider(
  provider : ModelProvider,
  execution : @environment.ModelExecutionContract,
  dependencies : @environment.SingleAttemptModelDependencies,
  validate : (@environment.ModelTaskContract, @environment.ModelDependency) -> Bool,
) -> Result[AdmittedModelProvider, ModelProviderAdmissionIssue] {
  if !@environment.single_attempt_model_dependencies_match(
      dependencies, execution,
    ) {
    return Err(ForeignDependencies)
  }
  let task = @environment.model_execution_task(execution)
  if provider.provider_id != @environment.model_task_connector(task) {
    return Err(ForeignProvider)
  }
  if !validate(task, @environment.single_attempt_model_prompt(dependencies)) {
    return Err(UnsupportedPrompt)
  }
  Ok({ provider, execution, dependencies, })
}

///|
/// Dispatch must consume the same installed provider and execution contract.
/// This reader does not replace the current authority/account admission.
pub fn admitted_model_provider_for(
  value : AdmittedModelProvider,
  execution : @environment.ModelExecutionContract,
) -> ModelProvider? {
  if physical_equal(value.execution, execution) &&
    @environment.single_attempt_model_dependencies_match(
      value.dependencies,
      execution,
    ) {
    Some(value.provider)
  } else {
    None
  }
}
