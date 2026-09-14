///|
test "policy expression traversal charges every node independently of unknown leaf position" {
  for
    (text, unknown) in [("id + id", false), ("1 + id", true), ("id + 1", true)] {
    let program = checked_direct_program_fixture(
      derive_body="{\"x\":\"" + text + "\"}",
    )
    let policy = publication_source_policy(program.units[0].publications[0]).unwrap()
    let operation = publication_policy_derivation_at(policy, 0).unwrap().operation
    let expression = @relation.binding_expression_at(operation, 0).unwrap()
    // Each expression has two leaves and one addition, irrespective of the
    // parser's node order. This expectation does not use a remaining-budget delta.
    assert_eq(@typing.node_count(expression), 3)
    let budget = IdentityBudget::{ work: 3, bytes: 0, nodes: 0, depth: 0, }
    assert_eq(publication_expression_unknown(expression, budget), unknown)
    assert_eq(budget.work, 0)
    let short = IdentityBudget::{ work: 2, bytes: 0, nodes: 0, depth: 0, }
    try publication_expression_unknown(expression, short) catch {
      BudgetExceeded => ()
      error => raise error
    } noraise {
      _ => fail("unknown provenance must not short-circuit work accounting")
    }
  }
}
