///|
fn interval_join_owner(
  kind : String,
  mode : String,
  timestamp : Bool,
  suffix : String,
) -> @lowering_relation.BoundPrepared {
  let type_name = if timestamp { "timestamp" } else { "number" }
  let value = if timestamp { "\"2020-01-01T00:00:00.000Z\"" } else { "1" }
  let temporal = if mode == "overlap" {
    "\"left\":{\"start\":\"clock\",\"end\":\"clock\"}," +
    "\"right\":{\"start\":\"clock\",\"end\":\"clock\"}"
  } else {
    "\"left\":{\"time\":\"clock\"}," +
    "\"right\":{\"start\":\"clock\",\"end\":\"clock\"}"
  }
  let pipeline = @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"clock\":{\"type\":\"" +
      type_name +
      "\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"clock\":" +
      value +
      ",\"key\":1}]},\"as\":\"seed\"},{\"interval_join\":{\"with\":\"seed\",\"kind\":\"" +
      kind +
      "\",\"mode\":\"" +
      mode +
      "\",\"on\":[{\"left\":\"key\",\"right\":\"key\"},{\"left\":\"key\",\"right\":\"key\"}]," +
      temporal +
      suffix +
      "}}]",
    ),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 100000,
      max_nodes: 10000,
      max_tokens: 10000,
      max_depth: 100,
    },
  ).unwrap()
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(pipeline, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
fn interval_join_wire(owner : @lowering_relation.BoundPrepared) -> String raise {
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(IntervalJoinStep(join)) else {
    abort("interval join step")
  }
  let writer = @encode.writer(100000, 10000, 100)
  @encode.begin_array(writer)
  @lowering_relation.emit_interval_join(join, writer)
  @encode.end_array(writer)
  @encode.finish(writer)
}

///|
test "interval join lowering retains modes kinds domains and repeated keys" {
  for timestamp in [false, true] {
    for mode in ["point_in_interval", "overlap"] {
      for kind in ["inner", "left", "semi", "anti"] {
        let owner = interval_join_owner(kind, mode, timestamp, "")
        let sequence = @lowering_relation.prepare_sequence(
          owner,
          sequence_limits(),
        ).unwrap()
        guard @lowering_relation.sequence_step(sequence, 1)
          is Some(IntervalJoinStep(join)) else {
          abort("interval join step")
        }
        let expected_kind = match kind {
          "inner" => @join.Kind::Inner
          "left" => @join.Left
          "semi" => @join.Semi
          "anti" => @join.Anti
          _ => abort("interval join kind")
        }
        assert_eq(@lowering_relation.interval_join_kind(join), expected_kind)
        assert_eq(
          @lowering_relation.interval_join_mode(join),
          if mode == "overlap" {
            @join.Overlap
          } else {
            @join.PointInInterval
          },
        )
        assert_eq(
          @lowering_relation.interval_join_uses_timestamps(join),
          timestamp,
        )
        assert_eq(@lowering_relation.interval_join_key_count(join), 2)
        assert_eq(
          @lowering_relation.sequence_canonical_node_count(sequence, 1),
          Some(1),
        )
        let occurrence = @lowering_relation.sequence_canonical_node_at(
          sequence, 1, 0,
        ).unwrap()
        assert_eq(
          (occurrence.source_step, occurrence.id, occurrence.operation),
          (1, "interval_join_1", "TEA.join.interval"),
        )
        assert_true(
          @lowering_relation.sequence_canonical_node_at(sequence, 1, 1) is None,
        )
        assert_eq(
          @lowering_relation.interval_join_input(join, true),
          "values_0",
        )
        assert_eq(
          @lowering_relation.interval_join_input(join, false),
          "values_0",
        )
        let wire = interval_join_wire(owner)
        assert_true(wire.contains("\"op\":\"TEA.join.interval\""))
        assert_true(wire.contains("\"how\":\"" + kind + "\""))
        assert_true(wire.contains("\"mode\":\"" + mode + "\""))
        assert_true(
          wire.contains(
            "\"time_domain\":\"" +
            (if timestamp { "timestamp" } else { "utc_milliseconds" }) +
            "\"",
          ),
        )
      }
    }
  }
}

///|
test "interval join lowering retains aliases and literal output guard" {
  let owner = interval_join_owner(
    "left", "point_in_interval", false, ",\"select\":{\"left_clock\":\"left.clock\",\"right_clock\":\"right.clock\"},\"max_output_rows\":7",
  )
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(IntervalJoinStep(join)) else {
    abort("interval join step")
  }
  assert_eq(@lowering_relation.interval_join_output_limit(join), Some(7L))
  assert_eq(@lowering_relation.interval_join_field_count(join), 2)
  assert_eq(
    @lowering_relation.interval_join_field_at(join, 0).unwrap().output,
    @schema.Unqualified("left_clock"),
  )
  let wire = interval_join_wire(owner)
  assert_true(wire.contains("\"max_output_rows\":7"))
  assert_true(wire.contains("{\"from\":\"left.clock\",\"to\":\"left_clock\"}"))
}

///|
test "interval join preparation enforces exact entry budget" {
  let owner = interval_join_owner(
    "left", "point_in_interval", false, ",\"select\":{\"left_clock\":\"left.clock\",\"right_clock\":\"right.clock\"}",
  )
  let exact = { ..sequence_limits(), max_bindings: 7, }
  assert_true(@lowering_relation.prepare_sequence(owner, exact) is Ok(_))
  assert_true(
    @lowering_relation.prepare_sequence(owner, { ..exact, max_bindings: 6, })
    is Err(
      @lowering_relation.IntervalJoinFailure(
        1,
        @lowering_relation.IntervalJoinPreparationLimit
      )
    ),
  )
}
