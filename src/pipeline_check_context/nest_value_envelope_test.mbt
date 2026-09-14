///|
fn nest_depth_policy(depth : Int) -> @policy.Policy {
  let fields = [
    "max_aggregate_array_items", "max_artifact_bytes", "max_artifact_rows", "max_effect_items",
    "max_graph_input_edges", "max_graph_input_nodes", "max_graph_output_rows", "max_graph_paths",
    "max_infer_items", "max_model_input_tokens_per_item", "max_model_request_bytes_per_item",
    "max_model_total_duration_ms", "max_nested_value_bytes", "max_nested_value_depth",
    "max_relation_output_rows", "max_temporal_matches_per_key", "max_temporal_output_rows",
  ]
  let body = "{" +
    fields
    .map(name => {
      "\"" +
      name +
      "\":" +
      (if name == "max_nested_value_depth" { depth.to_string() } else { "1" })
    })
    .join(",") +
    ",\"version\":\"actql-capacity-host-policy/0.1\"}"
  @policy.admit(@utf8.encode(body), "sha256:" + @sha.text_hex(body).unwrap(), {
    max_bytes: 4096,
    max_nodes: 100,
    max_depth: 4,
  }).unwrap()
}

///|
test "nest value scopes validate empty declared payloads and retain sibling arrays" {
  // Expected depths follow only Array/Object constructors in the nest rule:
  // generated array + generated object + zero or two payload arrays.
  for (field, expected) in [("id", 2), ("v", 2), ("payload", 4)] {
    for depth in [expected - 1, expected] {
      let owner = index_program_operation_resolutions(
        resolution_profiles(
          operation_order_fixture(
            "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"v\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}},\"rows\":[]},\"as\":\"seed\"},{\"derive\":{\"x\":\"concat($p, to_string($n))\",\"payload\":\"[[id]]\"}},{\"assert_rows\":{\"unique_by\":[\"id\"]},\"as\":\"keyed\"},{\"nest\":{\"with\":\"keyed\",\"on\":[{\"left\":\"id\",\"right\":\"id\"}],\"into\":\"items\",\"fields\":[\"" +
            field +
            "\"]}}]",
            capacity_policy=nest_depth_policy(depth),
            host_profile=bound_profile().replace(
              old="\"max_nested_value_depth\":1",
              new="\"max_nested_value_depth\":" + depth.to_string(),
            ),
          ),
        ),
        10000000,
        100,
      ).unwrap()
      let mut found = 0
      for i in 0..<operation_resolution_count(owner) {
        let site = operation_requirements_at(
          operation_resolution_requirements(owner),
          i,
        ).unwrap()
        guard site.requirement is @pipeline.NestRequirement(ResolveItemLimit) else {
          continue
        }
        let items = select_nest_item_limit(owner, i, 10000000, 100).unwrap()
        if depth < expected {
          assert_true(
            prepare_nest_value_envelope(items, 10000000, 100)
            is Err(DepthExceeded),
          )
        } else {
          let envelope = prepare_nest_value_envelope(items, 10000000, 100).unwrap()
          assert_true(physical_equal(envelope.items, items))
          assert_eq(envelope.type_depth, expected)
          assert_eq(@policy.ceiling_value(envelope.byte_ceiling), 1L)
          let names = []
          for j in 0..<nest_attachment_field_count(envelope) {
            names.push(
              @schema.reference_name(
                nest_attachment_field_at(envelope, j).unwrap().name,
              ),
            )
          }
          assert_eq(names.length(), 2)
          assert_true(names.contains("payload"))
          assert_true(names.contains("items"))
          assert_true(!names.contains("v"))
          assert_true(nest_attachment_field_at(envelope, -1) is None)
          assert_true(nest_attachment_field_at(envelope, 2) is None)
          assert_true(
            prepare_nest_value_envelope(items, envelope.work, expected) is Ok(_),
          )
          assert_true(
            prepare_nest_value_envelope(items, envelope.work - 1, expected)
            is Err(BudgetExceeded),
          )
          assert_true(
            prepare_nest_value_envelope(items, envelope.work, expected - 1)
            is Err(BudgetExceeded),
          )
        }
        found += 1
      }
      assert_eq(found, 3)
    }
  }
}
