///|
test "optional derived alias preserves the existing budget with fused producers" {
  let q = @query.parse_query(
    "SELECT id FROM (SELECT 1 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) UNION ALL SELECT 2 UNION ALL SELECT 1) WHERE id IS NOT NULL ORDER BY id DESC NULLS FIRST LIMIT 3",
    syntax_limits(),
  ).unwrap()
  let p = compile(q, { ..values_context(), inputs: [], }, construction_limits()).unwrap()
  match
    @check.check_parsed(
      p,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed query")
  }
  // Binding does not materialize each UNION arm into a separate Stage.
  // Keep the original 20-step allowance, and independently prove that the
  // structural limit is still enforced below the minimum required pipeline.
  assert_eq(@program.stage_count(p), 1)
  let original = check_limits()
  let too_small = {
    ..original,
    compilation: {
      ..original.compilation,
      structure: { ..original.compilation.structure, steps: 1, },
    },
  }
  match @check.check_parsed(p, check_environment(numeric=true), None, too_small) {
    Rejected(issue) => assert_eq(@check.diagnostic_category(issue), @check.CompileLimit)
    _ => fail("the ordinary checker must retain its structural step limit")
  }
}

///|
test "named derived alias preserves the same predicate limit and budget" {
  let q = @query.parse_query(
    "SELECT id FROM (SELECT 1 AS id UNION ALL SELECT CAST(NULL AS FLOAT64) UNION ALL SELECT 2 UNION ALL SELECT 1) chosen WHERE id IS NOT NULL ORDER BY id DESC NULLS FIRST LIMIT 3",
    syntax_limits(),
  ).unwrap()
  let p = compile(q, { ..values_context(), inputs: [], }, construction_limits()).unwrap()
  match
    @check.check_parsed(
      p,
      check_environment(numeric=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(issue) => raise @check.diagnostic_cause(issue)
    NeedsInputs(_) => fail("closed named query")
  }
  // Binding does not materialize each UNION arm into a separate Stage.
  // Keep the original 20-step allowance, and independently prove that the
  // structural limit is still enforced below the minimum required pipeline.
  assert_eq(@program.stage_count(p), 1)
  let original = check_limits()
  let too_small = {
    ..original,
    compilation: {
      ..original.compilation,
      structure: { ..original.compilation.structure, steps: 1, },
    },
  }
  match @check.check_parsed(p, check_environment(numeric=true), None, too_small) {
    Rejected(issue) => assert_eq(@check.diagnostic_category(issue), @check.CompileLimit)
    _ => fail("the ordinary checker must retain its structural step limit")
  }
}
