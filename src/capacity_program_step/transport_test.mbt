///|
test "bounds cross reducing and left preserving binary operations" {
  for
    middle in [
      "{\"except\":{\"with\":\"rows\",\"duplicates\":\"all\"}}", "{\"except\":{\"with\":\"rows\",\"duplicates\":\"distinct\"}}",
      "{\"intersect\":{\"with\":\"rows\",\"duplicates\":\"all\"}}", "{\"intersect\":{\"with\":\"rows\",\"duplicates\":\"distinct\"}}",
      "{\"nest\":{\"with\":\"rows\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"id\"]}}",
      "{\"join\":{\"with\":\"rows\",\"kind\":\"semi\",\"on\":\"id\"}}", "{\"join\":{\"with\":\"rows\",\"kind\":\"anti\",\"on\":\"id\"}}",
      "{\"cross_join\":{\"with\":\"rows\",\"right_rows\":\"one\"}}",
    ] {
    transport_case("[{\"take\":3}," + middle + ",{\"take\":9}]", 2)
  }
  for kind in ["semi", "anti"] {
    transport_case(
      "[{\"take\":3},{\"interval_join\":{\"with\":\"rows\",\"kind\":\"" +
      kind +
      "\",\"mode\":\"point_in_interval\",\"on\":[],\"left\":{\"time\":\"id\"},\"right\":{\"start\":\"id\",\"end\":\"id\"}}},{\"take\":9}]",
      2,
    )
  }
  for kind in ["left", "inner"] {
    transport_case(
      "[{\"take\":3},{\"asof_join\":{\"with\":\"rows\",\"kind\":\"" +
      kind +
      "\",\"by\":[],\"left_time\":\"id\",\"right_time\":\"id\",\"left_id\":\"id\",\"direction\":\"backward\",\"tolerance\":1,\"select\":{\"id\":\"left.id\"}}},{\"take\":9}]",
      2,
    )
  }
}

///|
test "bound transport distinguishes non expanding factors from unbounded expansion" {
  for
    middle in [
      "{\"take\":1}", "{\"take\":{\"count\":1,\"offset\":10}}", "{\"top_k\":{\"k\":1,\"by\":[{\"id\":\"asc\"}]}}",
      "{\"top_k_by\":{\"partition_by\":[\"id\"],\"k\":1,\"by\":[{\"id\":\"asc\"}]}}",
      "{\"unpivot\":{\"columns\":[\"id\"],\"name_column\":\"name\",\"value_column\":\"value\",\"keep\":[]}}",
      "{\"row_window\":{\"kind\":\"fixed\",\"time\":\"id\",\"size\":10}}",
    ] {
    transport_case("[{\"take\":3}," + middle + ",{\"take\":9}]", 2)
  }
  for items in [0L, 1L] {
    for outer in [false, true] {
      transport_case(
        "[{\"take\":3},{\"unnest\":{\"column\":\"id\",\"as\":\"item\",\"outer\":" +
        outer.to_string() +
        "}},{\"take\":9}]",
        2,
        field_type=@contract.array_contract(
          @contract.primitive(NumberType, nullable=false),
          nullable=false,
          max_items=Some(items),
        ).unwrap(),
      )
    }
  }
  for
    middle in [
      "{\"cross_join\":{\"with\":\"rows\"}}", "{\"join\":{\"with\":\"rows\",\"kind\":\"inner\",\"on\":\"id\"}}",
      "{\"unpivot\":{\"columns\":[\"id\",\"id\"],\"name_column\":\"name\",\"value_column\":\"value\",\"keep\":[]}}",
    ] {
    let p = pipeline("[{\"take\":3}," + middle + ",{\"take\":9}]")
    let bound = @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}"),
    ).unwrap()
    let id = bound_id(bound)
    let claim = proof(
      "actql.bound.take",
      3,
      "{\"input\":\"" + id + "\",\"maximum\":9,\"op\":\"clamp\"}",
      reference="checked-step:2",
      inputs=[id],
    )
    assert_true(
      @capacity_program_step.check_with_inputs(
        p,
        2,
        claim,
        [bound],
        max_input_work=10,
      )
      is Err(InputTargetMismatch(0)),
    )
  }
}

///|
test "pooling transports occurrence bounds through Vectors and Relation bridges" {
  for pooling in ["mean", "sum", "max"] {
    for relation_input in [false, true] {
      let bridge = if relation_input { "{\"vectors\":true}," } else { "" }
      transport_case(
        "[{\"take\":3},{\"derive\":{\"key\":{\"literal\":1}}},{\"to_vectors\":{\"id\":\"key\",\"vector\":\"id\"}}," +
        bridge +
        "{\"pool_vectors\":{\"vector\":\"id\",\"by\":[\"key\"],\"method\":\"" +
        pooling +
        "\"}},{\"vectors\":true},{\"take\":9}]",
        if relation_input {
          6
        } else {
          5
        },
        field_type=@contract.vector_contract(2, nullable=false).unwrap(),
      )
    }
  }
  transport_case(
    "[{\"take\":3},{\"to_events\":{\"id\":\"id\",\"time\":\"id\"}},{\"window_events\":{\"kind\":\"fixed\",\"size\":10}},{\"events\":true},{\"take\":9}]",
    4,
  )
}

///|
test "calendar buckets transport counts while generators cannot borrow them" {
  let text = "{\"conversion_law\":\"actql-calendar-boundaries/0.1\",\"coverage_end_ms\":253402300800000,\"coverage_start_ms\":-62135596800000,\"tzdb_version\":\"test-fixture\",\"version\":\"actql-tzdb-table/0.1\",\"zones\":{\"UTC\":{\"initial_offset_seconds\":0,\"transitions\":[]}}}"
  let profile = @calendar_profile.admit(
    @utf8.encode(text),
    "sha256:9f3724c9d9d160476ee7abf5d8eaa0701bbd5c17f900154496bb8615bf20f4ca",
    "test-fixture",
    {
      max_bytes: 1000,
      max_nodes: 100,
      max_depth: 8,
      max_zones: 1,
      max_transitions: 0,
    },
  ).unwrap()
  for generator in [false, true] {
    let middle = if generator {
      "{\"calendar_series\":{\"start\":\"2000-01-01T00:00:00.000Z\",\"end\":\"2000-01-02T00:00:00.000Z\",\"unit\":\"day\",\"timezone\":\"UTC\"},\"as\":\"days\"}"
    } else {
      "{\"calendar_bucket\":{\"time\":\"id\",\"into\":\"bucket\",\"unit\":\"day\",\"timezone\":\"UTC\"}}"
    }
    let p = pipeline(
      "[{\"take\":3}," + middle + ",{\"take\":9}]",
      field_type=@contract.primitive(TimestampType, nullable=false),
      calendar_profile=Some(profile),
    )
    let bound = @capacity_program_step.check(
      p,
      0,
      proof("actql.bound.take", 3, "{\"maximum\":3,\"op\":\"clamp\"}"),
    ).unwrap()
    let id = bound_id(bound)
    let claim = proof(
      "actql.bound.take",
      3,
      "{\"input\":\"" + id + "\",\"maximum\":9,\"op\":\"clamp\"}",
      reference="checked-step:2",
      inputs=[id],
    )
    let result = @capacity_program_step.check_with_inputs(
      p,
      2,
      claim,
      [bound],
      max_input_work=1,
    )
    if generator {
      assert_true(result is Err(InputTargetMismatch(0)))
    } else {
      let app = result.unwrap()
      guard @pipeline.step_at(@capacity_program_step.checked_pipeline(app), 1).unwrap().operation
        is Calendar(op) else {
        fail("calendar operation expected")
      }
      assert_true(physical_equal(@calendar.profile(op), profile))
      assert_true(!@calendar.pending_validations(op).is_empty())
    }
  }
}
