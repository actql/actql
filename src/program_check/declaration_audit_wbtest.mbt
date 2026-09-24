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

///|
test "computation bypass requires headers from the exact Program owner" {
  let text = "{\"version\":\"actql/0.1\",\"id\":\"audit\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[],\"results\":{\"rows\":{\"from\":\"generated\"}},\"effects\":{\"write\":{\"create\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.create.v1\",\"payload\":{}}}}}],\"results\":{\"rows\":{\"from\":{\"stage\":\"s\",\"result\":\"rows\"}}}}"
  let limits : @syntax.Limits = {
    source: { max_input_bytes: 2000, max_nodes: 100, max_depth: 20, },
    tree: {
      max_nodes: 100,
      max_depth: 20,
      max_string_bytes: 2000,
      max_total_string_bytes: 2000,
    },
    max_stages: 1,
  }
  let first = @syntax.parse(text, limits, format=Json).unwrap()
  let second = @syntax.parse(text, limits, format=Json).unwrap()
  let headers = @syntax.collect_effect_headers(first, 1, 1).unwrap()
  assert_true(audit_declarations(first, 100, effect_headers=Some(headers)) > 0)
  try audit_declarations(second, 100, effect_headers=Some(headers)) catch {
    SourceFailure::UnsupportedEffects(_) => ()
    _ => fail("foreign Effect headers escaped the owner check")
  } noraise {
    _ => fail("foreign Effect headers escaped the owner check")
  }
  try audit_declarations(first, 100) catch {
    SourceFailure::UnsupportedEffects(_) => ()
    _ => fail("ordinary declaration audit admitted an Effect")
  } noraise {
    _ => fail("ordinary declaration audit admitted an Effect")
  }
}
