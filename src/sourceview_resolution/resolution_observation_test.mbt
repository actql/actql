///|
test "selection observer excludes completed collection prefix and retains original unresolved custody" {
  let catalog = selector_empty_catalog()
  let inputs = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"missing\"}",
  )
  // Collection: stage1+slot1+name6+fields2+preflight37 =47.
  assert_eq(@inputs.work(inputs), 47)
  let (result, spent) = observe_resolve(inputs, catalog, caps())
  // This pass: one input visit1 +connector8 +resource7 =16.
  assert_eq(spent, 16)
  guard result is Err(issue) else { fail("original unresolved selection") }
  assert_eq(issue.kind, Unresolved)
  assert_true(
    physical_equal(
      unresolved_selector_declaration(issue, inputs, catalog).unwrap(),
      @inputs.at(inputs, 0).unwrap(),
    ),
  )
  assert_true(
    unresolved_selector_declaration(
      issue,
      fixture_inputs("{\"connector\":\"crm/main\",\"resource\":\"missing\"}"),
      catalog,
    )
    is None,
  )
  let explicit = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"missing\",\"view\":\"v\"}",
  )
  assert_eq(@inputs.work(explicit), 55)
  let (result, spent) = observe_resolve(explicit, catalog, caps())
  // Original explicit selection adds view1 +failure-only source indexing3.
  assert_eq(spent, 20)
  guard result is Err(issue) else {
    fail("original explicit unresolved selection")
  }
  assert_eq(issue.kind, Unresolved)
  assert_eq(@decode.cursor_path(issue.source.unwrap()).length(), 5)
}

///|
test "selection observer reports only performed new prefix on one-short refusal" {
  let catalog = selector_empty_catalog()
  let inputs = fixture_inputs(
    "{\"connector\":\"crm/main\",\"resource\":\"missing\"}",
  )
  let inherited = 47
  for (maximum, expected) in [(46, 0), (47, 0), (48, 1), (56, 9), (62, 9)] {
    let (result, spent) = observe_resolve(inputs, catalog, {
      ..caps(),
      max_work: maximum,
    })
    guard result is Err(issue) else { fail("original work refusal") }
    assert_eq(issue.kind, WorkLimit)
    assert_eq(spent, expected)
    assert_true(unresolved_selector_declaration(issue, inputs, catalog) is None)
  }
  let (result, spent) = observe_resolve(inputs, catalog, {
    ..caps(),
    max_work: inherited + 16,
  })
  assert_true(result is Err({ kind: Unresolved, .. }))
  assert_eq(spent, 16)
  let invalid : Array[Limits] = [
    { ..caps(), max_work: -1, },
    { ..caps(), max_inputs: 0, },
  ]
  for limits in invalid {
    let (result, spent) = observe_resolve(inputs, catalog, limits)
    assert_true(result is Err({ kind: InvalidLimits | InputLimit, .. }))
    assert_eq(spent, 0)
  }
}
