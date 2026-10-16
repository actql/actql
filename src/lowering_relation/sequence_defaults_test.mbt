///|
fn sequence_defaults_canonical_wire(explicit : Bool) -> String raise {
  let body = "{\"id\":\"id\",\"time\":\"clock\",\"pattern\":[{\"as\":\"opened\",\"where\":\"kind = 1\"},{\"as\":\"closed\",\"where\":\"kind = 2\"}],\"within\":20" +
    (if explicit {
      ",\"by\":[],\"overlap\":\"disallow\",\"contiguity\":\"adjacent\""
    } else {
      ""
    }) +
    "}"
  let pipeline = @pipeline.check(
    cursor(
      "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"clock\":{\"type\":\"number\",\"nullable\":false},\"kind\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":1,\"clock\":0,\"kind\":1},{\"id\":2,\"clock\":10,\"kind\":2}]},\"as\":\"seed\"},{\"sequence\":" +
      body +
      "}]",
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
  let owner = @lowering_relation.bind_parameters(
    @lowering_relation.prepare(pipeline, limits()).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
  let sequence = @lowering_relation.prepare_sequence(owner, sequence_limits()).unwrap()
  guard @lowering_relation.sequence_step(sequence, 1)
    is Some(SequenceMatchStep(matcher)) else {
    fail("the existing sequence Owner must consume the completed defaults")
  }
  assert_eq(@lowering_relation.sequence_match_key_count(matcher), 0)
  assert_eq(@lowering_relation.sequence_match_overlap(matcher), Disallow)
  assert_eq(@lowering_relation.sequence_match_contiguity(matcher), Adjacent)
  assert_true(@lowering_relation.sequence_match_per_key_limit(matcher) is None)
  assert_true(@lowering_relation.sequence_match_output_limit(matcher) is None)
  let writer = @encode.writer(100000, 10000, 100)
  @lowering_relation.emit_sequence_steps(sequence, writer)
  @encode.finish(writer)
}

///|
test "sequence omitted defaults emit the same complete canonical occurrence as the explicit body" {
  let wire = sequence_defaults_canonical_wire(false)
  assert_eq(wire, sequence_defaults_canonical_wire(true))
  let steps = cursor(wire)
  let step = @decode.open_object(@decode.element_at(steps, 1).unwrap()).unwrap()
  let params = @decode.lookup(step, "params").unwrap()
  assert_eq(@decode.object_length(params), Some(8))
  assert_eq(
    (0..<8).to_array().map(index => @decode.field_at(params, index).unwrap().0),
    [
      "by", "contiguity", "id", "overlap", "pattern", "time", "time_domain", "within_ms",
    ],
  )
  let params = @decode.open_object(params).unwrap()
  assert_eq(
    @decode.array_length(@decode.lookup(params, "by").unwrap()),
    Some(0),
  )
  for
    (key, value) in [
      ("contiguity", "adjacent"),
      ("id", "id"),
      ("overlap", "disallow"),
      ("time", "clock"),
      ("time_domain", "utc_milliseconds"),
    ] {
    assert_eq(
      @decode.text(@decode.lookup(params, key).unwrap()).unwrap(),
      value,
    )
  }
  assert_eq(
    @decode.number(@decode.lookup(params, "within_ms").unwrap()).unwrap(),
    20.0,
  )
}
