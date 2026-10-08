///|
fn authoring_publication_fixture() -> (
  PipelineAuthoringContext,
  @results.ResultPorts,
) raise {
  let (authoring, orders, limits, metadata) = authoring_context_fixture()
  let context = prepare_pipeline_authoring_context(
    authoring, orders, limits, metadata,
  ).unwrap()
  let ports = @results.prepare_ports(prepared_pipeline_orders(orders), {
    max_results: 1,
    max_work: 100000,
    max_nodes: 1000,
    max_text_bytes: 100000,
    max_depth: 100,
  }).unwrap()
  (context, ports)
}

///|
test "authoring publication selects exact Result order and all real row candidates before values bind" {
  let (owner, ports) = authoring_publication_fixture()
  let checked = prepare_authoring_publications(owner, ports, 100000, 100).unwrap()
  assert_true(physical_equal(authoring_publication_owner(checked), owner))
  assert_true(physical_equal(authoring_publication_ports(checked), ports))
  assert_eq(authoring_publication_count(checked), 1)
  let selected = authoring_publication_at(checked, 0).unwrap()
  assert_true(
    physical_equal(
      authoring_publication_port(selected),
      @results.port_at(ports, 0).unwrap(),
    ),
  )
  assert_eq(authoring_publication_candidate_count(selected), 1)
  let candidate = authoring_publication_candidate_at(selected, 0).unwrap()
  assert_eq(
    @program.target_rows_value(@capacity.target_membership_rows(candidate)),
    1L,
  )
  assert_eq(authoring_publication_maximum_rows(selected), 1L)
  let context = pipeline_authoring_context_pipeline(owner)
  let policy = @capacity.application_closure_policy(checked_capacity(context))
  assert_true(
    physical_equal(
      @policy.ceiling_policy(authoring_publication_row_host(selected)),
      policy,
    ),
  )
  assert_true(
    physical_equal(
      @policy.ceiling_policy(authoring_publication_byte_host(selected)),
      policy,
    ),
  )
  assert_eq(
    @policy.ceiling_field(authoring_publication_row_host(selected)),
    "max_artifact_rows",
  )
  assert_eq(
    @policy.ceiling_field(authoring_publication_byte_host(selected)),
    "max_artifact_bytes",
  )
  assert_true(authoring_publication_at(checked, -1) is None)
  assert_true(authoring_publication_at(checked, 1) is None)
  assert_true(authoring_publication_candidate_at(selected, -1) is None)
  assert_true(authoring_publication_candidate_at(selected, 1) is None)
  let work = authoring_publication_work(checked)
  assert_true(prepare_authoring_publications(owner, ports, work, 100) is Ok(_))
  assert_true(
    prepare_authoring_publications(owner, ports, work - 1, 100)
    is Err(BudgetExceeded),
  )
  // One Result, one order obligation, one Program row candidate and two Host
  // quantities are retained. No obligation can disappear under truncation.
  assert_true(prepare_authoring_publications(owner, ports, 100000, 5) is Ok(_))
  assert_true(
    prepare_authoring_publications(owner, ports, 100000, 4)
    is Err(BudgetExceeded),
  )
}

///|
test "authoring publication refuses foreign Result ports and exhausted report inventory" {
  let (owner, ports) = authoring_publication_fixture()
  let (_, foreign) = authoring_publication_fixture()
  assert_true(
    prepare_authoring_publications(owner, foreign, 100000, 100)
    is Err(ForeignOrders),
  )
  assert_true(
    prepare_authoring_publications(owner, ports, 0, 100) is Err(BudgetExceeded),
  )
  assert_true(
    prepare_authoring_publications(owner, ports, 100000, 0)
    is Err(BudgetExceeded),
  )
  assert_true(
    prepare_authoring_publications(owner, ports, -1, 100) is Err(InvalidLimits),
  )
}
