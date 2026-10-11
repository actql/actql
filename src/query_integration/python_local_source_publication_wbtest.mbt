///|
// The Catalog's independent preimages are fixed in query_amount_catalog_wbtest.
// This publication is Host installation input, not a query or grant from a Client.
let python_local_publication : String =
  #|{"environmentCid":"sha256:b734cc90c9bffcd4098a70223685a9d9489992f426e861af2232e58261dd7424","aliases":[{"name":"records","sourceRef":"connector://crm/main/r#v","sourceViewContractCid":"sha256:ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3","schemaContractCid":"sha256:2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4"}],"tableWrites":[]}

///|
fn python_local_publication_environment() -> @program_check.CheckEnvironment {
  @program_check.checking_environment(
    @environment.member_environment(
      @environment.source_request_member(
        @environment.source_request_at(query_amount_nullable_catalog(), 0).unwrap(),
      ),
    ),
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
}

///|
test "installed Local publication binds original AQL and Program to exact Catalog" {
  let environment = python_local_publication_environment()
  let context = @local_input.bind_local_published_input_context(
    environment,
    python_local_publication,
    None,
  ).unwrap()
  let text = "FROM records |> WHERE id > 2 |> EXTEND id + 1 AS value |> SELECT value |> RESULT answer"
  let document =
    #|{"version":"actql/0.1","id":"python.local.source","stages":[{"id":"acquire","inputs":{"r":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"filter":"id > 2","as":"filtered"},{"select":["id"],"as":"captured"}],"results":{"out":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"r":{"result":{"stage":"acquire","result":"out"}}},"steps":[{"derive":{"value":"id + 1"},"as":"derived"},{"select":["value"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["value"]}}}],"results":{"answer":{"from":{"stage":"compute","result":"out"}}}}
  for input in [@local_input.Program(document), @local_input.Aql(text)] {
    let original = @local_input.prepare_local_input_material(
      input,
      environment,
      None,
      Some(context),
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    let prepared = @local_input.local_prepared_program(original)
    assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 1)
    assert_true(
      @strategy.graph_task_count(
        @publication_host.prepared_client_graph(prepared),
      ) >
      1,
    )
    assert_eq(
      @publication_host.prepared_client_result_name(prepared, 0),
      Some("answer"),
    )
    match (@local_input.local_prepared_original(original), input) {
      (Program(actual), Program(expected)) | (Aql(actual), Aql(expected)) =>
        assert_eq(actual, expected)
      _ => fail("Input kind must retain authored provenance")
    }
  }
}

///|
test "Local publication rejects foreign generation and substituted Source facts" {
  let environment = python_local_publication_environment()
  for
    (old, replacement) in [
      (
        "b734cc90c9bffcd4098a70223685a9d9489992f426e861af2232e58261dd7424",
        "a".repeat(64),
      ),
      ("connector://crm/main/r#v", "connector://crm/main/other#v"),
      (
        "ffa240d28d8b7253cd0f9750544576ab92aac05eee6ee95626210b41978e5eb3",
        "b".repeat(64),
      ),
      (
        "2fe8005dbfa26b68a2e50a3fc86a54b14f4d845275acfd3770b09ba7d4316bc4",
        "c".repeat(64),
      ),
      ("\"name\":\"records\"", "\"name\":null"),
      ("\"name\":\"records\",", ""),
      ("\"name\":\"records\"", "\"name\":\"records\",\"unknown\":true"),
    ] {
    assert_true(
      @local_input.bind_local_published_input_context(
        environment,
        python_local_publication.replace(old~, new=replacement),
        None,
      )
      is Err(_),
    )
  }
  assert_true(
    @local_input.bind_local_published_input_context(
      environment,
      python_local_publication,
      Some("{\"x\":null}"),
    )
    is Err(_),
  )
  let context = @local_input.bind_local_published_input_context(
    environment,
    python_local_publication,
    None,
  ).unwrap()
  assert_true(
    @local_input.prepare_local_input_material(
      Aql("SELECT id FROM missing"),
      environment,
      None,
      Some(context),
      @publication_host.client_standard_program_preparation_limits(),
    )
    is Err(_),
  )
}
