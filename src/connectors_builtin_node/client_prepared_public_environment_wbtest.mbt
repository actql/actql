///|
test "prepared public Source bridge keeps each new Program and supplied value original" {
  let environment = keyed_source_environment()
  let publication = "{\"environmentCid\":\"" +
    client_program_checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let prepared = client_program_prepare_public_source_environment(
    environment, publication,
  ).unwrap()
  let units : Array[String] = []
  let values : Array[String] = []
  for
    (query, declarations, supplied) in [
      ("SELECT 1 AS id", None, None),
      (
        "SELECT @p AS id",
        Some("{\"p\":{\"type\":\"number\"}}"),
        Some("{\"p\":1}"),
      ),
      (
        "SELECT @p AS id",
        Some("{\"p\":{\"type\":\"number\"}}"),
        Some("{\"p\":2}"),
      ),
    ] {
    let outcome = client_program_prepare_source_computation_in_public_environment(
      query,
      "sql",
      environment,
      prepared,
      declarations,
      supplied,
      false,
      [],
    )
    guard outcome is SourcePure(Prepared(value)) else {
      fail("new Program and Parameters must use the ordinary checker")
    }
    units.push(
      @program_check.unit_definition_cid(
        @strategy.graph_program(@publication_host.prepared_client_graph(value)),
        0,
      ).unwrap(),
    )
    values.push(
      @program_check.unit_used_values_cid(
        @strategy.graph_program(@publication_host.prepared_client_graph(value)),
        0,
      ).unwrap(),
    )
    let original = client_program_prepare_public_source_computation_with_parameters(
      query,
      "sql",
      environment,
      publication,
      declarations,
      supplied,
      false,
      [],
    )
    guard original is SourcePure(Prepared(original)) else {
      fail("the original public wire-based caller must remain supported")
    }
    assert_eq(
      @publication_host.prepared_client_program_semantics_cid(value),
      @publication_host.prepared_client_program_semantics_cid(original),
    )
  }
  assert_true(units[0] != units[1])
  assert_eq(units[1], units[2])
  assert_true(values[1] != values[2])
}

///|
test "prepared public Source bridge rejects foreign Environment and invalid new values" {
  let environment = keyed_source_environment()
  let publication = "{\"environmentCid\":\"" +
    client_program_checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let prepared = client_program_prepare_public_source_environment(
    environment, publication,
  ).unwrap()
  let foreign = keyed_source_environment()
  assert_false(
    client_program_public_source_environment_matches(prepared, foreign),
  )
  assert_true(
    client_program_prepare_source_computation_in_public_environment(
      "SELECT 1 AS id",
      "sql",
      foreign,
      prepared,
      None,
      None,
      false,
      [],
    )
    is SourcePure(Rejected(SourcePreparation(Publication))),
  )
  assert_true(
    client_program_prepare_source_computation_in_public_environment(
      "SELECT @p AS id",
      "sql",
      environment,
      prepared,
      Some("{\"p\":{\"type\":\"number\"}}"),
      Some("{\"p\":\"wrong\"}"),
      false,
      [],
    )
    is SourcePure(Rejected(_)),
  )
  assert_true(
    client_program_prepare_source_computation_in_public_environment(
      "SELECT @p + 1 AS id",
      "sql",
      environment,
      prepared,
      Some("{\"p\":{\"type\":\"string\"}}"),
      Some("{\"p\":\"text\"}"),
      false,
      [],
    )
    is SourcePure(Rejected(_)),
  )
  assert_true(
    client_program_prepare_source_computation_in_public_environment(
      "SELECT @missing AS id",
      "sql",
      environment,
      prepared,
      None,
      None,
      false,
      [],
    )
    is SourcePure(Rejected(_)),
  )
  assert_true(
    client_program_prepare_public_source_environment(
      environment,
      publication + "x",
    )
    is None,
  )
}

///|
test "prepared public JSON Effect uses the same static STORE target as Source" {
  let environment = store_source_preparation_environment()
  let publication = store_public_bridge_publication(environment)
  let prepared = client_program_prepare_public_source_environment(
    environment, publication,
  ).unwrap()
  let source = client_program_prepare_source_computation_in_public_environment(
    store_source_preparation_text(),
    "sql",
    environment,
    prepared,
    None,
    None,
    true,
    [],
  )
  guard source is SourceEffect(EffectPrepared(source)) else {
    fail("the static Source Effect must retain its original STORE target")
  }
  let document = client_program_lower_source(
      store_source_preparation_text(),
      "sql",
      environment,
      publication,
      None,
    ).unwrap().document
  let json = client_program_prepare_effect_computation_in_public_environment(
    document,
    "json",
    environment,
    prepared,
    None,
    [],
  )
  guard json is EffectPrepared(json) else {
    fail("the JSON Effect must share the original static publication")
  }
  assert_eq(
    @publication_host.prepared_client_effect_computation_definition_cid(source),
    @publication_host.prepared_client_effect_computation_definition_cid(json),
  )
  assert_true(
    client_program_prepare_source_computation_in_public_environment(
      store_source_preparation_text(),
      "sql",
      environment,
      prepared,
      None,
      None,
      false,
      [],
    )
    is SourcePure(Rejected(Preparation(EffectNotSupported(_)))),
  )
}
