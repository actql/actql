///|
fn key_column_body() -> String {
  (
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[],"identity_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","node_definitions":[{"key_columns":["person_key","tenant_key"],"key_contracts":[{"nullable":false,"type":"number"},{"nullable":false,"type":"string"}],"labels":{},"name":"Person","properties":{}}],"value_law_cid":"sha256:6a6da6032f71b2b5e629ece1155c98e9dc92fd16e7b204a5f4925e2d74453e34","version":"actql-graph-contract/0.1"}
  )
}

///|
test "Graph contract roundtrip retains original key column component and type correspondence" {
  let decoded = read_cursor(read_source(key_column_body()), caps()).unwrap()
  assert_eq(stringify(decoded, caps()), key_column_body())
  let profile = @carrier.graph_definition(graph(decoded))
  let node = @carrier.graph_node_at(profile, 0).unwrap()
  assert_eq(
    @carrier.graph_element_definition_key_column_at(node, 0),
    Some("person_key"),
  )
  assert_eq(
    @carrier.graph_element_definition_key_column_at(node, 1),
    Some("tenant_key"),
  )
  assert_true(
    @carrier.graph_element_definition_key_at(node, 0).unwrap().shape
    is @value.Number,
  )
  assert_true(
    @carrier.graph_element_definition_key_at(node, 1).unwrap().shape
    is @value.Text(_),
  )
  let admitted = admit(@carrier.graph_carrier(graph(decoded)), caps()).unwrap()
  assert_eq(cid(admitted), cid(decoded))
}

///|
test "Graph contract rejects incomplete duplicate and erased key column correspondence" {
  for
    replacement in [
      "[\"person_key\"]", "[\"person_key\",null]", "[\"person_key\",\"PERSON_KEY\"]",
    ] {
    assert_true(
      read_cursor(
        read_source(
          key_column_body().replace(
            old="[\"person_key\",\"tenant_key\"]",
            new=replacement,
          ),
        ),
        caps(),
      )
      is Err(InvalidStructure),
    )
  }
  assert_true(
    read_cursor(
      read_source(
        key_column_body().replace(
          old="\"key_columns\":[\"person_key\",\"tenant_key\"],",
          new="",
        ),
      ),
      caps(),
    )
    is Err(InvalidBody),
  )
  let changed = read_cursor(
    read_source(key_column_body().replace(old="person_key", new="company_key")),
    caps(),
  ).unwrap()
  let original = read_cursor(read_source(key_column_body()), caps()).unwrap()
  assert_true(cid(original) != cid(changed))
}
