///|
// The source and declared parameter contracts are independent authored fixtures.
// These Source-free controls execute public lowering and the normal common check.
// No Model/provider I/O, Host execution or Result publication is claimed.

///|
test "WITH property public lowering order-property-selected-property-receiver-collision" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"a\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"b\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"c\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"oa\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"ob\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"oc\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH objects AS (SELECT 2 AS id, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other) SELECT id, payload.score AS original_score, other AS payload FROM objects ORDER BY payload.score NULLS LAST",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}

///|
test "WITH property public lowering analytic-property-sql-lag" {
  let declarations = @parameters.read_declarations(
    Some(
      from_unpivot_public_cursor(
        "{\"a\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"b\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"c\":{\"type\":\"object\",\"nullable\":true,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"oa\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"ob\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}},\"oc\":{\"type\":\"object\",\"nullable\":false,\"fields\":{\"score\":{\"type\":\"number\",\"nullable\":false}}}}",
      ),
    ),
    {
      max_parameters: 10,
      max_nodes: 1000,
      max_depth: 100,
      max_text_bytes: 10000,
    },
  ).unwrap()
  let context = {
    ..fixture_context(),
    inputs: [],
    parameter_declarations: Some(declarations),
  }
  let lowered = @frontend.lower(
    "WITH objects AS (SELECT 2 AS id, @a AS payload, @oa AS other UNION ALL SELECT 1 AS id, @b AS payload, @ob AS other UNION ALL SELECT 3 AS id, @c AS payload, @oc AS other) SELECT id, LAG(payload.score) OVER (ORDER BY id) AS previous FROM objects ORDER BY id",
    Text,
    Some(context),
  ).unwrap()
  assert_true(lowered.program is Some(_))
}
