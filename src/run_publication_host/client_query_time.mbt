///|
priv enum ClientQueryTimeOwner {
  Query(PreparedClientProgram)
  Effect(PreparedClientEffectComputation)
}

///|
/// A fresh invocation's preparation DATA. The trusted Host samples before
/// dependent acquisition; this retains its exact checked owner and request.
/// Neither the sample nor this value grants a physical dispatch or COMMIT.
struct ClientQueryTimePreparation {
  owner : ClientQueryTimeOwner
  request : ClientRequestIdentity
  created_at : String
  sample : @values.CheckedValue
  mut definition : @publication.PublicationContract?
  mut context : @publication.QueryEvaluationTime?
}

///|
pub(all) enum ClientQueryTimeIssue {
  InvalidSample
  ForeignPreparation
  ForeignRequest
  ForeignRun
  RunBinding(@publication.RunProgramBindingIssue)
  Requirement(@lower.QueryTimeRequirementIssue)
  WorkLimit
  MissingTask
}

///|
/// Read the complete original checked graph, including lazy expressions.
/// The same remaining inspection budget crosses every task boundary.
pub fn prepared_client_requires_query_time(
  owner : PreparedClientProgram,
  max_work : Int,
  max_expressions_per_task : Int,
) -> Result[Bool, ClientQueryTimeIssue] {
  if max_work < 0 || max_expressions_per_task < 0 {
    return Err(WorkLimit)
  }
  let count = @strategy.graph_task_count(owner.graph)
  let mut remaining = max_work
  let mut required = false
  for task in 0..<count {
    if remaining == 0 {
      return Err(WorkLimit)
    }
    remaining -= 1
    guard @strategy.graph_task_owner(owner.graph, task) is Some(prepared) else {
      return Err(MissingTask)
    }
    let (needed, spent) = match
      @lower.bound_prepared_query_time_requirement_usage(
        prepared,
        max_work=remaining,
        max_expressions=max_expressions_per_task,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Requirement(issue))
    }
    if spent < 0 || spent > remaining {
      return Err(WorkLimit)
    }
    remaining -= spent
    required = required || needed
  }
  Ok(required)
}

///|
pub fn prepared_client_effect_requires_query_time(
  owner : PreparedClientEffectComputation,
  max_work : Int,
  max_expressions_per_task : Int,
) -> Result[Bool, ClientQueryTimeIssue] {
  prepared_client_requires_query_time(
    client_effect_program_view(owner),
    max_work,
    max_expressions_per_task,
  )
}

///|
fn prepare_client_query_time_sample(
  owner : ClientQueryTimeOwner,
  identity : ClientProgramIdentity,
  request : ClientRequestIdentity,
  created_at : String,
) -> Result[ClientQueryTimePreparation, ClientQueryTimeIssue] {
  if identity.program_definition_cid != request.program_definition_cid ||
    identity.parameter_values_cid != request.parameter_values_cid {
    return Err(ForeignRequest)
  }
  guard @values.checked_timestamp_value(
      created_at,
      @contract.primitive(@contract.TimestampType, nullable=false),
    )
    is Some(sample) else {
    return Err(InvalidSample)
  }
  Ok({ owner, request, created_at, sample, definition: None, context: None, })
}

///|
pub fn prepare_client_query_time(
  owner : PreparedClientProgram,
  request : ClientRequestIdentity,
  created_at : String,
) -> Result[ClientQueryTimePreparation, ClientQueryTimeIssue] {
  prepare_client_query_time_sample(
    Query(owner),
    prepared_client_identity(owner),
    request,
    created_at,
  )
}

///|
pub fn prepare_client_effect_query_time(
  owner : PreparedClientEffectComputation,
  request : ClientRequestIdentity,
  created_at : String,
) -> Result[ClientQueryTimePreparation, ClientQueryTimeIssue] {
  if request.caller_input_intent_cid !=
    client_effect_original_input_intent_cid(owner) {
    return Err(ForeignRequest)
  }
  prepare_client_query_time_sample(
    Effect(owner),
    prepared_client_effect_identity(owner),
    request,
    created_at,
  )
}

///|
/// This is the original preparation value, not a new clock read. The Run
/// issuer must use it unchanged; final binding below rejects substitution.
pub fn client_query_time_preparation_created_at(
  preparation : ClientQueryTimePreparation,
) -> String {
  preparation.created_at
}

///|
pub fn client_query_time_preparation_context(
  preparation : ClientQueryTimePreparation,
) -> @publication.QueryEvaluationTime? {
  preparation.context
}

///|
fn check_client_query_time_request(
  preparation : ClientQueryTimePreparation,
  request : ClientRequestIdentity,
  definition : @publication.PublicationContract,
) -> Result[Unit, ClientQueryTimeIssue] {
  if !physical_equal(preparation.request, request) {
    return Err(ForeignRequest)
  }
  guard @publication.run_definition_lifetime(definition) is Some((created, _)) &&
    created == preparation.created_at else {
    return Err(ForeignRun)
  }
  if preparation.definition is Some(original) &&
    !physical_equal(original, definition) {
    return Err(ForeignRun)
  }
  Ok(())
}

///|
pub fn bind_client_query_evaluation_time(
  preparation : ClientQueryTimePreparation,
  owner : PreparedClientProgram,
  compilation : ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
) -> Result[@publication.QueryEvaluationTime, ClientQueryTimeIssue] {
  guard preparation.owner is Query(original) &&
    physical_equal(original, owner) &&
    client_compiled_run_matches(compilation, owner) else {
    return Err(ForeignPreparation)
  }
  match check_client_query_time_request(preparation, request, definition) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if check_client_compiled_run_definition(compilation, definition) is Err(_) {
    return Err(ForeignRun)
  }
  if preparation.context is Some(original) {
    if @publication.query_evaluation_time_matches(
        original,
        compilation.admission,
        definition,
      ) {
      return Ok(original)
    }
    return Err(ForeignRun)
  }
  let time = match
    @publication.bind_query_evaluation_time(
      compilation.admission,
      definition,
      prepared_client_identity(owner).program_definition_cid,
      prepared_client_program_semantics_cid(owner),
      prepared_client_check_environment_cid(owner),
    ) {
    Ok(value) => value
    Err(issue) => return Err(RunBinding(issue))
  }
  preparation.definition = Some(definition)
  preparation.context = Some(time)
  Ok(time)
}

///|
pub fn bind_client_effect_query_evaluation_time(
  preparation : ClientQueryTimePreparation,
  owner : PreparedClientEffectComputation,
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
) -> Result[@publication.QueryEvaluationTime, ClientQueryTimeIssue] {
  guard preparation.owner is Effect(original) && physical_equal(original, owner) else {
    return Err(ForeignPreparation)
  }
  match check_client_query_time_request(preparation, request, definition) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if bind_client_effect_compiled_run(owner, allowed, definition) is Err(_) {
    return Err(ForeignRun)
  }
  if preparation.context is Some(original) {
    if @publication.query_evaluation_time_matches(
        original,
        allowed.admission,
        definition,
      ) {
      return Ok(original)
    }
    return Err(ForeignRun)
  }
  let time = match
    @publication.bind_query_evaluation_time(
      allowed.admission,
      definition,
      prepared_client_effect_identity(owner).program_definition_cid,
      prepared_client_effect_computation_semantics_cid(owner),
      prepared_client_effect_computation_environment_cid(owner),
    ) {
    Ok(value) => value
    Err(issue) => return Err(RunBinding(issue))
  }
  preparation.definition = Some(definition)
  preparation.context = Some(time)
  Ok(time)
}

///|
/// Reopening uses the saved admitted definition, never a replacement sample.
pub fn restore_client_effect_query_evaluation_time(
  owner : PreparedClientEffectComputation,
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
) -> Result[@publication.QueryEvaluationTime, ClientQueryTimeIssue] {
  if bind_client_effect_compiled_run(owner, allowed, definition) is Err(_) {
    return Err(ForeignRun)
  }
  guard @publication.run_definition_lifetime(definition) is Some((created, _)) else {
    return Err(ForeignRun)
  }
  let preparation = match
    prepare_client_effect_query_time(owner, request, created) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  bind_client_effect_query_evaluation_time(
    preparation, owner, allowed, definition, request,
  )
}

///|
pub fn restore_client_query_evaluation_time(
  owner : PreparedClientProgram,
  compilation : ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
) -> Result[@publication.QueryEvaluationTime, ClientQueryTimeIssue] {
  if !client_compiled_run_matches(compilation, owner) ||
    check_client_compiled_run_definition(compilation, definition) is Err(_) {
    return Err(ForeignRun)
  }
  guard @publication.run_definition_lifetime(definition) is Some((created, _)) else {
    return Err(ForeignRun)
  }
  let preparation = match prepare_client_query_time(owner, request, created) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  bind_client_query_evaluation_time(
    preparation, owner, compilation, definition, request,
  )
}

///|
pub fn restore_client_effect_query_time_preparation(
  owner : PreparedClientEffectComputation,
  allowed : ClientEffectAllowedRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
) -> Result[ClientQueryTimePreparation, ClientQueryTimeIssue] {
  if bind_client_effect_compiled_run(owner, allowed, definition) is Err(_) {
    return Err(ForeignRun)
  }
  guard @publication.run_definition_lifetime(definition) is Some((created, _)) else {
    return Err(ForeignRun)
  }
  let preparation = match
    prepare_client_effect_query_time(owner, request, created) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    bind_client_effect_query_evaluation_time(
      preparation, owner, allowed, definition, request,
    ) {
    Ok(_) => Ok(preparation)
    Err(issue) => Err(issue)
  }
}

///|
pub fn restore_client_query_time_preparation(
  owner : PreparedClientProgram,
  compilation : ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : ClientRequestIdentity,
) -> Result[ClientQueryTimePreparation, ClientQueryTimeIssue] {
  if !client_compiled_run_matches(compilation, owner) ||
    check_client_compiled_run_definition(compilation, definition) is Err(_) {
    return Err(ForeignRun)
  }
  guard @publication.run_definition_lifetime(definition) is Some((created, _)) else {
    return Err(ForeignRun)
  }
  let preparation = match prepare_client_query_time(owner, request, created) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match
    bind_client_query_evaluation_time(
      preparation, owner, compilation, definition, request,
    ) {
    Ok(_) => Ok(preparation)
    Err(issue) => Err(issue)
  }
}

///|
fn client_query_time_acquisition_context(
  preparation : ClientQueryTimePreparation,
  request : ClientRequestIdentity,
) -> @publication.QueryEvaluationTime? {
  guard physical_equal(preparation.request, request) &&
    preparation.definition is Some(definition) &&
    preparation.context is Some(context) &&
    physical_equal(
      @publication.query_evaluation_time_definition(context),
      definition,
    ) &&
    @publication.query_evaluation_time_value(context).value
    is @values.Timestamp(actual) &&
    preparation.sample.value is @values.Timestamp(expected) &&
    actual == expected else {
    return None
  }
  Some(context)
}

///|
fn prepare_client_acquisition_at_query_time(
  prepared : PreparedClientProgram,
  stage : Int,
  source_index : Int,
  context : @publication.QueryEvaluationTime,
) -> Result[@acquisition.QueryAcquisition, ClientAcquisitionIssue] {
  let identity = @checked.source_identity(
    @strategy.graph_program(prepared.graph),
  )
  guard @context.program_identity_stage_at(identity, stage) is Some(_) else {
    return Err(MissingStage)
  }
  guard @context.program_identity_stage_requests(identity, stage)
    is Some(requests) else {
    return Err(MissingRequests)
  }
  @acquisition.derive_query_acquisition_with_query_time(
    requests, source_index, 1000000, context,
  ).map_err(issue => UnsupportedAcquisition(issue))
}

///|
/// Bind physical predicate preparation only after the exact checked request
/// and Run have sealed the original sample. No caller Timestamp is accepted.
pub fn prepare_client_query_acquisition_at_query_time(
  prepared : PreparedClientProgram,
  stage : Int,
  source_index : Int,
  preparation : ClientQueryTimePreparation,
  request : ClientRequestIdentity,
) -> Result[@acquisition.QueryAcquisition, ClientAcquisitionIssue] {
  guard preparation.owner is Query(original) &&
    physical_equal(original, prepared) &&
    client_query_time_acquisition_context(preparation, request) is Some(context) else {
    return Err(UnsupportedAcquisition(@acquisition.UnboundRequest))
  }
  prepare_client_acquisition_at_query_time(
    prepared, stage, source_index, context,
  )
}

///|
pub fn prepare_client_effect_query_acquisition_at_query_time(
  prepared : PreparedClientEffectComputation,
  stage : Int,
  source_index : Int,
  preparation : ClientQueryTimePreparation,
  request : ClientRequestIdentity,
) -> Result[@acquisition.QueryAcquisition, ClientAcquisitionIssue] {
  guard preparation.owner is Effect(original) &&
    physical_equal(original, prepared) &&
    client_query_time_acquisition_context(preparation, request) is Some(context) else {
    return Err(UnsupportedAcquisition(@acquisition.UnboundRequest))
  }
  prepare_client_acquisition_at_query_time(
    client_effect_program_view(prepared),
    stage,
    source_index,
    context,
  )
}

///|
fn prepare_client_time_bound_query_requirement(
  prepared : PreparedClientProgram,
  generated : @execution.GeneratedSequence,
  acquisition : @acquisition.QueryAcquisition,
  context : @publication.QueryEvaluationTime,
  guards : @planning.QueryLogicalGuards,
  limits : @planning.QueryMaterialLimits,
) -> Result[@planning.QueryRequirement, ClientQueryRequirementIssue] {
  let bound = match
    @execution.bind_generated_sequence_query_time(
      generated,
      context,
      limits.max_work,
      limits.max_nodes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Sequence(@query.Execution(issue)))
  }
  prepare_client_query_requirement_from_acquisition(
    prepared, bound, acquisition, guards, limits,
  )
}

///|
pub fn prepare_client_query_requirement_at_query_time(
  prepared : PreparedClientProgram,
  generated : @execution.GeneratedSequence,
  stage : Int,
  source_index : Int,
  preparation : ClientQueryTimePreparation,
  request : ClientRequestIdentity,
  guards : @planning.QueryLogicalGuards,
  limits : @planning.QueryMaterialLimits,
) -> Result[@planning.QueryRequirement, ClientQueryRequirementIssue] {
  let acquisition = match
    prepare_client_query_acquisition_at_query_time(
      prepared, stage, source_index, preparation, request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Acquisition(issue))
  }
  guard client_query_time_acquisition_context(preparation, request)
    is Some(context) else {
    return Err(Acquisition(UnsupportedAcquisition(@acquisition.UnboundRequest)))
  }
  prepare_client_time_bound_query_requirement(
    prepared, generated, acquisition, context, guards, limits,
  )
}

///|
pub fn prepare_client_effect_query_requirement_at_query_time(
  prepared : PreparedClientEffectComputation,
  generated : @execution.GeneratedSequence,
  stage : Int,
  source_index : Int,
  preparation : ClientQueryTimePreparation,
  request : ClientRequestIdentity,
  guards : @planning.QueryLogicalGuards,
  limits : @planning.QueryMaterialLimits,
) -> Result[@planning.QueryRequirement, ClientQueryRequirementIssue] {
  let acquisition = match
    prepare_client_effect_query_acquisition_at_query_time(
      prepared, stage, source_index, preparation, request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Acquisition(issue))
  }
  guard client_query_time_acquisition_context(preparation, request)
    is Some(context) else {
    return Err(Acquisition(UnsupportedAcquisition(@acquisition.UnboundRequest)))
  }
  prepare_client_time_bound_query_requirement(
    client_effect_program_view(prepared),
    generated,
    acquisition,
    context,
    guards,
    limits,
  )
}

///|
/// Same prepared Program/occurrence and original invocation context. This
/// reads completed immutable binding DATA; it issues no current/Run permission.
pub fn client_query_requirement_matches_original_query_time(
  prepared : PreparedClientProgram,
  stage : Int,
  source_index : Int,
  requirement : @planning.QueryRequirement,
  selected : ClientQueryTimePreparation?,
  request : ClientRequestIdentity,
) -> Bool {
  if !client_query_requirement_matches_program(
      prepared, stage, source_index, requirement,
    ) {
    return false
  }
  let acquisition = @query.query_sequence_requirement(
    @planning.query_material_owner(
      @planning.query_requirement_material(requirement),
    ),
  )
  match selected {
    None => @acquisition.query_acquisition_query_time(acquisition) is None
    Some(original) => {
      guard original.owner is Query(owner) &&
        physical_equal(owner, prepared) &&
        client_query_time_acquisition_context(original, request)
        is Some(context) &&
        @acquisition.query_acquisition_query_time(acquisition) is Some(captured) else {
        return false
      }
      physical_equal(context, captured)
    }
  }
}
