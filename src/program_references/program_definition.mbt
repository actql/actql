///|
struct ProgramDefinition {
  semantics : ProgramSemantics
  semantics_cid : String
  hash_bytes : Int
  hash_nodes : Int
}

///|
/// Hash the exact owned source semantics. Neither the ID nor its semantics CID
/// can be supplied independently. This is an identity, not execution approval.
pub fn prepare_program_definition(
  semantics : ProgramSemantics,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> ProgramDefinition raise @encode.EncodeFailure {
  let writer = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
  emit_program_semantics(semantics, writer)
  let (hash, bytes, nodes) = @encode.finish_hash_usage(writer)
  {
    semantics,
    semantics_cid: "sha256:" + hash,
    hash_bytes: bytes,
    hash_nodes: nodes,
  }
}

///|
pub fn program_definition_semantics(v : ProgramDefinition) -> ProgramSemantics {
  v.semantics
}

///|
pub fn program_definition_semantics_cid(v : ProgramDefinition) -> String {
  v.semantics_cid
}

///|
pub fn program_definition_id(v : ProgramDefinition) -> String {
  @stages.program(@requests.source(v.semantics.usage.inventory.requests)).id
}

///|
/// Work performed by this preparation, excluding stage-hash preparation and
/// the subsequent Definition output. Counts are logical output bytes/nodes.
pub fn program_definition_hash_usage(v : ProgramDefinition) -> (Int, Int) {
  (v.hash_bytes, v.hash_nodes)
}

///|
pub fn emit_program_definition(
  v : ProgramDefinition,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "id")
  @encode.string_value(writer, program_definition_id(v))
  @encode.key(writer, "program_semantics_cid")
  @encode.string_value(writer, v.semantics_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-program-definition/0.1")
  @encode.end_object(writer)
}

///|
pub fn program_definition_cid(
  v : ProgramDefinition,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
  emit_program_definition(v, writer)
  "sha256:" + @encode.finish_hash(writer)
}
