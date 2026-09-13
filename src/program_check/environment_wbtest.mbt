///|
test "owned Environment admission validates Catalog with aggregate exact budgets" {
  let environment = keyed_sourceview_environment()
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let checked = prepare_environment(environment, budget)
  let reference = catalog_fixture(environment)
  assert_eq(
    @environment.source_request_usage(checked),
    @environment.source_request_usage(reference),
  )
  assert_true(@environment.source_request_usage(checked).2 > 0)
  let work = 10000000 - budget.work
  let bytes = 1000000 - budget.bytes
  let nodes = 100000 - budget.nodes
  let exact = IdentityBudget::{ work, bytes, nodes, depth: 100, }
  let _ = prepare_environment(environment, exact)
  assert_eq((exact.work, exact.bytes, exact.nodes), (0, 0, 0))
  for
    (w, b, n) in [
      (work - 1, bytes, nodes),
      (work, bytes - 1, nodes),
      (work, bytes, nodes - 1),
    ] {
    let short = IdentityBudget::{ work: w, bytes: b, nodes: n, depth: 100, }
    try prepare_environment(environment, short) catch {
      _ => ()
    } noraise {
      _ => fail("short Environment admission budget succeeded")
    }
    assert_eq((short.work, short.bytes, short.nodes), (w, b, n))
  }
}
