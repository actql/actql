///|
struct ExpressionExecution {
  owner : @context.ProgramExpressionClosure
  requirement_index : Int
  bound : @context.TextBoundResolution
}

///|
// Retain the existing demand-aware bound, including its exact policy and
// expression site. This is an execution requirement, not an evaluated value.
// Profile and pattern admission are static resolutions, not runtime checks.
fn prepare_expression_execution(
  owner : @context.ProgramExpressionClosure,
  budget : IdentityBudget,
) -> Array[ExpressionExecution] raise UnitBuildFailure {
  let count = @context.expression_closure_count(owner)
  identity_charge(budget, count)
  let result : Array[ExpressionExecution] = []
  for index in 0..<count {
    let requirement = @context.expression_closure_at(owner, index).unwrap()
    match requirement.resolution {
      Profile(_) | Pattern(_) => ()
      Envelope(bound) => {
        identity_charge(budget, 1)
        result.push({ owner, requirement_index: index, bound, })
      }
    }
  }
  result
}
