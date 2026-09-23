///|
fn effect_binding_inputs(
  effects : String,
  reference_nullable? : Bool? = None,
) -> (Checked, @syntax.EffectHeaders) {
  let fields = if reference_nullable is Some(_) {
    "[\"amount\",\"ref\"]"
  } else {
    "[\"amount\"]"
  }
  let operations = prepared(
    "{\"from\":\"rows\",\"fields\":" + fields + "}",
    effects=",\"effects\":" + effects,
    reference_nullable~,
  )
  let checked = check(operations, limits()).unwrap()
  let program = @parameters.program(@parameters.operations_source(operations))
  let headers = @syntax.collect_effect_headers(program, 8, 32).unwrap()
  (checked, headers)
}

///|
test "Effect Result bindings retain exact Stage definitions and budget" {
  let effects = "{\"update\":{\"update\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.update.v1\",\"from\":{\"result\":\"r\"},\"id\":\"amount\",\"set\":{\"value\":{\"field\":\"amount\"}}}}," +
    "\"upsert\":{\"upsert\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.upsert.v1\",\"from\":{\"result\":\"r\"},\"key\":\"amount\",\"set\":{\"value\":{\"literal\":1}}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let bindings = bind_effect_results(headers, checked, 12).unwrap()
  assert_eq(effect_result_binding_count(bindings), 4)
  assert_eq(effect_result_bindings_work(bindings), 12)
  assert_true(physical_equal(effect_result_bindings_owner(bindings), checked))
  assert_true(physical_equal(effect_result_bindings_headers(bindings), headers))
  for index in 0..<4 {
    let binding = effect_result_binding_at(bindings, index).unwrap()
    let header = effect_result_binding_header(binding)
    let stage = stage_at(checked, @syntax.effect_header_stage(header)).unwrap()
    let expected = @results.lookup(stage, "r").unwrap()
    assert_true(
      physical_equal(effect_result_binding_result(binding).unwrap(), expected),
    )
  }
  let update = effect_result_binding_at(bindings, 0).unwrap()
  assert_eq(effect_result_field_binding_count(update), 2)
  let selector = effect_result_field_binding_at(update, 0).unwrap()
  assert_eq(effect_result_field_binding_role(selector), EffectSelector)
  assert_eq(
    @schema.field_reference_name(effect_result_field_binding_field(selector)),
    "amount",
  )
  assert_eq(
    effect_result_field_binding_role(
      effect_result_field_binding_at(update, 1).unwrap(),
    ),
    EffectValue("value"),
  )
  let upsert = effect_result_binding_at(bindings, 1).unwrap()
  assert_eq(effect_result_field_binding_count(upsert), 1)
  assert_eq(
    effect_result_field_binding_role(
      effect_result_field_binding_at(upsert, 0).unwrap(),
    ),
    EffectUpsertKey,
  )
  assert_true(effect_result_binding_at(bindings, -1) is None)
  assert_true(effect_result_binding_at(bindings, 4) is None)
  assert_eq(
    effect_result_binding_issue_kind(
      bind_effect_results(headers, checked, 11).unwrap_err(),
    ),
    WorkLimit,
  )
  assert_eq(
    effect_result_binding_issue_kind(
      bind_effect_results(headers, checked, -1).unwrap_err(),
    ),
    InvalidLimits,
  )
  let (foreign, _) = effect_binding_inputs(effects)
  assert_eq(
    effect_result_binding_issue_kind(
      bind_effect_results(headers, foreign, 12).unwrap_err(),
    ),
    ForeignProgram,
  )
}

///|
test "Effect Result bindings reject absent selector and value fields" {
  for (selector, values) in [("missing", "amount"), ("amount", "missing")] {
    let effects = "{\"update\":{\"update\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.update.v1\",\"from\":{\"result\":\"r\"},\"id\":\"" +
      selector +
      "\",\"set\":{\"value\":{\"field\":\"" +
      values +
      "\"}}}}}"
    let (checked, headers) = effect_binding_inputs(effects)
    let issue = bind_effect_results(headers, checked, 10).unwrap_err()
    assert_eq(effect_result_binding_issue_kind(issue), MissingField)
    assert_eq(effect_result_binding_issue_stage(issue), 0)
    assert_eq(effect_result_binding_issue_effect(issue), "update")
    assert_eq(effect_result_binding_issue_field(issue), Some("missing"))
  }
}

///|
test "Effect Result bindings reject absent command ResourceRef field" {
  let effects = "{\"command\":{\"command\":{\"target\":{\"field\":\"missing\"},\"contract\":\"command:crm.invoke.v1\",\"from\":{\"result\":\"r\"},\"input\":{}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  assert_eq(
    effect_result_binding_issue_kind(
      bind_effect_results(headers, checked, 4).unwrap_err(),
    ),
    MissingField,
  )
}

///|
test "Effect Result bindings retain command target and input field types" {
  let effects = "{\"command\":{\"command\":{\"target\":{\"field\":\"ref\"},\"contract\":\"command:crm.invoke.v1\",\"from\":{\"result\":\"r\"},\"input\":{\"value\":{\"field\":\"amount\"}}}}}"
  let (checked, headers) = effect_binding_inputs(
    effects,
    reference_nullable=Some(false),
  )
  let bindings = bind_effect_results(headers, checked, 6).unwrap()
  let first = effect_result_binding_at(bindings, 0).unwrap()
  assert_eq(effect_result_field_binding_count(first), 2)
  assert_eq(
    effect_result_field_binding_role(
      effect_result_field_binding_at(first, 0).unwrap(),
    ),
    EffectCommandTarget,
  )
  assert_eq(
    effect_result_field_binding_role(
      effect_result_field_binding_at(first, 1).unwrap(),
    ),
    EffectValue("value"),
  )
  let target = effect_result_field_binding_at(first, 0).unwrap()
  assert_eq(
    @contract.nonnull_resource_ref_kind(
      @schema.field_contract(effect_result_field_binding_field(target)),
    ),
    Some("crm/account"),
  )
}

///|
test "Effect Result bindings reject numeric or nullable command targets" {
  for (field, nullable) in [("amount", false), ("ref", true)] {
    let effects = "{\"command\":{\"command\":{\"target\":{\"field\":\"" +
      field +
      "\"},\"contract\":\"command:crm.invoke.v1\",\"from\":{\"result\":\"r\"},\"input\":{}}}}"
    let (checked, headers) = effect_binding_inputs(
      effects,
      reference_nullable=Some(nullable),
    )
    let issue = bind_effect_results(headers, checked, 6).unwrap_err()
    assert_eq(effect_result_binding_issue_kind(issue), InvalidCommandTarget)
    assert_eq(effect_result_binding_issue_field(issue), Some(field))
  }
}

///|
test "Effect Result bindings cover match, upsert, and command inputs" {
  let cases = [
    "{\"update\":{\"update\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.update.v1\",\"from\":{\"result\":\"r\"},\"match\":{\"target_field\":\"Id\",\"result_field\":\"missing\"},\"set\":{\"value\":{\"literal\":1}}}}}",
    "{\"upsert\":{\"upsert\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.upsert.v1\",\"from\":{\"result\":\"r\"},\"key\":\"missing\",\"set\":{\"value\":{\"literal\":1}}}}}",
    "{\"command\":{\"command\":{\"target\":{\"field\":\"ref\"},\"contract\":\"command:crm.invoke.v1\",\"from\":{\"result\":\"r\"},\"input\":{\"value\":{\"field\":\"missing\"}}}}}",
  ]
  for effects in cases {
    let (checked, headers) = effect_binding_inputs(
      effects,
      reference_nullable=Some(false),
    )
    let issue = bind_effect_results(headers, checked, 8).unwrap_err()
    assert_eq(effect_result_binding_issue_kind(issue), MissingField)
    assert_eq(effect_result_binding_issue_field(issue), Some("missing"))
  }
}

///|
test "literal create has no Result owner and cannot gain field authority" {
  let effects = "{\"create\":{\"create\":{\"target\":\"crm\",\"mapping\":\"mapping:crm.create.v1\",\"payload\":{}}}}"
  let (checked, headers) = effect_binding_inputs(effects)
  let bindings = bind_effect_results(headers, checked, 2).unwrap()
  assert_eq(effect_result_binding_count(bindings), 2)
  assert_true(
    effect_result_binding_result(effect_result_binding_at(bindings, 0).unwrap())
    is None,
  )
  assert_eq(
    effect_result_field_binding_count(
      effect_result_binding_at(bindings, 0).unwrap(),
    ),
    0,
  )
}
