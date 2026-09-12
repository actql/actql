///|
struct StageDefinition {
  semantics : StageSemantics
  cid : String
  bytes : Int
  nodes : Int
}

///|
/// Reuse a stage hash already prepared under the Program's cumulative limits.
/// This performs no new hashing; hash_usage is (0, 0), not the inherited cost.
pub fn stage_definition_at(
  program : ProgramSemantics,
  index : Int,
) -> StageDefinition? {
  program.descriptors
  .get(index)
  .map(d => {
    semantics: stage_semantics_at(program.usage, index).unwrap(),
    cid: d.cid,
    bytes: 0,
    nodes: 0,
  })
}

///|
/// Bind the authored ID to this exact owned stage, never to a supplied CID.
/// This source identity is not Unit extraction or executable admission.
pub fn prepare_stage_definition(
  semantics : StageSemantics,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> StageDefinition raise @encode.EncodeFailure {
  let writer = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
  emit_stage_semantics(semantics, writer)
  let (hash, bytes, nodes) = @encode.finish_hash_usage(writer)
  { semantics, cid: "sha256:" + hash, bytes, nodes, }
}

///|
pub fn stage_definition_semantics(v : StageDefinition) -> StageSemantics {
  v.semantics
}

///|
pub fn stage_definition_id(v : StageDefinition) -> String {
  let source = @requests.source(v.semantics.usage.inventory.requests)
  @stages.stage_at(source, v.semantics.index).unwrap().id
}

///|
pub fn stage_definition_semantics_cid(v : StageDefinition) -> String {
  v.cid
}

///|
pub fn stage_definition_hash_usage(v : StageDefinition) -> (Int, Int) {
  (v.bytes, v.nodes)
}

///|
pub fn emit_stage_definition(
  v : StageDefinition,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "id")
  @encode.string_value(writer, stage_definition_id(v))
  @encode.key(writer, "stage_semantics_cid")
  @encode.string_value(writer, v.cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-stage-definition/0.1")
  @encode.end_object(writer)
}

///|
pub fn stage_definition_cid(
  v : StageDefinition,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
  emit_stage_definition(v, writer)
  "sha256:" + @encode.finish_hash(writer)
}
