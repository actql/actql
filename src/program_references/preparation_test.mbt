///|
fn preparation_body_limits() -> @body.Limits {
  {
    max_work: 1000000,
    selectors: {
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
      max_tokens: 1000,
      tree: {
        max_nodes: 10000,
        max_depth: 100,
        max_string_bytes: 100000,
        max_total_string_bytes: 100000,
      },
    },
  }
}

///|
fn preparation_use_limits() -> @collection.Limits {
  {
    max_work: 1000000,
    max_slots: 1000,
    max_references: 1000,
    max_pointer_units: 100000,
    max_direct_text_bytes: 100000,
  }
}

///|
fn retained_stages(
  uses : Array[@body.ParameterUses],
) -> Array[@stages.CollectedStage] {
  uses.map(value => @body.stage(@body.parameter_body(value)))
}

///|
fn prepare_usage(
  requests : @requests.Slots,
  stages : Array[@stages.CollectedStage],
  max_work : Int,
) -> Result[DeclarationUsage, PreparationIssue] {
  prepare_declaration_usage(
    requests,
    stages,
    preparation_body_limits(),
    preparation_use_limits(),
    caps(),
    max_work~,
  )
}

///|
test "owned declaration preparation needs no runtime values and retains original coordinates" {
  let (slots, uses) = fixture(used_bindings=true)
  let source = @requests.source(slots)
  assert_true(
    @parameter.bind(@stages.declarations(source), None, {
      max_nodes: 10000,
      max_depth: 100,
      max_text_bytes: 100000,
    })
    is Ok(NeedsBindings(_)),
  )
  let stages = retained_stages(uses)
  let checked = prepare_usage(slots, stages, 8000000).unwrap()
  let inventory = usage_inventory(checked)
  assert_true(physical_equal(requests(inventory), slots))
  for i in 0..<stages.length() {
    assert_true(
      physical_equal(
        @body.stage(@body.parameter_body(stage_uses(inventory, i).unwrap())),
        stages[i],
      ),
    )
  }
  let index = parameters(program_index(inventory))
  let paths = []
  for i in 0..<@parameters.reference_count(index) {
    paths.push(@parameters.reference_at(index, i).unwrap().path)
  }
  assert_eq(paths, [
    "/stages/0/effects/d/delete/where/0/lt/1", "/stages/0/inputs/remote~1~0/request/p",
    "/stages/0/steps/0/take", "/stages/1/steps/0/take",
  ])
  let existing = check_declaration_usage(
    prepare(slots, uses, caps()).unwrap(),
    max_work=8000000,
  ).unwrap()
  assert_eq(usage_work(checked), usage_work(existing))
  let exact = usage_work(checked)
  assert_eq(usage_work(prepare_usage(slots, stages, exact).unwrap()), exact)
  assert_true(prepare_usage(slots, stages, exact - 1) is Err(_))
  assert_true(prepare_usage(slots, stages, 0) is Err(BudgetExceeded))
  assert_true(prepare_usage(slots, stages, -1) is Err(InvalidLimits))
}

///|
test "missing values cannot hide an independently unused declaration in owned preparation" {
  let (slots, uses) = fixture(
    used_bindings=true,
    parameters=Some(
      "{\"n\":{\"type\":\"number\"},\"m\":{\"type\":\"number\"},\"unused\":{\"type\":\"number\"}}",
    ),
  )
  match prepare_usage(slots, retained_stages(uses), 8000000) {
    Err(Usage(UnusedParameter(d))) => {
      assert_eq(d.name, "unused")
      assert_true(!@parameter.has_default(d))
    }
    _ =>
      fail(
        "an unused required declaration must be rejected without binding values",
      )
  }
}

///|
test "owned declaration preparation rejects foreign reordered and incomplete stage owners" {
  let (slots, uses) = fixture(used_bindings=true)
  let (_, foreign) = fixture(used_bindings=true)
  let stages = retained_stages(uses)
  assert_true(
    prepare_usage(slots, retained_stages(foreign), 8000000)
    is Err(Inventory(ForeignStage(0))),
  )
  assert_true(
    prepare_usage(slots, [stages[1], stages[0]], 8000000)
    is Err(Inventory(ForeignStage(0))),
  )
  assert_true(
    prepare_usage(slots, [stages[0]], 8000000)
    is Err(Inventory(StageCountMismatch)),
  )
  assert_true(
    prepare_declaration_usage(
      slots,
      stages,
      { ..preparation_body_limits(), max_work: 0, },
      preparation_use_limits(),
      caps(),
      max_work=8000000,
    )
    is Err(Body(0, WorkLimit)),
  )
  assert_true(
    prepare_declaration_usage(
      slots,
      stages,
      preparation_body_limits(),
      { ..preparation_use_limits(), max_work: 0, },
      caps(),
      max_work=8000000,
    )
    is Err(Uses(0, WorkLimit)),
  )
  assert_true(
    prepare_declaration_usage(
      slots,
      stages,
      preparation_body_limits(),
      preparation_use_limits(),
      { ..caps(), max_work: 0, },
      max_work=8000000,
    )
    is Err(Inventory(WorkLimit)),
  )
}
