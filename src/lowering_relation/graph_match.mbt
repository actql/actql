///|
struct PreparedGraphMatch {
  node : PreparedNode
  checked : @graph.CheckedMatch
  predicate : Expression?
}

///|
/// Whether this prepared occurrence matches nodes rather than edges.
pub fn graph_match_nodes(value : PreparedGraphMatch) -> Bool {
  @graph.match_entity(value.checked) == @graph.Nodes
}

///|
pub fn graph_match_definition_index(value : PreparedGraphMatch) -> Int {
  @graph.match_definition_index(value.checked)
}

///|
pub fn graph_match_property_schema(
  value : PreparedGraphMatch,
) -> @carrier.Knowledge {
  @graph.match_property_schema(value.checked)
}

///|
pub fn graph_match_graph_scope_fields(
  value : PreparedGraphMatch,
) -> @carrier.Knowledge {
  @graph.match_graph_scope_fields(value.checked)
}

///|
pub fn graph_match_graph_binding(
  value : PreparedGraphMatch,
  role : String,
) -> @schema.FieldName? {
  @graph.match_graph_binding(value.checked, role)
}

///|
/// The checked Relation schema produced by this match occurrence.
pub fn graph_match_output_schema(value : PreparedGraphMatch) -> @schema.Schema {
  value.node.output_schema.unwrap()
}

///|
/// Number of authored output fields, in authored projection order.
pub fn graph_match_field_count(value : PreparedGraphMatch) -> Int {
  @graph.match_field_count(value.checked)
}

///|
/// One authored output field, in authored projection order.
pub fn graph_match_field_at(
  value : PreparedGraphMatch,
  index : Int,
) -> @schema.FieldName? {
  @graph.match_field_at(value.checked, index)
}

///|
/// Number of checked identities in the node identity-list branch.
pub fn graph_match_id_count(value : PreparedGraphMatch) -> Int {
  @graph.match_id_count(value.checked)
}

///|
/// One checked node identity from the authored identity list.
pub fn graph_match_id_at(
  value : PreparedGraphMatch,
  index : Int,
) -> @value.CheckedValue? {
  @graph.match_id_at(value.checked, index)
}

///|
/// Number of authored edge types, preserving absence versus an empty list.
pub fn graph_match_type_count(value : PreparedGraphMatch) -> Int? {
  @graph.match_type_count(value.checked)
}

///|
/// One authored edge type. Repeated entries remain observable here.
pub fn graph_match_type_at(value : PreparedGraphMatch, index : Int) -> String? {
  @graph.match_type_at(value.checked, index)
}

///|
/// Whether this occurrence contains a checked predicate expression.
pub fn graph_match_has_predicate(value : PreparedGraphMatch) -> Bool {
  value.predicate is Some(_)
}

///|
/// The checked predicate retained by this graph match occurrence.
/// Consumers must evaluate this expression through the common evaluator;
/// it is not permission to rediscover or reinterpret authored syntax.
pub fn graph_match_predicate(value : PreparedGraphMatch) -> Expression? {
  value.predicate
}

///|
/// The predicate-only selections that require no row-expression evaluator.
/// A missing predicate is distinct from a checked literal that selects none.
pub(all) enum GraphMatchLiteralSelection {
  NoLiteralSelection
  SelectNoEntities
  SelectAllEntities
} derive(Eq, Debug)

///|
/// Classify a checked literal predicate without rediscovering source syntax.
pub fn graph_match_literal_selection(
  value : PreparedGraphMatch,
) -> GraphMatchLiteralSelection {
  match value.predicate {
    None => NoLiteralSelection
    Some(expression) =>
      match expression_body(expression) {
        Literal(checked) =>
          match checked.value {
            @value.Boolean(true) => SelectAllEntities
            @value.Boolean(false) | @value.Null => SelectNoEntities
            _ => NoLiteralSelection
          }
        TypedNull => SelectNoEntities
        _ => NoLiteralSelection
      }
  }
}

///|
pub(all) enum GraphMatchIssue {
  InvalidGraphMatchLimits
  InvalidGraphMatchWiring
  GraphMatchPreparationLimit
  GraphMatchExpression(ExpressionIssue)
}

///|
fn prepare_graph_match_node(
  owner : BoundPrepared,
  step_index : Int,
  max_entries~ : Int,
  max_name_bytes~ : Int,
  expressions~ : ExpressionLimits,
) -> Result[(PreparedGraphMatch, Int, Int, ExpressionLimits), GraphMatchIssue] {
  if max_entries < 0 ||
    max_name_bytes < 0 ||
    expressions.max_nodes < 0 ||
    expressions.max_work < 0 ||
    expressions.max_depth < 0 ||
    expressions.max_literal_nodes < 0 ||
    expressions.max_literal_text_bytes < 0 {
    return Err(InvalidGraphMatchLimits)
  }
  guard owner.prepared.nodes.get(step_index) is Some(node) &&
    node.payload is GraphMatchRows(checked) &&
    node.inputs.length() == 1 else {
    return Err(InvalidGraphMatchWiring)
  }
  let fields = @graph.match_field_count(checked)
  let ids = @graph.match_id_count(checked)
  let types = @graph.match_type_count(checked).unwrap_or(0)
  let mut scope_entries = 1
  if @graph.match_property_label(checked) is Some(_) {
    scope_entries += 1
  }
  for role in ["identity", "source", "target"] {
    if @graph.match_graph_binding(checked, role) is Some(_) {
      scope_entries += 1
    }
  }
  let entries = fields + ids + types + scope_entries
  if fields > max_entries ||
    ids > max_entries - fields ||
    types > max_entries - fields - ids ||
    scope_entries > max_entries - fields - ids - types {
    return Err(GraphMatchPreparationLimit)
  }
  let mut name_bytes = 0
  let charge_name = fn(name : String) -> Bool {
    let bytes = @utf8.encode(name).length()
    if bytes > max_name_bytes - name_bytes {
      false
    } else {
      name_bytes += bytes
      true
    }
  }
  if !charge_name(@graph.match_graph_element_definition_name(checked)) {
    return Err(GraphMatchPreparationLimit)
  }
  if @graph.match_property_label(checked) is Some(name) && !charge_name(name) {
    return Err(GraphMatchPreparationLimit)
  }
  for role in ["identity", "source", "target"] {
    if @graph.match_graph_binding(checked, role) is Some(field) &&
      !charge_name(@schema.reference_name(field)) {
      return Err(GraphMatchPreparationLimit)
    }
  }
  for index in 0..<fields {
    guard @graph.match_field_at(checked, index) is Some(field) else {
      return Err(InvalidGraphMatchWiring)
    }
    if !charge_name(@schema.reference_name(field)) {
      return Err(GraphMatchPreparationLimit)
    }
  }
  for index in 0..<types {
    guard @graph.match_type_at(checked, index) is Some(name) else {
      return Err(InvalidGraphMatchWiring)
    }
    if !charge_name(name) {
      return Err(GraphMatchPreparationLimit)
    }
  }
  let (predicate, remaining) = match @graph.match_predicate(checked) {
    None => (None, expressions)
    Some(_) => {
      let (expression, usage) = match
        lower_expression_measured(owner, step_index, 0, expressions) {
        Ok(value) => value
        Err(issue) => return Err(GraphMatchExpression(issue))
      }
      (
        Some(expression),
        {
          ..expressions,
          max_nodes: expressions.max_nodes - usage.nodes,
          max_work: expressions.max_work - usage.work,
          max_literal_nodes: expressions.max_literal_nodes - usage.literal_nodes,
          max_literal_text_bytes: expressions.max_literal_text_bytes -
          usage.literal_bytes,
        },
      )
    }
  }
  Ok(({ node, checked, predicate, }, entries, name_bytes, remaining))
}

///|
fn emit_graph_match_node(
  prepared : PreparedGraphMatch,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, prepared.node.id)
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(out, prepared.node.inputs[0])
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, operation(prepared.node))
  @encode.key(out, "params")
  @encode.begin_object(out)
  @encode.key(out, "definition")
  @encode.string_value(
    out,
    @graph.match_graph_element_definition_name(prepared.checked),
  )
  if @graph.match_property_label(prepared.checked) is Some(label) {
    @encode.key(out, "label")
    @encode.string_value(out, label)
  }
  @encode.key(out, "bindings")
  @encode.begin_object(out)
  for role in ["identity", "source", "target"] {
    if @graph.match_graph_binding(prepared.checked, role) is Some(name) {
      @encode.key(out, role)
      @encode.string_value(out, @schema.reference_name(name))
    }
  }
  @encode.end_object(out)
  @encode.key(out, "fields")
  @encode.begin_array(out)
  for index in 0..<@graph.match_field_count(prepared.checked) {
    let field = @graph.match_field_at(prepared.checked, index).unwrap()
    @encode.string_value(out, @schema.reference_name(field))
  }
  @encode.end_array(out)
  if @graph.match_id_count(prepared.checked) > 0 {
    @encode.key(out, "ids")
    @encode.begin_array(out)
    for index in 0..<@graph.match_id_count(prepared.checked) {
      let value = @graph.match_id_at(prepared.checked, index).unwrap()
      emit_wire_value(value.value, out)
    }
    @encode.end_array(out)
  }
  if @graph.match_type_count(prepared.checked) is Some(count) {
    @encode.key(out, "types")
    @encode.begin_array(out)
    for index in 0..<count {
      @encode.string_value(
        out,
        @graph.match_type_at(prepared.checked, index).unwrap(),
      )
    }
    @encode.end_array(out)
  }
  if prepared.predicate is Some(predicate) {
    @encode.key(out, "where")
    emit_expression(predicate, out)
  }
  @encode.end_object(out)
  @encode.end_object(out)
}
