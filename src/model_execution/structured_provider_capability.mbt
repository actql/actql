///|
/// The original Host-selected model. The selector is a Task reference and
/// the model ID and API mode identify the resolved implementation.
pub(all) struct ResolvedStructuredModel {
  selector : String
  model_id : String
  adapter_kind : String
  api_mode : String
  endpoint : String
} derive(Eq, Debug)

///|
/// Typed support for structured generation on one installed Provider and one
/// resolved model. This declaration grants no transport, budget or authority.
pub struct StructuredModelCapability {
  priv provider : ModelProvider
  priv binding : @publication.RunEvidenceValue
  priv profile : @environment.ModelResponseProfile
  priv resolved : ResolvedStructuredModel
  priv adapter_supports : Bool
  priv model_supports : Bool
}

///|
pub(all) enum StructuredModelCapabilityIssue {
  InvalidRegistration
  ForeignConfiguration
  ForeignProfile
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
  binding : @publication.RunEvidenceValue,
  configuration_wire : String,
  resolved : ResolvedStructuredModel,
  profile : @environment.ModelResponseProfile,
  adapter_supports : Bool,
  model_supports : Bool,
) -> Result[StructuredModelCapability, StructuredModelCapabilityIssue] {
  if !(provider.invocation is AsynchronousPhysical) ||
    resolved.selector.is_empty() ||
    resolved.model_id.is_empty() ||
    resolved.adapter_kind.is_empty() ||
    resolved.api_mode.is_empty() ||
    resolved.endpoint.is_empty() {
    return Err(InvalidRegistration)
  }
  if !@publication_host.client_model_resolved_configuration_matches(
      binding,
      configuration_wire,
      provider.provider_id,
      resolved.selector,
      resolved.model_id,
      resolved.adapter_kind,
      resolved.api_mode,
      resolved.endpoint,
    ) {
    return Err(ForeignConfiguration)
  }
  Ok({ provider, binding, profile, resolved, adapter_supports, model_supports, })
}

///|
pub fn admit_structured_model_provider(
  capability : StructuredModelCapability,
  selected : ResolvedStructuredModel,
  execution : @environment.ModelExecutionContract,
  dependencies : @environment.SingleAttemptModelDependencies,
  installation : @environment.ModelResponseProfileInstallation,
  validate : (@environment.ModelTaskContract, @environment.ModelDependency) -> Bool,
) -> Result[AdmittedStructuredModelProvider, StructuredModelCapabilityIssue] {
  match
    check_structured_model_selection(
      capability, selected, execution, installation,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    admit_model_provider(capability.provider, execution, dependencies, validate) {
    Ok(original) => Ok({ capability, original, })
    Err(issue) => Err(ProviderAdmission(issue))
  }
}

///|
/// Specialize the already admitted provider without reopening its prompt,
/// dependency or authority decisions.
pub fn bind_admitted_structured_model_provider(
  capability : StructuredModelCapability,
  original : AdmittedModelProvider,
  installation : @environment.ModelResponseProfileInstallation,
) -> Result[AdmittedStructuredModelProvider, StructuredModelCapabilityIssue] {
  guard admitted_model_provider_for(original, original.execution)
    is Some(provider) &&
    physical_equal(provider, capability.provider) else {
    return Err(ProviderAdmission(ForeignProvider))
  }
  check_structured_model_selection(
    capability,
    capability.resolved,
    original.execution,
    installation,
  ).map(_ => { capability, original, })
}

///|
fn check_structured_model_selection(
  capability : StructuredModelCapability,
  selected : ResolvedStructuredModel,
  execution : @environment.ModelExecutionContract,
  installation : @environment.ModelResponseProfileInstallation,
) -> Result[Unit, StructuredModelCapabilityIssue] {
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
  if installation.endpoint != selected.endpoint ||
    @environment.check_model_response_profile_binding(
      capability.profile,
      task,
      installation,
      None,
    )
    is Err(_) {
    return Err(ForeignProfile)
  }
  Ok(())
}

///|
/// Read the Provider with the exact capability selected by the original
/// admission. A replacement registry declaration cannot supply this fact.
pub fn admitted_structured_model_provider_for(
  value : AdmittedStructuredModelProvider,
  current : StructuredModelCapability,
  binding : @publication.RunEvidenceValue,
  selected : ResolvedStructuredModel,
  execution : @environment.ModelExecutionContract,
) -> ModelProvider? {
  if !physical_equal(value.capability, current) ||
    !physical_equal(current.binding, binding) ||
    current.resolved != selected {
    return None
  }
  admitted_model_provider_for(value.original, execution)
}

///|
/// Check the installer-selected route before initializing the SDK factory.
/// This is not the original Entry, credential or transport gate.
pub fn admitted_structured_model_route_matches(
  value : AdmittedStructuredModelProvider,
  actual : ResolvedStructuredModel,
) -> Bool {
  let current = value.capability
  admitted_structured_model_provider_for(
    value,
    current,
    current.binding,
    actual,
    value.original.execution,
  )
  is Some(_)
}

///|
/// Consume the admitted route and actual response profile before the existing
/// physical builder can supply a Plan for an Entry. The builder still owns
/// Task binding, exact codec/SDK installation checking and resource bounds.
/// No new transport, dispatch decision or send gate is issued here.
pub fn structured_model_async_request_plan(
  value : AdmittedStructuredModelProvider,
  current : StructuredModelCapability,
  binding : @publication.RunEvidenceValue,
  actual : ResolvedStructuredModel,
  request : ModelRequest,
  wire_bytes : Int64,
  quantities : @resources.QuantityAmounts,
  profile : @environment.ModelResponseProfile,
  installation : @environment.ModelResponseProfileInstallation,
  start : (ModelCallEntry) -> ModelPhysicalCall?,
  read_decoded : (ModelPhysicalCall, ModelSavedRawReceipt, Bytes) -> ModelPhysicalEncodedResponse?,
  evidence? : ModelPhysicalRequestEvidence,
  attachments? : Array[ModelContentAdmission] = [],
) -> Result[ModelPhysicalRequestPlan, ModelExecutionIssue] {
  let execution = value.original.execution
  if admitted_structured_model_provider_for(
      value, current, binding, actual, execution,
    )
    is None ||
    !physical_equal(current.profile, profile) ||
    !physical_equal(@environment.model_execution_task(execution), request.task) ||
    installation.endpoint != actual.endpoint {
    return Err(InvalidProvider)
  }
  prepare_structured_model_physical_plan(
    request,
    wire_bytes,
    quantities,
    profile,
    installation,
    AsynchronousSavedStructured(current, start, read_decoded),
    evidence,
    attachments,
  )
}

///|
/// The installed port already carries the one original admitted selection.
pub fn bound_structured_model_async_request_plan(
  value : AdmittedStructuredModelProvider,
  request : ModelRequest,
  wire_bytes : Int64,
  quantities : @resources.QuantityAmounts,
  profile : @environment.ModelResponseProfile,
  installation : @environment.ModelResponseProfileInstallation,
  start : (ModelCallEntry) -> ModelPhysicalCall?,
  read_decoded : (ModelPhysicalCall, ModelSavedRawReceipt, Bytes) -> ModelPhysicalEncodedResponse?,
) -> Result[ModelPhysicalRequestPlan, ModelExecutionIssue] {
  let original = value.capability
  structured_model_async_request_plan(
    value,
    original,
    original.binding,
    original.resolved,
    request,
    wire_bytes,
    quantities,
    profile,
    installation,
    start,
    read_decoded,
  )
}
