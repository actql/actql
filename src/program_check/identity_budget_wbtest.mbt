///|
test "identity sorting bounds long names and preserves UTF16 stable ordering" {
  let prefix = "x".repeat(4096)
  let original = [
    (prefix + "z", "last"),
    (prefix + "a", "first"),
    (prefix + "a", "second"),
    ("\u{10000}", "supplementary"),
    ("\u{E000}", "bmp"),
  ]
  let budget = IdentityBudget::{ work: 100000, bytes: 0, nodes: 0, depth: 0, }
  let sorted = original.copy()
  identity_sort(sorted, budget)
  assert_eq(sorted, [
    (prefix + "a", "first"),
    (prefix + "a", "second"),
    (prefix + "z", "last"),
    ("\u{10000}", "supplementary"),
    ("\u{E000}", "bmp"),
  ])
  let cost = 100000 - budget.work
  assert_true(cost > 4096)
  let exact = IdentityBudget::{ work: cost, bytes: 0, nodes: 0, depth: 0, }
  let repeated = original.copy()
  identity_sort(repeated, exact)
  assert_eq(exact.work, 0)
  assert_eq(repeated, sorted)
  let short = IdentityBudget::{ work: cost - 1, bytes: 0, nodes: 0, depth: 0, }
  try identity_sort(original.copy(), short) catch {
    UnitBuildFailure::BudgetExceeded => ()
    _ => fail("expected work exhaustion")
  } noraise {
    _ => fail("comparison work must not escape the aggregate budget")
  }
  assert_true(short.work >= 0)
  // The comparator cannot scan a long common prefix before reserving its work.
  let tiny = IdentityBudget::{ work: 4, bytes: 0, nodes: 0, depth: 0, }
  try identity_compare(prefix + "a", prefix + "z", tiny) catch {
    UnitBuildFailure::BudgetExceeded => ()
    _ => fail("expected pre-comparison rejection")
  } noraise {
    _ => fail("long comparison must reject before scanning")
  }
  assert_eq(tiny.work, 4)
}
