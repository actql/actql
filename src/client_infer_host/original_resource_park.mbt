///|
/// Restrict the original Resource owner only at a checked quiescent Model
/// boundary. No callback/await occurs between the Model check and its fence.
/// This initial private shape does not cover in-flight I/O or issue a cut grant.
pub fn park_original_model_resources(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
) -> Result[@publication_host.ClientModelResourcePark, Issue] {
  park_original_model_resources_impl(active, scope, false)
}

///|
// Explicit prepaid current-census operation. This does not reinterpret an
// ordinary park or adopt physical Writer/Store funding from logical work.
pub fn park_original_model_resources_for_state_write(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
) -> Result[@publication_host.ClientModelResourcePark, Issue] {
  park_original_model_resources_impl(active, scope, true)
}

///|
fn park_original_model_resources_impl(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  write_state : Bool,
) -> Result[@publication_host.ClientModelResourcePark, Issue] {
  guard !active.advancing &&
    !active.cancelled &&
    !active.reclaimed &&
    active.phase is Model &&
    active.rows is Some(rows) &&
    active.call_scope is Some(call_scope) &&
    active.model is Some(model) &&
    active.original_preparation is Some(original) &&
    original.read is Claimed(consumer) &&
    active.run_binding is Some(bound) &&
    active.plan is Some(plan) &&
    @model.model_original_park_candidate(model, rows, call_scope) is Some(_) else {
    return Err(InvalidAdvance)
  }
  if @model.model_execution_mutation_current(model) is Err(issue) {
    return Err(Model(issue))
  }
  // A successful park is returned directly to its existing caller/custody.
  // Do not add a fallible post-fence bind that could discard its only handle.
  let result = if write_state {
    @publication_host.park_client_model_read_consumer_for_state_write(
      scope, consumer, bound.compiled, bound.definition, plan,
    )
  } else {
    @publication_host.park_client_model_read_consumer(
      scope, consumer, bound.compiled, bound.definition, plan,
    )
  }
  result.map_err(issue => OriginalCapacity(@publication_host.Read(issue)))
}

///|
/// Recheck both original Owners after an await; the returned Resource token is
/// unchanged. This observation is not journal COMMIT or resume/send authority.
pub fn original_model_resource_park_current(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
) -> @publication_host.ClientModelResourcePark? {
  guard !active.advancing &&
    !active.cancelled &&
    !active.reclaimed &&
    active.phase is Model &&
    active.rows is Some(rows) &&
    active.call_scope is Some(call_scope) &&
    active.model is Some(model) &&
    active.original_preparation is Some(original) &&
    original.read is Claimed(_) &&
    active.run_binding is Some(bound) &&
    active.plan is Some(plan) &&
    @model.model_original_resource_park_current(model, rows, call_scope, park)
    is Some(_) else {
    return None
  }
  @publication_host.client_model_resource_park_current(
    park,
    scope,
    bound.compiled,
    bound.definition,
    plan,
  )
}

///|
// The original Execution supplies its checked Run/plan; this does not accept
// replacement origin data or require dispatch admission during approval wait.
pub fn begin_original_model_resource_invalidation(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
) -> Result[@publication_host.ClientModelResourceInvalidationRequest, Issue] {
  guard original_model_resource_park_current(active, scope, park) is Some(_) &&
    active.run_binding is Some(bound) && active.plan is Some(plan) else {
    return Err(InvalidAdvance)
  }
  @publication_host.begin_client_model_resource_invalidation(
    park, scope, bound.compiled, bound.definition, plan,
  ).map_err(issue => OriginalCapacity(@publication_host.Read(issue)))
}

///|
pub fn original_model_resource_invalidation_current(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  request : @publication_host.ClientModelResourceInvalidationRequest,
) -> @publication_host.ClientModelResourceInvalidationRequest? {
  guard original_model_resource_park_current(active, scope, park) is Some(_) &&
    active.run_binding is Some(bound) && active.plan is Some(plan) else {
    return None
  }
  @publication_host.client_model_resource_invalidation_current(
    request, park, scope, bound.compiled, bound.definition, plan,
  )
}

///|
// Internal transition AFTER the actual installed journal's nominal four-ref
// check. No callback/await occurs between this final currentness and consume.
// The Node boundary must authenticate that actual journal, never export this
// inner transition by itself. Fence removal is not Model send permission.
pub fn consume_original_model_resource_invalidation(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  request : @publication_host.ClientModelResourceInvalidationRequest,
) -> Result[Unit, Issue] {
  guard original_model_resource_invalidation_current(
      active, scope, park, request,
    ) is Some(_) && active.run_binding is Some(bound) &&
    active.plan is Some(plan) else {
    return Err(InvalidAdvance)
  }
  @publication_host.consume_client_model_resource_invalidation(
    request, park, scope, bound.compiled, bound.definition, plan,
  ).map_err(issue => OriginalCapacity(@publication_host.Read(issue)))
}
