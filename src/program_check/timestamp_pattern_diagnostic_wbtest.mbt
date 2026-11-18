///|
test "original timestamp parser failures retain the same typed cause as invalid input" {
  for pattern in ["", "%Y", "yyyyyyyy", "MM-dd", "yyyy-MM-dd ss"] {
    try {
      ignore(
        local_construction_fixture(
          { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
          through_check=true,
          text_time=true,
          text_policy=true,
          producer_expression="parse_timestamp('2026-01-02', '" + pattern + "')",
        ),
      )
      fail("invalid pattern constructed a checked Program")
    } catch {
      Source(Checks(Patterns(Timestamp(Pattern(_, _))))) as original => {
        let diagnostic = construction_failure_diagnostic(original)
        assert_eq(diagnostic_category(diagnostic), InvalidInput)
        assert_true(physical_equal(diagnostic_cause(diagnostic), original))
      }
      error => raise error
    }
  }
}
