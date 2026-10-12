///|
// Each label predicate sees the same original input scope and Parameter owner.
// Earlier labels introduce output names only after common sequence checking.
fn script_sequence_pattern(
  construction : Construction,
  argument : @query.SgaArgument,
  query : @query.Query,
  input : Input,
  sources : ScriptSources,
  limits : Limits,
) -> @builder.Node raise Abort {
  guard argument is ListValue(parts) else { raise Abort(InvalidQuery) }
  construction.array(parts.map(part => {
    guard part is ObjectValue(fields) && fields.all(field=>["as","where"].contains(field.0)) else { raise Abort(InvalidQuery) }
    construction.object(fields.map(field => {
      let value = match (field.0,field.1) {
        ("as", OutputName(name)) => construction.text(name.value)
        ("where", ExpressionValue(predicate)) => {
          let expression=@query.sga_predicate_expression(predicate)
          match script_input_scope(sources,input.name,query_range_name(query)) {
            Some(scope) => append_pipe_expression(construction,expression,scope.visible,scope.ranges,limits.max_expression_work,value_ranges=value_range_names(scope.receivers,scope.scalar_ranges))
            None => append_expression(construction,expression,query,input,columns(input),limits.max_expression_work)
          }
        }
        _ => raise Abort(InvalidQuery)
      }
      (field.0,value)
    }))
  }))
}
