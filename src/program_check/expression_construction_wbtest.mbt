///|
test "source construction closes nonempty expression obligations including unused branches" {
  for
    expression in [
      "regex_extract('x', '(.)', 1)", "if(FALSE, regex_extract('x', '(.)', 1), 'x')",
    ] {
    let budget = IdentityBudget::{
      work: 10000000,
      bytes: 1000000,
      nodes: 100000,
      depth: 100,
    }
    let (identity, _, _, _, units) = local_construction_fixture(
      budget,
      producer_expression=expression,
      text_time=true,
      text_policy=true,
    )
    let closure = units[0].expressions
    assert_true(
      physical_equal(@context.expression_closure_identity(closure), identity),
    )
    let mut profiles = 0
    let mut patterns = 0
    let mut envelopes = 0
    for i in 0..<@context.expression_closure_count(closure) {
      let entry = @context.expression_closure_at(closure, i).unwrap()
      match entry.resolution {
        Profile(name) => {
          assert_eq(name, "actql-text-time/0.1")
          profiles += 1
        }
        Pattern(value) => {
          assert_eq(
            @context.validation_site_location(@context.pattern_site(value)),
            @context.validation_site_location(entry.site),
          )
          patterns += 1
        }
        Envelope(value) => {
          assert_eq(
            @context.validation_site_location(@context.text_bound_site(value)),
            @context.validation_site_location(entry.site),
          )
          envelopes += 1
        }
      }
    }
    assert_true(profiles > 0)
    assert_true(patterns > 0)
    assert_true(envelopes > 0)
    assert_eq(units[0].expression_execution.length(), envelopes)
    for binding in units[0].expression_execution {
      assert_true(physical_equal(binding.owner, closure))
      let original = @context.expression_closure_at(
        closure,
        binding.requirement_index,
      ).unwrap()
      guard original.resolution is Envelope(bound) else {
        fail("non-envelope runtime binding")
      }
      assert_true(physical_equal(binding.bound, bound))
      assert_true(
        physical_equal(
          @context.text_bound_demands(binding.bound),
          @context.text_bound_demands(bound),
        ),
      )
      assert_true(
        physical_equal(
          @context.text_bound_policy(binding.bound),
          @context.text_bound_policy(bound),
        ),
      )
    }
    let exact = IdentityBudget::{
      work: @context.expression_closure_count(closure) + envelopes,
      bytes: 0,
      nodes: 0,
      depth: 0,
    }
    assert_eq(prepare_expression_execution(closure, exact).length(), envelopes)
    assert_eq(exact.work, 0)
  }
}

///|
test "missing expression configuration cannot produce constructed Units" {
  for (profile, policy) in [(false, true), (true, false)] {
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
        producer_expression="if(FALSE, regex_extract('x', '(.)', 1), 'x')",
        text_time=profile,
        text_policy=policy,
      )
    catch {
      LocalConstructionFailure::Source(_) => ()
      e => raise e
    } noraise {
      _ => fail("missing expression configuration escaped construction")
    }
    assert_eq((budget.work, budget.bytes, budget.nodes), before)
  }
}
