///|
// The retained acquisition-complete-facts corpus supplies this real Catalog.
// Its canonical preimage/CID is independently reproduced with Python hashlib;
// neither the expected capture placement nor request form comes from lowering.
fn chain_right_wire(
  host_capacity? : Bool = false,
) -> @environment.WireEnvironment {
  let text =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:9a7ee4daaf749f3a196d0e7ca49efc2dc70fe8b0590ae55488a767b10ef885a4","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{"additional_properties":false,"fields":{"extra":{"nullable":false,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"lookup_capacity":{"completeness":"complete_per_requested_key","max_pages_per_request":3,"max_response_bytes_per_page":4096,"max_rows_per_key":2,"version":"actql-lookup-capacity/0.1"}},"cid":"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"},"tenant":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","correlation":{"cardinality":"zero_or_many","identity":["id"],"request_fields":["id"],"response_fields":["id"]},"default_mode":"snapshot","kind":"fetch","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:1a03e9c57e04b3fe35e6c43e7ebe8814c346757d42c0d72c830ffab5cbaef2f9","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"},"tenant":{"nullable":true,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf","id":"fixture-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"lookup_capacity":{"completeness":"complete_per_requested_key","max_pages_per_request":3,"max_response_bytes_per_page":4096,"max_rows_per_key":2,"version":"actql-lookup-capacity/0.1"}},"cid":"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6","id":"fixture-3","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"extra":{"nullable":false,"type":"number"},"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742","id":"fixture-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/r#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:a8c80b49719db3ba178761ee4a200e45374a2dfc53d49f23e0efa3c570b223f2","host_policy_profile":{},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[{"acquisition":{"authority":"read_metadata","correlation":{"cardinality":"zero_or_many","identity":["id"],"request_fields":["id"],"response_fields":["id"]},"default_mode":"snapshot","kind":"fetch","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:9ed258994455d28e86f7029fa78995a4432882f346f46bbc25e5f7917ce7d1cf","id":"fixture-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:1a03e9c57e04b3fe35e6c43e7ebe8814c346757d42c0d72c830ffab5cbaef2f9","output":{"carrier":"relation","data_policy":{"cid":"sha256:e29dbae5d01c451177772ccd55550b9ec4be9b47eb12e56afffea74cfdd879bf","id":"fixture-2","version":"fixture"},"facts":{"cid":"sha256:4b8161d63b6b21e5781bfe8d3d35fe79b736c4403ec2cf3bbecb8c87accd33e6","id":"fixture-3","version":"fixture"},"schema":{"cid":"sha256:41a0729d8beebc81de0e25d9908ff9daad85dcc9b4dbe8cc80f975ec559c1742","id":"fixture-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:b1632a74e9ccd886ba08fb5082e7e053fe9cc1b141e8a48da7fec928a2e9fc24","id":"fixture-4","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}
  // This optional finite policy is test DATA, not Host resource admission.
  // Its containing identity is independently hashed with Python hashlib.
  let text = if host_capacity {
    text
    .replace(
      old="\"host_policy_profile\":{}",
      new="\"host_policy_profile\":{\"capacity\":{\"max_aggregate_array_items\":1000,\"max_analytic_frame_memberships\":1000,\"max_analytic_input_wire_bytes\":1000,\"max_analytic_output_wire_bytes\":1000,\"max_analytic_partition_wire_bytes\":1000,\"max_artifact_bytes\":1000,\"max_artifact_rows\":1000,\"max_effect_items\":1000,\"max_graph_input_edges\":1000,\"max_graph_input_nodes\":1000,\"max_graph_output_rows\":1000,\"max_graph_paths\":1000,\"max_infer_items\":1000,\"max_model_input_tokens_per_item\":1000,\"max_model_request_bytes_per_item\":1000,\"max_model_total_duration_ms\":1000,\"max_nested_value_bytes\":1000,\"max_nested_value_depth\":1000,\"max_relation_output_rows\":1000,\"max_temporal_matches_per_key\":1000,\"max_temporal_output_rows\":1000,\"version\":\"actql-capacity-host-policy/0.1\"}}",
    )
    .replace(
      old="sha256:a8c80b49719db3ba178761ee4a200e45374a2dfc53d49f23e0efa3c570b223f2",
      new="sha256:39eab696f7a707141e5c161d5df630c79ea5e080b6c26884bb08e1b87534e38c",
    )
  } else {
    text
  }
  let wire = @environment.read(
    @utf8.encode(text),
    if host_capacity {
      "sha256:39eab696f7a707141e5c161d5df630c79ea5e080b6c26884bb08e1b87534e38c"
    } else {
      "sha256:a8c80b49719db3ba178761ee4a200e45374a2dfc53d49f23e0efa3c570b223f2"
    },
    { max_bytes: 100000, max_nodes: 10000, max_depth: 100, max_members: 100, },
  ).unwrap()
  wire
}

///|
fn chain_right_catalog() -> @environment.SourceRequestContracts {
  let wire = chain_right_wire()
  @check.source_catalog_contracts(
    @check.prepare_source_catalog(
      @check.checking_environment(wire, { text_time: false, veca: false, }, {
        rela: true,
        sga: false,
        tea: false,
        calendar: false,
        text_rank: false,
      }),
      {
        max_work: 1000000,
        max_bytes: 100000,
        max_nodes: 10000,
        max_depth: 100,
      },
    ).unwrap(),
  )
}

///|
fn chain_right_context(
  direct~ : Bool,
  captured~ : Bool,
  parameters~ : Bool,
) -> Context {
  let declaration = @wire.admit(
    @source.parse_json(
      if direct {
        "{\"connector\":\"crm/main\",\"resource\":\"r\",\"view\":\"v\",\"request\":{\"tenant\":null,\"id\":1}}"
      } else {
        "{\"connector\":\"crm/main\",\"resource\":\"r\",\"view\":\"v\",\"request\":{\"tenant\":null}}"
      },
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let fields = @wire.admit(
    @source.parse_json(
      "{\"id\":{\"type\":\"number\",\"nullable\":false},\"extra\":{\"type\":\"number\",\"nullable\":false}}",
      construction_limits().source.source,
    ).unwrap(),
    construction_limits().source.tree,
  ).unwrap()
  let schema = @environment.read_relation_schema_fields(
      fields, 10000, 100, 100, 100000,
    ).unwrap().0
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"parents\":{\"type\":\"array\",\"max_items\":4,\"items\":{\"type\":\"object\",\"fields\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"items\":{\"type\":\"array\",\"nullable\":true,\"max_items\":3,\"items\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"code\":{\"type\":\"number\",\"nullable\":false},\"label\":{\"type\":\"string\",\"nullable\":true}}}}}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  {
    ..fixture_context(),
    parameter_declarations: if parameters {
      Some(declarations)
    } else {
      None
    },
    source_catalog: Some(chain_right_catalog()),
    captured_stage: if captured {
      Some("capture")
    } else {
      None
    },
    input_schemas: [("remote", schema)],
    inputs: [
      {
        relation: [{ value: "remote", quoted: false, }],
        name: "remote",
        source: Captured(declaration),
        visible_fields: ["id", "extra"],
        graph_bindings: [],
      },
    ],
  }
}

///|
fn chain_right_queries() -> Array[String] {
  [
    "FROM (SELECT 1 AS id) AS l |> JOIN remote AS r ON l.id = r.id MAX_OUTPUT_ROWS 4 |> JOIN (SELECT 1 AS id) AS s ON r.id = s.id MAX_OUTPUT_ROWS 4 |> SELECT l.id AS id",
    "WITH lefts AS (FROM UNNEST(@parents) p |> SELECT id, items) FROM lefts AS l |> JOIN remote AS r ON l.id = r.id MAX_OUTPUT_ROWS 4 |> CROSS JOIN UNNEST(l.items) AS n WITH OFFSET position |> SELECT l.id AS id, n.*, position",
  ]
}

///|
fn check_keyed_chain_right(query : String) -> Unit raise {
  for captured in [false, true] {
    let program = match
      compile_query_script(
        @query.parse_query_script(query, syntax_limits()).unwrap(),
        chain_right_context(
          direct=false,
          captured~,
          parameters=query.contains("@parents"),
        ),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(issue) => with_demand_program(Err(issue))
    }
    // A keyed template omits id deliberately; Direct Select/Result use is
    // forbidden by the existing Common request/consumer classification.
    assert_eq(@program.stage_count(program), 1, msg=query)
    assert_false(semantic(program).contains("\"id\":\"capture\""))
    assert_true(semantic(program).contains("\"with\":\"remote\""))
  }
}

///|
fn check_direct_chain_right(query : String) -> Unit raise {
  for captured in [false, true] {
    let program = match
      compile_query_script(
        @query.parse_query_script(query, syntax_limits()).unwrap(),
        chain_right_context(
          direct=true,
          captured~,
          parameters=query.contains("@parents"),
        ),
        construction_limits(),
      ) {
      Ok(program) => program
      Err(issue) => with_demand_program(Err(issue))
    }
    assert_eq(
      @program.stage_count(program),
      if captured {
        2
      } else {
        1
      },
      msg=query,
    )
    assert_true(
      semantic(program).contains("\"request\":{\"id\":1,\"tenant\":null}"),
    )
  }
}

///|
test "keyed right Source stays at the two-JOIN consumer" {
  check_keyed_chain_right(chain_right_queries()[0])
}

///|
test "fully supplied right Source keeps two-JOIN requested capture" {
  check_direct_chain_right(chain_right_queries()[0])
}

///|
test "keyed right Source stays at the preserved object scope consumer" {
  check_keyed_chain_right(chain_right_queries()[1])
}

///|
test "fully supplied right Source keeps preserved object scope capture" {
  check_direct_chain_right(chain_right_queries()[1])
}

///|
test "near WITH producer shadows the same-named outer keyed Source" {
  let query = "WITH remote AS (SELECT 1 AS id) FROM (SELECT 1 AS id) AS l |> JOIN remote AS r ON l.id = r.id MAX_OUTPUT_ROWS 4 |> JOIN (SELECT 1 AS id) AS s ON r.id = s.id MAX_OUTPUT_ROWS 4 |> SELECT l.id AS id"
  let program = with_demand_program(
    compile_query_script(
      @query.parse_query_script(query, syntax_limits()).unwrap(),
      chain_right_context(direct=false, captured=true, parameters=false),
      construction_limits(),
    ),
  )
  assert_eq(@program.stage_count(program), 1)
  assert_false(semantic(program).contains("\"connector\":\"crm/main\""))
  assert_false(semantic(program).contains("\"id\":\"capture\""))
}
