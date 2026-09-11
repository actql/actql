///|
test "declaration usage checks all stages and retains the exact inventory" {
  let (requests, stages) = fixture(used_bindings=true)
  let inventory = prepare(requests, stages, caps()).unwrap()
  let checked = check_declaration_usage(inventory, max_work=8000000).unwrap()
  assert_true(physical_equal(usage_inventory(checked), inventory))
  // Stage b uses only m. Parameter n and binding b are valid Program uses
  // because their occurrences belong to stage a, not because of declarations.
  assert_eq(
    @parameters.reference_count(parameters(stage_index(inventory, 1).unwrap())),
    1,
  )
  let exact = usage_work(checked)
  assert_true(exact > work(inventory))
  assert_eq(
    usage_work(check_declaration_usage(inventory, max_work=exact).unwrap()),
    exact,
  )
  assert_true(
    check_declaration_usage(inventory, max_work=exact - 1) is Err(WorkLimit),
  )
  assert_true(
    check_declaration_usage(inventory, max_work=-1) is Err(InvalidLimits),
  )
  assert_true(check_declaration_usage(inventory, max_work=0) is Err(WorkLimit))
}

///|
test "defaults and nested business parameter shapes do not count as use" {
  let (requests, stages) = fixture(unused_parameter=true)
  let inventory = prepare(requests, stages, caps()).unwrap()
  match check_declaration_usage(inventory, max_work=8000000) {
    Err(UnusedParameter(d)) => {
      assert_eq(d.name, "unknown")
      assert_true(@parameter.has_default(d))
    }
    _ => fail("unused Parameter must precede unused binding")
  }
  let (requests, stages) = fixture()
  let inventory = prepare(requests, stages, caps()).unwrap()
  match check_declaration_usage(inventory, max_work=8000000) {
    Err(UnusedBinding(d)) => {
      assert_eq(d.name, "unused")
      assert_true(d.constraint is Artifact(None))
    }
    _ => fail("unused binding must be rejected")
  }
}

///|
test "Parameter and binding names are separate and empty declarations pass" {
  let (requests, stages) = fixture(
    used_bindings=true,
    unused_parameter=true,
    unused_parameter_name="b",
  )
  let inventory = prepare(requests, stages, caps()).unwrap()
  match check_declaration_usage(inventory, max_work=8000000) {
    Err(UnusedParameter(d)) => assert_eq(d.name, "b")
    _ => fail("a binding occurrence cannot use a Parameter of the same name")
  }
  let (requests, stages) = fixture(empty=true)
  let inventory = prepare(requests, stages, caps()).unwrap()
  let checked = check_declaration_usage(inventory, max_work=8000000).unwrap()
  assert_true(physical_equal(usage_inventory(checked), inventory))
  assert_eq(usage_work(checked), work(inventory))
}
