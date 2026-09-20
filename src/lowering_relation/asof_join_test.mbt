///|
fn asof_join_owner(
  kind : String,
  direction : String,
  timestamp : Bool,
) -> @lowering_relation.BoundPrepared {
  let type_name = if timestamp { "timestamp" } else { "number" }
  let first = if timestamp { "\"2020-01-01T00:00:00.001Z\"" } else { "1" }
  let pipeline = @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"clock\":{\"type\":\"" +
      type_name +
      "\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"clock\":" +
      first +
      ",\"key\":1}]},\"as\":\"seed\"},{\"asof_join\":{\"with\":\"seed\",\"kind\":\"" +
      kind +
      "\",\"by\":[{\"left\":\"key\",\"right\":\"key\"},{\"left\":\"key\",\"right\":\"key\"}],\"left_id\":\"id\",\"left_time\":\"clock\",\"right_time\":\"clock\",\"direction\":\"" +
      direction +
      "\",\"tolerance\":7,\"right_tie_break\":[\"id\"],\"select\":{\"id\":\"left.id\",\"clock\":\"right.clock\"}},\"as\":\"selected\"}]",
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
fn asof_join_wire(owner : @lowering_relation.BoundPrepared) -> String raise {
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(AsOfJoinStep(join)) else {
    abort("as-of join step")
  }
  let writer = @encode.writer(100000, 10000, 100)
  @encode.begin_array(writer)
  @lowering_relation.emit_asof_join(join, writer)
  @encode.end_array(writer)
  @encode.finish(writer)
}

///|
test "as-of join lowering retains kinds directions domains and repeated keys" {
  for timestamp in [false, true] {
    for kind in ["inner", "left"] {
      for direction in ["backward", "forward", "nearest"] {
        let owner = asof_join_owner(kind, direction, timestamp)
        let sequence = @lowering_relation.prepare_sequence(
          owner,
          sequence_limits(),
        ).unwrap()
        guard @lowering_relation.sequence_step(sequence, 1)
          is Some(AsOfJoinStep(join)) else {
          abort("as-of join step")
        }
        assert_eq(
          @lowering_relation.asof_join_kind(join),
          if kind == "left" {
            @join.Left
          } else {
            @join.Inner
          },
        )
        assert_eq(
          @lowering_relation.asof_join_direction(join),
          match direction {
            "backward" => @asof.AsOfDirection::Backward
            "forward" => @asof.AsOfDirection::Forward
            _ => @asof.AsOfDirection::Nearest
          },
        )
        assert_eq(@lowering_relation.asof_join_key_count(join), 2)
        assert_eq(@lowering_relation.asof_join_tolerance(join), 7L)
        assert_eq(
          @lowering_relation.asof_join_uses_timestamp(join, true),
          timestamp,
        )
        assert_eq(
          @lowering_relation.sequence_canonical_node_count(sequence, 1),
          Some(1),
        )
        let occurrence = @lowering_relation.sequence_canonical_node_at(
          sequence, 1, 0,
        ).unwrap()
        assert_eq(
          (occurrence.source_step, occurrence.id, occurrence.operation),
          (1, "asof_join_1", "TEA.join.asof"),
        )
        assert_eq(@lowering_relation.asof_join_input(join, true), "values_0")
        assert_eq(@lowering_relation.asof_join_input(join, false), "values_0")
        let wire = asof_join_wire(owner)
        assert_true(wire.contains("\"op\":\"TEA.join.asof\""))
        assert_true(wire.contains("\"how\":\"" + kind + "\""))
        assert_true(wire.contains("\"direction\":\"" + direction + "\""))
        assert_true(wire.contains("\"tolerance_ms\":7"))
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
test "as-of join preparation enforces exact entry budget" {
  let owner = asof_join_owner("left", "nearest", false)
  let exact = { ..sequence_limits(), max_bindings: 12, }
  assert_true(@lowering_relation.prepare_sequence(owner, exact) is Ok(_))
  assert_true(
    @lowering_relation.prepare_sequence(owner, { ..exact, max_bindings: 11, })
    is Err(
      @lowering_relation.AsOfJoinFailure(
        1,
        @lowering_relation.AsOfJoinPreparationLimit
      )
    ),
  )
}

///|
test "as-of join emitter matches an independent canonical body" {
  assert_eq(
    asof_join_wire(asof_join_owner("left", "nearest", false)),
    "[{\"id\":\"asof_join_1\",\"in\":[\"values_0\",\"values_0\"],\"op\":\"TEA.join.asof\",\"params\":{\"columns\":[{\"from\":\"right.clock\",\"to\":\"clock\"},{\"from\":\"left.id\",\"to\":\"id\"}],\"direction\":\"nearest\",\"how\":\"left\",\"identity\":[\"id\"],\"key_pairs\":[{\"left\":\"key\",\"right\":\"key\"},{\"left\":\"key\",\"right\":\"key\"}],\"left_time\":\"clock\",\"right_tie_break\":[\"id\"],\"right_time\":\"clock\",\"time_domain\":\"utc_milliseconds\",\"tolerance_ms\":7}}]",
  )
}
