///|
// A private borrow of the SAME original read and its dedicated encoder, not a
// new resource Owner or cleanup machine. Bootstrap must cover this view, Writer
// construction/backing, census validation and finish-text overlap BEFORE entry.
// The caller keeps the returned text funded through Store ACK or failed-write
// cleanup. Codec completion and content bytes issue no restoration/send grant.
struct ClientNodeModelStateWriter {
  mut read : ClientModelReadPreparation?
  mut writer : @encode.Writer?
}

///|
pub(all) enum ClientNodeModelStateIssue {
  Layout(ClientModelPreparationLayoutIssue)
  State(@resources.OriginalStateWriteIssue)
} derive(Eq, Debug)

///|
// The original scope binding, selected layout and current bootstrap are checked
// before allocating an encoder. The existing resource issuer rechecks the same
// origin and spends planning/reserves read exactly once; this is NOT a fallback
// to the normal descriptor issuer or a numerical physical-layout proof.
pub fn prepare_client_node_model_read_state(
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  layout : ClientNodeModelPreparationLayout?,
  installation : @environment.ModelResponseProfileInstallation,
  runtime_artifact_cid : String,
  layout_artifact_cid : String,
  probability : @environment.DecisionProbabilityProfile?,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientNodeModelStateWriter, ClientNodeModelStateIssue] {
  if scope.group is Some(_) {
    return Err(State(@resources.Original(@resources.SpentClaim)))
  }
  // A retired bootstrap cannot fund even the subsequent layout-validation
  // workspace. This guard is non-consuming; the actual prepare repeats it.
  match @resources.check_original_state_write_preparation(scope.identity) {
    Err(issue) => return Err(State(issue))
    Ok(_) => ()
  }
  if !client_model_origin_matches(scope.origin, compiled, definition, plan) {
    return Err(Layout(Read(ForeignRun)))
  }
  match
    check_client_node_model_preparation_layout(
      layout, plan, installation, runtime_artifact_cid, layout_artifact_cid, probability,
    ) {
    Err(issue) => return Err(Layout(issue))
    Ok(_) => ()
  }
  if max_bytes < 0 || max_nodes < 1 || max_depth < 0 {
    return Err(State(@resources.Encoding))
  }
  guard layout is Some(layout) else { return Err(Layout(Unavailable)) }
  let writer = @encode.writer(max_bytes, max_nodes, max_depth) catch {
    _ => return Err(State(@resources.Encoding))
  }
  match
    prepare_client_model_read_state(
      scope,
      writer,
      layout.retained_bytes,
      layout.execution_bytes,
    ) {
    Err(issue) => {
      // A refusal never hides a read, refunds planning, or settles the scope.
      // Only this helper's provisional encoder is cancelled here.
      @encode.cancel_writer(writer)
      Err(State(issue))
    }
    Ok(read) => Ok({ read: Some(read), writer: Some(writer), })
  }
}

///|
// The original read is also needed for cleanup while Writing. It is not an
// available consumer until the existing Owner has completed the Writer.
pub fn client_node_model_state_read(
  value : ClientNodeModelStateWriter,
) -> Result[ClientModelReadPreparation, ClientNodeModelStateIssue] {
  match value.read {
    Some(read) => Ok(read)
    None => Err(State(@resources.Terminal))
  }
}

///|
pub fn advance_client_node_model_read_state(
  value : ClientNodeModelStateWriter,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  quantum : Int,
) -> @resources.OriginalStateWritePoll {
  guard value.read is Some(read) else {
    return @resources.StateWriteFailed(@resources.Terminal, work=0)
  }
  advance_client_model_read_state(read, compiled, definition, plan, quantum)
}

///|
// Finish only the encoder issued with this exact read, after the original
// Owner's Written/current check. Foreign/unfinished/consumed reads cannot finish
// it. No caller-supplied Writer, digest or cleanup Bool establishes association.
pub fn finish_client_node_model_read_state(
  value : ClientNodeModelStateWriter,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Result[String, ClientNodeModelStateIssue] {
  guard value.read is Some(read) && value.writer is Some(writer) else {
    return Err(State(@resources.Terminal))
  }
  if !client_model_read_origin_matches(read, compiled, definition, plan) {
    return Err(State(@resources.Original(@resources.ForeignOrigin)))
  }
  if !client_model_read_available(read, compiled, definition, plan) {
    return Err(State(@resources.Terminal))
  }
  let wire = @encode.finish(writer) catch {
    _ => {
      @encode.cancel_writer(writer)
      value.writer = None
      return Err(State(@resources.Encoding))
    }
  }
  @encode.cancel_writer(writer)
  value.writer = None
  Ok(wire)
}

///|
pub fn stop_client_node_model_read_state(
  value : ClientNodeModelStateWriter,
  scope : ClientModelReadScope,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
) -> Result[Unit, ClientModelReadPreparationIssue] {
  guard value.read is Some(read) else {
    return Err(Resource(@resources.SpentClaim))
  }
  match
    stop_client_model_read_checked(scope, read, compiled, definition, plan) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.writer is Some(writer) {
    @encode.cancel_writer(writer)
    value.writer = None
  }
  Ok(())
}

///|
// Failed cleanup keeps the same opaque read. Only the existing resource Owner's
// successful settlement retires this borrow, including its original graph.
pub fn settle_client_node_model_read_state(
  value : ClientNodeModelStateWriter,
  compiled : ClientCompiledRun,
  definition : @publication.PublicationContract,
  plan : ClientInferPlanGraph,
  physical_cleanup_complete : Bool,
) -> Result[Unit, ClientModelReadPreparationIssue] {
  guard value.read is Some(read) else {
    return Err(Resource(@resources.SpentClaim))
  }
  match
    settle_client_model_read_checked(
      read, compiled, definition, plan, physical_cleanup_complete,
    ) {
    Err(issue) => Err(issue)
    Ok(_) => {
      if value.writer is Some(writer) {
        @encode.cancel_writer(writer)
      }
      value.writer = None
      value.read = None
      Ok(())
    }
  }
}
