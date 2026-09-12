///|
fn pushdown_fixture(
  body : Json,
  carrier : String,
  operations : Json,
  views? : Int = 1,
  unused? : Json? = None,
) -> Result[SourceViewShapes, SourceViewShapeIssue] raise {
  let bodies = value_bodies(
    "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{}}",
  )
  bodies["pushdown"] = body
  let contents = reference_fixture(
    bodies~,
    complete_view=true,
    carrier~,
    view_count=views,
    policy_body=Some(policy_body_fixture("unknown")),
    path=["view", "pushdown", "operations"],
    replacement=Some(operations),
    unused_pushdown=unused,
  )
  let references = check_catalog_references(contents, reference_caps()).unwrap()
  let policies = check_source_data_policies(references, policy_limits()).unwrap()
  let values = check_protocol_value_contracts(policies, protocol_value_limits()).unwrap()
  check_source_view_shapes(values, { max_views: 10, max_work: 100000, })
}

///|
test "pushdown validation covers unused contracts and charges repeated SourceViews" {
  let body = @json.parse(
    "{\"version\":\"actql-source-view-pushdown/0.1\",\"carrier\":\"relation\",\"operations\":[\"projection\",\"filter\"]}",
  )
  let operations = @json.parse("[\"filter\",\"projection\"]")
  let caps : PushdownLimits = {
    max_work: 100000,
    max_contracts: 100,
    max_operations: 100,
  }
  let shapes = pushdown_fixture(body, "relation", operations, views=3).unwrap()
  let checked = check_pushdown_contracts(shapes, caps).unwrap()
  assert_eq(pushdown_usage(checked).1, 1)
  assert_eq(pushdown_usage(checked).2, 8) // one body plus three source occurrences
  let refs = data_policy_references(
    value_contract_policies(source_view_shape_values(shapes)),
  )
  let catalog = catalog_at(reference_contents(refs), 0).unwrap()
  for i in 0..<3 {
    let item = catalog_view_at(catalog, i).unwrap()
    assert_true(
      physical_equal(
        source_pushdown(checked, item).unwrap().contract,
        pushdown_contract_at(checked, 0).unwrap(),
      ),
    )
  }
  assert_true(
    check_pushdown_contracts(shapes, { ..caps, max_operations: 7, })
    is Err({ kind: BudgetExceeded, .. }),
  )
  for
    invalid in [
      Json::null(),
      @json.parse("{\"extra\":true}"),
      @json.parse(
        "{\"version\":\"other\",\"carrier\":\"relation\",\"operations\":[]}",
      ),
    ] {
    let shapes = pushdown_fixture(
      body,
      "relation",
      operations,
      unused=Some(invalid),
    ).unwrap()
    guard check_pushdown_contracts(shapes, caps) is Err(issue) else {
      fail("unreferenced invalid contract admitted")
    }
    assert_true(issue.kind == InvalidBody || issue.kind == UnsupportedBody)
    assert_true(issue.source is Some(_))
  }
}

///|
fn assert_pushdown_case(
  body : Json,
  carrier : String,
  operations : Json,
  accepted : Bool,
) -> Unit raise {
  let shapes = match pushdown_fixture(body, carrier, operations) {
    Ok(v) => v
    Err(_) => {
      assert_false(accepted)
      return
    }
  }
  let caps : PushdownLimits = {
    max_work: 100000,
    max_contracts: 100,
    max_operations: 100,
  }
  let result = check_pushdown_contracts(shapes, caps)
  assert_eq(result is Ok(_), accepted)
  guard result is Ok(checked) else { return }
  assert_true(physical_equal(pushdown_shapes(checked), shapes))
  let (work, count, ops) = pushdown_usage(checked)
  assert_eq(count, 1)
  let contract = pushdown_contract_at(checked, 0).unwrap()
  let dependencies = check_pushdown_body_dependencies(
    checked,
    pushdown_envelope(contract),
  ).unwrap()
  guard catalog_body_admission(dependencies) is PushdownBody(retained) else {
    fail("pushdown owner")
  }
  assert_true(physical_equal(retained, contract))
  let expected = match body {
    Object(fields) =>
      match fields.get("operations") {
        Some(Array(xs)) => xs
        _ => []
      }
    _ => []
  }
  assert_eq(pushdown_operation_count(contract), expected.length())
  for i in 0..<expected.length() {
    guard expected[i] is String(name) else { fail("string operation") }
    assert_eq(pushdown_operation_at(contract, i), Some(name))
  }
  let dependency_count = 1 +
    (if expected.length() > 0 { 1 } else { 0 }) +
    (if expected.contains(Json::string("filter")) { 1 } else { 0 })
  assert_eq(catalog_body_dependency_count(dependencies), dependency_count)
  assert_eq(
    catalog_body_dependency_at(dependencies, 0).unwrap().role,
    GoverningGrammar,
  )
  if dependency_count > 1 {
    assert_eq(
      catalog_body_dependency_at(dependencies, 1).unwrap().role,
      RelationLaws,
    )
  }
  if dependency_count > 2 {
    assert_eq(
      catalog_body_dependency_at(dependencies, 2).unwrap().role,
      ExpressionContract,
    )
  }
  let references = data_policy_references(
    value_contract_policies(source_view_shape_values(shapes)),
  )
  let item = catalog_view_at(
    catalog_at(reference_contents(references), 0).unwrap(),
    0,
  ).unwrap()
  let selected = source_pushdown(checked, item).unwrap()
  assert_true(physical_equal(reference_member(selected.reference), item))
  assert_true(physical_equal(selected.contract, contract))
  for invalid in [-2147483648, -1, 1, 2147483647] {
    assert_true(pushdown_contract_at(checked, invalid) is None)
  }
  assert_true(pushdown_operation_at(contract, -1) is None)
  assert_true(pushdown_operation_at(contract, expected.length()) is None)
  let exact : PushdownLimits = {
    max_work: work,
    max_contracts: count,
    max_operations: ops,
  }
  assert_true(check_pushdown_contracts(shapes, exact) is Ok(_))
  for
    short in [{ ..exact, max_work: work - 1, }, { ..exact, max_contracts: 0, }] {
    assert_true(
      check_pushdown_contracts(shapes, short)
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  if ops > 0 {
    assert_true(
      check_pushdown_contracts(shapes, { ..exact, max_operations: ops - 1, })
      is Err({ kind: BudgetExceeded, .. }),
    )
  }
  for
    invalid in [
      { ..exact, max_work: -1, },
      { ..exact, max_contracts: -1, },
      { ..exact, max_operations: -1, },
    ] {
    assert_true(
      check_pushdown_contracts(shapes, invalid)
      is Err({ kind: InvalidLimits, .. }),
    )
  }
  let foreign = pushdown_fixture(body, carrier, operations).unwrap()
  let other = check_pushdown_contracts(foreign, caps).unwrap()
  assert_true(
    check_pushdown_body_dependencies(other, pushdown_envelope(contract))
    is Err(ForeignEnvironment),
  )
  assert_true(source_pushdown(other, item) is None)
}
