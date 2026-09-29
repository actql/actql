///|
// Internal encoding material, not a public constructor or proof of closure.
// The check orchestrator must derive these fields from one admitted Program.
priv struct UnitIdentityMaterial {
  program_id : String
  node_id : String
  local_body : String
  declarations : String
  contracts : String
  imports : Array[String]
  gates : Array[String]
}

///|
fn emit_cids(
  values : Array[String],
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  for value in values {
    @encode.string_value(writer, value)
  }
  @encode.end_array(writer)
}

///|
fn emit_namespace(
  program_id : String,
  node_id : String,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "node_id")
  @encode.string_value(writer, node_id)
  @encode.key(writer, "program_id")
  @encode.string_value(writer, program_id)
  @encode.end_object(writer)
}

///|
// Selection, deduplication and canonical CID ordering precede this emitter.
// Serializing a set does not certify that the selected dependencies are complete.
fn emit_contract_set(
  ordered_cids : Array[String],
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "contracts")
  emit_cids(ordered_cids, writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-local-contracts/0.1")
  @encode.end_object(writer)
}

///|
fn emit_unit_preimage(
  value : UnitIdentityMaterial,
  writer : @encode.Writer,
  self_cid? : String? = None,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "import_interface_cids")
  emit_cids(value.imports, writer)
  @encode.key(writer, "incoming_gate_contract_cids")
  emit_cids(value.gates, writer)
  @encode.key(writer, "local_body_cid")
  @encode.string_value(writer, value.local_body)
  @encode.key(writer, "local_contract_closure_cid")
  @encode.string_value(writer, value.contracts)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "unit_namespace")
  emit_namespace(value.program_id, value.node_id, writer)
  @encode.key(writer, "used_parameter_declarations_cid")
  @encode.string_value(writer, value.declarations)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-local-unit-dependencies/0.1")
  @encode.end_object(writer)
}

///|
fn emit_result_interface(
  input_name : String,
  program_id : String,
  node_id : String,
  unit_cid : String,
  result_name : String,
  type_cid : String,
  writer : @encode.Writer,
  self_cid? : String? = None,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "availability")
  @encode.string_value(writer, "stage_success")
  @encode.key(writer, "input_name")
  @encode.string_value(writer, input_name)
  @encode.key(writer, "producer_namespace")
  emit_namespace(program_id, node_id, writer)
  @encode.key(writer, "producer_result")
  @encode.string_value(writer, result_name)
  @encode.key(writer, "producer_unit_definition_cid")
  @encode.string_value(writer, unit_cid)
  if self_cid is Some(cid) {
    @encode.key(writer, "self_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "value_contract_cid")
  @encode.string_value(writer, type_cid)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-result-import-interface/0.1")
  @encode.end_object(writer)
}
