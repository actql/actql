///|
fn string_limit_policy(value : Int64?) -> @policy.Policy raise {
  guard value is Some(value) else { return policy() }
  let base = policy()
  let fields = [
    "max_aggregate_array_items", "max_aggregate_string_bytes", "max_artifact_bytes",
    "max_artifact_rows", "max_effect_items", "max_graph_input_edges", "max_graph_input_nodes",
    "max_graph_output_rows", "max_graph_paths", "max_infer_items", "max_model_input_tokens_per_item",
    "max_model_request_bytes_per_item", "max_model_total_duration_ms", "max_nested_value_bytes",
    "max_nested_value_depth", "max_relation_output_rows", "max_temporal_matches_per_key",
    "max_temporal_output_rows",
  ]
  let writer = @encode.writer(4096, 100, 4)
  @encode.begin_object(writer)
  for name in fields {
    @encode.key(writer, name)
    let n = if name == "max_aggregate_string_bytes" {
      value
    } else {
      @policy.ceiling_value(@policy.ceiling(base, name).unwrap())
    }
    @encode.number_value(writer, n.to_double())
  }
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-capacity-host-policy/0.1")
  @encode.end_object(writer)
  let bytes = @utf8.encode(@encode.finish(writer))
  @policy.admit(bytes, "sha256:" + @sha.hex(bytes), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
}

///|
fn string_limit_fixture(
  ceiling : @policy.Policy,
  guard_text : String,
  extra_steps? : String = "",
) -> ProgramOperationResolutionIndex {
  let profile = match @policy.ceiling(ceiling, "max_aggregate_string_bytes") {
    Some(value) =>
      bound_profile().replace(
        old="\"max_aggregate_array_items\":1",
        new="\"max_aggregate_array_items\":1,\"max_aggregate_string_bytes\":" +
          @policy.ceiling_value(value).to_string(),
      )
    None => bound_profile()
  }
  let profiles = resolution_profiles(
    operation_order_fixture(
      "[{\"derive\":{\"x\":\"concat($p, to_string($n))\"}},{\"assert_rows\":{\"unique_by\":[\"id\"]}}," +
      extra_steps +
      "{\"group\":{\"by\":[],\"aggregates\":{\"a\":{\"fn\":\"string_agg\",\"field\":\"x\",\"delimiter\":\",\",\"order_by\":[{\"id\":\"asc\"}]" +
      guard_text +
      "}}}}]",
      capacity_policy=ceiling,
      host_profile=profile,
    ),
  )
  index_program_operation_resolutions(profiles, 10000000, 100).unwrap()
}

///|
test "aggregate guard reads only its owned operation resolution group" {
  for extra_count in [0, 1, 4] {
    let takes = Array::make(
      extra_count, "{\"take\":{\"count\":{\"$param\":\"n\"},\"offset\":{\"$param\":\"n\"}}},",
    ).join("")
    let extra = if extra_count == 0 {
      ""
    } else {
      "{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"x\":{\"type\":\"string\",\"nullable\":false}},\"rows\":[{\"id\":1,\"x\":\"a\"}]},\"as\":\"seed\"}," +
      takes
    }
    let owner = string_limit_fixture(
      string_limit_policy(Some(7L)),
      ",\"max_bytes\":{\"$param\":\"n\"}",
      extra_steps=extra,
    )
    let mut found = 0
    for i in 0..<operation_resolution_count(owner) {
      let site = operation_requirements_at(
        operation_resolution_requirements(owner),
        i,
      ).unwrap()
      if site.requirement is @pipeline.RelationRequirement(p) &&
        p.kind is @relation.AggregateEnvelope {
        let limit = select_group_string_limit(owner, i, 10000000, 2).unwrap()
        // One selector visit, this group's slots, and the two-unit comparison
        // of the authored one-unit Parameter name. No other step is scanned.
        let expected = operation_resolution_work(owner) +
          1 +
          @pipeline.operation_obligations_count(site.obligations) +
          2
        assert_eq(group_string_limit_work(limit), expected)
        assert_true(select_group_string_limit(owner, i, expected, 2) is Ok(_))
        assert_true(
          select_group_string_limit(owner, i, expected - 1, 2)
          is Err(BudgetExceeded),
        )
        let scalar = group_string_limit_guard_resolution(limit).unwrap()
        guard operation_resolution_at(owner, scalar.requirement_index)
          is Some(Resolved(Scalar(retained))) else {
          abort("retained scalar resolution")
        }
        assert_true(physical_equal(scalar, retained))
        assert_eq(scalar.site.step, site.step)
        assert_eq(scalar.site.producer_visit, site.producer_visit)
        assert_eq(group_string_limit_guard(limit), Some(1L))
        found += 1
      }
    }
    assert_true(found > 0)
  }
}

///|
test "string aggregate ceilings retain exact Host and author scopes without requiring an optional Host field" {
  for host_value in [None, Some(1L), Some(7L), Some(1000L)] {
    let policy = string_limit_policy(host_value)
    for
      guard_text in [
        "", ",\"max_bytes\":1", ",\"max_bytes\":7", ",\"max_bytes\":{\"$param\":\"n\"}",
      ] {
      let owner = string_limit_fixture(policy, guard_text)
      let expected_guard = if guard_text == "" {
        None
      } else if guard_text.contains(":7") {
        Some(7L)
      } else {
        Some(1L)
      }
      let mut found = 0
      for i in 0..<operation_resolution_count(owner) {
        let site = operation_requirements_at(
          operation_resolution_requirements(owner),
          i,
        ).unwrap()
        if site.requirement is @pipeline.RelationRequirement(p) &&
          p.kind is @relation.AggregateEnvelope {
          found += 1
          if host_value is None && expected_guard is None {
            // Other byte ceilings are present and equal to one, but not applicable.
            assert_true(
              select_group_string_limit(owner, i, 10000000, 2)
              is Err(MissingFiniteBound(_)),
            )
            continue
          }
          let limit = select_group_string_limit(owner, i, 10000000, 2).unwrap()
          assert_true(physical_equal(group_string_limit_owner(limit), owner))
          assert_eq(group_string_limit_requirement(limit), i)
          assert_eq(group_string_limit_guard(limit), expected_guard)
          let expected = match (host_value, expected_guard) {
            (Some(a), Some(b)) => Int64::min(a, b)
            (Some(a), None) | (None, Some(a)) => a
            _ => abort("finite bound")
          }
          assert_eq(group_string_limit_maximum(limit), expected)
          match group_string_limit_host(limit) {
            Some(host) => {
              assert_eq(
                @policy.ceiling_field(host),
                "max_aggregate_string_bytes",
              )
              assert_eq(Some(@policy.ceiling_value(host)), host_value)
              assert_true(physical_equal(@policy.ceiling_policy(host), policy))
            }
            None => assert_true(host_value is None)
          }
          let call = group_string_limit_call(limit)
          assert_eq(
            group_string_limit_name(limit),
            @relation.aggregate_name(call),
          )
          assert_eq(@relation.aggregate_name(call), "a")
          guard @pipeline.step_at(site.pipeline, site.step).unwrap().operation
            is @pipeline.Unary(operation) else {
            abort("ordinary group")
          }
          assert_true(
            physical_equal(
              call,
              @relation.aggregate_for_validation(
                @relation.group(operation).unwrap(),
                site.index,
              ).unwrap(),
            ),
          )
          if guard_text.contains("$param") {
            let r = group_string_limit_guard_resolution(limit).unwrap()
            assert_true(physical_equal(r.site.pipeline, site.pipeline))
            assert_eq(r.site.stage, site.stage)
            assert_eq(r.site.producer_visit, site.producer_visit)
            assert_eq(r.site.step, site.step)
            assert_true(r.value is Integer(1L))
          } else {
            assert_true(group_string_limit_guard_resolution(limit) is None)
          }
          let work = group_string_limit_work(limit)
          assert_true(select_group_string_limit(owner, i, work, 2) is Ok(_))
          assert_true(
            select_group_string_limit(owner, i, work - 1, 2)
            is Err(BudgetExceeded),
          )
          assert_true(
            select_group_string_limit(owner, i, work, 0) is Err(InvalidLimits),
          )
          if host_value is Some(_) && expected_guard is Some(_) {
            assert_true(
              select_group_string_limit(owner, i, work, 1)
              is Err(BudgetExceeded),
            )
          } else {
            assert_true(select_group_string_limit(owner, i, work, 1) is Ok(_))
          }
          assert_true(operation_resolution_at(owner, i) is Some(Unresolved))
          assert_true(
            select_group_array_limit(owner, i, 10000000, 2)
            is Err(InvalidRequirement),
          )
        } else {
          assert_true(
            select_group_string_limit(owner, i, 10000000, 2)
            is Err(InvalidRequirement),
          )
        }
      }
      assert_true(found > 0)
      assert_true(
        select_group_string_limit(owner, -1, 10000000, 2)
        is Err(InvalidRequirement),
      )
      assert_true(
        select_group_string_limit(
          owner,
          operation_resolution_count(owner),
          10000000,
          2,
        )
        is Err(InvalidRequirement),
      )
    }
  }
}
