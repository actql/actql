///|
test "staged check and Catalog continuation retain the original Source and completed Parameter binding" {
  for route in [0, 1, 2, 3] {
    let (_, program, environment, evidence, limits) = public_input_fixture(
      generated=true,
      repeated=true,
    )
    let source = @stages.prepare(program, {
      max_parameters: 1,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    }).unwrap()
    let (source, binding) = @stages.prepare_bindings(source, None, {
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    })
    guard binding is Ok(Ready(original_values)) else {
      fail("original binding")
    }
    let input = @program_check.prepare_parsed_check_input(
      program,
      environment,
      None,
      evidence,
      limits,
      source_preparation=Some(source),
    ).unwrap()
    // The captured binder result, not this now-invalid registration array,
    // continues through every real semantic entrance below.
    let original_sources = evidence[0].sources
    evidence.clear()
    evidence.push({
      stage: "not-the-original-stage",
      sources: original_sources,
      uses: [],
    })
    let outcome = if route == 0 {
      @program_check.finish_parsed_check_input(input)
    } else {
      let prelude = @program_check.observe_parsed_check_prelude(input).0.unwrap()
      if route == 1 {
        @program_check.finish_parsed_check_prelude(prelude).unwrap()
      } else {
        let selected = @program_check.prepare_parsed_catalog_input(prelude).unwrap()
        let owner = @program_check.observe_parsed_check_registry(selected).0.unwrap()
        if route == 3 {
          @program_check.observe_parsed_check_contents(
            @program_check.prepare_parsed_contents_input(owner).unwrap(),
          ).0.unwrap()
          @program_check.observe_parsed_check_references(
            @program_check.prepare_parsed_references_input(owner).unwrap(),
          ).0.unwrap()
          @program_check.observe_parsed_check_policies(
            @program_check.prepare_parsed_policies_input(owner).unwrap(),
          ).0.unwrap()
          @program_check.observe_parsed_check_values(
            @program_check.prepare_parsed_values_input(owner).unwrap(),
          ).0.unwrap()
          @program_check.observe_parsed_check_views(
            @program_check.prepare_parsed_views_input(owner).unwrap(),
          ).0.unwrap()
          @program_check.observe_parsed_check_carriers(
            @program_check.prepare_parsed_carriers_input(owner).unwrap(),
          ).0.unwrap()
          @program_check.observe_parsed_check_requests(
            @program_check.prepare_parsed_requests_input(owner).unwrap(),
          ).0.unwrap()
        }
        @program_check.finish_parsed_check_registry(owner).unwrap()
      }
    }
    let checked = public_checked(outcome)
    let pipeline = @program_check.unit_pipeline(checked, 0).unwrap()
    assert_true(
      physical_equal(
        @pipeline.parameters(pipeline).unwrap(),
        @stages.declarations(source),
      ),
    )
    let identity = @context.program_identity_stage_at(
      @program_check.source_identity(checked),
      0,
    ).unwrap()
    assert_true(
      physical_equal(
        @parameter_refs.used_value_at(
          @context.stage_identity_parameter_values(identity),
          0,
        ).unwrap(),
        @parameters.bound_value_at(original_values, 0).unwrap(),
      ),
    )
  }
  // Only the original input holder's added borrowed Source reference. This
  // neither prices its backing nor grants a successful semantic verdict.
  assert_eq(@program_check.parsed_check_input_retained_control_extent(), {
    record_headers: 1L,
    reference_slots: 7L,
    scalar_words: 0L,
  })
}

///|
test "Request-stage original supplied binding reuses fitting values and replaces a tight failed read" {
  for original_nodes in [1000, 0] {
    let (_, program, environment, evidence, limits) = public_input_fixture(
      generated=true,
    )
    let supplied = quotation_supplied("{\"n\":7}")
    let source = @stages.prepare(program, {
      max_parameters: 1,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    }).unwrap()
    let (source, bound) = @stages.prepare_bindings(source, Some(supplied), {
      max_nodes: original_nodes,
      max_depth: 0,
      max_text_bytes: 10000,
    })
    if original_nodes == 0 {
      assert_true(bound is Err(_))
    } else {
      assert_true(bound is Ok(Ready(_)))
    }
    let original = @program_check.prepare_parsed_check_input(
      program,
      environment,
      Some(supplied),
      evidence,
      limits,
      source_preparation=Some(source),
    ).unwrap()
    let prelude = @program_check.observe_parsed_check_prelude(original).0.unwrap()
    let registry = @program_check.observe_parsed_check_registry(
      @program_check.prepare_parsed_catalog_input(prelude).unwrap(),
    ).0.unwrap()
    @program_check.observe_parsed_check_contents(
      @program_check.prepare_parsed_contents_input(registry).unwrap(),
    ).0.unwrap()
    @program_check.observe_parsed_check_references(
      @program_check.prepare_parsed_references_input(registry).unwrap(),
    ).0.unwrap()
    @program_check.observe_parsed_check_policies(
      @program_check.prepare_parsed_policies_input(registry).unwrap(),
    ).0.unwrap()
    @program_check.observe_parsed_check_values(
      @program_check.prepare_parsed_values_input(registry).unwrap(),
    ).0.unwrap()
    @program_check.observe_parsed_check_views(
      @program_check.prepare_parsed_views_input(registry).unwrap(),
    ).0.unwrap()
    @program_check.observe_parsed_check_carriers(
      @program_check.prepare_parsed_carriers_input(registry).unwrap(),
    ).0.unwrap()
    @program_check.observe_parsed_check_requests(
      @program_check.prepare_parsed_requests_input(registry).unwrap(),
    ).0.unwrap()
    let checked = public_checked(
      @program_check.finish_parsed_check_registry(registry).unwrap(),
    )
    let identity = @context.program_identity_stage_at(
      @program_check.source_identity(checked),
      0,
    ).unwrap()
    let actual = @parameter_refs.used_value_at(
      @context.stage_identity_parameter_values(identity),
      0,
    ).unwrap()
    match bound {
      Ok(Ready(original_values)) =>
        assert_true(
          physical_equal(
            actual,
            @parameters.bound_value_at(original_values, 0).unwrap(),
          ),
        )
      _ => () // The failed zero-node original could not supply this value.
    }
    assert_true(
      @program_check.finish_parsed_check_registry(registry)
      is Err(AlreadyConsumed),
    )
  }
}
