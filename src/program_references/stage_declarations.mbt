///|
/// The exact used declaration map from this owned stage's semantic envelope.
/// Not effective values, reference occurrences or the whole Program map.
pub fn emit_stage_parameter_declarations(
  v : StageSemantics,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @parameters.emit_used_declarations(v.references.parameters, writer)
}

///|
pub fn stage_parameter_declarations_cid(
  v : StageSemantics,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
  emit_stage_parameter_declarations(v, writer)
  "sha256:" + @encode.finish_hash(writer)
}
