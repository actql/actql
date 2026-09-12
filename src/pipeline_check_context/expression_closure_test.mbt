///|
fn expression_closure_fixture(expression : String) -> ProgramSourceIdentity {
  let (operations, references, bindings) = program_sources_fixture(expression~)
  identify_program_sources(
    bind_program_sources(operations, references, bindings, 10000000).unwrap(),
    identity_limits(),
  ).unwrap()
}

///|
test "expression closure maps every obligation to its owned resolution" {
  for
    (expression, expected_count) in [
      ("regex_extract($p, '(.)', $n)", 9),
      ("regex_extract(substring($p, 1, $n), '(.)', 1)", 15),
      ("if(FALSE, regex_extract($p, '(.)', $n), 'x')", 9),
      (
        "concat(format_timestamp(CAST(NULL AS TIMESTAMP), 'yyyy'), regex_extract($p, '(.)', $n))",
        18,
      ),
      ("if($p LIKE 'a%', regex_extract($p, '(.)', $n), 'x')", 12),
    ] {
    let identity = expression_closure_fixture(expression)
    let closed = close_program_expressions(identity, 10000000, 100).unwrap()
    assert_true(physical_equal(expression_closure_identity(closed), identity))
    let preparation = operation_profiles_preparation(
      program_sources_operations(program_identity_sources(identity)),
    )
    let bounds = preparation_expressions(preparation)
    let patterns = text_bounds_patterns(bounds)
    let context = pattern_context(patterns)
    let count = expression_closure_count(closed)
    assert_eq(count, expression_validation_count(context))
    assert_eq(count, expected_count)
    let mut profiles = 0
    let mut pattern_entries = 0
    let mut envelopes = 0
    for i in 0..<count {
      let entry = expression_closure_at(closed, i).unwrap()
      assert_true(physical_equal(validation_site_context(entry.site), context))
      assert_eq(
        validation_site_location(entry.site),
        validation_site_location(expression_validation_at(context, i).unwrap()),
      )
      match entry.resolution {
        Profile(name) => {
          assert_eq(name, "actql-text-time/0.1")
          assert_true(
            validation_site_requirement(entry.site).obligation.kind
            is @typing.ProfileAdmission(_),
          )
          profiles += 1
        }
        Pattern(p) => {
          assert_eq(
            validation_site_location(pattern_site(p)),
            validation_site_location(entry.site),
          )
          assert_true(
            validation_site_requirement(entry.site).obligation.kind
            is @typing.PatternValidation(_),
          )
          pattern_entries += 1
        }
        Envelope(b) => {
          assert_true(
            physical_equal(b, text_bound_at(bounds, envelopes).unwrap()),
          )
          assert_eq(
            validation_site_location(text_bound_site(b)),
            validation_site_location(entry.site),
          )
          assert_true(
            validation_site_requirement(entry.site).obligation.kind
            is @typing.HostEnvelope,
          )
          envelopes += 1
        }
      }
    }
    assert_eq(
      profiles,
      expression_profiles_count(preparation_profiles(preparation)),
    )
    assert_eq(pattern_entries, pattern_count(patterns))
    assert_eq(envelopes, text_bound_count(bounds))
    let work = expression_closure_work(closed)
    assert_eq(work, program_identity_usage(identity).0 + count + 1)
    assert_true(close_program_expressions(identity, work, count) is Ok(_))
    assert_true(
      close_program_expressions(identity, work - 1, count)
      is Err(BudgetExceeded),
    )
    assert_true(
      close_program_expressions(identity, work, count - 1)
      is Err(BudgetExceeded),
    )
    assert_true(
      close_program_expressions(identity, -1, count) is Err(InvalidLimits),
    )
    assert_true(
      close_program_expressions(identity, work, -1) is Err(InvalidLimits),
    )
    for index in [-1, count, 2147483647] {
      assert_true(expression_closure_at(closed, index) is None)
    }
  }
}

///|
test "empty expression obligation closure retains its source owner" {
  let identity = expression_closure_fixture("concat($p, to_string($n))")
  let work = program_identity_usage(identity).0 + 1
  let closed = close_program_expressions(identity, work, 0).unwrap()
  assert_eq(expression_closure_count(closed), 0)
  assert_eq(expression_closure_work(closed), work)
  assert_true(physical_equal(expression_closure_identity(closed), identity))
  assert_true(
    close_program_expressions(identity, work - 1, 0) is Err(BudgetExceeded),
  )
}
