///|
/// A bounded concrete instance of the shared acquisition requirement. This is
/// not a substitute CheckedProgram, Plan, observation, or Host authorization.
struct QueryRequirement {
  material : QueryMaterial
  program : @context.ProgramSourceIdentity
  guards : QueryLogicalGuards
  wire : @encode.EncodedDocument
  cid : String
  source_ref : String
  source_contract_cid : String
  input_contract_cid : String
  output_contract_cid : String
  stage : String
  input : String
  work : Int
  bytes : Int
  nodes : Int
}

///|
/// Selected logical guards, not estimates or a claim that execution passed.
/// This bounded Local implementation supports nonnegative machine Int limits.
pub(all) struct QueryLogicalGuards {
  max_rows : Int
  max_value_bytes : Int
}

///|
pub(all) enum QueryRequirementIssue {
  InvalidLimits
  ForeignProgram
  InvalidQuery
  FieldLimit
  WorkLimit
  Encoding(@encode.EncodeFailure)
}

///|
fn emit_query_schema(
  schema : @schema.Schema,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  for i in 0..<@schema.field_count(schema) {
    let field = @schema.field_at(schema, i).unwrap()
    @encode.key(writer, @schema.reference_name(field.name))
    @contract.emit_checked(field.contract, writer)
  }
  @encode.end_object(writer)
}

///|
pub fn prepare_query_requirement(
  material : QueryMaterial,
  program : @context.ProgramSourceIdentity,
  guards : QueryLogicalGuards,
  limits : QueryMaterialLimits,
) -> Result[QueryRequirement, QueryRequirementIssue] {
  if guards.max_rows < 0 ||
    guards.max_value_bytes < 0 ||
    limits.max_work < 0 ||
    limits.max_fields < 0 ||
    limits.max_parameters < 0 ||
    limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 {
    return Err(InvalidLimits)
  }
  if limits.max_work < 1 {
    return Err(WorkLimit)
  }
  let query = @execution.query_sequence_requirement(material.owner)
  let requests = @acquisition.query_acquisition_owner(query)
  guard @acquisition.pipeline_request_at(
      requests,
      @acquisition.query_acquisition_source_index(query),
    )
    is Some(@acquisition.Direct(mode, _)) else {
    return Err(InvalidQuery)
  }
  let selected = @acquisition.mode_input(mode)
  let declaration = @acquisition.declaration(selected)
  let contexts = @context.source_rows_requests(
    @context.source_policy_rows(
      @context.source_capacity_context(
        @context.source_producer_capacity(
          @context.preparation_sources(
            @context.source_bindings_preparation(
              @context.program_sources_bindings(
                @context.program_identity_sources(program),
              ),
            ),
          ),
        ),
      ),
    ),
  )
  guard @context.source_request_stage(contexts, declaration.stage_index)
    is Some(expected) &&
    physical_equal(expected, requests) else {
    return Err(ForeignProgram)
  }
  guard @context.program_identity_stage_at(program, declaration.stage_index)
    is Some(stage_identity) else {
    return Err(ForeignProgram)
  }
  let pipeline = @acquisition.query_acquisition_pipeline(query)
  guard @pipeline.schema_at(
      pipeline,
      @acquisition.query_acquisition_input(query),
    )
    is Some(input_schema) &&
    @pipeline.schema_at(pipeline, @acquisition.query_acquisition_capture(query))
    is Some(output_schema) &&
    @acquisition.query_acquisition_capture(query)
    is @pipeline.Step(select_index) else {
    return Err(InvalidQuery)
  }
  let input_count = @schema.field_count(input_schema)
  let output_count = @schema.field_count(output_schema)
  if input_count > limits.max_fields ||
    output_count > limits.max_fields - input_count {
    return Err(FieldLimit)
  }
  // Preflight all schema and projection traversal/copy before allocating. Only
  // the unqualified fields admitted by this single-source profile are accepted.
  let mut remaining = limits.max_work - 1
  for count in [input_count, output_count, output_count] {
    if count > remaining {
      return Err(WorkLimit)
    }
    remaining -= count
  }
  for schema in [input_schema, output_schema] {
    for i in 0..<@schema.field_count(schema) {
      guard @schema.field_at(schema, i).unwrap().name
        is @schema.Unqualified(name) else {
        return Err(InvalidQuery)
      }
      if name.length() > remaining {
        return Err(WorkLimit)
      }
      remaining -= name.length()
    }
  }
  let projection = @relation.projection(
    @acquisition.query_acquisition_select(query),
  )
  if projection.length() != output_count {
    return Err(InvalidQuery)
  }
  let policies = @environment.value_contract_policies(
    @environment.source_view_shape_values(
      @environment.read_mode_shapes(
        @environment.carrier_schema_modes(
          @environment.source_request_carriers(
            @acquisition.catalog_owner(selected),
          ),
        ),
      ),
    ),
  )
  guard @environment.source_view_policy(
      policies,
      @environment.source_request_member(
        @acquisition.selected_contract(selected),
      ),
    )
    is Some(policy) else {
    return Err(InvalidQuery)
  }
  let source_ref = @environment.data_policy_source(
    @environment.source_view_data_policy(policy),
  )
  let source_contract_cid = @acquisition.selected_cid(selected)
  let stage = @program_refs.stage_definition_id(
    @context.stage_identity_definition(stage_identity),
  )
  let input = declaration.input_name
  let budget = QueryMaterialBudget::{
    work: remaining,
    bytes: limits.max_bytes,
    nodes: limits.max_nodes,
    depth: limits.max_depth,
  }
  try {
    let input_contract_cid = material_hash(budget, writer => {
      emit_query_schema(input_schema, writer)
    })
    let output_contract_cid = material_hash(budget, writer => {
      emit_query_schema(output_schema, writer)
    })
    let writer = @encode.writer(
      budget.bytes / 2,
      budget.nodes / 2,
      budget.depth,
    )
    @encode.begin_object(writer)
    @encode.key(writer, "filter")
    @encode.begin_object(writer)
    @encode.key(writer, "expression_cid")
    @encode.string_value(writer, material.filter_cid)
    @encode.key(writer, "occurrence")
    @encode.string_value(
      writer,
      "/steps/" +
      @acquisition.query_acquisition_filter_index(query).to_string() +
      "/filter",
    )
    @encode.end_object(writer)
    @encode.key(writer, "input_contract_cid")
    @encode.string_value(writer, input_contract_cid)
    @encode.key(writer, "logical_guards")
    @encode.begin_object(writer)
    @encode.key(writer, "max_rows")
    @encode.number_value(writer, guards.max_rows.to_double())
    @encode.key(writer, "max_value_bytes")
    @encode.number_value(writer, guards.max_value_bytes.to_double())
    @encode.end_object(writer)
    @encode.key(writer, "output_contract_cid")
    @encode.string_value(writer, output_contract_cid)
    @encode.key(writer, "owner")
    @encode.begin_object(writer)
    @encode.key(writer, "input")
    @encode.string_value(writer, input)
    @encode.key(writer, "program_source_cid")
    @encode.string_value(
      writer,
      @context.program_identity_definition_cid(program),
    )
    @encode.key(writer, "stage")
    @encode.string_value(writer, stage)
    @encode.end_object(writer)
    @encode.key(writer, "parameter_values_cid")
    @encode.string_value(writer, material.parameter_values_cid)
    @encode.key(writer, "request")
    @encode.emit_document(writer, material.request)
    @encode.key(writer, "select")
    @encode.begin_object(writer)
    @encode.key(writer, "fields")
    @encode.begin_array(writer)
    for field in projection {
      @encode.begin_object(writer)
      @encode.key(writer, "input")
      @encode.string_value(writer, @schema.reference_name(field.input))
      @encode.key(writer, "output")
      @encode.string_value(writer, @schema.reference_name(field.output))
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "occurrence")
    @encode.string_value(
      writer,
      "/steps/" + select_index.to_string() + "/select",
    )
    @encode.end_object(writer)
    @encode.key(writer, "source_contract_cid")
    @encode.string_value(writer, source_contract_cid)
    @encode.key(writer, "source_order_cid")
    @encode.null_value(writer)
    @encode.key(writer, "source_ref")
    @encode.string_value(writer, source_ref)
    @encode.key(writer, "source_validation")
    @encode.begin_object(writer)
    @encode.key(writer, "fields")
    @encode.begin_array(writer)
    for i in 0..<input_count {
      @encode.string_value(
        writer,
        @schema.reference_name(@schema.field_at(input_schema, i).unwrap().name),
      )
    }
    @encode.end_array(writer)
    @encode.key(writer, "scope")
    @encode.string_value(writer, "selected_scan")
    @encode.end_object(writer)
    @encode.key(writer, "version")
    @encode.string_value(writer, "actql-query-acquisition/0.1")
    @encode.end_object(writer)
    let wire = @encode.finish_document(writer)
    let before_nodes = budget.nodes
    let cid = material_hash(budget, writer => {
      @encode.emit_document(writer, wire)
    })
    budget.bytes -= @encode.document_bytes(wire)
    budget.nodes -= before_nodes - budget.nodes
    Ok({
      material,
      program,
      guards,
      wire,
      cid,
      source_ref,
      source_contract_cid,
      input_contract_cid,
      output_contract_cid,
      stage,
      input,
      work: limits.max_work - remaining,
      bytes: limits.max_bytes - budget.bytes,
      nodes: limits.max_nodes - budget.nodes,
    })
  } catch {
    issue => Err(Encoding(issue))
  }
}

///|
pub fn query_requirement_cid(value : QueryRequirement) -> String {
  value.cid
}

///|
pub fn query_requirement_document(
  value : QueryRequirement,
) -> @encode.EncodedDocument {
  value.wire
}

///|
pub fn query_requirement_usage(value : QueryRequirement) -> (Int, Int, Int) {
  (value.work, value.bytes, value.nodes)
}

///|
pub fn query_requirement_material(value : QueryRequirement) -> QueryMaterial {
  value.material
}

///|
pub fn query_requirement_program(
  value : QueryRequirement,
) -> @context.ProgramSourceIdentity {
  value.program
}

///|
pub fn query_requirement_guards(value : QueryRequirement) -> QueryLogicalGuards {
  value.guards
}

///|
pub fn query_requirement_source(value : QueryRequirement) -> (String, String) {
  (value.source_ref, value.source_contract_cid)
}

///|
pub fn query_requirement_contracts(
  value : QueryRequirement,
) -> (String, String) {
  (value.input_contract_cid, value.output_contract_cid)
}

///|
pub fn query_requirement_site(value : QueryRequirement) -> (String, String) {
  (value.stage, value.input)
}
