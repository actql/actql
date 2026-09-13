///|
test "owned window construction retains membership and Result publication requirements" {
  for
    kind in [
      "\"kind\":\"fixed\",\"size\":10", "\"kind\":\"sliding\",\"size\":10,\"step\":3",
    ] {
    let (_, requirements, gates, _, units) = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      tea=true,
      second_steps="[{\"row_window\":{\"time\":\"id\"," +
        kind +
        "},\"as\":\"selected\"}]",
      second_result_from="selected",
    )
    assert_eq(units.length(), 2)
    let operations = @context.stage_requirement_operations(requirements)
    let publications = @context.stage_requirement_publications(requirements)
    let mut found = 0
    for i in 0..<@context.operation_closure_count(operations) {
      guard @context.operation_closure_at(operations, i)
        is Some(StaticResolution(WindowPublication(link))) else {
        continue
      }
      found += 1
      assert_eq(link.site.stage, 1)
      assert_eq(link.site.step, 0)
      assert_eq(link.requirement_index, i)
      assert_true(physical_equal(link.publications, publications))
      assert_true(
        physical_equal(link.site.pipeline, link.membership.site.pipeline),
      )
      assert_true(
        physical_equal(link.site.obligations, link.membership.site.obligations),
      )
      assert_eq(link.membership.maximum, 1000L)
      assert_true(
        @context.window_membership_bound_maximum(link.membership.bounds) is None,
      )
      assert_true(@context.publication_closure_count(publications) > 0)
    }
    assert_eq(found, 1)
    let owner = @context.stage_requirement_owner(requirements)
    let (work, count) = @context.stage_requirement_usage(requirements)
    let exact : @context.StageRequirementLimits = {
      max_work: work,
      max_requirements: count,
      max_local_inputs: 10,
    }
    let again = @context.close_stage_requirements(owner, exact).unwrap()
    assert_eq(@context.stage_requirement_usage(again), (work, count))
    assert_true(
      @context.close_stage_requirements(owner, { ..exact, max_work: work - 1, })
      is Err(_),
    )
    assert_true(
      @context.close_stage_requirements(owner, {
        ..exact,
        max_requirements: count - 1,
      })
      is Err(_),
    )
    // The Stage closure owns a new index; it does not mutate its input owner.
    assert_true(
      @context.close_program_operations(
        @context.incoming_links_resolutions(owner),
        10000000,
        10000,
      )
      is Err(IncompleteResolution(_)),
    )
    let raw = @context.index_program_operation_resolutions(
      @context.operation_resolution_profiles(
        @context.incoming_links_resolutions(owner),
      ),
      10000000,
      10000,
    ).unwrap()
    let missing = @context.link_resolved_program_incoming(
      raw,
      @context.incoming_links_requirements(owner),
      { max_work: 10000000, max_name_units: 100000, max_requirements: 10000, },
    ).unwrap()
    guard @context.close_stage_requirements(missing, {
        max_work: 10000000,
        max_requirements: 10000,
        max_local_inputs: 10,
      })
      is Err(Operations(IncompleteResolution(index))) else {
      fail("publication closure must not waive membership enforcement")
    }
    assert_true(
      @context.operation_requirements_at(
        @context.operation_resolution_requirements(raw),
        index,
      ).unwrap().requirement
      is @pipeline.WindowRequirement(ResolveMembershipBound),
    )
    let (_, _, _, foreign_contracts, _) = local_construction_fixture(
      { work: 10000000, bytes: 1000000, nodes: 100000, depth: 100, },
      second_stage=true,
      tea=true,
      second_steps="[{\"row_window\":{\"time\":\"id\"," +
        kind +
        "},\"as\":\"selected\"}]",
      second_result_from="selected",
    )
    try
      build_units(foreign_contracts, requirements, gates, {
        work: 10000000,
        bytes: 1000000,
        nodes: 100000,
        depth: 100,
      })
    catch {
      UnitBuildFailure::ForeignOwner => ()
      _ => fail("expected a publication owner mismatch")
    } noraise {
      _ => fail("equal source must not permit foreign publication requirements")
    }
  }
}
