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

///|
test "unattended Sample start respects the complete effective execution interval" {
  let no_breakpoints = "[]"
  let breakpoint =
    #|[{"kind":"gate","gate_kind":"effect_set","position":"before"}]
  let guard_wire =
    #|{"estimated_cost_ceiling":{"currency":"USD","amount_micro":"1","scope_cids":["sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],"tariff_revision_cid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","valid_until":"2098-01-01T00:00:00.000Z"}}
  for
    (until, breakpoints, guards, stop, unattended) in [
      ("terminal", no_breakpoints, "null", false, true),
      ("terminal", no_breakpoints, "null", true, false),
      ("step", no_breakpoints, "null", false, false),
      ("breakpoint", no_breakpoints, "null", false, false),
      ("terminal", breakpoint, "null", false, false),
      ("terminal", no_breakpoints, guard_wire, false, false),
    ] {
    let body = "{\"version\":\"actql-control-profile/0.1\",\"retain\":{},\"execution\":{\"stop_on_entry\":" +
      stop.to_string() +
      ",\"default_until\":\"" +
      until +
      "\",\"breakpoints\":" +
      breakpoints +
      ",\"guards\":" +
      guards +
      "}}"
    let profile = seal_run_evidence_value(
      "control_profile", body, 20000, 2000, 32,
    ).unwrap()
    assert_eq(
      interactive_profile_allows_unattended_terminal(profile),
      unattended,
    )
  }
}
