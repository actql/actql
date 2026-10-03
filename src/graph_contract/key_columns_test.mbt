///|
fn key_column_body() -> String {
  (
    #|{"domain":"sha256:0000000000000000000000000000000000000000000000000000000000000000","edge_definitions":[],"identity_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","node_definitions":[{"key_columns":["person_key","tenant_key"],"key_contracts":[{"nullable":false,"type":"number"},{"nullable":false,"type":"string"}],"labels":{},"name":"Person","properties":{}}],"value_law_cid":"sha256:654315b04dd9391454d0b5ffdf1a559d2bf5cae57eebfcf18c5cc4de2cad66dc","version":"actql-property-graph-contract/0.1"}
  )
}

///|
test "Graph contract roundtrip retains original key column component and type correspondence" {
  let decoded = read_property_graph_cursor(
    read_source(key_column_body()),
    caps(),
  ).unwrap()
  assert_eq(stringify_property_graph(decoded, caps()), key_column_body())
  let profile = @carrier.graph_property_definition(property_graph(decoded))
  let node = @carrier.property_graph_node_at(profile, 0).unwrap()
  assert_eq(
    @carrier.property_definition_key_column_at(node, 0),
    Some("person_key"),
  )
  assert_eq(
    @carrier.property_definition_key_column_at(node, 1),
    Some("tenant_key"),
  )
  assert_true(
    @carrier.property_definition_key_at(node, 0).unwrap().shape is @value.Number,
  )
  assert_true(
    @carrier.property_definition_key_at(node, 1).unwrap().shape
    is @value.Text(_),
  )
  let admitted = admit_property_graph(
    @carrier.graph_carrier(property_graph(decoded)),
    caps(),
  ).unwrap()
  assert_eq(property_cid(admitted), property_cid(decoded))
}

///|
test "Graph contract rejects incomplete duplicate and erased key column correspondence" {
  for
    replacement in [
      "[\"person_key\"]", "[\"person_key\",null]", "[\"person_key\",\"PERSON_KEY\"]",
    ] {
    assert_true(
      read_property_graph_cursor(
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
    read_property_graph_cursor(
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
  let changed = read_property_graph_cursor(
    read_source(key_column_body().replace(old="person_key", new="company_key")),
    caps(),
  ).unwrap()
  let original = read_property_graph_cursor(
    read_source(key_column_body()),
    caps(),
  ).unwrap()
  assert_true(property_cid(original) != property_cid(changed))
}
