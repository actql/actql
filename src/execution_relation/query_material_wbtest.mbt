///|
fn query_material_limits() -> @planning.QueryMaterialLimits {
  {
    max_work: 1000000,
    max_fields: 100,
    max_parameters: 100,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 100,
  }
}

///|
fn query_material_expected(text : String) -> String raise {
  @identity.cid_value(
    @identity.from_json(@json.parse(text), 10000, 100, 100000),
    100000,
    10000,
    100,
  )
}

///|
test "query material resolves only request slots and unions request and filter Parameter uses" {
  let catalog = query_request_catalog_fixture()
  let mut previous : (String, String, String)? = None
  for
    request in [
      "{\"threshold\":{\"$param\":\"minimum\"},\"payload\":{\"literal\":{\"$param\":\"business\",\"literal\":{\"a\":1}}}}",
      "{\"payload\":{\"literal\":{\"literal\":{\"a\":1},\"$param\":\"business\"}},\"threshold\":{\"$param\":\"minimum\"}}",
    ] {
    let (query, owner) = query_sequence_fixture(request~, catalog=Some(catalog))
    let sequence = prepare_query_sequence(query, query_generated(owner), 10000).unwrap()
    let limits = {
      ..query_material_limits(),
      max_parameters: 1,
      max_fields: 2,
    }
    let material = @planning.prepare_query_material(sequence, limits).unwrap()
    assert_eq(
      @encode.document_text(@planning.query_material_request(material)),
      // Request business objects do not use the expression literal wrapper.
      "{\"payload\":{\"literal\":{\"$param\":\"business\",\"literal\":{\"a\":1}}},\"threshold\":1}",
    )
    let cids = @planning.query_material_cids(material)
    assert_eq(
      cids.2,
      query_material_expected(
        (
          #|{"values":{"minimum":1},"version":"actql-parameter-values/0.1"}
        ),
      ),
    )
    if previous is Some(expected) {
      assert_eq(cids, expected)
    }
    previous = Some(cids)
    assert_true(
      @planning.prepare_query_material(sequence, { ..limits, max_fields: 1, })
      is Err(FieldLimit),
    )
  }
}

///|
test "query material retains its checked owner and exact unevaluated filter and used values" {
  let (query, owner) = query_sequence_fixture()
  let sequence = prepare_query_sequence(query, query_generated(owner), 10000).unwrap()
  let limits = query_material_limits()
  let material = @planning.prepare_query_material(sequence, limits).unwrap()
  assert_true(
    physical_equal(@planning.query_material_owner(material), sequence),
  )
  assert_eq(
    @encode.document_text(@planning.query_material_request(material)),
    "{}",
  )
  let (request, filter, parameters) = @planning.query_material_cids(material)
  assert_eq(request, query_material_expected("{}"))
  assert_eq(
    filter,
    query_material_expected(
      (
        #|{"gt":[{"field":"id"},{"$param":"minimum"}]}
      ),
    ),
  )
  assert_eq(
    parameters,
    query_material_expected(
      (
        #|{"values":{"minimum":1},"version":"actql-parameter-values/0.1"}
      ),
    ),
  )
  let (work, bytes, nodes) = @planning.query_material_usage(material)
  assert_true(work > 0 && bytes > 0 && nodes > 0)
  assert_true(
    @planning.prepare_query_material(sequence, {
      ..limits,
      max_work: work,
      max_bytes: bytes,
      max_nodes: nodes,
    })
    is Ok(_),
  )
  assert_true(
    @planning.prepare_query_material(sequence, { ..limits, max_work: work - 1, })
    is Err(WorkLimit),
  )
  assert_true(
    @planning.prepare_query_material(sequence, {
      ..limits,
      max_bytes: bytes - 1,
    })
    is Err(Encoding(_)),
  )
  assert_true(
    @planning.prepare_query_material(sequence, {
      ..limits,
      max_nodes: nodes - 1,
    })
    is Err(Encoding(_)),
  )
  assert_true(
    @planning.prepare_query_material(sequence, { ..limits, max_parameters: 0, })
    is Err(ParameterLimit),
  )
  assert_true(
    @planning.prepare_query_material(sequence, { ..limits, max_depth: 0, })
    is Err(Encoding(_)),
  )
  assert_true(
    @planning.prepare_query_material(sequence, { ..limits, max_fields: -1, })
    is Err(InvalidLimits),
  )
}

///|
test "query material excludes unused Parameters and binding origin but includes demanded values" {
  let declarations =
    #|{"minimum":{"type":"number","nullable":false,"default":1},"unused":{"type":"number","nullable":false,"default":99}}
  let mut previous : (String, String, String)? = None
  for supplied in ["{}", "{\"unused\":1000}", "{\"minimum\":1,\"unused\":-1}"] {
    let (query, owner) = query_sequence_fixture(
      parameters=declarations,
      supplied~,
    )
    let sequence = prepare_query_sequence(query, query_generated(owner), 10000).unwrap()
    let material = @planning.prepare_query_material(
      sequence,
      query_material_limits(),
    ).unwrap()
    let cids = @planning.query_material_cids(material)
    if previous is Some(expected) {
      assert_eq(cids, expected)
    }
    previous = Some(cids)
  }
  let (query, owner) = query_sequence_fixture(
    parameters=declarations,
    supplied="{\"minimum\":2}",
  )
  let sequence = prepare_query_sequence(query, query_generated(owner), 10000).unwrap()
  let material = @planning.prepare_query_material(
    sequence,
    query_material_limits(),
  ).unwrap()
  let (request, filter, parameters) = @planning.query_material_cids(material)
  let expected = previous.unwrap()
  assert_eq(request, expected.0)
  assert_eq(filter, expected.1)
  assert_true(parameters != expected.2)
}
