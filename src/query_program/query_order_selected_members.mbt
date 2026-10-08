///|
// DISTINCT retains evaluated static input paths. They may appear as complete
// subtrees inside ORDER expressions; binding one does not restore its object
// receiver or a different unselected member. Ordinary evaluation stays common.
fn append_distinct_order_member_expression(
  construction : Construction,
  expression : @query.Expression,
  selected_expressions : Array[(@query.Expression, String)],
  input_scope : JoinChainScope,
  aliases : Array[(String, String)],
  resolve : (Array[@query.NamePart]) -> String?,
  active_fields : Array[String],
  max_work : Int,
) -> @builder.Node raise Abort {
  let paths = selected_expressions.filter(pair => {
    active_fields.contains(pair.1) &&
    group_reference_parts(pair.0, @query.expression_root(pair.0)) is Some(_)
  })
  let resolve_input = fn(path : Array[@query.NamePart]) -> String? {
    pipe_slot(path, input_scope.visible, input_scope.ranges)
  }
  let resolve_order_input = fn(path : Array[@query.NamePart]) -> String? {
    match order_output_slot(path, aliases) {
      Some(slot) => Some(slot)
      None => resolve_input(path)
    }
  }
  append_grouped_expression_resolved(
    construction, expression, paths, resolve_input, resolve_order_input, resolve,
    active_fields, max_work,
  ) catch {
    Abort(issue) => {
      if issue is Expression({ issue: @expression.UnknownReference, .. }) {
        raise Abort(UnsupportedOrdering)
      }
      raise Abort(issue)
    }
  }
}
