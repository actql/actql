///|
// Compiler DATA for the real generic file-content Source. There is no Native
// FileReadProfile, transport, activation or page in this original. The same
// checked JOIN still owns correlation, schema, policies and completed rows.
priv struct ClientGenericKeyedPlanBarrierInput {
  fragments : ClientKeyedPlanFragmentInputs
  policies : @checked.KeyedAcquisitionSourcePolicies
  output_policy : @checked.PublicationSourcePolicy
  request_policy_cid : String
  response_policy_cid : String
  response_data_policy_cid : String
  output_contract_cid : String
  request_schema_cid : String
  lookup_execution_cid : String
  mapping : Array[(String, String?, @acquisition.ParameterizedRequestValue?)]
  left_fields : Array[String]
  right_fields : Array[String]
  barrier_id : String
}

///|
fn prepare_client_generic_keyed_plan_barrier_input(
  fragments : ClientKeyedPlanFragmentInputs,
  max_work : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientGenericKeyedPlanBarrierInput, ClientInferPlanGraphIssue] {
  let acquisition = fragments.acquisition
  let selected = @acquisition.keyed_request_input(
    @acquisition.parameterized_keyed_request(
      @acquisition.keyed_join_request(acquisition.binding.join),
    ),
  )
  guard @environment.source_request_file_content(
      @acquisition.selected_contract(selected),
    )
    is Some(_) &&
    client_keyed_plan_program_matches(acquisition, fragments.program) &&
    physical_equal(acquisition.owner, fragments.preparation) &&
    @environment.lookup_execution_policy(
      @acquisition.lookup_bounds_policy(acquisition.binding.bounds),
    )
    is Some(execution) else {
    return Err(ForeignExecution)
  }
  let prepared = @lower.bound_preparation(acquisition.owner)
  let pipeline = @lower.pipeline(prepared)
  guard @lower.preparation_carrier_at(prepared, fragments.left_target)
    is Some(left) &&
    @pipeline.input_at(
      pipeline,
      @acquisition.keyed_join_input(acquisition.binding.join),
    )
    is Some((_, right)) &&
    client_keyed_plan_field_names(left, max_nodes) is Some(left_fields) &&
    client_keyed_plan_field_names(right, max_nodes) is Some(right_fields) &&
    client_task_carrier_contract(right, max_wire_bytes, max_nodes, max_depth)
    is Some(("relation", output_contract_cid)) else {
    return Err(UnsupportedProgram)
  }
  let policies = @checked.prepare_keyed_acquisition_source_policies(
    @strategy.graph_program(fragments.program.graph),
    acquisition.binding,
    max_work,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ) catch {
    _ => return Err(UnsupportedProgram)
  }
  guard physical_equal(policies.original, acquisition.check) &&
    policies.output is Some(output_policy) else {
    return Err(ForeignExecution)
  }
  let request_policy_cid = try {
    let writer = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth)
    @checked.emit_effective_policy(policies.request, writer)
    "sha256:" + @encode.finish_hash(writer)
  } catch {
    _ => return Err(Encoding)
  }
  let template = @acquisition.keyed_join_request(acquisition.binding.join)
  let request = @acquisition.parameterized_keyed_request(template)
  let correlation = @acquisition.keyed_request_correlation(request)
  let count = @environment.source_correlation_pair_count(correlation)
  let static_count = @acquisition.parameterized_keyed_request_field_count(
    template,
  )
  if count <= 0 || count > max_nodes || static_count > max_nodes - count {
    return Err(UnsupportedProgram)
  }
  let mapping : Array[
    (String, String?, @acquisition.ParameterizedRequestValue?),
  ] = []
  for index in 0..<count {
    guard @acquisition.keyed_join_role_at(acquisition.binding.join, index)
      is Some((role, pair)) &&
      client_task_record_role(pair.left) is Some(name) else {
      return Err(UnsupportedProgram)
    }
    mapping.push((role.request.name, Some(name), None))
  }
  for index in 0..<static_count {
    guard @acquisition.parameterized_keyed_request_field_at(template, index)
      is Some(field) else {
      return Err(UnsupportedProgram)
    }
    if field.value is @acquisition.UnboundHostBinding(_) {
      return Err(UnsupportedProgram)
    }
    mapping.push((field.field.slot.field_name, None, Some(field.value)))
  }
  mapping.sort_by((a, b) => @canonical_value.compare_utf16(a.0, b.0))
  for index in 1..<mapping.length() {
    if mapping[index - 1].0 == mapping[index].0 {
      return Err(UnsupportedProgram)
    }
  }
  let selected = @acquisition.keyed_request_input(request)
  let request_schema_cid = @environment.contract_identity(
      @environment.reference_contract(
        @environment.source_request_reference(
          @acquisition.selected_contract(selected),
        ),
      ),
    ).2
  let data_policy = @environment.source_view_data_policy(
    @checked.source_execution_subject(acquisition.check).response_policy.authoritative,
  )
  Ok({
    fragments,
    policies,
    output_policy,
    request_policy_cid,
    response_policy_cid: @checked.source_execution_subject(acquisition.check).response_policy_cid,
    response_data_policy_cid: @environment.contract_identity(
      @environment.data_policy_envelope(data_policy),
    ).2,
    output_contract_cid,
    request_schema_cid,
    lookup_execution_cid: @environment.lookup_execution_cid(execution),
    mapping,
    left_fields,
    right_fields,
    barrier_id: "task_" +
    fragments.task.to_string() +
    "_lookup_" +
    fragments.join_step.to_string(),
  })
}

///|
fn emit_client_generic_keyed_plan_barrier_body(
  value : ClientGenericKeyedPlanBarrierInput,
  cid : String?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let keyed = value.fragments.acquisition
  let request = @acquisition.parameterized_keyed_request(
    @acquisition.keyed_join_request(keyed.binding.join),
  )
  let correlation = @acquisition.keyed_request_correlation(request)
  let cardinality = @environment.source_correlation_cardinality(correlation)
  @encode.begin_object(writer)
  if cid is Some(cid) {
    @encode.key(writer, "barrier_cid")
    @encode.string_value(writer, cid)
  }
  @encode.key(writer, "barrier_id")
  @encode.string_value(writer, value.barrier_id)
  @encode.key(writer, "capacity_guarantee")
  @encode.string_value(writer, "complete")
  @encode.key(writer, "correlation")
  @encode.begin_object(writer)
  @encode.key(writer, "cardinality")
  @encode.string_value(
    writer,
    match cardinality {
      ZeroOrOne => "zero_or_one"
      ZeroOrMany => "zero_or_many"
      One => "one"
      OneOrMany => "one_or_many"
    },
  )
  @encode.key(writer, "identity")
  @encode.begin_array(writer)
  for index in 0..<@environment.source_correlation_identity_count(correlation) {
    @encode.string_value(
      writer,
      @environment.source_correlation_identity_at(correlation, index).unwrap().name,
    )
  }
  @encode.end_array(writer)
  @encode.key(writer, "null_request_policy")
  @encode.string_value(
    writer,
    match
      @join.null_key(@acquisition.keyed_join_operation(keyed.binding.join)) {
      NoMatch => "exclude_from_request"
      Fail => "fail"
    },
  )
  @encode.key(writer, "on")
  @encode.begin_array(writer)
  for index in 0..<@environment.source_correlation_pair_count(correlation) {
    let pair = @environment.source_correlation_pair_at(correlation, index).unwrap()
    @encode.begin_object(writer)
    @encode.key(writer, "request")
    @encode.string_value(writer, pair.request.name)
    @encode.key(writer, "response")
    @encode.string_value(writer, pair.response.name)
    @encode.end_object(writer)
  }
  @encode.end_array(writer)
  @encode.key(writer, "on_duplicate_identity")
  @encode.string_value(writer, "fail")
  @encode.key(writer, "on_excess_cardinality")
  @encode.string_value(writer, "fail")
  @encode.key(writer, "on_missing")
  @encode.string_value(
    writer,
    match cardinality {
      One | OneOrMany => "fail"
      ZeroOrOne | ZeroOrMany => "emit_no_row"
    },
  )
  @encode.key(writer, "on_unrequested_key")
  @encode.string_value(writer, "fail")
  @encode.end_object(writer)
  @encode.key(writer, "correlation_fields")
  @encode.begin_array(writer)
  for index in 0..<@environment.source_correlation_pair_count(correlation) {
    @encode.string_value(
      writer,
      @environment.source_correlation_pair_at(correlation, index).unwrap().response.name,
    )
  }
  @encode.end_array(writer)
  @encode.key(writer, "effective_output_classification")
  emit_client_keyed_plan_classification(
    @checked.publication_policy_classification(value.output_policy),
    writer,
  )
  @encode.key(writer, "effective_output_data_policy_cid")
  @encode.string_value(writer, value.output_policy.cid)
  @encode.key(writer, "effective_request_classification")
  emit_client_keyed_plan_classification(
    @checked.effective_policy_classification(value.policies.request),
    writer,
  )
  @encode.key(writer, "effective_request_data_policy_cid")
  @encode.string_value(writer, value.request_policy_cid)
  @encode.key(writer, "effective_response_classification")
  emit_client_keyed_plan_classification(
    @checked.source_execution_subject(keyed.check).response_policy.classification,
    writer,
  )
  @encode.key(writer, "effective_response_data_policy_cid")
  @encode.string_value(writer, value.response_policy_cid)
  @encode.key(writer, "egress_requirements")
  @encode.begin_object(writer)
  @encode.key(writer, "kind")
  // The checked file-content Source uses its own existing acquisition
  // authority. This issues no Model egress or permission to read the file.
  @encode.string_value(writer, "not_required")
  @encode.end_object(writer)
  @encode.key(writer, "input_artifact_fields")
  emit_client_keyed_plan_names(value.left_fields, writer)
  @encode.key(writer, "input_ref")
  @encode.string_value(writer, "input_0")
  @encode.key(writer, "lookup_execution_cid")
  @encode.string_value(writer, value.lookup_execution_cid)
  @encode.key(writer, "observed_response_fields")
  emit_client_keyed_plan_names(value.right_fields, writer)
  @encode.key(writer, "on_non_success")
  @encode.string_value(writer, "fail")
  @encode.key(writer, "output_contract_cid")
  @encode.string_value(writer, value.output_contract_cid)
  @encode.key(writer, "output_ref")
  @encode.string_value(writer, "rows")
  @encode.key(writer, "request_input_data_policy_cids")
  @encode.begin_array(writer)
  for
    index in 0..<@checked.effective_policy_source_count(value.policies.request) {
    @encode.string_value(
      writer,
      @checked.effective_policy_source_at(value.policies.request, index).unwrap(),
    )
  }
  @encode.end_array(writer)
  @encode.key(writer, "request_mapping")
  @encode.begin_object(writer)
  for (name, field, literal) in value.mapping {
    @encode.key(writer, name)
    @encode.begin_object(writer)
    match (field, literal) {
      (Some(name), None) => {
        @encode.key(writer, "field")
        @encode.string_value(writer, name)
      }
      (None, Some(@acquisition.CheckedLiteral(value))) => {
        @encode.key(writer, "literal")
        @values.emit_checked_wire_value(value, writer)
      }
      (None, Some(@acquisition.BoundParameter(parameter))) => {
        @encode.key(writer, "$param")
        @encode.string_value(writer, parameter.name)
      }
      _ => raise @encode.OutputLimit
    }
    @encode.end_object(writer)
  }
  @encode.end_object(writer)
  @encode.key(writer, "request_schema_cid")
  @encode.string_value(writer, value.request_schema_cid)
  @encode.key(writer, "response_identity_fields")
  @encode.begin_array(writer)
  for index in 0..<@environment.source_correlation_identity_count(correlation) {
    @encode.string_value(
      writer,
      @environment.source_correlation_identity_at(correlation, index).unwrap().name,
    )
  }
  @encode.end_array(writer)
  @encode.key(writer, "response_source_data_policy_cid")
  @encode.string_value(writer, value.response_data_policy_cid)
  @encode.key(writer, "source_input_ref")
  @encode.string_value(
    writer,
    @pipeline.input_at(
      @lower.pipeline(@lower.bound_preparation(keyed.owner)),
      @acquisition.keyed_join_input(keyed.binding.join),
    ).unwrap().0,
  )
  @encode.key(writer, "source_view_contract_cid")
  @encode.string_value(
    writer,
    @acquisition.selected_cid(@acquisition.keyed_request_input(request)),
  )
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-lookup-barrier/0.1")
  @encode.end_object(writer)
}

///|
fn[B] emit_client_generic_keyed_plan_node_body(
  original : ClientGenericKeyedPlanBarrierInput,
  barrier : B,
  emit_barrier : (B, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  input_contract_cid : String,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "barrier")
  emit_barrier(barrier, writer)
  @encode.key(writer, "barrier_contract_cid")
  @encode.string_value(
    writer,
    @environment.compiler_lookup_barrier_contract_cid(),
  )
  @encode.key(writer, "input_contracts")
  @encode.begin_object(writer)
  @encode.key(writer, "input_0")
  @encode.string_value(writer, input_contract_cid)
  @encode.end_object(writer)
  @encode.key(writer, "input_refs")
  @encode.begin_array(writer)
  @encode.string_value(writer, "input_0")
  @encode.end_array(writer)
  @encode.key(writer, "kind")
  @encode.string_value(writer, "acquisition_barrier")
  @encode.key(writer, "node_id")
  @encode.string_value(writer, original.barrier_id)
  @encode.key(writer, "output_contracts")
  @encode.begin_object(writer)
  @encode.key(writer, "rows")
  @encode.string_value(writer, original.output_contract_cid)
  @encode.end_object(writer)
  @encode.key(writer, "output_ref")
  @encode.string_value(writer, "rows")
  @encode.key(writer, "profile_id")
  @encode.string_value(writer, "actql-lookup/0.1")
  @encode.end_object(writer)
}

///|
// The containing private issuer constructs the actual prefix from these same
// retained inputs. Fragment DATA is not accepted as an input authorization.
fn issue_client_generic_keyed_plan_barrier(
  original : ClientGenericKeyedPlanBarrierInput,
  left : ClientTaskFragmentNode,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (ClientTaskFragmentNode, @encode.EncodedDocument),
  ClientInferPlanGraphIssue,
] {
  if left.node_id != original.fragments.left_node_id ||
    left.output_port != original.fragments.left.output ||
    left.output_carrier != "relation" {
    return Err(UnsupportedProgram)
  }
  try {
    let hash = @encode.hashing_writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_generic_keyed_plan_barrier_body(original, None, hash)
    let cid = "sha256:" + @encode.finish_hash(hash)
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_generic_keyed_plan_barrier_body(original, Some(cid), writer)
    let body = @encode.finish_document(writer)
    let node = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_generic_keyed_plan_node_body(
      original,
      body,
      (document, writer) => @encode.emit_document(writer, document),
      left.output_contract_cid,
      node,
    )
    let fragment : ClientTaskFragmentNode = {
      wire: @encode.finish(node),
      node_id: original.barrier_id,
      output_port: "rows",
      logical_cid: cid,
      output_contract_cid: original.output_contract_cid,
      output_carrier: "relation",
    }
    Ok((fragment, body))
  } catch {
    _ => Err(Encoding)
  }
}

///|
priv struct ClientGenericKeyedPlanComponent {
  original : ClientGenericKeyedPlanBarrierInput
  left : ClientTaskFragmentNode
  barrier : ClientTaskFragmentNode
  barrier_body : @encode.EncodedDocument
  joined : ClientTaskFragmentNode
}

///|
fn measure_client_generic_keyed_plan_barrier(
  original : ClientGenericKeyedPlanBarrierInput,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[((Int, Int, Int), (Int, Int, Int)), ClientInferPlanGraphIssue] {
  try {
    let body = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    let cid = "sha256:" + "0".repeat(64)
    emit_client_generic_keyed_plan_barrier_body(original, Some(cid), body)
    let measured = @encode.finish_measurement_usage(body)
    let node = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_generic_keyed_plan_node_body(
      original, measured, emit_client_task_pipeline_measurement, cid, node,
    )
    Ok((measured, @encode.finish_measurement_usage(node)))
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn issue_client_generic_keyed_plan_component(
  original : ClientGenericKeyedPlanBarrierInput,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientGenericKeyedPlanComponent, ClientInferPlanGraphIssue] {
  let (left, joined) = match
    issue_client_keyed_plan_fragments(
      original.fragments,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let (barrier, barrier_body) = match
    issue_client_generic_keyed_plan_barrier(
      original, left, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ original, left, barrier, barrier_body, joined, })
}
