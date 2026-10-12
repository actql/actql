///|
// The exact Core request, without another retained wrapper or Scope field.
pub type ClientModelResourceInvalidationRequest = @resources.OriginalResourceInvalidationRequest[
  ClientModelReadOrigin,
]

///|
pub fn begin_client_model_resource_invalidation(
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Result[
  ClientModelResourceInvalidationRequest,
  ClientModelReadPreparationIssue,
] {
  guard client_model_resource_park_current(
      park, scope, compiled, definition, plan,
    )
    is Some(_) else {
    return Err(Resource(@resources.ChangedOriginalState))
  }
  @resources.begin_original_resource_invalidation(park, scope.origin).map_err(issue => {
    Resource(issue)
  })
}

///|
pub fn client_model_resource_invalidation_current(
  request : ClientModelResourceInvalidationRequest,
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> ClientModelResourceInvalidationRequest? {
  guard client_model_resource_park_current(
      park, scope, compiled, definition, plan,
    )
    is Some(_) else {
    return None
  }
  @resources.original_resource_invalidation_current(request, park, scope.origin)
}

///|
// Compiled inner seam, NOT a general Node export or journal receipt issuer.
// A's actual private installation handle authenticates same-journal COMMIT and
// exact operation/park/request first. Repeat original Scope/Run/lifecycle here
// before Core consumes; do not demand new current INFER send permission.
pub fn consume_client_model_resource_invalidation(
  request : ClientModelResourceInvalidationRequest,
  park : ClientModelResourcePark,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Result[Unit, ClientModelReadPreparationIssue] {
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) {
    return Err(ForeignRun)
  }
  @resources.consume_original_resource_invalidation(request, park, scope.origin).map_err(issue => {
      Resource(issue)
    },
  )
}
