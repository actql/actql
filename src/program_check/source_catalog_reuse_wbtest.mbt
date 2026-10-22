///|
fn reuse_catalog_environment() -> CheckEnvironment {
  checking_environment(
    keyed_sourceview_environment(),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
}

///|
fn reuse_catalog_limits() -> SourceCatalogLimits {
  { max_work: 10000000, max_bytes: 1000000, max_nodes: 100000, max_depth: 100, }
}

///|
test "same original Catalog admission runs once and reuses exact references under current accounting" {
  let environment = reuse_catalog_environment()
  let calls = Ref(0)
  let read = (wire, budget) => {
    calls.val += 1
    prepare_environment(wire, budget)
  }
  let prepared = prepare_source_catalog_with_reader(
    environment,
    reuse_catalog_limits(),
    read,
  ).unwrap()
  assert_eq(calls.val, 1)
  let used = source_catalog_usage(prepared)
  let budget = IdentityBudget::{
    work: used.work,
    bytes: used.bytes,
    nodes: used.nodes,
    depth: 100,
  }
  let (catalog, references) = reuse_source_catalog_with_reader(
    prepared,
    environment.wire,
    budget,
    read,
  )
  assert_eq(calls.val, 1)
  assert_true(physical_equal(catalog, prepared.catalog))
  assert_true(physical_equal(references, prepared.references))
  assert_eq((budget.work, budget.bytes, budget.nodes), (0, 0, 0))
  assert_eq(budget.depth, 100)
}

///|
test "same CID foreign Catalog wire refuses without another admission or owner substitution" {
  let environment = reuse_catalog_environment()
  let prepared = prepare_source_catalog(environment, reuse_catalog_limits()).unwrap()
  let foreign = keyed_sourceview_environment()
  assert_eq(@environment.cid(foreign), @environment.cid(environment.wire))
  let calls = Ref(0)
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  try
    reuse_source_catalog_with_reader(prepared, foreign, budget, (wire, budget) => {
      calls.val += 1
      prepare_environment(wire, budget)
    })
  catch {
    ForeignPreparedCatalog => ()
    other => raise other
  } noraise {
    _ => fail("foreign original Catalog was accepted")
  }
  assert_eq(calls.val, 0)
  assert_eq(
    (budget.work, budget.bytes, budget.nodes),
    (10000000, 1000000, 100000),
  )
}

///|
test "unproved tighter Catalog bounds retain the original reader and failed budgets" {
  let environment = reuse_catalog_environment()
  let prepared = prepare_source_catalog(environment, reuse_catalog_limits()).unwrap()
  let used = source_catalog_usage(prepared)
  let calls = Ref(0)
  let read = (wire, budget) => {
    calls.val += 1
    prepare_environment(wire, budget)
  }
  // The first interpretation admitted depth 100. A new lower depth bound is
  // not proved by that allowance; it must not become a blanket refusal either.
  let depth = IdentityBudget::{
    work: used.work,
    bytes: used.bytes,
    nodes: used.nodes,
    depth: 99,
  }
  let (_, _) = reuse_source_catalog_with_reader(
    prepared,
    environment.wire,
    depth,
    read,
  )
  assert_eq(calls.val, 1)
  assert_eq((depth.work, depth.bytes, depth.nodes), (0, 0, 0))
  for
    (work, bytes, nodes) in [
      (used.work - 1, used.bytes, used.nodes),
      (used.work, used.bytes - 1, used.nodes),
      (used.work, used.bytes, used.nodes - 1),
    ] {
    let before = calls.val
    let short = IdentityBudget::{ work, bytes, nodes, depth: 100, }
    try
      reuse_source_catalog_with_reader(prepared, environment.wire, short, read)
    catch {
      _ => ()
    } noraise {
      _ => fail("short current Catalog allowance succeeded")
    }
    assert_eq(calls.val, before + 1)
    assert_eq((short.work, short.bytes, short.nodes), (work, bytes, nodes))
  }
  let exact = IdentityBudget::{
    work: used.work,
    bytes: used.bytes,
    nodes: used.nodes,
    depth: 100,
  }
  let before = calls.val
  let (same, refs) = reuse_source_catalog_with_reader(
    prepared,
    environment.wire,
    exact,
    read,
  )
  assert_eq(calls.val, before)
  assert_true(physical_equal(same, prepared.catalog))
  assert_true(physical_equal(refs, prepared.references))
}
