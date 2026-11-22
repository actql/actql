///|
test "authored regex parser failures preserve the exact typed invalid-input cause" {
  for pattern in ["(", "[z-a]", "a**", "(a?)+"] {
    try {
      ignore(
        local_construction_fixture(
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
          through_check=true,
          text_time=true,
          text_policy=true,
          producer_expression="regex_match(NULL, '" + pattern + "')",
        ),
      )
      fail("invalid regex constructed a checked Program")
    } catch {
      Source(Checks(Patterns(Regex(Pattern(_, _))))) as original => {
        let diagnostic = construction_failure_diagnostic(original)
        assert_eq(diagnostic_category(diagnostic), InvalidInput)
        assert_true(physical_equal(diagnostic_cause(diagnostic), original))
      }
      error => raise error
    }
  }
}
