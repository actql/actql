///|
// Establish a source-free value table's visible fields from the ordinary
// expression checker, including empty and NULL ARRAYs. This type lookup does
// not discharge profiles, parameter-value checks or runtime obligations.
fn unnest_source_element(
  expression : @query.Expression,
  declarations : @parameters.Declarations?,
  source_limits : @builder.Limits,
  max_work : Int,
  resolve_parameter : ((String) -> Result[String, @expression.Issue])?,
) -> @contract.Contract? raise Abort {
  let origin = @query.expression_origin(
    expression,
    @query.expression_root(expression),
  )
  let lowered = match
    @expression.lower(
      expression,
      _ => None,
      {
        construction: source_limits,
        expression: {
          max_nodes: source_limits.tree.max_nodes,
          max_depth: source_limits.tree.max_depth,
          max_text_bytes: source_limits.tree.max_total_string_bytes,
          max_tokens: source_limits.tree.max_nodes,
          tree: source_limits.tree,
        },
        max_work,
      },
      resolve_parameter~,
    ) {
    Ok(lowered) => lowered
    // Relation-bound correlation has no field schema in this scope probe.
    // The caller lowers it against the actual row/ranges below; explicit
    // projection does not require guessed element fields. Budget and all
    // other lowerer errors still propagate. Unknown stars remain refused.
    Err({ issue: @expression.UnknownReference, .. }) => return None
    Err(diagnostic) => raise Abort(Expression(diagnostic))
  }
  let typed = match
    @typing.check(
      @expression.expression(lowered),
      { fields: None, left: None, right: None, parameters: declarations, },
      {
        max_nodes: source_limits.tree.max_nodes,
        max_depth: source_limits.tree.max_depth,
        max_work,
        max_text_bytes: source_limits.tree.max_total_string_bytes,
      },
    ) {
    Ok(typed) => typed
    Err({ kind: BudgetExceeded, .. }) =>
      raise Abort(Expression({ issue: @expression.WorkLimit, origin, }))
    Err({ kind: InvalidLimits, .. }) =>
      raise Abort(Expression({ issue: @expression.InvalidLimits, origin, }))
    // No guessed scope for an unresolved, unknown or inadmissible type. The
    // completed Program still undergoes its normal common admission checks.
    Err(_) => return None
  }
  match @typing.result_type(typed).shape {
    @contract.Array(element, ..) => Some(element)
    _ => None
  }
}

///|
// A STRUCT value-table range denotes its original value, but is not an extra
// visible column. Current columns take precedence over a bare range name.
fn unnest_expression_columns(
  visible : Array[(String, String)],
  receivers : Array[(@query.NamePart, String)],
) -> Array[(String, String)] {
  let columns = visible.copy()
  for (name, slot) in receivers {
    if !pipe_name_exists(columns, name) {
      columns.push((name.value, slot))
    }
  }
  columns
}
