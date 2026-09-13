///|
test "uninterpreted Bindings are rejected even when unused" {
  let budget = IdentityBudget::{
    work: 10000000,
    bytes: 1000000,
    nodes: 100000,
    depth: 100,
  }
  let before = (budget.work, budget.bytes, budget.nodes)
  try
    local_construction_fixture(
      budget,
      root_extra="\"bindings\":{\"b\":{\"type\":\"string\"}},",
    )
  catch {
    LocalConstructionFailure::Source(SourceFailure::UnsupportedBindings(cursor)) =>
      assert_eq(@decode.cursor_path(cursor), [@source.Key("bindings")])
    e => raise e
  } noraise {
    _ => fail("uninterpreted Binding escaped construction")
  }
  assert_eq((budget.work, budget.bytes, budget.nodes), before)
}

///|
test "terminal Effects cannot bypass static admission because no gate consumes them" {
  for second_stage in [false, true] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let before = (budget.work, budget.bytes, budget.nodes)
    try
      local_construction_fixture(
        budget,
        second_stage~,
        last_effects=Some("{\"e\":{\"create\":{}}}"),
      )
    catch {
      LocalConstructionFailure::Source(
        SourceFailure::UnsupportedEffects(cursor)
      ) =>
        assert_eq(@decode.cursor_path(cursor), [
          @source.Key("stages"),
          @source.Index(if second_stage { 1 } else { 0 }),
          @source.Key("effects"),
        ])
      e => raise e
    } noraise {
      _ => fail("uninterpreted Effect escaped construction")
    }
    assert_eq((budget.work, budget.bytes, budget.nodes), before)
    let (_, _, _, _, units) = local_construction_fixture(
      budget,
      second_stage~,
      last_effects=Some("{}"),
    )
    assert_eq(units.length(), if second_stage { 2 } else { 1 })
  }
}
