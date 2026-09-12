///|
pub enum SourceStateIssue {
  InvalidLimits
  InvalidOccurrence
  MissingCheckpoint
  Encoding(@encode.EncodeFailure)
}

///|
pub struct SourceStateRequirement {
  identity : ProgramSourceIdentity
  stage : Int
  input : Int
  request : @sourceviews.AcquisitionRequest
  stage_id : String
  input_name : String
  source_view_cid : String
  checkpoint_cid : String
  cid : String
  bytes : Int
  nodes : Int
}

///|
fn emit_source_state_body(
  program : String,
  stage : String,
  name : String,
  view : String,
  checkpoint : String,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for
    (key, value) in [
      ("checkpoint_contract_cid", checkpoint),
      ("initial_position", "explicit_state_required"),
      ("input_name", name),
      ("mode", "changes"),
      ("program_definition_cid", program),
      ("requirement", "required"),
      ("source_view_contract_cid", view),
      ("stage_id", stage),
      ("version", "actql-source-state-requirement/0.1"),
    ] {
    @encode.key(writer, key)
    @encode.string_value(writer, value)
  }
  @encode.end_object(writer)
}

///|
/// Construct from an owned selected request, never from caller-supplied CIDs.
/// Snapshot selections return None; changes do not imply bounded range or Run state.
pub fn prepare_source_state_requirement(
  identity : ProgramSourceIdentity,
  stage : Int,
  input : Int,
  limits : @snapshot.Limits,
) -> Result[SourceStateRequirement?, SourceStateIssue] {
  if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  let requests = identity.sources.operations.preparation.sources.capacity.context.rows.requests
  guard requests.stages.get(stage) is Some(selected) else {
    return Err(InvalidOccurrence)
  }
  guard @sourceviews.pipeline_request_at(selected, input) is Some(request) else {
    return Err(InvalidOccurrence)
  }
  let (mode, resolved, checkpoint) = match request {
    @sourceviews.Direct(mode, _) =>
      (
        @sourceviews.mode_contract(mode),
        @sourceviews.mode_input(mode),
        @sourceviews.mode_checkpoint(mode),
      )
    @sourceviews.Keyed(mode, _) =>
      (
        @sourceviews.keyed_mode_contract(mode),
        @sourceviews.keyed_mode_input(mode),
        @sourceviews.keyed_mode_checkpoint(mode),
      )
  }
  if @environment.read_mode_kind(mode) != @environment.ChangesMode {
    return Ok(None)
  }
  guard checkpoint is Some(checkpoint) else { return Err(MissingCheckpoint) }
  let declaration = @sourceviews.declaration(resolved)
  guard declaration.stage_index == stage &&
    program_identity_stage_at(identity, stage) is Some(source) else {
    return Err(InvalidOccurrence)
  }
  let stage_id = @program_refs.stage_definition_id(
    stage_identity_definition(source),
  )
  let input_name = declaration.input_name
  let source_view_cid = @sourceviews.selected_cid(resolved)
  let checkpoint_cid = @environment.contract_identity(
      @environment.reference_contract(
        @sourceviews.checkpoint_reference(checkpoint),
      ),
    ).2
  try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    emit_source_state_body(
      program_identity_definition_cid(identity),
      stage_id,
      input_name,
      source_view_cid,
      checkpoint_cid,
      writer,
    )
    let (digest, bytes, nodes) = @encode.finish_hash_usage(writer)
    Ok(
      Some({
        identity,
        stage,
        input,
        request,
        stage_id,
        input_name,
        source_view_cid,
        checkpoint_cid,
        cid: "sha256:" + digest,
        bytes,
        nodes,
      }),
    )
  } catch {
    e => Err(Encoding(e))
  }
}
