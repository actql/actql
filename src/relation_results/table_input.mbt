///|
/// A private closed Relation input to one Table operation. It cannot serve as a
/// Named Result, a publication port, or evidence that Conditional cells exist.
struct TableInputDefinition {
  name : String
  source : @decode.Cursor
  target : @pipeline.Target
  schema : @schema.Schema
  fields : Array[String]
}

///|
struct CheckedTableInputs {
  pipeline : @pipeline.CheckedPipeline
  source : @decode.Cursor
  definitions : Array[TableInputDefinition]
  names : Map[String, Int]
  usage : Usage
}

///|
fn check_table_inputs_impl(
  pipeline : @pipeline.CheckedPipeline,
  root : @decode.Cursor,
  limits : Limits,
) -> CheckedTableInputs raise Stop {
  if limits.max_results < 0 ||
    limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 {
    fail(root, InvalidLimits)
  }
  let b : Budget = {
    limits,
    work: limits.max_work,
    nodes: limits.max_nodes,
    text: limits.max_text_bytes,
  }
  let object = decoded(@decode.open_object(root), root)
  let names = @decode.object_field_names(root).unwrap()
  if names.is_empty() {
    fail(root, InvalidBody)
  }
  if names.length() > limits.max_results {
    fail(root, BudgetExceeded)
  }
  source_preflight(b, root)
  let inputs : Map[Int, Map[String, @schema.Field]] = Map([])
  let steps : Map[Int, Map[String, @schema.Field]] = Map([])
  let definitions : Array[TableInputDefinition] = []
  let index : Map[String, Int] = Map([])
  for name in names {
    let source = @decode.lookup(object, name).unwrap()
    spend(b, source, 1)
    valid_name(source, name)
    // A private bulk input has no query-order override or public serializer.
    let body = decoded(
      @decode.closed_object(source, ["from", "fields"]),
      source,
    )
    let from = decoded(@decode.required(body, "from"), source)
    let (target, fields) = definition_fields(b, pipeline, from, inputs, steps)
    let selected = decoded(@decode.required(body, "fields"), source)
    let (schema, projection) = closed_fields(
      b,
      selected,
      fields,
      TableInputFields,
    )
    index[name] = definitions.length()
    definitions.push({ name, source, target, schema, fields: projection, })
  }
  {
    pipeline,
    source: root,
    definitions,
    names: index,
    usage: {
      work: limits.max_work - b.work,
      nodes: limits.max_nodes - b.nodes,
      text_bytes: limits.max_text_bytes - b.text,
    },
  }
}

///|
/// Reuse the same bounded source, field and contract admission as Results,
/// while retaining presence in a separate checked type. Completion, physical
/// capture, Table capability and current Effect authority remain obligations.
pub fn check_table_inputs(
  pipeline : @pipeline.CheckedPipeline,
  source : @decode.Cursor,
  limits : Limits,
) -> Result[CheckedTableInputs, Issue] {
  Ok(check_table_inputs_impl(pipeline, source, limits)) catch {
    Stop(issue) => Err(issue)
  }
}

///|
pub fn table_inputs_pipeline(
  value : CheckedTableInputs,
) -> @pipeline.CheckedPipeline {
  value.pipeline
}

///|
pub fn table_inputs_source(value : CheckedTableInputs) -> @decode.Cursor {
  value.source
}

///|
pub fn table_inputs_usage(value : CheckedTableInputs) -> Usage {
  value.usage
}

///|
pub fn table_input_count(value : CheckedTableInputs) -> Int {
  value.definitions.length()
}

///|
pub fn table_input_at(
  value : CheckedTableInputs,
  index : Int,
) -> TableInputDefinition? {
  value.definitions.get(index)
}

///|
pub fn lookup_table_input(
  value : CheckedTableInputs,
  name : String,
) -> TableInputDefinition? {
  value.names.get(name).map(index => value.definitions[index])
}

///|
pub fn table_input_name(value : TableInputDefinition) -> String {
  value.name
}

///|
pub fn table_input_source(value : TableInputDefinition) -> @decode.Cursor {
  value.source
}

///|
pub fn table_input_target(value : TableInputDefinition) -> @pipeline.Target {
  value.target
}

///|
pub fn table_input_schema(value : TableInputDefinition) -> @schema.Schema {
  value.schema
}

///|
pub fn table_input_fields(value : TableInputDefinition) -> Array[String] {
  value.fields.copy()
}
