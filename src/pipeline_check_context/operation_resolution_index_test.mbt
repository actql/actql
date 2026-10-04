///|
fn resolution_profiles(
  requirements : ProgramOperationRequirements,
) -> ProgramOperationProfileLinks {
  let orders = link_program_operation_orders(requirements, 10000000, 100).unwrap()
  let scalars = check_program_operation_scalars(orders, 10000000, 100).unwrap()
  let frames = check_program_operation_frames(scalars, 10000000, 100).unwrap()
  let fills = check_program_operation_fills(frames, 10000000, 100).unwrap()
  profiles_from_ranges(
    check_program_operation_ranges(fills, 10000000, 100).unwrap(),
  )
}

///|
fn check_resolution_index(
  profiles : ProgramOperationProfileLinks,
  seen : Array[Bool],
) -> Unit raise {
  let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
  assert_true(physical_equal(operation_resolution_profiles(index), profiles))
  let requirements = operation_resolution_requirements(index)
  let count = operation_requirements_count(requirements)
  check_operation_closure(index)
  assert_eq(operation_resolution_count(index), count)
  let mut resolved = 0
  let mut execution = 0
  let mut execution_work = operation_calendar_count(
    operation_profile_links_calendar(profiles),
  )
  for i in 0..<count {
    let state = operation_resolution_at(index, i).unwrap()
    let site = operation_requirements_at(requirements, i).unwrap()
    match state {
      Execution(SequenceMatch(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
        if check.within_resolution is Some(scalar) {
          execution_work += @pipeline.operation_obligations_count(
              site.obligations,
            ) +
            scalar.parameter.name.length() * 2
        }
      }
      Execution(SequenceLimits(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(PropertyGraphConstructionExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(GraphDiagnosticExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(GraphEqualityExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(GraphNormalizeExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(SequenceExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(CalendarExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
        execution_work += @pipeline.operation_obligations_count(
          site.obligations,
        )
      }
      Execution(SeriesExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
        execution_work += @pipeline.operation_obligations_count(
            site.obligations,
          ) +
          check.range.start.length() +
          check.range.end.length() +
          1
        if check.step_resolution is Some(scalar) {
          execution_work += scalar.parameter.name.length() * 2
        }
      }
      Execution(EventEnvelope(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(SessionExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(AsOfExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(AsOfSearch(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(EventExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(IntervalSearch(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(IntervalExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(WatermarkExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(WindowMembershipLimit(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Unresolved => ()
      Execution(WindowExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(AnalyticExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(AnalyticEnvelope(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(ExpansionExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(JsonPickExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(LagExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(TopKExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(GroupExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(PivotExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(NestExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(NestItems(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(NestValues(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(RowAssertion(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(DedupeTopTie(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(AppendRows(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(SetRows(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(GraphMatchExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(GraphSelectorExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(VectorExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(NearestExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(PoolExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(RankingExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(TextRankExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(TraversalLimits(check) | TraversalOutputGuard(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(TraversalExecution(check)) => {
        execution += 1
        assert_true(physical_equal(check.site, site))
      }
      Execution(ValuesPublication(_)) =>
        abort("values resources require explicit resolution")
      Execution(JoinOutputLimit(_)) =>
        abort("join limits require explicit linking")
      Execution(JoinRowOrder(_)) =>
        abort("join order requires explicit linking")
      Execution(JoinInputValidation(_)) =>
        abort("join input validation requires explicit linking")
      Execution(JoinIdentity(_)) =>
        abort("join identity requires explicit linking")
      Execution(CrossJoinRows(_)) =>
        abort("cross join requires explicit linking")
      Execution(CrossJoinIdentity(_)) =>
        abort("cross join identity requires explicit linking")
      Resolved(v) => {
        resolved += 1
        let (position, owner, kind) = match v {
          AsOfCompletion(_) => abort("as-of completion has dedicated tests")
          RankingEnvelope(_) => abort("ranking envelopes have dedicated tests")
          WindowPublication(_) =>
            abort("window publication requires owned Stage closure")
          Order(r) => (r.requirement_index, r.site, 0)
          Scalar(r) => (r.requirement_index, r.site, 1)
          Frame(r) => (r.requirement_index, r.site, 2)
          Fill(r) => (r.requirement_index, r.site, 3)
          Range(r) => (r.requirement_index, r.site, 4)
          Query(r) => (r.requirement_index, r.site, 5)
          Cell(r) => (r.requirement_index, r.site, 6)
          ProfileResolution(r) => (r.requirement_index, r.site, 7)
          JoinCardinality(_) =>
            abort("join cardinality requires explicit linking")
          AssertionConsumption(_) =>
            abort("assertion consumption has dedicated tests")
        }
        seen[kind] = true
        assert_eq(position, i)
        assert_true(physical_equal(owner, site))
      }
    }
  }
  assert_eq(
    operation_resolution_unresolved_count(index),
    count - resolved - execution,
  )
  let cells = operation_lexical_cells(
    operation_calendar_lexical(operation_profile_links_calendar(profiles)),
  )
  let queries = operation_cells_queries(cells)
  let ranges = operation_queries_ranges(queries)
  let fills = operation_ranges_fills(ranges)
  let frames = operation_fills_frames(fills)
  let scalars = operation_frames_scalars(frames)
  let orders = operation_scalars_orders(scalars)
  let expected = operation_orders_count(orders) +
    operation_scalars_count(scalars) +
    operation_frames_count(frames) +
    operation_fills_count(fills) +
    operation_ranges_count(ranges) +
    operation_queries_count(queries) +
    operation_cells_count(cells) +
    operation_profile_links_count(profiles)
  assert_eq(resolved, expected)
  let calendar = operation_profile_links_calendar(profiles)
  let lexical = operation_calendar_lexical(calendar)
  let identity = expression_closure_identity(
    operation_requirements_expressions(requirements),
  )
  let limits : OperationResolutionLimits = {
    max_work: operation_resolution_work(index),
    max_requirements: count +
    expression_closure_count(operation_requirements_expressions(requirements)),
    max_resolutions: expected +
    operation_calendar_count(calendar) +
    operation_lexical_count(lexical),
  }
  let combined = resolve_program_operations(
    identity,
    limits,
    calendar=operation_calendar_profile(calendar),
    text_rank=operation_lexical_profile(lexical),
  ).unwrap()
  assert_eq(
    operation_resolution_work(combined),
    operation_resolution_work(index),
  )
  assert_eq(operation_resolution_count(combined), count)
  assert_eq(
    operation_resolution_unresolved_count(combined),
    operation_resolution_unresolved_count(index),
  )
  assert_true(
    physical_equal(
      expression_closure_identity(
        operation_requirements_expressions(
          operation_resolution_requirements(combined),
        ),
      ),
      identity,
    ),
  )
  for i in 0..<count {
    let kind = fn(v : OperationResolutionState) {
      match v {
        Resolved(RankingEnvelope(_)) => 15
        Resolved(AsOfCompletion(_)) => 13
        Resolved(WindowPublication(_)) => 12
        Resolved(AssertionConsumption(_)) => 11
        Unresolved => 0
        Execution(_) => 1
        Resolved(Order(_)) => 2
        Resolved(Scalar(_)) => 3
        Resolved(Frame(_)) => 4
        Resolved(Fill(_)) => 5
        Resolved(Range(_)) => 6
        Resolved(Query(_)) => 7
        Resolved(Cell(_)) => 8
        Resolved(ProfileResolution(_)) => 9
        Resolved(JoinCardinality(_)) => 10
      }
    }
    assert_eq(
      kind(operation_resolution_at(combined, i).unwrap()),
      kind(operation_resolution_at(index, i).unwrap()),
    )
  }
  let short = [{ ..limits, max_work: limits.max_work - 1, }]
  if limits.max_requirements > 0 {
    short.push({ ..limits, max_requirements: limits.max_requirements - 1, })
  }
  if limits.max_resolutions > 0 {
    short.push({ ..limits, max_resolutions: limits.max_resolutions - 1, })
  }
  for cap in short {
    assert_true(
      resolve_program_operations(
        identity,
        cap,
        calendar=operation_calendar_profile(calendar),
        text_rank=operation_lexical_profile(lexical),
      )
      is Err(_),
    )
  }
  let work = operation_resolution_work(index)
  assert_eq(
    work,
    operation_profile_links_work(profiles) +
    1 +
    count * 2 +
    resolved +
    execution_work +
    operation_lexical_count(lexical),
  )
  assert_true(
    index_program_operation_resolutions(profiles, work, count) is Ok(_),
  )
  assert_true(
    index_program_operation_resolutions(profiles, work - 1, count)
    is Err(BudgetExceeded),
  )
  if count > 0 {
    assert_true(
      index_program_operation_resolutions(profiles, work, count - 1)
      is Err(BudgetExceeded),
    )
  }
  assert_true(
    index_program_operation_resolutions(profiles, -1, count)
    is Err(InvalidLimits),
  )
  assert_true(
    index_program_operation_resolutions(profiles, work, -1)
    is Err(InvalidLimits),
  )
  for i in [-2147483648, -1, count, 2147483647] {
    assert_true(operation_resolution_at(index, i) is None)
  }
}

///|
fn check_operation_closure(
  index : ProgramOperationResolutionIndex,
) -> Unit raise {
  let count = operation_resolution_count(index)
  let work = operation_resolution_work(index) + count + 1
  let mut first_unresolved = None
  for i in 0..<count {
    if operation_resolution_at(index, i) is Some(Unresolved) &&
      first_unresolved is None {
      first_unresolved = Some(i)
    }
  }
  if first_unresolved is Some(position) {
    guard close_program_operations(index, work, count)
      is Err(IncompleteResolution(actual)) else {
      fail("unresolved operations must not be sealed")
    }
    assert_eq(actual, position)
  } else {
    let closed = close_program_operations(index, work, count).unwrap()
    assert_true(physical_equal(operation_closure_index(closed), index))
    assert_eq(operation_closure_count(closed), count)
    assert_eq(operation_closure_work(closed), work)
    for i in 0..<count {
      match
        (
          operation_resolution_at(index, i).unwrap(),
          operation_closure_at(closed, i).unwrap(),
        ) {
        (Resolved(before), StaticResolution(after)) =>
          assert_true(physical_equal(before, after))
        (Execution(DedupeTopTie(before)), ExecutionCheck(DedupeTopTie(after))) => {
          assert_true(physical_equal(before, after))
          assert_eq(
            operation_execution_phase(DedupeTopTie(after)),
            BeforeOperationOutput,
          )
          assert_eq(
            operation_execution_failure(DedupeTopTie(after)),
            RejectOperationOutput,
          )
        }
        (Execution(before), ExecutionCheck(after)) =>
          assert_true(physical_equal(before, after))
        _ => fail("closure must preserve the original disposition")
      }
    }
    for invalid in [-2147483648, -1, count, 2147483647] {
      assert_true(operation_closure_at(closed, invalid) is None)
    }
  }
  assert_true(
    close_program_operations(index, work - 1, count) is Err(BudgetExceeded),
  )
  if count > 0 {
    assert_true(
      close_program_operations(index, work, count - 1) is Err(BudgetExceeded),
    )
  }
  assert_true(close_program_operations(index, -1, count) is Err(InvalidLimits))
  assert_true(close_program_operations(index, work, -1) is Err(InvalidLimits))
}

///|
test "profile preparation retains the exact original requirement inventory" {
  let text = scalar_steps(
    "{\"sort\":[{\"id\":\"asc\"}]},{\"take\":{\"$param\":\"n\"}}",
  )
  let first = operation_order_fixture(text)
  let second = operation_order_fixture(text)
  assert_true(!physical_equal(first, second))
  for original in [first, second] {
    let profiles = resolution_profiles(original)
    let index = index_program_operation_resolutions(profiles, 10000000, 1000).unwrap()
    assert_true(
      physical_equal(operation_resolution_requirements(index), original),
    )
    for i in 0..<operation_requirements_count(original) {
      assert_true(
        physical_equal(
          operation_requirements_at(operation_resolution_requirements(index), i).unwrap(),
          operation_requirements_at(original, i).unwrap(),
        ),
      )
    }
  }
}

///|
test "resolution index covers all static result families with exact occurrence ownership" {
  let seen = Array::make(8, false)
  check_resolution_index(
    resolution_profiles(
      operation_order_fixture(
        scalar_steps(
          "{\"sort\":[{\"id\":\"asc\"}]},{\"take\":{\"$param\":\"n\"}}",
        ),
      ),
    ),
    seen,
  )
  let frames = check_program_operation_frames(
    frame_fixture(
      "{\"preceding\":{\"$param\":\"n\"}}", "{\"preceding\":1}", "2",
    ),
    10000000,
    100,
  ).unwrap()
  let fills = check_program_operation_fills(frames, 10000000, 100).unwrap()
  check_resolution_index(
    profiles_from_ranges(
      check_program_operation_ranges(fills, 10000000, 100).unwrap(),
    ),
    seen,
  )
  let fills = check_program_operation_fills(
    fill_fixture(
      "{\"type\":\"number\",\"default\":3}", "{\"type\":\"number\",\"nullable\":false}",
      "1", "{\"$param\":\"n\"}",
    ),
    10000000,
    100,
  ).unwrap()
  check_resolution_index(
    profiles_from_ranges(
      check_program_operation_ranges(fills, 10000000, 100).unwrap(),
    ),
    seen,
  )
  let ranges = check_program_operation_ranges(
    range_fixture(
      false, "{\"$param\":\"n\"}", "\"2000-01-01T00:00:00.000Z\"", "1999-12-31T23:59:59.999Z",
    ),
    10000000,
    100,
  ).unwrap()
  check_resolution_index(profiles_from_ranges(ranges), seen)
  check_resolution_index(
    profiles_from_ranges(query_fixture("{\"$param\":\"n\"}", "[1,2]")),
    seen,
  )
  let cells = check_program_operation_cells(
    cells_fixture(
      "{\"type\":\"number\",\"nullable\":false}", "{\"type\":\"number\",\"default\":7}",
      "[{\"x\":{\"$param\":\"n\"}},{\"x\":{\"$param\":\"n\"}}]",
    ),
    10000000,
    100,
  ).unwrap()
  let lexical = check_program_operation_lexical(cells, None, 10000000, 100).unwrap()
  let calendar = check_program_operation_calendar(lexical, None, 10000000, 100).unwrap()
  check_resolution_index(
    link_program_operation_profiles(calendar, 10000000, 100).unwrap(),
    seen,
  )
  assert_true(seen.all(v => v))
}

///|
test "dedupe execution checks retain their exact occurrences without claiming execution success" {
  let profiles = resolution_profiles(
    operation_order_fixture(
      "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"dedupe_rows\":{\"by\":[\"id\",\"id\"],\"order_by\":[{\"id\":\"asc\"}]}}]",
    ),
  )
  let index = index_program_operation_resolutions(profiles, 10000000, 3).unwrap()
  assert_eq(operation_resolution_count(index), 3)
  assert_eq(operation_resolution_unresolved_count(index), 0)
  check_operation_closure(index)
  for i in 0..<3 {
    let site = operation_requirements_at(
      operation_resolution_requirements(index),
      i,
    ).unwrap()
    guard site.requirement is @pipeline.RelationRequirement(p) else {
      abort("relation")
    }
    assert_eq(p.kind, FailOnTopTie)
    guard operation_resolution_at(index, i) is Some(Execution(check)) else {
      abort("execution")
    }
    guard check is DedupeTopTie(tie) else { abort("dedupe execution") }
    assert_true(physical_equal(tie.site, site))
    assert_true(
      physical_equal(
        tie.step,
        @pipeline.step_at(site.pipeline, site.step).unwrap(),
      ),
    )
    assert_eq(tie.step.input, Some(tie.input))
    assert_eq(@relation.dedupe_key_count(tie.operation), 2)
    assert_eq(@relation.dedupe_order_count(tie.operation), 1)
    assert_eq(dedupe_top_tie_law(tie), "aoa.rela.REL.dedupeRows.v0.1")
    assert_eq(operation_execution_phase(check), BeforeOperationOutput)
    assert_eq(operation_execution_failure(check), RejectOperationOutput)
  }
  let (identity, _, _) = prepared_identity_fixture()
  let expressions = close_program_expressions(identity, 10000000, 0).unwrap()
  let requirements = collect_program_operation_requirements(
    expressions, 10000000, 0,
  ).unwrap()
  let empty = resolution_profiles(requirements)
  check_resolution_index(empty, Array::make(8, false))
  assert_eq(
    operation_resolution_count(
      index_program_operation_resolutions(empty, 10000000, 0).unwrap(),
    ),
    0,
  )
}

///|
test "vector resource bindings retain the selected policy and exact operation" {
  let index = index_program_operation_resolutions(
    profiles_from_ranges(query_fixture("{\"$param\":\"n\"}", "[1,2]")),
    10000000,
    100,
  ).unwrap()
  // Values resource preparation is separate from these vector bindings.
  assert_eq(operation_resolution_unresolved_count(index), 3)
  check_operation_closure(index)
  let mut resources = 0
  for i in 0..<operation_resolution_count(index) {
    let site = operation_requirements_at(
      operation_resolution_requirements(index),
      i,
    ).unwrap()
    if site.requirement is @pipeline.VectorRequirement(ResolveVectorResources) {
      resources += 1
      guard operation_resolution_at(index, i)
        is Some(Execution(VectorExecution(check))) else {
        fail("missing vector resource binding")
      }
      assert_true(physical_equal(check.site, site))
      assert_eq(check.rule, RequireVectorResources)
      assert_eq(
        vector_resource_count(check),
        if site.step == 2 {
          3
        } else {
          4
        },
      )
      assert_eq(
        vector_resource_at(check, 3),
        if site.step == 2 {
          None
        } else {
          Some(ScoreOrderingWork)
        },
      )
      assert_true(vector_resource_at(check, 4) is None)
    }
  }
  assert_true(resources > 0)
}

///|
test "global dedupe keeps its empty authored partition and nonempty order in execution binding" {
  let profiles = resolution_profiles(
    operation_order_fixture(
      "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"dedupe_rows\":{\"by\":[],\"order_by\":[{\"id\":\"desc\"}]}}]",
    ),
  )
  let index = index_program_operation_resolutions(profiles, 10000000, 3).unwrap()
  assert_eq(operation_resolution_count(index), 3)
  for i in 0..<3 {
    guard operation_resolution_at(index, i)
      is Some(Execution(DedupeTopTie(tie))) else {
      abort("global tie check")
    }
    assert_eq(@relation.dedupe_key_count(tie.operation), 0)
    assert_eq(@relation.dedupe_order_count(tie.operation), 1)
    let order = @relation.dedupe_order_at(tie.operation, 0).unwrap()
    assert_eq(order.direction, Desc)
    assert_eq(order.nulls, Last)
    assert_eq(tie.site.stage, if i == 0 { 0 } else { 1 })
    assert_eq(tie.site.step, 1)
    assert_eq(tie.input, @pipeline.Step(0))
  }
  check_resolution_index(profiles, Array::make(8, false))
}
