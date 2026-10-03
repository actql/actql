///|
/// Static node_rows layout. This is typing evidence only, not execution,
/// retained content, row order or permission to publish a sparse Result.
struct CheckedPropertyNodeRows {
  source : @decode.Cursor
  input : @carrier.Carrier
  output : @carrier.Carrier
  schema : @row.ConditionalSchema
  id_column : Int
  property_columns : Array[Array[Int]]
  source_properties : Array[Map[Int, Int]]
  usage : Usage
}

///|
/// The definition-keyed profile has a fixed id role and finite declared
/// properties. Property spellings are case-insensitive across definitions;
/// the first admitted spelling is the output name for that shared property.
/// Authored aliases outside the checked Graph contract require separate
/// retained metadata and are not issued by this typing-only check.
pub fn check_property_node_rows(
  source : @decode.Cursor,
  input : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedPropertyNodeRows, Issue] {
  if limits.max_work < 0 ||
    limits.max_nodes < 0 ||
    limits.max_text_bytes < 0 ||
    limits.max_depth < 0 {
    return Err(issue(source, InvalidLimits))
  }
  if @decode.boolean(source) != Ok(true) {
    return Err(issue(source, InvalidBody))
  }
  guard input is @carrier.GraphValue(graph) else {
    return Err(issue(source, WrongCarrier(@carrier.kind(input))))
  }
  let definition = @carrier.graph_property_definition(graph)
  let count = @carrier.property_graph_node_count(definition)
  if limits.max_work == 0 || limits.max_nodes == 0 || count > limits.max_nodes {
    return Err(issue(source, BudgetExceeded))
  }
  let id = @carrier.graph_identity(graph)
  let declarations : Array[Array[(@row.FieldName, @contract.Contract)]] = []
  let definition_properties : Array[Array[String]] = []
  let shared_names : Map[String, String] = Map([])
  let mut remaining = limits.max_work - 1
  let mut total_fields = 0
  for index in 0..<count {
    if remaining == 0 {
      return Err(issue(source, BudgetExceeded))
    }
    remaining -= 1
    let node = @carrier.property_graph_node_at(definition, index).unwrap()
    let properties = @carrier.property_definition_properties(node)
    let width = @carrier.field_count(properties)
    if @carrier.field_set(properties) != @carrier.Closed {
      return Err(issue(source, IncompleteGraph))
    }
    if width > remaining || width >= limits.max_nodes - total_fields {
      return Err(issue(source, BudgetExceeded))
    }
    let fields = [(@row.Unqualified("id"), id)]
    let properties_for_definition = []
    total_fields += 1
    for column in 0..<width {
      remaining -= 1
      let property = @carrier.field_at(properties, column).unwrap()
      guard property.name is @row.Unqualified(name) &&
        property.contract is Some(contract) else {
        return Err(issue(source, IncompleteGraph))
      }
      let folded = name.to_lower()
      if folded == "id" {
        return Err(issue(source, OutputCollision(property.name)))
      }
      let output_name = match shared_names.get(folded) {
        Some(name) => name
        None => {
          shared_names[folded] = name
          name
        }
      }
      fields.push((@row.Unqualified(output_name), contract))
      properties_for_definition.push(output_name)
      total_fields += 1
    }
    declarations.push(fields)
    definition_properties.push(properties_for_definition)
  }
  if count == 0 {
    declarations.push([(@row.Unqualified("id"), id)])
  }
  let (schema, used) = match
    @row.from_definition_fields(
      declarations,
      max_definitions=Int::max(count, 1),
      max_fields=limits.max_nodes,
      max_name_bytes=limits.max_text_bytes,
      max_contract_work=remaining,
    ) {
    Ok(value) => value
    Err(@row.DefinitionLimit | @row.DefinitionSchema(@row.LimitExceeded)) =>
      return Err(issue(source, BudgetExceeded))
    Err(problem) => return Err(issue(source, GraphDeclaration(problem)))
  }
  remaining -= used
  if @row.presence_field_count(schema) >= limits.max_nodes {
    return Err(issue(source, BudgetExceeded))
  }
  let output_columns : Map[String, Int] = Map([])
  let output_width = @row.presence_field_count(schema)
  if output_width > remaining {
    return Err(issue(source, BudgetExceeded))
  }
  remaining -= output_width
  for column in 0..<output_width {
    let field = @row.presence_field_at(schema, column).unwrap()
    output_columns[@row.reference_name(@row.presence_field_name(field))] = column
  }
  let id_column = output_columns.get("id").unwrap()
  let property_columns = []
  let source_properties = []
  for names in definition_properties {
    if names.length() > remaining {
      return Err(issue(source, BudgetExceeded))
    }
    remaining -= names.length()
    let columns = []
    let sources : Map[Int, Int] = Map([])
    for index, name in names {
      let column = output_columns.get(name).unwrap()
      columns.push(column)
      sources[column] = index
    }
    property_columns.push(columns)
    source_properties.push(sources)
  }
  let mut text = limits.max_text_bytes
  for column in 0..<@row.presence_field_count(schema) {
    let field = @row.presence_field_at(schema, column).unwrap()
    let name = @row.reference_name(@row.presence_field_name(field))
    let size = match @scalar.admit_utf8_length(name, text) {
      Ok(value) => value
      Err(_) => return Err(issue(source, BudgetExceeded))
    }
    text -= size
  }
  Ok({
    source,
    input,
    output: @carrier.relation(@carrier.conditional_rows(schema)),
    schema,
    id_column,
    property_columns,
    source_properties,
    usage: {
      work: limits.max_work - remaining,
      nodes: @row.presence_field_count(schema) + 1,
      text_bytes: limits.max_text_bytes - text,
    },
  })
}

///|
pub fn property_node_rows_output(
  value : CheckedPropertyNodeRows,
) -> @carrier.Carrier {
  value.output
}

///|
pub fn property_node_rows_source(
  value : CheckedPropertyNodeRows,
) -> @decode.Cursor {
  value.source
}

///|
pub fn property_node_rows_input(
  value : CheckedPropertyNodeRows,
) -> @carrier.Carrier {
  value.input
}

///|
pub fn property_node_rows_schema(
  value : CheckedPropertyNodeRows,
) -> @row.ConditionalSchema {
  value.schema
}

///|
pub fn property_node_rows_id_column(value : CheckedPropertyNodeRows) -> Int {
  value.id_column
}

///|
pub fn property_node_rows_definition_count(
  value : CheckedPropertyNodeRows,
) -> Int {
  value.property_columns.length()
}

///|
/// This maps the storage definition's canonical property index to the common
/// output schema, including compatible case-spelling differences.
pub fn property_node_rows_property_column(
  value : CheckedPropertyNodeRows,
  definition : Int,
  property : Int,
) -> Int? {
  value.property_columns.get(definition).bind(columns => columns.get(property))
}

///|
/// Read one output column without scanning the whole definition's properties.
/// None is an absent property in this definition; the fixed id role is read
/// separately through property_node_rows_id_column.
pub fn property_node_rows_source_property(
  value : CheckedPropertyNodeRows,
  definition : Int,
  output_column : Int,
) -> Int? {
  value.source_properties
  .get(definition)
  .bind(columns => columns.get(output_column))
}

///|
pub fn property_node_rows_usage(value : CheckedPropertyNodeRows) -> Usage {
  value.usage
}
