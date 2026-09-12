///|
struct StageSemantics {
  usage : DeclarationUsage
  index : Int
  references : Index
  body : @body.Body
}

///|
/// Prepare the normative unbound stage preimage from an owned all-Program use
/// check. This identity does not establish complete Input/Effect admission,
/// issuer evidence, executable readiness or a Stage/Unit Definition identity.
pub fn stage_semantics_at(
  usage : DeclarationUsage,
  index : Int,
) -> StageSemantics? {
  usage.inventory.stages
  .get(index)
  .map(stage => {
    usage,
    index,
    references: usage.inventory.locals[index],
    body: @body.parameter_body(stage),
  })
}

///|
pub fn stage_semantics_usage(v : StageSemantics) -> DeclarationUsage {
  v.usage
}

///|
/// Internal source coordinate, excluded from the hash preimage.
pub fn stage_semantics_index(v : StageSemantics) -> Int {
  v.index
}

///|
pub fn emit_stage_semantics(
  v : StageSemantics,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "binding_references")
  emit_binding_references(v.references, writer)
  @encode.key(writer, "bindings")
  emit_used_bindings(v.references, writer)
  @encode.key(writer, "expression_contract_cid")
  @encode.string_value(writer, stage_expression_contract_cid)
  @encode.key(writer, "local_body")
  @body.emit(v.body, writer)
  @encode.key(writer, "parameter_references")
  @parameters.emit_references(v.references.parameters, writer)
  @encode.key(writer, "parameters")
  @parameters.emit_used_declarations(v.references.parameters, writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-stage-semantics/0.1")
  @encode.end_object(writer)
}

///|
pub fn stage_semantics_cid(
  v : StageSemantics,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> String raise @encode.EncodeFailure {
  let writer = @encode.hashing_writer(max_bytes, max_nodes, max_depth)
  emit_stage_semantics(v, writer)
  "sha256:" + @encode.finish_hash(writer)
}
