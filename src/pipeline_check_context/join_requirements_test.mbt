///|
fn join_resolution_fixture(
  changes? : Bool = false,
  artifact_rows? : Int = 1,
) -> ProgramOperationResolutionIndex raise {
  let sources = prepare_program_source_acquisitions(
    prepared_keyed_source_context(changes~, artifact_rows~),
    [[(0, 0)]],
    {
      max_work: 10000000,
      max_pairs: 1000,
      values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
    },
    max_bindings=100,
    max_slots=1000,
  ).unwrap()
  let operations = prepare_program_checks(
    sources,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    preparation_limits(),
    max_policy_depth=100,
    max_requirements=1000,
    max_regex_depth=100,
  ).unwrap()
  let identity = prepare_program_source_identity(
    operations,
    source_preparation_limits(),
  ).unwrap()
  resolve_program_operations(identity, {
    max_work: 10000000,
    max_requirements: 1000,
    max_resolutions: 1000,
  }).unwrap()
}

///|
test "join requirements retain exact owners without inventing total order" {
  let index = join_resolution_fixture()
  let count = operation_resolution_count(index)
  let work = operation_resolution_work(index) + count * 2
  let linked = link_program_join_requirements(index, work, 3).unwrap()
  assert_eq(operation_resolution_work(linked), work)
  assert_eq(
    operation_resolution_unresolved_count(linked),
    operation_resolution_unresolved_count(index) - 3,
  )
  let requirements = operation_resolution_requirements(index)
  let mut seen = 0
  for i in 0..<count {
    let site = operation_requirements_at(requirements, i).unwrap()
    match operation_resolution_at(linked, i).unwrap() {
      Resolved(JoinCardinality(v)) => {
        seen += 1
        assert_true(physical_equal(v.site, site))
        assert_eq(v.requirement_index, i)
        // A keyed acquisition request is not a candidate-key uniqueness proof.
        assert_true(v.evidence.right is None)
        assert_true(v.evidence.cardinality is None)
        assert_true(v.evidence.assertion is None)
        assert_true(operation_resolution_at(index, i) is Some(Unresolved))
      }
      Execution(JoinOutputLimit(v)) => {
        seen += 1
        assert_true(physical_equal(v.site, site))
        assert_true(
          physical_equal(@program.join_limit_pipeline(v.limit), site.pipeline),
        )
        assert_eq(@program.join_limit_step(v.limit), site.step)
        assert_true(operation_resolution_at(index, i) is Some(Unresolved))
      }
      Execution(JoinRowOrder(v)) => {
        seen += 1
        assert_true(physical_equal(v.site, site))
        assert_true(
          physical_equal(
            v.step,
            @pipeline.step_at(site.pipeline, site.step).unwrap(),
          ),
        )
        assert_true(v.left_order is Some(_))
        assert_true(v.right_order is None)
        assert_true(v.output_order is None)
        assert_eq(
          operation_execution_phase(JoinRowOrder(v)),
          BeforeOperationOutput,
        )
        assert_eq(
          operation_execution_failure(JoinRowOrder(v)),
          RejectOperationOutput,
        )
        assert_true(operation_resolution_at(index, i) is Some(Unresolved))
      }
      _ => ()
    }
  }
  assert_eq(seen, 3)
  assert_true(
    link_program_join_requirements(index, work - 1, 3) is Err(BudgetExceeded),
  )
  assert_true(
    link_program_join_requirements(index, work, 2) is Err(BudgetExceeded),
  )
  assert_true(
    link_program_join_requirements(index, -1, 3) is Err(InvalidLimits),
  )
  assert_true(
    link_program_join_requirements(linked, work + count * 2, 3)
    is Err(ForeignOccurrence(_)),
  )
  // Linking cannot turn unrelated values requirements into completed checks.
  assert_true(
    close_program_operations(linked, work + count + 1, count)
    is Err(IncompleteResolution(_)),
  )
}
