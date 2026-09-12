///|
fn prepared_stage_fixture() -> @stage_results.PreparedLocalSource {
  let (_, wiring, _, _, _, _) = prepared_local_context_fixture()
  @stage_results.prepare_local_source(
    @stages.program(@stage_results.wiring_source(wiring)),
    None,
    max_parameters=1,
    {
      max_stages: 2,
      max_steps: 2,
      max_results: 2,
      max_work: 1000000,
      max_nodes: 100000,
      max_tokens: 10000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
  ).unwrap()
}

///|
fn prepared_stage_applications(
  prepared : @stage_results.PreparedLocalSource,
  index : Int,
) -> Array[@capacity.ApplicationCoverage] {
  let port = @stage_results.wiring_stage_at(
    @stage_results.local_source_wiring(prepared),
    index,
  ).unwrap()
  let closure = @results.checked_producer_orders(
    @results.ports_orders(@stage_results.stage_port_publications(port)),
  )
  Array::makei(@pipeline.contextual_closure_count(closure), i => {
    // The fixture has only scalar derives, with no capacity claims. This is
    // not a capacity ledger default for arbitrary operations.
    capacity(
      @pipeline.contextual_orders_pipeline(
        @pipeline.contextual_closure_at(closure, i).unwrap(),
      ),
    )
  })
}

///|
test "prepared Stage contexts derive order and value owners without caller binding arrays" {
  let prepared = prepared_stage_fixture()
  let foreign = prepared_stage_fixture()
  for i in 0..<2 {
    let apps = prepared_stage_applications(prepared, i)
    let checked = check_prepared_local_stage(
      prepared,
      i,
      apps,
      policy(),
      max_work=1000000,
      max_text_bytes=1000000,
    ).unwrap()
    let context = parameter_context(checked)
    let port = @stage_results.wiring_stage_at(
      @stage_results.local_source_wiring(prepared),
      i,
    ).unwrap()
    assert_true(
      physical_equal(
        checked_orders(context),
        @results.ports_orders(@stage_results.stage_port_publications(port)),
      ),
    )
    for j in 0..<parameter_visit_count(checked) {
      let values = @pipeline.bound_guard_bindings(
        @pipeline.bound_guard_closure_at(bound_guards(context), j).unwrap(),
      ).unwrap()
      assert_true(
        physical_equal(values, @stage_results.local_source_values(prepared)),
      )
    }
    let (work, text) = parameter_usage(checked)
    assert_true(
      check_prepared_local_stage(
        prepared,
        i,
        apps,
        policy(),
        max_work=work,
        max_text_bytes=text,
      )
      is Ok(_),
    )
    assert_true(
      check_prepared_local_stage(
        prepared,
        i,
        apps,
        policy(),
        max_work=work - 1,
        max_text_bytes=text,
      )
      is Err(_),
    )
    assert_true(
      check_prepared_local_stage(
        prepared,
        i,
        apps,
        policy(),
        max_work=work,
        max_text_bytes=text - 1,
      )
      is Err(_),
    )
    assert_true(
      check_prepared_local_stage(
        prepared,
        i,
        prepared_stage_applications(foreign, i),
        policy(),
        max_work=1000000,
        max_text_bytes=1000000,
      )
      is Err(Context(Capacity(ForeignPipeline(_)))),
    )
    assert_true(
      check_prepared_local_stage(
        prepared,
        i,
        [],
        policy(),
        max_work=1000000,
        max_text_bytes=1000000,
      )
      is Err(Context(Capacity(CoverageCount(..)))),
    )
  }
  for i in [-2147483648, -1, 2, 2147483647] {
    assert_true(
      check_prepared_local_stage(
        prepared,
        i,
        [],
        policy(),
        max_work=1000000,
        max_text_bytes=1000000,
      )
      is Err(MissingStage),
    )
  }
  assert_true(
    check_prepared_local_stage(
      prepared,
      0,
      [],
      policy(),
      max_work=-1,
      max_text_bytes=0,
    )
    is Err(InvalidLimits),
  )
}
