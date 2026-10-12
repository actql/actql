///|
// The supplied Writer is already owned and funded by the original installed
// capture/Store caller. Shape/codec limits do not establish physical funding.
pub fn start_original_model_current_state_write(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  writer : @encode.Writer,
) -> Result[@publication_host.ClientModelCurrentStateWrite, @resources.OriginalStateWriteIssue] {
  guard original_model_resource_park_current(active, scope, park) is Some(_) &&
    active.run_binding is Some(bound) && active.plan is Some(plan) else {
    return Err(@resources.Original(@resources.ChangedOriginalState))
  }
  @publication_host.start_client_model_current_state_write(
    park, scope, bound.compiled, bound.definition, plan, writer,
  )
}

///|
// Recheck both actual original Owners before every bounded block. No Model
// advance, send, restored descriptor/read or journal grant is created here.
pub fn advance_original_model_current_state_write(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  value : @publication_host.ClientModelCurrentStateWrite,
  quantum : Int,
) -> @resources.OriginalStateWritePoll {
  guard original_model_resource_park_current(active, scope, park) is Some(_) &&
    active.run_binding is Some(bound) && active.plan is Some(plan) else {
    return @resources.StateWriteFailed(
      @resources.Original(@resources.ChangedOriginalState), work=0,
    )
  }
  @publication_host.advance_client_model_current_state_write(
    value, park, scope, bound.compiled, bound.definition, plan, quantum,
  )
}
