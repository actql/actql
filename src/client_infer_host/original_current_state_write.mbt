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
// A codec borrow of the existing cursor/encoder, not another resource Owner.
// Installation funds all four fields, backing and finish-text overlap before
// entry. Completion is set only by the original Writer's actual complete poll.
struct OriginalModelCurrentStateWriter {
  mut park : @publication_host.ClientModelResourcePark?
  mut cursor : @publication_host.ClientModelCurrentStateWrite?
  mut writer : @encode.Writer?
  mut complete : Bool
}

///|
pub fn prepare_original_model_current_state_writer(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[OriginalModelCurrentStateWriter, @resources.OriginalStateWriteIssue] {
  guard original_model_resource_park_current(active, scope, park) is Some(_) else {
    return Err(@resources.Original(@resources.ChangedOriginalState))
  }
  if max_bytes < 0 || max_nodes < 1 || max_depth < 0 {
    return Err(@resources.Encoding)
  }
  // This provisional encoder is already covered by the original installation
  // envelope. A spent/foreign cursor refusal cancels only this encoder, never
  // the park, Model, read, planning charge or original cleanup responsibility.
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(@resources.Encoding)
  }
  match start_original_model_current_state_write(active, scope, park, writer) {
    Err(issue) => {
      @encode.cancel_writer(writer)
      Err(issue)
    }
    Ok(cursor) => Ok({ park: Some(park), cursor: Some(cursor), writer: Some(writer), complete: false, })
  }
}

///|
pub fn advance_original_model_current_state_writer(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  value : OriginalModelCurrentStateWriter,
  quantum : Int,
) -> @resources.OriginalStateWritePoll {
  guard value.park is Some(original) && physical_equal(original, park) else {
    return @resources.StateWriteFailed(@resources.Original(@resources.ChangedOriginalState), work=0)
  }
  guard value.cursor is Some(cursor) && value.writer is Some(_) &&
    !value.complete else {
    return @resources.StateWriteFailed(@resources.Terminal, work=0)
  }
  let poll = advance_original_model_current_state_write(active, scope, park, cursor, quantum)
  if poll is @resources.StateWriteComplete(..) {
    value.complete = true
  }
  poll
}

///|
pub fn finish_original_model_current_state_writer(
  active : Execution,
  scope : @publication_host.ClientModelReadScope,
  park : @publication_host.ClientModelResourcePark,
  value : OriginalModelCurrentStateWriter,
) -> Result[String, @resources.OriginalStateWriteIssue] {
  guard value.park is Some(original) && physical_equal(original, park) &&
    original_model_resource_park_current(active, scope, park) is Some(_) else {
    return Err(@resources.Original(@resources.ChangedOriginalState))
  }
  guard value.complete && value.writer is Some(writer) else {
    return Err(@resources.Terminal)
  }
  let wire = @encode.finish(writer) catch {
    _ => {
      cancel_original_model_current_state_writer(value)
      return Err(@resources.Encoding)
    }
  }
  cancel_original_model_current_state_writer(value)
  // This immutable data String stays in the installing caller's funded
  // custody through same-Store ACK or failure. It issues no restoration grant.
  Ok(wire)
}

///|
pub fn cancel_original_model_current_state_writer(
  value : OriginalModelCurrentStateWriter,
) -> Unit {
  if value.cursor is Some(cursor) {
    @publication_host.cancel_client_model_current_state_write(cursor)
  }
  if value.writer is Some(writer) {
    @encode.cancel_writer(writer)
  }
  value.cursor = None
  value.writer = None
  value.park = None
  value.complete = false
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
