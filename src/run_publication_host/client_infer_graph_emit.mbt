///|
// Original Model emitters shared with pre-construction geometry. No original
// binding, policy, graph selection or identity is issued by a measuring writer.
fn emit_client_infer_request_body(
  infer : @infer.CheckedInfer,
  mappings : @lower.PreparedInferInputs,
  writer : @encode.Writer,
) -> Bool raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for index in 0..<@infer.input_binding_count(infer) {
    guard @infer.input_binding_at(infer, index) is Some(binding) &&
      @lower.infer_input_expression_at(mappings, index) is Some(expression) else {
      return false
    }
    @encode.key(writer, @infer.input_binding_role(binding))
    @lower.emit_expression(expression, writer)
  }
  @encode.end_object(writer)
  true
}

///|
fn[C] emit_client_infer_barrier_body(
  writer : @encode.Writer,
  infer : @infer.CheckedInfer,
  egress_requirements_cid : C,
  input_contract_cid : C,
  input_fragment_cid : C,
  limits_cid : C,
  execution_cid : C,
  task_cid : C,
  output_contract_cid : C,
  request_cid : C,
  cid : C?,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  if cid is Some(cid) {
    @encode.key(writer, "barrier_cid")
    emit_cid(cid, writer)
  }
  @encode.key(writer, "egress_requirements_cid")
  emit_cid(egress_requirements_cid, writer)
  @encode.key(writer, "input_contract_cid")
  emit_cid(input_contract_cid, writer)
  @encode.key(writer, "input_fragment_cid")
  emit_cid(input_fragment_cid, writer)
  @encode.key(writer, "input_roles")
  @encode.begin_object(writer)
  for index in 0..<@infer.input_binding_count(infer) {
    let role = @infer.input_binding_role(
      @infer.input_binding_at(infer, index).unwrap(),
    )
    @encode.key(writer, role)
    @encode.string_value(
      writer,
      "/" + role.replace(old="~", new="~0").replace(old="/", new="~1"),
    )
  }
  @encode.end_object(writer)
  @encode.key(writer, "key_fields")
  @encode.begin_array(writer)
  for index in 0..<@infer.key_count(infer) {
    @encode.string_value(
      writer,
      @schema.reference_name(@infer.key_at(infer, index).unwrap().field),
    )
  }
  @encode.end_array(writer)
  @encode.key(writer, "limits_cid")
  emit_cid(limits_cid, writer)
  @encode.key(writer, "model_execution_contract_cid")
  emit_cid(execution_cid, writer)
  @encode.key(writer, "model_task_contract_cid")
  emit_cid(task_cid, writer)
  @encode.key(writer, "on_non_success")
  @encode.string_value(
    writer,
    match @infer.result_mode(infer) {
      Outcomes => "outcomes"
      Fail => "fail"
    },
  )
  @encode.key(writer, "output_contract_cid")
  emit_cid(output_contract_cid, writer)
  @encode.key(writer, "request_fragment_cid")
  emit_cid(request_cid, writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-inference-barrier/0.1")
  @encode.end_object(writer)
}

///|
fn[B, C] emit_client_infer_node_body(
  writer : @encode.Writer,
  barrier : B,
  emit_body : (B, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  barrier_id : String,
  output_port : String,
  input_contract_cid : C,
  output_contract_cid : C,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "barrier")
  emit_body(barrier, writer)
  @encode.key(writer, "barrier_contract_cid")
  @encode.string_value(
    writer,
    @environment.compiler_inference_barrier_contract_cid(),
  )
  @encode.key(writer, "input_contracts")
  @encode.begin_object(writer)
  @encode.key(writer, "input_0")
  emit_cid(input_contract_cid, writer)
  @encode.end_object(writer)
  @encode.key(writer, "input_refs")
  @encode.begin_array(writer)
  @encode.string_value(writer, "input_0")
  @encode.end_array(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "acquisition_barrier")
  @encode.key(writer, "node_id")
  @encode.string_value(writer, barrier_id)
  @encode.key(writer, "output_contracts")
  @encode.begin_object(writer)
  @encode.key(writer, output_port)
  emit_cid(output_contract_cid, writer)
  @encode.end_object(writer)
  @encode.key(writer, "output_ref")
  @encode.string_value(writer, output_port)
  @encode.key(writer, "profile_id")
  @encode.string_value(writer, "actql-infer/0.1")
  @encode.end_object(writer)
}
