///|
fn listing_policy_fixture() -> @capacity.Policy {
  // Independently authored canonical bytes and SHA-256. Generic Relation
  // output is capped at one here; it is not this full-scan acquisition scope.
  let text = "{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_file_listing_items\":2,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":1,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}"
  @capacity.admit(
    @utf8.encode(text),
    "sha256:89727cf1523defcd7b85e3a74e062fc18c56f21d1319120d171682fb9d567599",
    { max_bytes: 4096, max_nodes: 100, max_depth: 4, },
  ).unwrap()
}

///|
test "listing consumes the resolved row ceiling at N and rejects N plus one" {
  let policy = listing_policy_fixture()
  let read = listing_read_fixture(policy=Some(policy))
  begin_row_listing_request(read, None, 0L).unwrap()
  assert_eq(
    accept_row_source_listing_page(
      read,
      listing_page("[{\"id\":1,\"p\":7},{\"id\":2,\"p\":null}]", None, None),
      10L,
    ).unwrap(),
    2,
  )
  assert_true(read.listing.unwrap().complete)
  assert_true(cancel_row_source_read(read))
  assert_false(cancel_row_source_read(read))
  let over = listing_read_fixture(policy=Some(policy))
  begin_row_listing_request(over, None, 0L).unwrap()
  assert_true(
    accept_row_source_listing_page(
      over,
      listing_page("[{\"id\":1},{\"id\":2},{\"id\":3}]", None, None),
      10L,
    )
    is Err(ListingLimit("max_listing_items")),
  )
  assert_false(over.listing.unwrap().complete)
  assert_false(cancel_row_source_read(over))
}
