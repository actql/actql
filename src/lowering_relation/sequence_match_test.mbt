///|
fn sequence_match_owner() -> @lowering_relation.BoundPrepared raise {
  let checked = @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"clock\":{\"type\":\"number\",\"nullable\":false},\"key\":{\"type\":\"number\",\"nullable\":false},\"value\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"clock\":1,\"key\":7,\"value\":1},{\"id\":2,\"clock\":2,\"key\":7,\"value\":2}]},\"as\":\"seed\"},{\"to_events\":{\"id\":\"id\",\"time\":\"clock\"}},{\"sequence\":{\"by\":[\"key\"],\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"start\",\"where\":\"value = 1\"},{\"as\":\"end\",\"where\":\"value = 2\"}],\"within\":10,\"overlap\":\"disallow\",\"contiguity\":\"adjacent\",\"max_matches_per_key\":2,\"max_output_rows\":3}}]",
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
  )
  let pipeline = match checked {
    Ok(value) => value
    Err(issue) => {
      debug_inspect(issue.kind, content="sequence pipeline")
      abort("sequence pipeline")
    }
  }
  @lowering_relation.bind_parameters(
    @lowering_relation.prepare(pipeline, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "sequence lowering retains typed matching semantics and predicates" {
  let owner = sequence_match_owner()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 2)
    is Some(SequenceMatchStep(matcher)) else {
    abort("sequence match step")
  }
  assert_eq(@lowering_relation.sequence_match_input(matcher), "to_events_1")
  assert_eq(@lowering_relation.sequence_match_key_count(matcher), 1)
  assert_eq(
    @lowering_relation.sequence_match_key_at(matcher, 0),
    Some(@schema.Unqualified("key")),
  )
  assert_eq(@lowering_relation.sequence_match_pattern_count(matcher), 2)
  assert_eq(
    @lowering_relation.sequence_match_pattern_label(matcher, 0),
    Some("start"),
  )
  assert_eq(@lowering_relation.sequence_match_within(matcher), 10L)
  assert_eq(
    @lowering_relation.sequence_match_overlap(matcher),
    @relation.SequenceOverlap::Disallow,
  )
  assert_eq(
    @lowering_relation.sequence_match_contiguity(matcher),
    @relation.SequenceContiguity::Adjacent,
  )
  assert_eq(@lowering_relation.sequence_match_per_key_limit(matcher), Some(2L))
  assert_eq(@lowering_relation.sequence_match_output_limit(matcher), Some(3L))
  assert_eq(
    @lowering_relation.sequence_canonical_node_at(sequence, 2, 0).unwrap().operation,
    "TEA.sequence.match",
  )
  let roots = @lowering_relation.prepare_roots(sequence, {
    max_roots: 2,
    max_pointer_bytes: 32,
    max_work: 100,
  }).unwrap()
  assert_eq(@lowering_relation.root_count(roots), 2)
  assert_eq(
    @lowering_relation.root_at(roots, 0).unwrap().parameter_pointer,
    "/pattern/0/where",
  )
}

///|
test "sequence emitter publishes one canonical typed occurrence" {
  let sequence = @lowering_relation.prepare_sequence(
    sequence_match_owner(),
    sequence_limits(),
  ).unwrap()
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  let wire = @encode.finish(writer)
  assert_true(wire.contains("\"op\":\"TEA.sequence.match\""))
  assert_true(wire.contains("\"contiguity\":\"adjacent\""))
  assert_true(wire.contains("\"overlap\":\"disallow\""))
  assert_true(wire.contains("\"within_ms\":10"))
  assert_true(wire.contains("\"max_matches_per_key\":2"))
  assert_true(wire.contains("\"max_output_rows\":3"))
  assert_true(wire.contains("\"as\":\"start\""))
  assert_true(wire.contains("\"op\":\"eq\""))
}

///|
test "sequence preparation enforces exact binding and name budgets" {
  let owner = sequence_match_owner()
  let exact = { ..sequence_limits(), max_bindings: 7, max_name_bytes: 25, }
  assert_true(@lowering_relation.prepare_sequence(owner, exact) is Ok(_))
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..exact,
      max_bindings: exact.max_bindings - 1,
    })
    is Err(_),
  )
  assert_true(
    @lowering_relation.prepare_sequence(owner, {
      ..exact,
      max_name_bytes: exact.max_name_bytes - 1,
    })
    is Err(_),
  )
}
