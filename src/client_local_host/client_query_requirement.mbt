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
// The same checked acquisition borrows the input/output schemas and request
// already admitted by this Program's Source/Environment. Their actual shape,
// not the private standard collection default, supplies the traversal bound.
// Other material policies and the full original issuers remain unchanged.
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
  guard installed_local_query_field_bound(
      @schema.field_count(input),
      @schema.field_count(output),
      @sourceviews.parameterized_request_field_count(request),
    )
    is Some(fields) else {
    return Err(FieldLimit)
  }
  Ok({ ..limits, max_fields: fields, })
}

///|
// Scalar geometry only. A caller cannot issue a Query, Source or permission
// from these counts. Both schema traversals coexist; a request collection may
// be wider. Keep the former default as a conservative floor, not eligibility.
fn installed_local_query_field_bound(
  input : Int,
  output : Int,
  request : Int,
) -> Int? {
  guard input >= 0 && output >= 0 && request >= 0 else { return None }
  let schemas = input.to_int64() + output.to_int64()
  guard schemas <= 2147483647L else { return None }
  Some(
    Int::max(
      installed_local_query_material_limits().max_fields,
      Int::max(schemas.to_int(), request),
    ),
  )
}
