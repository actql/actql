///|
test "guard domains distinguish positive counts nonnegative reports and temporal widths" {
  for
    (obligation, expected) in [
      (
        @pipeline_typing.JoinRequirement(BindGuard("n")),
        @pipeline_typing.SafeInteger("n", minimum=1L),
      ),
      (
        @pipeline_typing.CrossJoinRequirement(BindGuard("n")),
        @pipeline_typing.SafeInteger("n", minimum=1L),
      ),
      (
        @pipeline_typing.IntervalJoinRequirement(BindGuard("n")),
        @pipeline_typing.SafeInteger("n", minimum=1L),
      ),
      (
        @pipeline_typing.AsOfRequirement(BindGuard("n")),
        @pipeline_typing.SafeInteger("n", minimum=1L),
      ),
      (
        @pipeline_typing.AsOfRequirement(BindTolerance("n")),
        @pipeline_typing.Milliseconds("n", signed=false),
      ),
      (
        @pipeline_typing.NestRequirement(@nest.BindGuard("n")),
        @pipeline_typing.SafeInteger("n", minimum=1L),
      ),
      (
        @pipeline_typing.SequenceRequirement(@relation.BindWithin("n")),
        @pipeline_typing.Milliseconds("n", signed=false),
      ),
      (
        @pipeline_typing.GraphRequirement(@graph.BindPositiveCount("n")),
        @pipeline_typing.SafeInteger("n", minimum=1L),
      ),
      (
        @pipeline_typing.GraphRequirement(@graph.BindNonnegativeCount("n")),
        @pipeline_typing.SafeInteger("n", minimum=0L),
      ),
      (
        @pipeline_typing.TraverseRequirement(
          @graph.BindTraversalOutputGuard("n"),
        ),
        @pipeline_typing.SafeInteger("n", minimum=1L),
      ),
    ] {
    assert_eq(
      @pipeline_typing.operation_scalar_demand(obligation),
      Some(expected),
    )
  }
  for
    obligation in [
      @pipeline_typing.JoinRequirement(ValidateExactlyOneRightRow),
      @pipeline_typing.AsOfRequirement(RejectAsOfTies),
      @pipeline_typing.NestRequirement(@nest.ResolveItemLimit),
      @pipeline_typing.SequenceRequirement(@relation.AtomicMatchLimits),
      @pipeline_typing.GraphRequirement(@graph.EnforceOutputGuard),
      @pipeline_typing.TraverseRequirement(@graph.EnforceTraversalOutputGuard),
    ] {
    assert_true(@pipeline_typing.operation_scalar_demand(obligation) is None)
  }
}

///|
test "parsed guards and sequence widths reach the grouped operation inventory" {
  let parameters = @parameter.read_declarations(
    Some(cursor("{\"n\":{\"type\":\"number\"}}")),
    { max_parameters: 1, max_nodes: 10, max_depth: 10, max_text_bytes: 100, },
  ).unwrap()
  for
    (body, milliseconds) in [
      (
        "\"join\":{\"with\":\"r\",\"kind\":\"semi\",\"on\":\"id\",\"max_output_rows\":{\"$param\":\"n\"}}",
        false,
      ),
      (
        "\"cross_join\":{\"with\":\"r\",\"max_output_rows\":{\"$param\":\"n\"}}",
        false,
      ),
      (
        "\"nest\":{\"with\":\"r\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\"],\"max_items\":{\"$param\":\"n\"}}",
        false,
      ),
      (
        "\"sequence\":{\"by\":[],\"id\":\"id\",\"time\":\"amount\",\"pattern\":[{\"as\":\"begin\",\"where\":\"TRUE\"},{\"as\":\"end\",\"where\":\"TRUE\"}],\"within\":{\"$param\":\"n\"},\"overlap\":\"allow\",\"contiguity\":\"adjacent\"}",
        true,
      ),
    ] {
    let pipeline = @pipeline_typing.check(
      cursor("[{" + body + ",\"from\":\"l\"}]"),
      [("l", schema()), ("r", schema())],
      Some(parameters),
      None,
      limits(),
    ).unwrap()
    let op = @pipeline_typing.step_at(pipeline, 0).unwrap().operation
    let mut selected = 0
    let mut other = 0
    for i in 0..<@pipeline_typing.operation_obligation_group_count(op) {
      let group = @pipeline_typing.operation_obligation_group_at(op, i).unwrap()
      for j in 0..<@pipeline_typing.operation_obligations_count(group) {
        match
          @pipeline_typing.operation_scalar_demand(
            @pipeline_typing.operation_obligations_at(group, j).unwrap(),
          ) {
          Some(demand) => {
            selected += 1
            assert_eq(
              demand,
              if milliseconds {
                @pipeline_typing.Milliseconds("n", signed=false)
              } else {
                @pipeline_typing.SafeInteger("n", minimum=1L)
              },
            )
          }
          None => other += 1
        }
      }
    }
    assert_eq(selected, 1)
    assert_true(other > 0)
  }
}
