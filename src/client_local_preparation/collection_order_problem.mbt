///|
/// Project only the original typed query-order causes to a submission Problem.
/// This uses the existing invalid-input and operation-failed classifications.
pub fn client_query_order_problem(issue : @frontend.Issue) -> (String, String)? {
  match issue {
    QuerySyntax({ issue: AggregateOrderRequired, .. }) =>
      Some(("ClientProgramAggregateOrderRequired", "invalid_input"))
    QueryLowering(
      BindingPreparation(
        LocalProgram(Order(_, PipelineOrder({ kind: UnresolvedOrder, .. })))
      )
      | BindingPreparation(
        SourceProgram(
          Program(Order(_, PipelineOrder({ kind: UnresolvedOrder, .. })))
        )
      )
      | BindingPreparationSource(
        LocalProgram(Order(_, PipelineOrder({ kind: UnresolvedOrder, .. }))),
        _
      )
      | BindingPreparationSource(
        SourceProgram(
          Program(Order(_, PipelineOrder({ kind: UnresolvedOrder, .. })))
        ),
        _
      )
    ) => Some(("ClientProgramOrderUnresolved", "operation_failed"))
    _ => None
  }
}
