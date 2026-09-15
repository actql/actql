///|
test "normal Program budget sweep exposes limits without preparation wrappers" {
  let (text, parsed, environment, _, limits) = public_input_fixture(
    generated=true,
  )
  let unexpected : Array[Int] = []
  let mut successes = 0
  let mut failures = 0
  for work in 0..<=100 {
    let amount = work * 1000
    let bounded = {
      ..limits,
      compilation: { ..limits.compilation, work: amount, },
    }
    for
      outcome in [
        @program_check.check_parsed(parsed, environment, None, bounded),
        @program_check.check_document(
          text,
          environment,
          None,
          bounded,
          format=Json,
        ),
      ] {
      match outcome {
        Checked(_) => successes += 1
        Rejected(diagnostic) => {
          failures += 1
          if @program_check.diagnostic_category(diagnostic) !=
            @program_check.CompileLimit {
            unexpected.push(amount)
          }
        }
        NeedsInputs(_) =>
          fail("a compile budget cannot become an external input request")
      }
    }
  }
  assert_eq(unexpected, [])
  assert_true(successes > 0 && failures > 0)
  assert_true(
    @program_check.check_parsed(parsed, environment, None, {
      ..limits,
      compilation: { ..limits.compilation, work: 100000, },
    })
    is Checked(_),
  )
}
