///|
fn demand_limits() -> @expression_typing.DemandLimits {
  { max_work: 10000000, max_text_bytes: 10000000, max_links: 1000000, }
}

///|
fn demands(text : String) -> @expression_typing.DemandPaths {
  @expression_typing.derive_demands(
    @expression_typing.check(syntax(text), env(), test_limits()).unwrap(),
    demand_limits(),
  ).unwrap()
}

///|
fn demand_node(
  v : @expression_typing.DemandPaths,
  pointer : String,
) -> Int raise {
  for
    i in 0..<@expression_typing.node_count(
      @expression_typing.demand_expression(v),
    ) {
    if @expression_typing.demand_pointer(v, i, max_bytes=100000).unwrap() ==
      Some(pointer) {
      return i
    }
  }
  fail("missing semantic pointer " + pointer)
}

///|
fn assert_demand(
  v : @expression_typing.DemandPaths,
  pointer : String,
  expected : Array[(String, @expression_typing.DemandTestKind)],
) -> Unit raise {
  let tests = @expression_typing.demand_tests(
    v,
    demand_node(v, pointer),
    max_tests=100,
  ).unwrap()
  assert_eq(tests.length(), expected.length())
  for i in 0..<tests.length() {
    assert_eq(
      @expression_typing.demand_pointer(
        v,
        tests[i].node_index,
        max_bytes=100000,
      ).unwrap(),
      Some(expected[i].0),
    )
    assert_eq(tests[i].kind, expected[i].1)
  }
}

///|
test "demand paths derive outer-to-inner IF CASE and coalesce tests" {
  let v = demands(
    "\"if(TRUE, coalesce(NULL, case_fold('x'), 'fallback'), 'else')\"",
  )
  assert_demand(v, "", [])
  assert_demand(v, "/if/0", [])
  assert_demand(v, "/if/1", [("/if/0", IsTrue)])
  assert_demand(v, "/if/1/coalesce/0", [("/if/0", IsTrue)])
  assert_demand(v, "/if/1/coalesce/1/case_fold", [
    ("/if/0", IsTrue),
    ("/if/1/coalesce/0", IsNull),
  ])
  assert_demand(v, "/if/1/coalesce/2", [
    ("/if/0", IsTrue),
    ("/if/1/coalesce/0", IsNull),
    ("/if/1/coalesce/1", IsNull),
  ])
  assert_demand(v, "/if/2", [("/if/0", NotTrue)])
  let v = demands(
    "\"CASE WHEN TRUE THEN 'a' WHEN FALSE THEN nfkc('b') ELSE 'c' END\"",
  )
  assert_demand(v, "/case/when/0/when", [])
  assert_demand(v, "/case/when/0/then", [("/case/when/0/when", IsTrue)])
  assert_demand(v, "/case/when/1/when", [("/case/when/0/when", NotTrue)])
  assert_demand(v, "/case/when/1/then/nfkc", [
    ("/case/when/0/when", NotTrue),
    ("/case/when/1/when", IsTrue),
  ])
  assert_demand(v, "/case/else", [
    ("/case/when/0/when", NotTrue),
    ("/case/when/1/when", NotTrue),
  ])
}

///|
test "demand addresses use normalized JSON pointers and preserve opaque data" {
  let v = demands("{\"object\":{\"a~/😀\":\"if(TRUE, 1, 2)\"}}")
  assert_demand(v, "/object/a~0~1😀/if/1", [
    ("/object/a~0~1😀/if/0", IsTrue),
  ])
  let node = demand_node(v, "/object/a~0~1😀/if/1")
  let pointer = "/object/a~0~1😀/if/1"
  let bytes = @scalar.admit_utf8_length(pointer, 100).unwrap()
  assert_eq(
    @expression_typing.demand_pointer(v, node, max_bytes=bytes).unwrap(),
    Some(pointer),
  )
  assert_true(
    @expression_typing.demand_pointer(v, node, max_bytes=bytes - 1)
    is Err(BudgetExceeded),
  )
  let v = demands("{\"literal\":{\"if\":[true,1,2],\"$param\":\"business\"}}")
  assert_eq(
    @expression_typing.node_count(@expression_typing.demand_expression(v)),
    1,
  )
  assert_demand(v, "", [])
  let v = demands("\"1 IN (1, NULL, 2)\"")
  assert_demand(v, "/in/1/literal/1", [])
  let v = demands("\"TRUE AND (FALSE OR TRUE)\"")
  for
    i in 0..<@expression_typing.node_count(
      @expression_typing.demand_expression(v),
    ) {
    assert_true(
      @expression_typing.demand_tests(v, i, max_tests=0).unwrap().is_empty(),
    )
  }
  let v = demands("\"CASE WHEN TRUE THEN 1 END\"")
  let typed = @expression_typing.demand_expression(v)
  let last = @expression_typing.node_count(typed) - 1
  assert_true(@expression_typing.node_form(typed, last) is Some(ImplicitNull))
  assert_eq(
    @expression_typing.demand_pointer(v, last, max_bytes=0).unwrap(),
    None,
  )
  let tests = @expression_typing.demand_tests(v, last, max_tests=1).unwrap()
  assert_eq(tests[0].kind, NotTrue)
}

///|
test "demand ownership detached views and exact admission budgets" {
  let typed = @expression_typing.check(
    syntax("\"if(TRUE, 1, 2)\""),
    env(),
    test_limits(),
  ).unwrap()
  let v = @expression_typing.derive_demands(typed, demand_limits()).unwrap()
  assert_true(physical_equal(@expression_typing.demand_expression(v), typed))
  let u = @expression_typing.demand_usage(v)
  let exact : @expression_typing.DemandLimits = {
    max_work: u.work,
    max_text_bytes: u.text_bytes,
    max_links: u.links,
  }
  assert_true(@expression_typing.derive_demands(typed, exact) is Ok(_))
  for
    short in [
      { ..exact, max_work: u.work - 1, },
      { ..exact, max_text_bytes: u.text_bytes - 1, },
      { ..exact, max_links: u.links - 1, },
    ] {
    assert_true(
      @expression_typing.derive_demands(typed, short) is Err(BudgetExceeded),
    )
  }
  assert_true(
    @expression_typing.derive_demands(typed, { ..exact, max_links: -1, })
    is Err(InvalidLimits),
  )
  assert_true(
    @expression_typing.demand_tests(v, -1, max_tests=10) is Err(InvalidNode),
  )
  assert_true(
    @expression_typing.demand_pointer(v, 100, max_bytes=10) is Err(InvalidNode),
  )
  assert_true(
    @expression_typing.demand_tests(v, 0, max_tests=-1) is Err(InvalidLimits),
  )
  assert_true(
    @expression_typing.demand_pointer(v, 0, max_bytes=-1) is Err(InvalidLimits),
  )
  let child = demand_node(v, "/if/1")
  assert_true(
    @expression_typing.demand_tests(v, child, max_tests=0)
    is Err(BudgetExceeded),
  )
  let copy = @expression_typing.demand_tests(v, child, max_tests=1).unwrap()
  copy.clear()
  assert_eq(
    @expression_typing.demand_tests(v, child, max_tests=1).unwrap().length(),
    1,
  )
}

///|
test "long demand prefixes and deep addresses remain linear retained structures" {
  let text = "coalesce(" + "NULL,".repeat(9999) + "'x')"
  let v = demands(text.to_json().stringify())
  let typed = @expression_typing.demand_expression(v)
  let last = @expression_typing.node_count(typed) - 1
  assert_eq(
    @expression_typing.demand_tests(v, last, max_tests=9999).unwrap().length(),
    9999,
  )
  assert_true(
    @expression_typing.demand_tests(v, last, max_tests=9998)
    is Err(BudgetExceeded),
  )
  assert_true(
    @expression_typing.demand_usage(v).links <
    3 * @expression_typing.node_count(typed),
  )
  let text = "nfkc(".repeat(10000) + "'x'" + ")".repeat(10000)
  let v = demands(text.to_json().stringify())
  let pointer = "/nfkc".repeat(10000)
  assert_eq(
    @expression_typing.demand_pointer(v, 10000, max_bytes=50000).unwrap(),
    Some(pointer),
  )
  assert_true(
    @expression_typing.demand_pointer(v, 10000, max_bytes=49999)
    is Err(BudgetExceeded),
  )
  assert_eq(@expression_typing.demand_usage(v).links, 10001)
}
