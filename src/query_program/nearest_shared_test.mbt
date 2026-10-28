///|
// Authored before the frontend lowerer. One query has two matches: query_id
// alone is not unique. KEEP correspondence uses many-to-one joins on each side.
fn nearest_shared_program(object_projection : Bool) -> @program.Program {
  let suffix = if object_projection {
    (
      #|,{"derive":{"neighbor":{"object":{"query_key":{"object":{"request_id":{"field":"query_id"}}},"candidate_key":{"object":{"item_id":{"field":"candidate_id"}}},"score":{"field":"score"},"rank":{"field":"rank"}}}}},{"select":["note","label","neighbor"],"as":"out"}
    )
  } else {
    (
      #|,{"select":["note","label","query_id","candidate_id","score","rank"],"as":"out"}
    )
  }
  let fields = if object_projection {
    "[\"note\",\"label\",\"neighbor\"]"
  } else {
    "[\"note\",\"label\",\"query_id\",\"candidate_id\",\"score\",\"rank\"]"
  }
  @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.nearest_keep","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"request_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"note":{"type":"string","nullable":true}},"rows":[{"request_id":"q1","embedding":[1,0],"note":null}]},"as":"queries"},{"values":{"schema":{"item_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"item_id":"b","embedding":[0,1],"label":"second"},{"item_id":"a","embedding":[1,0],"label":"first"}]},"as":"candidates"},{"from":"candidates","nearest":{"queries":"queries","candidate_id":"item_id","candidate_vector":"embedding","query_id":"request_id","query_vector":"embedding","metric":"dot","k":2}},{"join":{"with":"queries","kind":"inner","cardinality":"many_to_one","on":[{"left":"query_id","right":"request_id"}],"select":{"note":"right.note","query_id":"left.query_id","candidate_id":"left.candidate_id","score":"left.score","rank":"left.rank"}}},{"join":{"with":"candidates","kind":"inner","cardinality":"many_to_one","on":[{"left":"candidate_id","right":"item_id"}],"select":{"note":"left.note","label":"right.label","query_id":"left.query_id","candidate_id":"left.candidate_id","score":"left.score","rank":"left.rank"}}}
    ) +
    suffix +
    "],\"results\":{\"rows\":{\"from\":\"out\",\"fields\":" +
    fields +
    "}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    construction_limits().program,
    format=Json,
  ).unwrap()
}

///|
test "independent nearest KEEP JSON checks two matches and named key objects" {
  for object_projection in [false, true] {
    let program = nearest_shared_program(object_projection)
    match
      @check.check_parsed(
        program,
        check_environment(veca=true),
        None,
        check_limits(),
      ) {
      Checked(_) => ()
      Rejected(error) => raise @check.diagnostic_cause(error)
      NeedsInputs(_) => fail("all inputs are closed Values")
    }
  }
}

///|
test "nearest produces a pair key rather than query-only uniqueness" {
  let checked = match
    @check.check_parsed(
      nearest_shared_program(false),
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(owner) => owner
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed Values")
  }
  let pipeline = @check.unit_pipeline(checked, 0).unwrap()
  let keys = @pipeline.candidate_keys(pipeline, Step(2)).unwrap()
  assert_eq(@evidence.key_witness_count(keys), 1)
  let key = @evidence.key_witness_at(keys, 0).unwrap()
  assert_eq(@evidence.key_origin(key), NearestResult)
  assert_eq(@evidence.key_field_count(key), 2)
  assert_eq(
    @evidence.key_field_at(key, 0).unwrap().name,
    Unqualified("query_id"),
  )
  assert_eq(
    @evidence.key_field_at(key, 1).unwrap().name,
    Unqualified("candidate_id"),
  )
}

///|
test "nearest named object projection retains nested typed key fields" {
  let checked = match
    @check.check_parsed(
      nearest_shared_program(true),
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(owner) => owner
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed Values")
  }
  let pipeline = @check.unit_pipeline(checked, 0).unwrap()
  let prepared = @lower.prepare(pipeline, {
    max_nodes: 1000,
    max_references: 1000,
    max_work: 10000,
    max_identifier_bytes: 10000,
  }).unwrap()
  let bound = @lower.bind_parameters(
    prepared,
    None,
    max_parameters=0,
    max_name_bytes=1000,
  ).unwrap()
  let expression = @lower.lower_expression(bound, 5, 0, {
    max_nodes: 1000,
    max_work: 10000,
    max_depth: 100,
    max_literal_nodes: 1000,
    max_literal_text_bytes: 10000,
  }).unwrap()
  guard @lower.expression_body(expression) is Object(fields) else {
    fail("expected a typed object projection")
  }
  assert_eq(fields.map(field => field.0), [
    "candidate_key", "query_key", "rank", "score",
  ])
  for
    (index, key, source) in [
      (0, "item_id", "candidate_id"),
      (1, "request_id", "query_id"),
    ] {
    guard @lower.expression_body(fields[index].1) is Object(nested) else {
      fail("expected a nested typed identity")
    }
    assert_eq(nested.length(), 1)
    assert_eq(nested[0].0, key)
    assert_true(
      @lower.expression_body(nested[0].1) is Field(name, _) && name == source,
    )
  }
}

///|
fn composite_identity_program(text : String) -> @program.Program {
  @program.parse(text, construction_limits().program, format=Json).unwrap()
}

///|
fn composite_identity_wire() -> String {
  (
    #|{"version":"actql/0.1","id":"fixture.nearest_composite_bridge","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"tenant":{"type":"string","nullable":false},"id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false}},"rows":[]},"as":"queries"},{"from":"queries","to_vectors":{"id":["tenant","id"],"vector":"embedding"},"as":"out"}],"results":{"rows":{"from":"out","fields":["tenant","id","embedding"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  )
}

///|
test "composite vector identity still cannot export a Vectors carrier as Relation fields" {
  let program = composite_identity_program(composite_identity_wire())
  match
    @check.check_parsed(
      program,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Rejected(error) =>
      match @check.diagnostic_cause(error) {
        Source(SourceView(Program(Program(Results(stage, issue))))) => {
          assert_eq(stage, 0)
          assert_true(issue.kind is WrongCarrier(VectorsKind))
        }
        other => raise other
      }
    _ =>
      fail("Vectors require an explicit Relation bridge before a field result")
  }
}

///|
test "independent composite identity bridge retains ordered typed identities through vectors" {
  // The only change to the retained negative is the explicit existing bridge.
  let wire = composite_identity_wire().replace(
    old="\"as\":\"out\"}],",
    new="\"as\":\"vector_rows\"},{\"from\":\"vector_rows\",\"vectors\":true,\"as\":\"out\"}],",
  )
  let program = composite_identity_program(wire)
  let owner = match
    @check.check_parsed(
      program,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(owner) => owner
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed Values add no acquisition")
  }
  let pipeline = @check.unit_pipeline(owner, 0).unwrap()
  let step = @pipeline.step_at(pipeline, 1).unwrap()
  guard step.output is @carrier.VectorValue(vectors) else {
    fail("Vectors expected")
  }
  assert_eq(@carrier.vector_identity_count(vectors), 2)
  assert_eq(
    @carrier.vector_identity_at(vectors, 0).unwrap().name,
    Unqualified("tenant"),
  )
  assert_eq(
    @carrier.vector_identity_at(vectors, 1).unwrap().name,
    Unqualified("id"),
  )
}

///|
test "composite identity support does not admit a numeric identity-role body" {
  let wire = composite_identity_wire()
    .replace(
      old="\"as\":\"out\"}],",
      new="\"as\":\"vector_rows\"},{\"from\":\"vector_rows\",\"vectors\":true,\"as\":\"out\"}],",
    )
    .replace(old="\"id\":[\"tenant\",\"id\"]", new="\"id\":7")
  match
    @check.check_parsed(
      composite_identity_program(wire),
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Rejected(error) =>
      match @check.diagnostic_cause(error) {
        Source(SourceView(Program(Program(Pipeline(stage, issue))))) => {
          assert_eq(stage, 0)
          assert_true(issue.kind is Vector(Decode(WrongType)))
        }
        other => raise other
      }
    _ =>
      fail(
        "an identity role must remain a field reference or ordered role vector",
      )
  }
}
