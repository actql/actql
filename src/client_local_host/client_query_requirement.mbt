///|
pub(all) enum ClientLocalQueryIssue {
  Sequences
  MissingStage
  Requirement(@publication_host.ClientQueryRequirementIssue)
}

///|
// The same installed single-Query controls used by the real material/requirement
// issuers. Request construction uses their existing writer/collection inventory
// before entry; this is not another query policy or a Provider read allowance.
fn installed_local_query_material_limits() -> @planning.QueryMaterialLimits {
  {
    max_work: 1000000,
    max_fields: 100,
    max_parameters: 100,
    max_bytes: 1000000,
    max_nodes: 100000,
    max_depth: 100,
  }
}

///|
/// The installed Local Host uses the same generated sequence for acquisition
/// checking and the later captured computation. This issues no provider grant.
pub fn prepare_local_query_requirement(
  prepared : @publication_host.PreparedClientProgram,
  stage : Int,
  source_index : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@planning.QueryRequirement, ClientLocalQueryIssue] {
  prepare_local_query_requirement_owned(
    Pure(prepared),
    stage,
    source_index,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
pub fn prepare_effect_local_query_requirement(
  prepared : @publication_host.PreparedClientEffectComputation,
  stage : Int,
  source_index : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@planning.QueryRequirement, ClientLocalQueryIssue] {
  prepare_local_query_requirement_owned(
    Effect(prepared),
    stage,
    source_index,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// Physical preparation retains the same admitted invocation as its capture
/// prefix. Missing or foreign context is never replaced by the legacy path.
pub fn prepare_local_query_requirement_at_query_time(
  prepared : @publication_host.PreparedClientProgram,
  stage : Int,
  source_index : Int,
  original : @publication_host.ClientQueryTimePreparation,
  request : @publication_host.ClientRequestIdentity,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@planning.QueryRequirement, ClientLocalQueryIssue] {
  prepare_local_query_requirement_owned(
    Pure(prepared),
    stage,
    source_index,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    query_time=Some((original, request)),
  )
}

///|
pub fn prepare_effect_local_query_requirement_at_query_time(
  prepared : @publication_host.PreparedClientEffectComputation,
  stage : Int,
  source_index : Int,
  original : @publication_host.ClientQueryTimePreparation,
  request : @publication_host.ClientRequestIdentity,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> Result[@planning.QueryRequirement, ClientLocalQueryIssue] {
  prepare_local_query_requirement_owned(
    Effect(prepared),
    stage,
    source_index,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    query_time=Some((original, request)),
  )
}

///|
fn prepare_local_query_requirement_owned(
  prepared : ClientLocalSequenceOwner,
  stage : Int,
  source_index : Int,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  query_time? : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )? = None,
) -> Result[@planning.QueryRequirement, ClientLocalQueryIssue] {
  if stage < 0 {
    return Err(MissingStage)
  }
  guard prepare_client_query_acquisition_prefix(
      prepared,
      stage,
      source_index,
      installed_contracts,
      values_body,
      fragment_body,
      ordered_body,
      query_time~,
    )
    is Some((sequence, query)) else {
    return Err(Sequences)
  }
  let limits = match installed_local_query_requirement_limits(query) {
    Ok(value) => value
    Err(issue) => return Err(Requirement(@publication_host.Requirement(issue)))
  }
  let guards : @planning.QueryLogicalGuards = {
    max_rows: 100,
    max_value_bytes: 10000,
  }
  match (prepared, query_time) {
    (Pure(value), Some((original, request))) =>
      @publication_host.prepare_client_query_requirement_at_query_time(
        value, sequence, stage, source_index, original, request, guards, limits,
      ).map_err(issue => Requirement(issue))
    (Effect(value), Some((original, request))) =>
      @publication_host.prepare_client_effect_query_requirement_at_query_time(
        value, sequence, stage, source_index, original, request, guards, limits,
      ).map_err(issue => Requirement(issue))
    (Pure(value), None) =>
      @publication_host.prepare_client_query_requirement(
        value, sequence, stage, source_index, guards, limits,
      ).map_err(issue => Requirement(issue))
    (Effect(value), None) =>
      @publication_host.prepare_client_effect_query_requirement(
        value, sequence, stage, source_index, guards, limits,
      ).map_err(issue => Requirement(issue))
  }
}

///|
// The same checked acquisition borrows two schemas. The installed collection
// bound of 100 still bounds each schema and the actual request-field array.
// QueryRequirement consumes their sum as a traversal inventory: a 71-field
// input captured unchanged traverses 142 fields without a larger collection.
// No checker/acquisition is repeated here and no wire/node/work/row policy or
// constructor array bound grows. Query/schema originals remain borrowed.
fn installed_local_query_requirement_limits(
  query : @sourceviews.QueryAcquisition,
) -> Result[@planning.QueryMaterialLimits, @planning.QueryRequirementIssue] {
  let limits = installed_local_query_material_limits()
  let pipeline = @sourceviews.query_acquisition_pipeline(query)
  guard @pipeline.schema_at(
      pipeline,
      @sourceviews.query_acquisition_input(query),
    )
    is Some(input) &&
    @pipeline.schema_at(pipeline, @sourceviews.query_acquisition_capture(query))
    is Some(output) &&
    @sourceviews.pipeline_request_at(
      @sourceviews.query_acquisition_owner(query),
      @sourceviews.query_acquisition_source_index(query),
    )
    is Some(@sourceviews.Direct(_, request)) else {
    return Err(InvalidQuery)
  }
  let input_count = @schema.field_count(input)
  let output_count = @schema.field_count(output)
  if input_count > limits.max_fields ||
    output_count > limits.max_fields ||
    @sourceviews.parameterized_request_field_count(request) > limits.max_fields {
    return Err(FieldLimit)
  }
  // Both counts already fit the installed bound of 100, so this sum cannot
  // overflow. It only quotes two original immutable schema traversals.
  Ok({
    ..limits,
    max_fields: Int::max(limits.max_fields, input_count + output_count),
  })
}
