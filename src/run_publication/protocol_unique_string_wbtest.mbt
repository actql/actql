///|
fn unique_string_budget(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> ProtocolValidationBudget {
  {
    remaining: 1000,
    max_wire_bytes: bytes,
    max_nodes: nodes,
    max_depth: depth,
  }
}

///|
test "borrowed unique strings preserve canonical serializer finite refusals" {
  for text in ["", "a", "\"\\\n\u0000", "é", "e\u0301", "日", "😀"] {
    let bytes = @encode.quoted_string_construction_extent(text).unwrap().0.to_int()
    for bound in [bytes - 1, bytes, bytes + 1] {
      for nodes in [0, 1, 2] {
        for depth in [-1, 0, 1] {
          let values : Array[@json.CanonicalValue] = [
            @json.from_json(Json::string(text), 1, 0, 4096, data_keys=true),
          ]
          assert_eq(
            protocol_unique_string_array(
              values,
              unique_string_budget(bound, nodes, depth),
            ),
            protocol_unique_array(
              values,
              unique_string_budget(bound, nodes, depth),
            ),
          )
        }
      }
    }
  }
  for units in [[0xd800], [0xdc00], [0xd800, 65]] {
    let text = String::from_array(units.map(unit => unit.unsafe_to_char()))
    // The canonical owner refuses malformed UTF16 before any validator can
    // borrow it; the scalar codec guard independently preserves that refusal.
    let rejected = try {
      ignore(@json.from_json(Json::string(text), 1, 0, 4096, data_keys=true))
      false
    } catch {
      @json.InvalidUnicode(_) => true
      _ => false
    }
    assert_true(rejected)
    assert_true(@encode.quoted_string_construction_extent(text) is None)
  }
  // No item ever constructs a writer for either algorithm on empty arrays.
  assert_eq(
    protocol_unique_string_array([], unique_string_budget(-1, 0, -1)),
    protocol_unique_array([], unique_string_budget(-1, 0, -1)),
  )
}

///|
test "StringRule uniqueness borrows decoded spelling and rejects foreign types" {
  let rules : Array[ProtocolSchemaRule] = [
    StringRule(None, [], 0, 0),
    ArrayRule(0, 0, true, -1),
  ]
  for
    (wire, expected) in [
      ("[\"a\",\"\\u0061\"]", false),
      ("[\"é\",\"e\\u0301\"]", true),
      ("[\"\\n\",\"\\u000a\"]", false),
      ("[\"😀\",\"日\"]", true),
      ("[\"a\",\"a\"]", false),
      ("[1]", false),
      ("[{\"deep\":[1,2]}]", false),
      ("[null]", false),
    ] {
    let value = parse_contract_wire(wire, 4096, 100, 10, data_keys=true).unwrap()
    guard value is @json.Array(items) else { fail("array") }
    let values = @json.array_values(items)
    // Historical complete StringRule result: generic uniqueness followed by
    // item type validation. Raw JSON spelling is gone at this boundary.
    let old = protocol_unique_array(values, unique_string_budget(4096, 100, 10)) &&
      values.all(value => value is @json.String(_))
    assert_eq(
      protocol_unique_string_array(values, unique_string_budget(4096, 100, 10)),
      old,
    )
    assert_eq(old, expected)
    assert_eq(
      validate_protocol_node(
        value,
        1,
        rules,
        unique_string_budget(4096, 100, 10),
      ),
      expected,
    )
  }
  // Non-StringRule unique arrays still use the general canonical codec.
  let numeric = [NumberRule, ArrayRule(0, 0, true, -1)]
  for (wire, expected) in [("[1,2]", true), ("[1,1]", false)] {
    let value = parse_contract_wire(wire, 4096, 100, 10).unwrap()
    assert_eq(
      validate_protocol_node(
        value,
        1,
        numeric,
        unique_string_budget(4096, 100, 10),
      ),
      expected,
    )
  }
}
