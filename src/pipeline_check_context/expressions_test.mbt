///|
test "static expression requirements retain unused branches and repeated producer occurrences" {
  let producer = base(
    true,
    steps="[{\"derive\":{\"normalized\":\"nfkc(NULL)\",\"matched\":\"if(TRUE, TRUE, regex_match('a', '(a)'))\"}}]",
  )
  let input = @pipeline.ProducedInput(
    @pipeline.produced_input(producer, Input(0)).unwrap(),
  )
  let root = pipeline([("a", input), ("unused", input)])
  let declarations : Array[@parameter.BoundValues?] = [None, None, None]
  let applications = [capacity(root), capacity(producer), capacity(producer)]
  let caps = { ..limits(), max_steps: 10, }
  let result = results(root)
  let checked = @pipeline_check_context.check(
    result,
    declarations,
    applications,
    policy(),
    caps,
  ).unwrap()
  assert_eq(@pipeline_check_context.expression_requirement_count(checked), 10)
  let mut profiles = 0
  let mut envelopes = 0
  let mut patterns = 0
  for i in 0..<10 {
    let requirement = @pipeline_check_context.expression_requirement_at(
      checked, i,
    ).unwrap()
    assert_eq(requirement.visit, if i < 5 { 1 } else { 2 })
    assert_eq(requirement.step, 0)
    assert_true(
      @typing.node_at(requirement.expression, requirement.obligation.node_index)
      is Some(_),
    )
    match requirement.obligation.kind {
      ProfileAdmission(name) => {
        assert_eq(name, "actql-text-time/0.1")
        profiles += 1
      }
      HostEnvelope => envelopes += 1
      PatternValidation(name) => {
        assert_eq(name, "regex_match")
        patterns += 1
      }
    }
    let repeated = @pipeline_check_context.expression_requirement_at(
      checked,
      i % 5,
    ).unwrap()
    assert_true(physical_equal(requirement.expression, repeated.expression))
    assert_true(
      @typing.pending_validation_at(requirement.expression, -1) is None,
    )
    assert_true(
      @typing.pending_validation_at(
        requirement.expression,
        @typing.pending_validation_count(requirement.expression),
      )
      is None,
    )
  }
  assert_eq((profiles, envelopes, patterns), (4, 4, 2))
  assert_true(
    @pipeline_check_context.expression_requirement_at(checked, -1) is None,
  )
  assert_true(
    @pipeline_check_context.expression_requirement_at(checked, 10) is None,
  )
  let (work, text) = @pipeline_check_context.usage(checked)
  let exact = { ..caps, max_work: work, max_text_bytes: text, }
  assert_true(
    @pipeline_check_context.check(
      result,
      declarations,
      applications,
      policy(),
      exact,
    )
    is Ok(_),
  )
  assert_true(
    @pipeline_check_context.check(
      result,
      declarations,
      applications,
      policy(),
      { ..exact, max_work: work - 1, },
    )
    is Err(_),
  )
  let orders = @pipeline_check_context.checked_orders(checked)
  let (order_work, _) = @results.checked_orders_usage(orders)
  let inventory_work = @pipeline_check_context.expression_requirement_work(
    checked,
  )
  assert_true(
    @pipeline_check_context.check(
      result,
      declarations,
      applications,
      policy(),
      { ..caps, max_work: order_work + inventory_work - 1, },
    )
    is Err(Expressions(_)),
  )
  let first = @pipeline_check_context.expression_requirement_at(checked, 0).unwrap()
  let copied = @typing.pending_validations(first.expression)
  copied.clear()
  assert_true(@typing.pending_validation_count(first.expression) > 0)
  assert_eq(@pipeline_check_context.expression_requirement_count(checked), 10)
}
