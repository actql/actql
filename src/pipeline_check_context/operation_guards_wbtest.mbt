///|
test "classified operation counts enforce exact domains without claiming guard execution" {
  let positive : Array[@pipeline.OperationObligation] = [
    @pipeline.JoinRequirement(BindGuard("n")),
    @pipeline.CrossJoinRequirement(BindGuard("n")),
    @pipeline.IntervalJoinRequirement(BindGuard("n")),
    @pipeline.AsOfRequirement(BindGuard("n")),
    @pipeline.NestRequirement(BindGuard("n")),
    @pipeline.GraphRequirement(BindPositiveCount("n")),
    @pipeline.TraverseRequirement(BindTraversalOutputGuard("n")),
    @pipeline.ShortestRequirement(BindShortestOutputGuard("n")),
  ]
  for requirement in positive {
    let demand = @pipeline.operation_scalar_demand(requirement).unwrap()
    for
      (n, integer) in [
        (1.0, 1L),
        (7.0, 7L),
        (9007199254740991.0, 9007199254740991L),
      ] {
      assert_eq(operation_scalar_number(n, demand), Some(Integer(integer)))
    }
    for n in [-1.0, 0.0, -0.0, 0.5, 9007199254740992.0, 0.0 / 0.0, 1.0 / 0.0] {
      assert_true(operation_scalar_number(n, demand) is None)
    }
  }
  let report = @pipeline.operation_scalar_demand(
    @pipeline.GraphRequirement(BindNonnegativeCount("n")),
  ).unwrap()
  assert_eq(operation_scalar_number(0.0, report), Some(Integer(0L)))
  for n in [-1.0, -0.0, 0.5, 9007199254740992.0] {
    assert_true(operation_scalar_number(n, report) is None)
  }
}

///|
test "sequence within and asof tolerance retain the positive millisecond domain" {
  for
    requirement in [
      @pipeline.SequenceRequirement(BindWithin("n")),
      @pipeline.AsOfRequirement(BindTolerance("n")),
    ] {
    let demand = @pipeline.operation_scalar_demand(requirement).unwrap()
    for
      (n, integer) in [
        (1.0, 1L),
        (1000.0, 1000L),
        (9007199254740991.0, 9007199254740991L),
      ] {
      assert_eq(operation_scalar_number(n, demand), Some(Milliseconds(integer)))
    }
    for n in [-1.0, 0.0, -0.0, 0.5, 9007199254740992.0, 0.0 / 0.0, 1.0 / 0.0] {
      assert_true(operation_scalar_number(n, demand) is None)
    }
  }
}
