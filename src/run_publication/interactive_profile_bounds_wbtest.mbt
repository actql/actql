///|
test "interactive graph sample item limits are aggregate exact and one-short" {
  for (items, valid) in [(3, true), (2, false)] {
    let body = "{\"version\":\"actql-control-profile/0.1\",\"execution\":{\"stop_on_entry\":false,\"default_until\":\"terminal\",\"breakpoints\":[],\"guards\":null},\"retain\":{\"samples\":{\"strategy\":\"execution_prefix\",\"capture_scope\":\"all_outputs\",\"targets\":[],\"max_items\":" +
      items.to_string() +
      ",\"max_bytes\":\"256\",\"max_artifacts\":1,\"ttl_seconds\":1,\"required\":false,\"graph\":{\"max_nodes\":1,\"max_edges\":2},\"vectors\":{\"max_components_per_item\":1}}}}"
    let profile = seal_run_evidence_value(
      "control_profile", body, 20000, 2000, 32,
    ).unwrap()
    assert_eq(check_interactive_profile_bounds(profile) is Ok(_), valid)
  }
}

///|
test "interactive intermediate retention rejects zero holding without changing Host caps" {
  for (bytes, valid) in [("0", false), ("1", true)] {
    let body = "{\"version\":\"actql-control-profile/0.1\",\"execution\":{\"stop_on_entry\":false,\"default_until\":\"terminal\",\"breakpoints\":[],\"guards\":null},\"retain\":{\"intermediate\":{\"max_bytes\":\"" +
      bytes +
      "\",\"max_artifacts\":1,\"ttl_seconds\":1}}}"
    let profile = seal_run_evidence_value(
      "control_profile", body, 20000, 2000, 32,
    ).unwrap()
    assert_eq(check_interactive_profile_bounds(profile) is Ok(_), valid)
  }
}
