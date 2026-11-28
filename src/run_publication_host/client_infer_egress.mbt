///|
/// Host/Connector observations, not author-supplied permission. This initial
/// owner combines these with the policy of the checked receiving input.
/// Provider observations cannot lower the source classification.
pub(all) struct ClientInferEgressObservation {
  classification : @environment.DataClassification
  region : String
  provider_retention : Bool
  training_use : Bool
} derive(Eq, Debug)

///|
pub struct ClientInferEgressAdmission {
  owner : PreparedClientProgram
  task : Int
  stage : Int
  step : Int
  execution : @environment.ModelExecutionContract
  observed : ClientInferEgressObservation
  priv classification : @environment.DataClassification
  priv dispatch_current : (() -> Bool)?
  current : () -> ClientInferEgressObservation?
}

///|
/// The checked input may still require a prior Model result. This selection
/// has no dispatch authority. Only the admitted variant can bind an exchange.
pub(all) enum ClientInferEgressSelection {
  EgressAdmitted(ClientInferEgressAdmission)
  EgressPending(ClientInferPendingEgress)
}

///|
priv struct ClientInferEgressCandidate {
  occurrence : ClientInferOccurrence
  execution : @environment.ModelExecutionContract
  observed : ClientInferEgressObservation
  current : () -> ClientInferEgressObservation?
  classification : @environment.DataClassification
}

///|
struct ClientInferPendingEgress {
  candidate : ClientInferEgressCandidate
  dependency : @checked.CheckedInferModelInputs
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
  guard client_infer_metadata_owner(owner, 0, step) is Some(prefix) else {
    return Err(ForeignOwner)
  }
  admit_client_infer_egress_for_occurrence(
    { owner, task: 0, stage: 0, step, preparation: prefix, },
    execution,
    observe,
  )
}

///|
/// Use the effective source policy of the actual checked Unit. All upstream
/// source classifications participate; a provider observation cannot replace
/// or lower the policy established by JOIN and imported Results.
pub fn admit_client_infer_occurrence_egress(
  occurrence : ClientInferOccurrence,
  execution : @environment.ModelExecutionContract,
  observe : () -> ClientInferEgressObservation?,
) -> Result[ClientInferEgressAdmission, ClientInferEgressIssue] {
  if !client_infer_occurrence_matches(occurrence, occurrence.owner) {
    return Err(ForeignOwner)
  }
  admit_client_infer_egress_for_occurrence(occurrence, execution, observe)
}

///|
/// Prepare the installed transport against the checked receiving occurrence.
/// The pending variant keeps the exact dependency and the strongest already
/// known input classification. The Host must separately prove the settled
/// original and its admitted output policy before using that dependency.
pub fn prepare_client_infer_occurrence_egress(
  occurrence : ClientInferOccurrence,
  execution : @environment.ModelExecutionContract,
  observe : () -> ClientInferEgressObservation?,
) -> Result[ClientInferEgressSelection, ClientInferEgressIssue] {
  if !client_infer_occurrence_matches(occurrence, occurrence.owner) {
    return Err(ForeignOwner)
  }
  prepare_client_infer_egress_candidate(occurrence, execution, observe).bind(pair => {
    let (candidate, pending) = pair
    check_infer_egress_observation(candidate).map(_ => {
      match pending {
        Some(dependency) => EgressPending({ candidate, dependency, })
        None => EgressAdmitted(admit_client_infer_egress_candidate(candidate))
      }
    })
  })
}

///|
fn admit_client_infer_egress_for_occurrence(
  occurrence : ClientInferOccurrence,
  execution : @environment.ModelExecutionContract,
  observe : () -> ClientInferEgressObservation?,
) -> Result[ClientInferEgressAdmission, ClientInferEgressIssue] {
  prepare_client_infer_egress_candidate(occurrence, execution, observe).bind(pair => {
    let (candidate, pending) = pair
    if pending is Some(_) {
      return Err(UnknownClassification)
    }
    check_infer_egress_observation(candidate).map(_ => {
      admit_client_infer_egress_candidate(candidate)
    })
  })
}

///|
fn prepare_client_infer_egress_candidate(
  occurrence : ClientInferOccurrence,
  execution : @environment.ModelExecutionContract,
  observe : () -> ClientInferEgressObservation?,
) -> Result[
  (ClientInferEgressCandidate, @checked.CheckedInferModelInputs?),
  ClientInferEgressIssue,
] {
  let owner = occurrence.owner
  let step = occurrence.step
  let prefix = occurrence.preparation
  guard @lower.node_at(@lower.bound_preparation(prefix), step) is Some(node) &&
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
  let policy = @checked.prepare_infer_input_policy(
    @strategy.graph_program(owner.graph),
    occurrence.stage,
    step,
    1000000,
    1000000,
    100000,
    100,
  ) catch {
    _ => return Err(InputPolicyUnavailable)
  }
  let pending = match policy {
    None | Some(@checked.CheckedSources(@environment.Unknown)) =>
      return Err(UnknownClassification)
    Some(@checked.ClosedLocal) => None
    Some(@checked.CheckedSources(input)) => {
      classification = stronger_infer_classification(classification, input)
      None
    }
    Some(@checked.PendingModelOutputs(dependency)) => {
      if @checked.checked_infer_model_input_source_classification(dependency)
        is Some(input) {
        classification = stronger_infer_classification(classification, input)
      }
      Some(dependency)
    }
  }
  Ok(
    (
      { occurrence, execution, observed, current: observe, classification, },
      pending,
    ),
  )
}

///|
fn stronger_infer_classification(
  left : @environment.DataClassification,
  right : @environment.DataClassification,
) -> @environment.DataClassification {
  if infer_classification_rank(left) >= infer_classification_rank(right) {
    left
  } else {
    right
  }
}

///|
fn check_infer_egress_observation(
  candidate : ClientInferEgressCandidate,
) -> Result[Unit, ClientInferEgressIssue] {
  let { execution, classification, observed, .. } = candidate
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
  Ok(())
}

///|
fn admit_client_infer_egress_candidate(
  candidate : ClientInferEgressCandidate,
  dispatch_current? : (() -> Bool)? = None,
) -> ClientInferEgressAdmission {
  let { occurrence, execution, observed, classification, current, } = candidate
  {
    owner: occurrence.owner,
    task: occurrence.task,
    stage: occurrence.stage,
    step: occurrence.step,
    execution,
    observed,
    classification,
    dispatch_current,
    current,
  }
}

///|
/// Reuse the checked producer graph only for this receiving occurrence and
/// selected execution contract. A pending selection is never an admission.
pub fn client_infer_pending_egress_matches(
  pending : ClientInferPendingEgress,
  plan : ClientInferPlanGraph,
) -> Bool {
  let candidate = pending.candidate
  let occurrence = candidate.occurrence
  client_infer_occurrence_matches_plan(occurrence, plan) &&
  client_infer_plan_graph_matches(plan, occurrence.owner, candidate.execution) &&
  @checked.checked_infer_model_inputs_match(
    pending.dependency,
    @strategy.graph_program(occurrence.owner.graph),
    occurrence.stage,
    occurrence.step,
  )
}

///|
/// Match the exact checked receiving import and producer Model coordinates.
/// This compares compilation evidence only. Actual data still comes from the
/// original settled output and the same runtime ProducerRead.
pub fn client_infer_pending_egress_result_matches(
  pending : ClientInferPendingEgress,
  receiving : ClientInferPlanGraph,
  import_index : Int,
  producer : ClientInferPlanGraph,
) -> Bool {
  let occurrence = pending.candidate.occurrence
  let program = @strategy.graph_program(occurrence.owner.graph)
  client_infer_pending_egress_matches(pending, receiving) &&
  client_infer_occurrence_matches(producer.occurrence, occurrence.owner) &&
  client_infer_occurrence_matches_plan(producer.occurrence, producer) &&
  @checked.unit_result_import_at(program, occurrence.stage, import_index)
  is Some(imported) &&
  @checked.checked_infer_model_result_dependency_matches(
    pending.dependency,
    imported,
    producer.stage,
    producer.source_ordinal,
  )
}

///|
pub fn client_infer_pending_egress_result_count(
  pending : ClientInferPendingEgress,
) -> Int {
  @checked.checked_infer_model_result_dependency_count(pending.dependency)
}

///|
/// Resolve the installed pending selection from the full ordered set of
/// original receiving Readers and completed producer egress proofs. The
/// installed Host authenticates each declaration and the durable evidence
/// before supplying these borrows. Later calls recheck the same observation.
pub fn resolve_client_infer_pending_egress(
  pending : ClientInferPendingEgress,
  receiving : ClientInferPlanGraph,
  members : Array[
    (
      ClientInferWholeResultReaderOriginal,
      ClientWholeModelEgressOriginal,
      @environment.DataClassification,
    ),
  ],
  installed_current : () -> Bool,
) -> Result[ClientInferEgressAdmission, ClientInferEgressIssue] {
  guard client_infer_pending_egress_matches(pending, receiving) &&
    !members.is_empty() &&
    members.length() == client_infer_pending_egress_result_count(pending) else {
    return Err(ForeignOwner)
  }
  let candidate = pending.candidate
  let mut classification = candidate.classification
  let mut previous = (-1, -1, -1)
  for (reader, producer, declared) in members {
    let key = (
      reader.import_index,
      producer.plan.stage,
      producer.plan.source_ordinal,
    )
    guard key > previous &&
      client_infer_occurrence_matches_plan(reader.occurrence, receiving) &&
      physical_equal(reader.artifact, producer.artifact) &&
      physical_equal(reader.manifest, producer.manifest) &&
      client_infer_pending_egress_result_matches(
        pending,
        receiving,
        reader.import_index,
        producer.plan,
      ) &&
      client_infer_whole_result_reader_retained(reader) else {
      return Err(ForeignOwner)
    }
    match
      client_infer_pending_egress_classification(
        pending,
        declared,
        producer.classification,
      ) {
      Ok(floor) =>
        classification = stronger_infer_classification(classification, floor)
      Err(issue) => return Err(issue)
    }
    previous = key
  }
  check_client_infer_pending_egress_current(pending).map(_ => {
    admit_client_infer_egress_candidate(
      { ..candidate, classification, },
      dispatch_current=Some(installed_current),
    )
  })
}

///|
/// Reject a declaration that already exceeds this receiving Task's declared
/// allowance. Settled producer provenance supplies a separate, late floor.
pub fn client_infer_pending_egress_accepts_classification(
  pending : ClientInferPendingEgress,
  declared : @environment.DataClassification,
) -> Bool {
  client_infer_pending_egress_classification(
    pending,
    declared,
    @environment.Public,
  )
  is Ok(_)
}

///|
/// Calculate the strongest known classification for the receiving Task.
/// This is a policy comparison. Only the original receiving boundary can
/// establish the declaration, actual producer floor and complete evidence.
pub fn client_infer_pending_egress_classification(
  pending : ClientInferPendingEgress,
  declared : @environment.DataClassification,
  producer : @environment.DataClassification,
) -> Result[@environment.DataClassification, ClientInferEgressIssue] {
  let candidate = pending.candidate
  let classification = stronger_infer_classification(
    candidate.classification,
    stronger_infer_classification(declared, producer),
  )
  if classification == @environment.Unknown {
    return Err(UnknownClassification)
  }
  if !@environment.model_task_accepts_classification(
      @environment.model_execution_task(candidate.execution),
      classification,
    ) {
    return Err(ClassificationDenied)
  }
  Ok(classification)
}

///|
pub fn check_client_infer_pending_egress_current(
  pending : ClientInferPendingEgress,
) -> Result[Unit, ClientInferEgressIssue] {
  require_infer_egress_observation_current(
    pending.candidate.current,
    pending.candidate.observed,
  )
}

///|
pub fn client_infer_egress_matches(
  admission : ClientInferEgressAdmission,
  owner : PreparedClientProgram,
  plan : ClientInferPlanGraph,
) -> Bool {
  physical_equal(admission.owner, owner) &&
  plan.task == admission.task &&
  plan.stage == admission.stage &&
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
  check_client_infer_egress_observation(admission).bind(_ => {
    if admission.dispatch_current is Some(current) && !current() {
      Err(MissingObservation)
    } else {
      Ok(())
    }
  })
}

///|
// A sealed producer's actual classification remains evidence after its
// receiving Readers retire. Its live permission to dispatch does not.
fn check_client_infer_egress_observation(
  admission : ClientInferEgressAdmission,
) -> Result[Unit, ClientInferEgressIssue] {
  require_infer_egress_observation_current(
    admission.current,
    admission.observed,
  )
}

///|
fn require_infer_egress_observation_current(
  observe : () -> ClientInferEgressObservation?,
  observed : ClientInferEgressObservation,
) -> Result[Unit, ClientInferEgressIssue] {
  guard observe() is Some(current) else { return Err(MissingObservation) }
  if current != observed {
    return Err(ChangedObservation)
  }
  Ok(())
}
