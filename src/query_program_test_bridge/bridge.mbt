///|
// Test-only adapter for Program equivalence and checker integration. The
// installed SDK continues to submit an ordinary JSON Program.
fn limits() -> @query.Limits {
  let source : @source.ParseLimits = {
    max_input_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let tree : @wire.Limits = {
    max_nodes: 10000,
    max_depth: 100,
    max_string_bytes: 10000,
    max_total_string_bytes: 100000,
  }
  {
    source: {
      source,
      tree,
      max_origin_entries: 20000,
      max_output_bytes: 100000,
    },
    program: { source, tree, max_stages: 10, },
    max_expression_work: 10000,
    max_join_output_rows: 1000L,
    max_collection_items: 1000L,
    max_collection_bytes: 10000L,
  }
}

///|
fn syntax_limits() -> @syntax.QueryLimits {
  let lexical : @syntax.LexicalLimits = {
    max_source_bytes: 100000,
    max_tokens: 10000,
    max_literal_bytes: 10000,
    max_work: 100000,
  }
  {
    lexical,
    expression: { lexical, max_nodes: 10000, max_depth: 100, max_work: 100000, },
    max_syntax_nodes: 10000,
    max_cte_count: 100,
    max_work: 100000,
  }
}

///|
pub suberror QueryBridgeRejected {
  QueryBridgeRejected
}

///|
fn graph_bridge_array(
  text : String,
) -> Array[@wire.Cursor] raise QueryBridgeRejected {
  let source = match @source.parse_json(text, limits().source.source) {
    Ok(value) => value
    Err(_) => raise QueryBridgeRejected
  }
  let cursor = match @wire.admit(source, limits().source.tree) {
    Ok(value) => value
    Err(_) => raise QueryBridgeRejected
  }
  match @wire.elements(cursor) {
    Ok(value) => value
    Err(_) => raise QueryBridgeRejected
  }
}

///|
fn graph_bridge_fields(
  text : String,
) -> Array[String] raise QueryBridgeRejected {
  let fields : Array[String] = []
  for field in graph_bridge_array(text) {
    match @wire.text(field) {
      Ok(name) => fields.push(name)
      Err(_) => raise QueryBridgeRejected
    }
  }
  fields
}

///|
#export_name("compileQueryJson")
pub fn compile_query_json(
  text : String,
  relation : String,
  input_name : String,
  declaration_json : String,
  fields_json : String,
  program_id : String,
) -> String {
  compile_query_json_checked(
    text,
    relation,
    input_name,
    declaration_json,
    fields_json,
    program_id,
    false,
    None,
  ) catch {
    _ => ""
  }
}

///|
#export_name("compileValuesQueryJson")
pub fn compile_values_query_json(
  text : String,
  relation : String,
  input_name : String,
  values_step_json : String,
  fields_json : String,
  program_id : String,
) -> String {
  compile_query_json_checked(
    text,
    relation,
    input_name,
    values_step_json,
    fields_json,
    program_id,
    true,
    None,
  ) catch {
    _ => ""
  }
}

///|
#export_name("compileCapturedQueryJson")
pub fn compile_captured_query_json(
  text : String,
  relation : String,
  input_name : String,
  declaration_json : String,
  fields_json : String,
  program_id : String,
) -> String {
  compile_query_json_checked(
    text,
    relation,
    input_name,
    declaration_json,
    fields_json,
    program_id,
    false,
    Some("capture"),
  ) catch {
    _ => ""
  }
}

///|
fn compile_query_json_checked(
  text : String,
  relation : String,
  input_name : String,
  declaration_json : String,
  fields_json : String,
  program_id : String,
  generated_values : Bool,
  captured_stage : String?,
) -> String raise {
  let parsed = match @syntax.parse_query(text, syntax_limits()) {
    Ok(query) => query
    Err(_) => raise QueryBridgeRejected
  }
  let declaration = match
    @source.parse_json(declaration_json, limits().source.source) {
    Ok(node) => node
    Err(_) => raise QueryBridgeRejected
  }
  let declaration = match @wire.admit(declaration, limits().source.tree) {
    Ok(cursor) => cursor
    Err(_) => raise QueryBridgeRejected
  }
  let fields = match @source.parse_json(fields_json, limits().source.source) {
    Ok(node) => node
    Err(_) => raise QueryBridgeRejected
  }
  let fields = match @wire.admit(fields, limits().source.tree) {
    Ok(cursor) => cursor
    Err(_) => raise QueryBridgeRejected
  }
  let fields = match @wire.elements(fields) {
    Ok(fields) => fields
    Err(_) => raise QueryBridgeRejected
  }
  let visible_fields : Array[String] = []
  for field in fields {
    match @wire.text(field) {
      Ok(name) => visible_fields.push(name)
      Err(_) => raise QueryBridgeRejected
    }
  }
  let context : @query.Context = {
    program_id,
    stage_id: "main",
    stage_result: "rows",
    result_name: "answer",
    captured_stage,
    parameter_declarations: None,
    inputs: [
      {
        relation: [{ value: relation, quoted: false, }],
        name: input_name,
        source: if generated_values {
          @query.GeneratedValues(declaration)
        } else {
          @query.Captured(declaration)
        },
        visible_fields,
        graph_bindings: [],
      },
    ],
    graph_inputs: [],
  }
  let program = match @query.compile(parsed, context, limits()) {
    Ok(program) => program
    Err(_) => raise QueryBridgeRejected
  }
  let writer = @encode.writer(100000, 10000, 100)
  @program.emit_metadata_stripped_program(program, writer)
  @encode.finish(writer)
}

///|
#export_name("compileGeneratedGraphQueryJson")
pub fn compile_generated_graph_query_json(
  text : String,
  relation : String,
  steps_json : String,
  node_fields_json : String,
  edge_fields_json : String,
  program_id : String,
) -> String {
  try {
    let parsed = match @syntax.parse_query(text, syntax_limits()) {
      Ok(value) => value
      Err(_) => raise QueryBridgeRejected
    }
    let steps = graph_bridge_array(steps_json)
    let nodes = graph_bridge_fields(node_fields_json)
    let edges = graph_bridge_fields(edge_fields_json)
    let context : @query.Context = {
      program_id,
      stage_id: "main",
      stage_result: "rows",
      result_name: "answer",
      captured_stage: None,
      parameter_declarations: None,
      inputs: [],
      graph_inputs: [
        {
          relation: [{ value: relation, quoted: false, }],
          name: relation,
          source: @query.GeneratedGraph(steps),
          node_fields: nodes,
          edge_fields: edges,
        },
      ],
    }
    let program = match @query.compile(parsed, context, limits()) {
      Ok(value) => value
      Err(_) => raise QueryBridgeRejected
    }
    let writer = @encode.writer(100000, 10000, 100)
    @program.emit_metadata_stripped_program(program, writer)
    @encode.finish(writer)
  } catch {
    _ => ""
  }
}

///|
fn values_input(
  name : String,
  declaration_json : String,
  fields_json : String,
) -> @query.Input raise QueryBridgeRejected {
  let declaration = match
    @source.parse_json(declaration_json, limits().source.source) {
    Ok(node) => node
    Err(_) => raise QueryBridgeRejected
  }
  let declaration = match @wire.admit(declaration, limits().source.tree) {
    Ok(cursor) => cursor
    Err(_) => raise QueryBridgeRejected
  }
  let field_node = match
    @source.parse_json(fields_json, limits().source.source) {
    Ok(node) => node
    Err(_) => raise QueryBridgeRejected
  }
  let field_node = match @wire.admit(field_node, limits().source.tree) {
    Ok(cursor) => cursor
    Err(_) => raise QueryBridgeRejected
  }
  let fields = match @wire.elements(field_node) {
    Ok(fields) => fields
    Err(_) => raise QueryBridgeRejected
  }
  let visible_fields : Array[String] = []
  for field in fields {
    match @wire.text(field) {
      Ok(value) => visible_fields.push(value)
      Err(_) => raise QueryBridgeRejected
    }
  }
  {
    relation: [{ value: name, quoted: false, }],
    name,
    source: @query.GeneratedValues(declaration),
    visible_fields,
    graph_bindings: [],
  }
}

///|
#export_name("compileTwoValuesSetQueryJson")
pub fn compile_two_values_set_query_json(
  text : String,
  left_name : String,
  left_json : String,
  left_fields_json : String,
  right_name : String,
  right_json : String,
  right_fields_json : String,
  program_id : String,
) -> String {
  try {
    let parsed = match @syntax.parse_query(text, syntax_limits()) {
      Ok(query) => query
      Err(_) => raise QueryBridgeRejected
    }
    let context : @query.Context = {
      program_id,
      stage_id: "main",
      stage_result: "rows",
      result_name: "answer",
      captured_stage: None,
      parameter_declarations: None,
      inputs: [
        values_input(left_name, left_json, left_fields_json),
        values_input(right_name, right_json, right_fields_json),
      ],
      graph_inputs: [],
    }
    let program = match @query.compile(parsed, context, limits()) {
      Ok(program) => program
      Err(_) => raise QueryBridgeRejected
    }
    let writer = @encode.writer(100000, 10000, 100)
    @program.emit_metadata_stripped_program(program, writer)
    @encode.finish(writer)
  } catch {
    _ => ""
  }
}
