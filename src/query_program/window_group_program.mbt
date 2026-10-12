///|
// Aggregate expressions use the existing original-input expression owner.
// The common aggregate checker owns fn-specific options, argument domains,
// Boolean filters, ordering completion, NULL and resolved collection bounds.
fn script_window_group_aggregates(
  construction : Construction,
  argument : @query.SgaArgument,
  query : @query.Query,
  input : Input,
  sources : ScriptSources,
  known : Array[Input],
  limits : Limits,
) -> @builder.Node raise Abort {
  guard argument is ObjectValue(aggregates) else { raise Abort(InvalidQuery) }
  construction.object(
    aggregates.map(aggregate => {
      guard aggregate.1 is ObjectValue(fields) else {
        raise Abort(InvalidQuery)
      }
      let body = construction.object(
        fields.map(field => {
          let value = if field.0 == "field" {
            script_carrier_field(construction, field.1, query, input, sources)
          } else if field.0 == "order_by" {
            script_carrier_order(
              construction,
              field.1,
              query,
              input,
              sources,
              known,
              limits,
            )
          } else if ["expr", "filter"].contains(field.0) {
            guard field.1 is ExpressionValue(owner) else {
              raise Abort(InvalidQuery)
            }
            let expression = @query.sga_predicate_expression(owner)
            match
              script_input_scope(sources, input.name, query_range_name(query)) {
              Some(scope) =>
                append_pipe_expression(
                  construction,
                  expression,
                  scope.visible,
                  scope.ranges,
                  limits.max_expression_work,
                  value_ranges=value_range_names(
                    scope.receivers,
                    scope.scalar_ranges,
                  ),
                )
              None =>
                append_expression(
                  construction,
                  expression,
                  query,
                  input,
                  columns(input),
                  limits.max_expression_work,
                )
            }
          } else {
            script_traversal_argument(construction, field.1, known, limits)
          }
          (field.0, value)
        }),
      )
      (aggregate.0, body)
    }),
  )
}
