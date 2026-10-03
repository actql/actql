///|
/// Host/Connector observations, not author-supplied permission. This initial
/// owner combines these with the checked effective input policy for acquired
/// inputs. Provider observations cannot lower the source classification.
pub(all) struct ClientInferEgressObservation {
  classification : @environment.DataClassification
  region : String
  provider_retention : Bool
  training_use : Bool
} derive(Eq, Debug)

///|
pub struct ClientInferEgressAdmission {
  owner : PreparedClientProgram
  step : Int
  execution : @environment.ModelExecutionContract
  observed : ClientInferEgressObservation
  current : () -> ClientInferEgressObservation?
}

///|
pub(all) enum ClientInferEgressIssue {
  ForeignOwner
  MissingObservation
  UnknownClassification
  ClassificationDenied
  RegionDenied
  RetentionDenied
  TrainingDenied
  ChangedObservation
  InputPolicyUnavailable
} derive(Eq, Debug)

///|
fn infer_classification_rank(value : @environment.DataClassification) -> Int {
  match value {
    @environment.Public => 0
    @environment.Internal => 1
    @environment.Confidential => 2
    @environment.Restricted => 3
    @environment.Unknown => 4
  }
}

///|
pub fn admit_prepared_client_infer_egress(
  owner : PreparedClientProgram,
  step : Int,
  execution : @environment.ModelExecutionContract,
  observe : () -> ClientInferEgressObservation?,
) -> Result[ClientInferEgressAdmission, ClientInferEgressIssue] {
  guard client_infer_metadata_owner(owner, 0, step) is Some(prefix) &&
    @lower.node_at(@lower.bound_preparation(prefix), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) &&
    physical_equal(
      @infer.model_task(infer),
      @environment.model_execution_task(execution),
    ) else {
    return Err(ForeignOwner)
  }
  guard observe() is Some(observed) else { return Err(MissingObservation) }
  if observed.classification == @environment.Unknown {
    return Err(UnknownClassification)
  }
  let mut classification = match @infer.minimum_classification(infer) {
    Some(minimum) =>
      if infer_classification_rank(minimum) >
        infer_classification_rank(observed.classification) {
        minimum
      } else {
        observed.classification
      }
    None => observed.classification
  }
  if client_acquired_infer_prefix_owner(owner, 0, step) is Some(_) {
    let policy = @checked.prepare_infer_input_source_policy(
      @strategy.graph_program(owner.graph),
      0,
      step,
      1000000,
      1000000,
      100000,
      100,
    ) catch {
      _ => return Err(InputPolicyUnavailable)
    }
    guard policy is Some(policy) else { return Err(UnknownClassification) }
    let input_classification = @checked.publication_policy_classification(
      policy,
    )
    if input_classification == @environment.Unknown {
      return Err(UnknownClassification)
    }
    if infer_classification_rank(input_classification) >
      infer_classification_rank(classification) {
      classification = input_classification
    }
  }
  let task = @environment.model_execution_task(execution)
  if !@environment.model_task_accepts_classification(task, classification) {
    return Err(ClassificationDenied)
  }
  if observed.region.is_empty() || observed.region.length() > 256 {
    return Err(RegionDenied)
  }
  let mut region_allowed = false
  for index in 0..<@environment.model_task_region_count(task) {
    if @environment.model_task_region_at(task, index) == Some(observed.region) {
      region_allowed = true
      break
    }
  }
  if !region_allowed {
    return Err(RegionDenied)
  }
  if observed.provider_retention &&
    !@environment.model_task_provider_retention(task) {
    return Err(RetentionDenied)
  }
  if observed.training_use {
    return Err(TrainingDenied)
  }
  Ok({ owner, step, execution, observed, current: observe, })
}

///|
pub fn client_infer_egress_matches(
  admission : ClientInferEgressAdmission,
  owner : PreparedClientProgram,
  plan : ClientInferPlanGraph,
) -> Bool {
  physical_equal(admission.owner, owner) &&
  client_infer_plan_graph_matches(plan, owner, admission.execution) &&
  client_infer_plan_graph_matches_occurrence(plan, owner, admission.step)
}

///|
pub fn client_infer_egress_matches_scope(
  admission : ClientInferEgressAdmission,
  scope : ClientInferCallScope,
) -> Bool {
  client_infer_egress_matches(admission, scope.owner, scope.plan)
}

///|
/// A changed or missing observation needs fresh admission. It must not reuse
/// a previous permission, even when the replacement could itself be allowed.
pub fn check_client_infer_egress_current(
  admission : ClientInferEgressAdmission,
) -> Result[Unit, ClientInferEgressIssue] {
  guard (admission.current)() is Some(current) else {
    return Err(MissingObservation)
  }
  if current != admission.observed {
    return Err(ChangedObservation)
  }
  Ok(())
}
