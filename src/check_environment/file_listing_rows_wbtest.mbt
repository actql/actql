///|
fn listing_policy_fixture() -> @policy.Policy {
  // Independently authored canonical bytes and SHA-256. Generic Relation
  // output is capped at one here; it is not this full-scan acquisition scope.
  let text = "{\"max_aggregate_array_items\":1,\"max_artifact_bytes\":1,\"max_artifact_rows\":1,\"max_effect_items\":1,\"max_file_listing_items\":2,\"max_graph_input_edges\":1,\"max_graph_input_nodes\":1,\"max_graph_output_rows\":1,\"max_graph_paths\":1,\"max_infer_items\":1,\"max_model_input_tokens_per_item\":1,\"max_model_request_bytes_per_item\":1,\"max_model_total_duration_ms\":1,\"max_nested_value_bytes\":1,\"max_nested_value_depth\":1,\"max_relation_output_rows\":1,\"max_temporal_matches_per_key\":1,\"max_temporal_output_rows\":1,\"version\":\"actql-capacity-host-policy/0.1\"}"
  @policy.admit(
    @utf8.encode(text),
    "sha256:89727cf1523defcd7b85e3a74e062fc18c56f21d1319120d171682fb9d567599",
    { max_bytes: 4096, max_nodes: 100, max_depth: 4, },
  ).unwrap()
}

///|
test "listing row resolution binds independent contract and Host ceilings" {
  let policy = listing_policy_fixture()
  let rows = resolve_listing_row_candidates(
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    Some(3L),
    Some(policy),
    "file-listing:fixture",
  ).unwrap()
  assert_eq(
    @listing_arithmetic.minimum_value(@bound_wire.limit_minimum(rows)),
    2L,
  )
  assert_eq(
    @bound_wire.limit_cid(rows),
    "sha256:0e541de3cd5e8f7a595a7fcf662cd9ce0dd151fef13d397f0a9ace559c9cea6e",
  )
  assert_eq(@bound_wire.limit_subject(rows), "file-listing:fixture")
  assert_eq(@bound_wire.limit_enforcement(rows), @bound_wire.StreamingAtomic)
  let different_selection = resolve_listing_row_candidates(
    "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    Some(3L),
    Some(policy),
    "file-listing:other-selection",
  ).unwrap()
  assert_true(
    @bound_wire.limit_cid(different_selection) != @bound_wire.limit_cid(rows),
  )
  let different_profile = resolve_listing_row_candidates(
    "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    Some(3L),
    Some(policy),
    "file-listing:fixture",
  ).unwrap()
  assert_true(
    @bound_wire.limit_cid(different_profile) != @bound_wire.limit_cid(rows),
  )
}

///|
test "unknown listing count needs a finite applicable ceiling not a count proof" {
  assert_eq(
    @listing_arithmetic.minimum_value(
      @bound_wire.limit_minimum(
        resolve_listing_row_candidates(
          "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          None,
          Some(listing_policy_fixture()),
          "file-listing:fixture",
        ).unwrap(),
      ),
    ),
    2L,
  )
  assert_eq(
    @listing_arithmetic.minimum_value(
      @bound_wire.limit_minimum(
        resolve_listing_row_candidates(
          "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          Some(3L),
          None,
          "file-listing:fixture",
        ).unwrap(),
      ),
    ),
    3L,
  )
  assert_true(
    resolve_listing_row_candidates(
      "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      None,
      None,
      "file-listing:fixture",
    )
    is Err(Unresolved),
  )
}
