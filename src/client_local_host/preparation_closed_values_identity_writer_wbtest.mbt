///|
// The original 97,999-byte fixture's admitted lexical facts, not constructed
// output. Independent arithmetic: replace seven4634514 writer envelopes with
// one4634514 plus six small-scope total47884 from the fixed shared tariff.
test "ClosedValues identity writer specialization removes six source-sized copies" {
  let facts : ClosedValuesLexicalFacts = {
    input_bytes: 97999,
    node_upper: 20640,
    objects: 210,
    arrays: 4,
    fields_upper: 10219,
    quoted_tokens: 10426,
    quoted_utf16_units: 31197,
    longest_quoted_utf16: 9,
    longest_atom_utf16: 5,
    depth_upper: 8,
  }
  let quote = closed_values_context_components_layout(facts, 100, 99).unwrap()
  assert_eq(preparation_representation_cost(quote.retained).unwrap(), 898703L)
  // Prior temporary47987835 - six unnecessary full-source scopes27759200.
  assert_eq(
    preparation_representation_cost(quote.temporary).unwrap(),
    20228635L,
  )
}

///|
test "ClosedValues identity writer specialization preserves width monotonicity and bounds" {
  let mut previous = 0L
  for width in [1, 2, 100] {
    let schema : Array[String] = []
    let cells : Array[String] = []
    let names : Array[String] = []
    for column in 0..<width {
      let name = "\"v" + column.to_string() + "\""
      schema.push(name + ":{\"type\":\"number\",\"nullable\":false}")
      cells.push(name + ":1")
      names.push(name)
    }
    let document = "{\"version\":\"actql/0.1\",\"id\":\"width\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{\"values\":{\"schema\":{" +
      schema.join(",") +
      "},\"rows\":[{" +
      cells.join(",") +
      "}]},\"as\":\"v\"}],\"results\":{\"r\":{\"from\":\"v\",\"fields\":[" +
      names.join(",") +
      "]}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
    let facts = closed_values_lexical_facts(document, document.length()).unwrap()
    let priced = preparation_representation_cost(
      closed_values_identity_writer_layout(facts.node_upper, facts.depth_upper).unwrap(),
    ).unwrap()
    assert_true(priced > previous)
    previous = priced
  }
  let small = closed_values_identity_writer_layout(40, 7).unwrap()
  let large = closed_values_identity_writer_layout(20640, 8).unwrap()
  let smaller = preparation_representation_cost(small).unwrap()
  let larger = preparation_representation_cost(large).unwrap()
  assert_true(larger > smaller)
  assert_eq(larger, 4682398L)
  // Every scope remains summed; no early retirement or peak-max substitution.
  let stage = closed_values_writer_layout(20648, 9, 1, 0, 0).unwrap()
  assert_eq(larger - preparation_representation_cost(stage).unwrap(), 47884L)
  for nodes in [0, -1, 2147483640] {
    assert_true(closed_values_identity_writer_layout(nodes, 8) is None)
  }
  for depth in [-1, 2147483647] {
    assert_true(closed_values_identity_writer_layout(40, depth) is None)
  }
}

///|
// Independent canonical template preimages, hashed with Python hashlib SHA256,
// not expected values regenerated from the product emitter. This freezes the
// identity contract while only resource projection changes.
test "ClosedValues identity writer specialization leaves actual identities and shape limits unchanged" {
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document =
    #|{"version":"actql/0.1","id":"identity-writer","stages":[{"id":"s","inputs":{},"steps":[{"values":{"schema":{"x":{"type":"number","nullable":false}},"rows":[{"x":1}]},"as":"v"}],"results":{"r":{"from":"v","fields":["x"]}}}],"results":{"r":{"from":{"stage":"s","result":"r"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  let facts = closed_values_lexical_facts(document, document.length()).unwrap()
  let before = @publication_host.prepared_client_identity(prepared)
  ignore(
    closed_values_identity_writer_layout(facts.node_upper, facts.depth_upper).unwrap(),
  )
  assert_eq(@publication_host.prepared_client_identity(prepared), before)
  assert_eq(
    before.program_definition_cid,
    "sha256:26334bc3b274becef9457799e919c5433306ce1f8324bb81ff4aae0604635ce5",
  )
  assert_eq(
    before.parameter_values_cid,
    "sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52",
  )
  assert_eq(
    @publication_host.prepared_client_program_semantics_cid(prepared),
    "sha256:fcaa7dcc999a2dff2b225caffc85e72987c1d4fd68f8250edd9100442e11d147",
  )
  assert_eq(
    @publication_host.emit_prepared_client_program_semantics(
      prepared, 10000, 20, 5,
    ).unwrap(),
    "{\"actql_version\":\"actql/0.1\",\"binding_references\":[],\"bindings\":{},\"expression_contract_cid\":\"sha256:b5701b2178a3b2e624d0fbfbda877d0117c367e42a855161e26e0d2e133f1c2c\",\"parameter_references\":[],\"parameters\":{},\"program_template\":{\"exports\":{\"r\":{\"from\":{\"result\":\"r\",\"stage\":\"s\"}}},\"stages\":[{\"after\":\"initial\",\"id\":\"s\",\"imports\":{},\"stage_semantics_cid\":\"sha256:114e89f94b5307288c47bf3612847f871da69dc4da4b48b5a13548fd707f4d93\"}]},\"version\":\"actql-program-semantics/0.1\"}",
  )
  assert_true(
    @publication_host.emit_prepared_client_program_semantics(
      prepared, 10000, 19, 5,
    )
    is Err(_),
  )
  assert_true(
    @publication_host.emit_prepared_client_program_semantics(
      prepared, 10000, 20, 4,
    )
    is Err(_),
  )
  assert_eq(
    @publication_host.emit_prepared_client_program_definition(
      prepared, 10000, 4, 1,
    ).unwrap(),
    "{\"id\":\"identity-writer\",\"program_semantics_cid\":\"sha256:fcaa7dcc999a2dff2b225caffc85e72987c1d4fd68f8250edd9100442e11d147\",\"version\":\"actql-program-definition/0.1\"}",
  )
  assert_true(
    @publication_host.emit_prepared_client_program_definition(
      prepared, 10000, 3, 1,
    )
    is Err(_),
  )
  assert_eq(
    @publication_host.emit_prepared_client_stage_semantics(
      prepared,
      0,
      10000,
      facts.node_upper + 8,
      facts.depth_upper + 1,
    ).unwrap(),
    "{\"binding_references\":[],\"bindings\":{},\"expression_contract_cid\":\"sha256:b5701b2178a3b2e624d0fbfbda877d0117c367e42a855161e26e0d2e133f1c2c\",\"local_body\":{\"effects\":{},\"inputs\":{},\"results\":{\"r\":{\"fields\":[\"x\"],\"from\":\"v\"}},\"steps\":[{\"as\":\"v\",\"values\":{\"rows\":[{\"x\":1}],\"schema\":{\"x\":{\"nullable\":false,\"type\":\"number\"}}}}]},\"parameter_references\":[],\"parameters\":{},\"version\":\"actql-stage-semantics/0.1\"}",
  )
  let identity = @checked.source_identity(
    @strategy.graph_program(@publication_host.prepared_client_graph(prepared)),
  )
  let local = @context.program_identity_stage_at(identity, 0).unwrap()
  assert_eq(
    @context.stage_identity_definition_cid(local),
    "sha256:2c32b3113d7b194a94b4374cd23d82145892b010b139f8fd6292452fc8a82a4d",
  )
  assert_eq(
    @context.stage_identity_parameter_values_cid(local),
    "sha256:c183484727a250f184812053fce437f9b9c90ca889a7a7505a9f9791d84a7b52",
  )
  assert_eq(
    @context.stage_identity_parameter_declarations_cid(local),
    "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a",
  )
}
