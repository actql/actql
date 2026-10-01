///|
fn nearest_context() -> Context {
  let seeds = [
    (
      "queries",
      ["request_id", "embedding", "note"],
      (
        #|{"values":{"schema":{"request_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"note":{"type":"string","nullable":true}},"rows":[{"request_id":"q1","embedding":[1,0],"note":null}]},"as":"queries"}
      ),
    ),
    (
      "candidates",
      ["item_id", "embedding", "label"],
      (
        #|{"values":{"schema":{"item_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"item_id":"b","embedding":[0,1],"label":"second"},{"item_id":"a","embedding":[1,0],"label":"first"}]},"as":"candidates"}
      ),
    ),
  ]
  {
    ..pair_context(),
    program_id: "fixture.nearest_keep",
    inputs: seeds.map(seed => {
      relation: [{ value: seed.0, quoted: false, }],
      name: seed.0,
      source: GeneratedValues(
        @wire.admit(
          @source.parse_json(seed.2, construction_limits().source.source).unwrap(),
          construction_limits().source.tree,
        ).unwrap(),
      ),
      visible_fields: seed.1,
      graph_bindings: [],
    }),
  }
}

///|
fn nearest_program(suffix : String) -> Result[@program.Program, Issue] {
  compile(
    @query.parse_query(
      "FROM queries AS q |> NEAREST candidates AS c QUERY KEY (q.request_id) VECTOR q.embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 " +
      suffix,
      syntax_limits(),
    ).unwrap(),
    nearest_context(),
    construction_limits(),
  )
}

///|
test "NEAREST KEEP lowers typed keys and repeats query correspondence without false uniqueness" {
  let program = nearest_program("KEEP (q.note, c.label) AS neighbor").unwrap()
  let body = semantic(program)
  assert_true(body.contains("\"cardinality\":\"many_to_one\""))
  assert_true(!body.contains("\"cardinality\":\"one_to_one\""))
  assert_true(body.contains("\"fields\":[\"note\",\"label\",\"neighbor\"]"))
  assert_true(
    body.contains("\"query_key\":{\"object\":{\"request_id\":{\"field\":"),
  )
  assert_true(
    body.contains("\"candidate_key\":{\"object\":{\"item_id\":{\"field\":"),
  )
  match
    @check.check_parsed(
      program,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(_) => ()
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("closed Values inputs")
  }
}

///|
test "NEAREST omitted KEEP discards old ranges but retains both named key objects" {
  let program = nearest_program("AS neighbor").unwrap()
  assert_true(semantic(program).contains("\"fields\":[\"neighbor\"]"))
  for
    suffix in [
      "SELECT q.note", "SELECT c.label", "WHERE q.note IS NULL", "SET note = c.label",
      "SELECT embedding", "ORDER BY q.request_id",
    ] {
    assert_true(
      nearest_program("AS neighbor |> " + suffix) is Err(_),
      msg=suffix,
    )
  }
  let kept = nearest_program(
    "KEEP (c.label, q.note) AS neighbor |> SELECT label, neighbor.score AS score",
  ).unwrap()
  assert_true(semantic(kept).contains("\"fields\":[\"label\",\"score\"]"))
}

///|
test "NEAREST rejects ambiguous KEEP and result names and preserves wildcard declaration order" {
  for
    suffix in [
      "KEEP (embedding) AS neighbor", "KEEP (*) AS neighbor", "KEEP (q.note AS neighbor) AS neighbor",
      "KEEP (q.note, q.note) AS neighbor", "KEEP (missing.*) AS neighbor", "KEEP (q.label) AS neighbor",
    ] {
    assert_true(nearest_program(suffix) is Err(_), msg=suffix)
  }
  let program = nearest_program("KEEP (c.label AS first, q.*) AS neighbor").unwrap()
  assert_true(
    semantic(program).contains(
      "\"fields\":[\"first\",\"request_id\",\"embedding\",\"note\",\"neighbor\"]",
    ),
  )
}

///|
test "NEAREST key roles cannot repeat a slot or refer to the opposite input" {
  let prefix = "FROM queries AS q |> NEAREST candidates AS c "
  for
    roles in ["QUERY KEY (q.request_id, q.request_id)", "QUERY KEY (c.item_id)"] {
    let query = @query.parse_query(
      prefix +
      roles +
      " VECTOR q.embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 AS n",
      syntax_limits(),
    ).unwrap()
    assert_true(
      compile(query, nearest_context(), construction_limits()) is Err(_),
    )
  }
  let collision = @query.parse_query(
    "FROM queries AS q |> NEAREST candidates AS `Q` QUERY KEY (request_id) VECTOR embedding CANDIDATE KEY (item_id) VECTOR embedding METRIC dot K 2 AS n",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(collision, nearest_context(), construction_limits())
    is Err(AmbiguousRelation),
  )
}

///|
// This Program is authored from the adopted roles and projections; it is not
// obtained from compile(). The external fixture contains the same graph.
test "NEAREST lowering matches an independent ordinary Program" {
  let expected = @program.parse(
    (
      #|{"version":"actql/0.1","id":"fixture.nearest_keep","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"request_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"note":{"type":"string","nullable":true}},"rows":[{"request_id":"q1","embedding":[1,0],"note":null}]},"as":"queries"},{"values":{"schema":{"item_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"label":{"type":"string","nullable":false}},"rows":[{"item_id":"b","embedding":[0,1],"label":"second"},{"item_id":"a","embedding":[1,0],"label":"first"}]},"as":"candidates"},{"from":"queries","select":["request_id","embedding","note"],"as":"aql_nearest_queries_0_2"},{"from":"candidates","select":["item_id","embedding","label"],"as":"aql_nearest_candidates_0_3"},{"from":"aql_nearest_queries_0_2","to_vectors":{"id":"request_id","vector":"embedding"},"as":"aql_nearest_query_vectors_0_4"},{"from":"aql_nearest_candidates_0_3","to_vectors":{"id":"item_id","vector":"embedding"},"as":"aql_nearest_candidate_vectors_0_5"},{"from":"aql_nearest_candidate_vectors_0_5","nearest":{"queries":"aql_nearest_query_vectors_0_4","metric":"dot","k":2}},{"derive":{"aql_nearest_key_7":{"field":"query_id"},"aql_nearest_key_8":{"field":"candidate_id"}}},{"join":{"with":"aql_nearest_queries_0_2","kind":"inner","cardinality":"many_to_one","on":[{"left":"aql_nearest_key_7","right":"request_id"}],"select":{"query_id":"left.query_id","candidate_id":"left.candidate_id","score":"left.score","rank":"left.rank","aql_nearest_key_7":"left.aql_nearest_key_7","aql_nearest_key_8":"left.aql_nearest_key_8","aql_nearest_keep_9":"right.note"}}},{"join":{"with":"aql_nearest_candidates_0_3","kind":"inner","cardinality":"many_to_one","on":[{"left":"aql_nearest_key_8","right":"item_id"}],"select":{"query_id":"left.query_id","candidate_id":"left.candidate_id","score":"left.score","rank":"left.rank","aql_nearest_key_7":"left.aql_nearest_key_7","aql_nearest_key_8":"left.aql_nearest_key_8","aql_nearest_keep_9":"left.aql_nearest_keep_9","aql_nearest_keep_10":"right.label"}}},{"derive":{"aql_nearest_result_11":{"object":{"query_key":{"object":{"request_id":{"field":"aql_nearest_key_7"}}},"candidate_key":{"object":{"item_id":{"field":"aql_nearest_key_8"}}},"score":{"field":"score"},"rank":{"field":"rank"}}}}},{"select":[{"note":"aql_nearest_keep_9"},{"label":"aql_nearest_keep_10"},{"neighbor":"aql_nearest_result_11"}],"as":"aql_gen_0"}],"results":{"rows":{"from":"aql_gen_0","fields":["note","label","neighbor"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
    ),
    construction_limits().program,
    format=Json,
  ).unwrap()
  assert_eq(
    semantic(nearest_program("KEEP (q.note, c.label) AS neighbor").unwrap()),
    semantic(expected),
  )
}

///|
test "NEAREST checker retains column order and nullable KEEP on an empty query" {
  let base = nearest_context()
  let empty = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"request_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"note":{"type":"string","nullable":true}},"rows":[]},"as":"queries"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let inputs = base.inputs.copy()
  inputs[0] = { ..inputs[0], source: GeneratedValues(empty), }
  let query = @query.parse_query(
    "FROM queries AS q |> NEAREST candidates AS c QUERY KEY (q.request_id) VECTOR q.embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 KEEP (q.note, c.label) AS neighbor",
    syntax_limits(),
  ).unwrap()
  let program = compile(query, { ..base, inputs, }, construction_limits()).unwrap()
  let checked = match
    @check.check_parsed(
      program,
      check_environment(veca=true),
      None,
      check_limits(),
    ) {
    Checked(owner) => owner
    Rejected(error) => raise @check.diagnostic_cause(error)
    NeedsInputs(_) => fail("empty Values remains typed")
  }
  let pipeline = @check.unit_pipeline(checked, 0).unwrap()
  let target = @pipeline.Step(@pipeline.step_count(pipeline) - 1)
  let rows = @carrier.relation_rows(
    @pipeline.step_at(pipeline, @pipeline.step_count(pipeline) - 1).unwrap().output,
  ).unwrap()
  assert_eq(@carrier.field_count(rows), 3)
  // Carrier contracts canonically sort field names; the Result declaration
  // independently retains the authored delivery column order.
  assert_true(
    semantic(program).contains("\"fields\":[\"note\",\"label\",\"neighbor\"]"),
  )
  let fields = [0, 1, 2]
  let note = fields
    .map(i => @carrier.field_at(rows, i).unwrap())
    .filter(field => field.name == Unqualified("note"))[0]
  assert_true(@contract.contract_nullable(note.contract.unwrap()))
  let neighbor = fields
  .map(i => @carrier.field_at(rows, i).unwrap())
  .filter(field => field.name == Unqualified("neighbor"))[0].contract.unwrap()
  assert_true(!@contract.contract_nullable(neighbor))
  guard neighbor.shape is @contract.Object(object) else {
    fail("closed object")
  }
  assert_eq(@contract.field_count(object), 4)
  // The flat nearest tuple is not arbitrarily redeclared on a nested object.
  assert_eq(
    @evidence.key_witness_count(
      @pipeline.candidate_keys(pipeline, target).unwrap(),
    ),
    0,
  )
}

///|
test "NEAREST composite keys report the missing common Program bridge" {
  let base = nearest_context()
  let composite = @wire.admit(
    @source.parse_json(
      (
        #|{"values":{"schema":{"request_id":{"type":"string","nullable":false},"tenant":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"note":{"type":"string","nullable":true}},"rows":[{"request_id":"q1","tenant":"one","embedding":[1,0],"note":null}]},"as":"queries"}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let inputs = base.inputs.copy()
  inputs[0] = {
    ..inputs[0],
    source: GeneratedValues(composite),
    visible_fields: ["request_id", "tenant", "embedding", "note"],
  }
  let query = @query.parse_query(
    "FROM queries AS q |> NEAREST candidates AS c QUERY KEY (q.tenant, q.request_id) VECTOR q.embedding CANDIDATE KEY (c.item_id) VECTOR c.embedding METRIC dot K 2 KEEP (q.note, c.label) AS neighbor",
    syntax_limits(),
  ).unwrap()
  assert_true(
    compile(query, { ..base, inputs, }, construction_limits())
    is Err(UnsupportedNearest),
  )
}

///|
test "NEAREST reuses one source producer without filtering the candidate corpus" {
  let context = nearest_context()
  let query = @query.parse_query(
    "FROM queries AS q |> WHERE q.request_id = 'q1' |> NEAREST queries AS c QUERY KEY (q.request_id) VECTOR q.embedding CANDIDATE KEY (c.request_id) VECTOR c.embedding METRIC dot K 2 KEEP (q.note AS input_note) AS neighbor",
    syntax_limits(),
  ).unwrap()
  let source = @wire.admit(
    @source.parse_json(
      (
        #|{"carrier":"relation","schema":{"request_id":{"type":"string","nullable":false},"embedding":{"type":"vector","dimensions":2,"nullable":false},"note":{"type":"string","nullable":true}},"primary_key":["request_id"]}
      ),
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let input = { ..context.inputs[0], source: Captured(source), }
  let program = compile(
    query,
    { ..context, inputs: [input], captured_stage: Some("captured"), },
    construction_limits(),
  ).unwrap()
  assert_eq(@program.stage_count(program), 2)
  let body = semantic(program)
  // Capture is shared by both demands. The query predicate remains downstream
  // of that producer and cannot silently shrink the explicitly named corpus.
  assert_true(body.contains("\"filter\":{\"literal\":true}"))
  assert_true(
    body.contains(
      "\"filter\":{\"eq\":[{\"field\":\"request_id\"},{\"literal\":\"q1\"}]}",
    ),
  )
  assert_true(
    body.contains(
      "\"from\":\"queries\",\"select\":[\"request_id\",\"embedding\",\"note\"]",
    ),
  )
}

///|
test "NEAREST resolves quoted names and enforces construction limits" {
  let query = @query.parse_query(
    "FROM queries AS `Q` |> NEAREST candidates AS `C` QUERY KEY (`q`.`REQUEST_ID`) VECTOR `Q`.`embedding` CANDIDATE KEY (`c`.`ITEM_ID`) VECTOR `c`.`EMBEDDING` METRIC dot K 2 KEEP (`q`.`note`, `c`.`label`) AS neighbor",
    syntax_limits(),
  ).unwrap()
  let context = nearest_context()
  let program = compile(query, context, construction_limits()).unwrap()
  assert_eq(
    semantic(program),
    semantic(nearest_program("KEEP (q.note, c.label) AS neighbor").unwrap()),
  )
  assert_true(
    compile(query, context, {
      ..construction_limits(),
      source: { ..construction_limits().source, max_output_bytes: 100, },
    })
    is Err(Construction(_)),
  )
  let missing = { ..context, inputs: [context.inputs[0]], }
  assert_true(
    compile(query, missing, construction_limits()) is Err(UnknownRelation),
  )
}
