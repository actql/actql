///|
fn wire(p : @policy.Policy) -> (String, String) raise @encode.EncodeFailure {
  let w = @capacity_host_witness.create(
    @policy.ceiling(p, "max_aggregate_array_items").unwrap(),
    limits(),
  ).unwrap()
  let writer = @encode.writer(4096, 100, 4)
  @capacity_host_witness.emit(w, writer)
  (@encode.finish(writer), @capacity_host_witness.cid(w))
}

///|
test "all host source witnesses admit from full canonical bytes" {
  let p = policy(fixture())
  for
    field in [
      "max_aggregate_array_items", "max_artifact_bytes", "max_artifact_rows", "max_effect_items",
      "max_graph_input_edges", "max_graph_input_nodes", "max_graph_output_rows",
      "max_graph_paths", "max_infer_items", "max_model_request_bytes_per_item", "max_nested_value_bytes",
      "max_relation_output_rows", "max_temporal_matches_per_key", "max_temporal_output_rows",
    ] {
    let w = @capacity_host_witness.create(
      @policy.ceiling(p, field).unwrap(),
      limits(),
    ).unwrap()
    let writer = @encode.writer(4096, 100, 4)
    @capacity_host_witness.emit(w, writer)
    let text = @encode.finish(writer)
    let admitted = @capacity_host_witness.admit(
      @utf8.encode(text),
      @capacity_host_witness.cid(w),
      p,
      limits(),
    ).unwrap()
    assert_eq(
      @capacity_host_witness.cid(admitted),
      @capacity_host_witness.cid(w),
    )
    assert_eq(
      @capacity_host_witness.law_id(admitted),
      @capacity_host_witness.law_id(w),
    )
    assert_eq(
      @capacity_host_witness.unit(admitted),
      @capacity_host_witness.unit(w),
    )
    assert_eq(
      @policy.ceiling_field(@capacity_host_witness.ceiling(admitted)),
      field,
    )
  }
}

///|
test "host witness admission rejects wire claims not derived from its policy" {
  let p = policy(fixture())
  let (text, cid) = wire(p)
  let mutations = [
    ("\"unit\":\"array_items\"", "\"unit\":\"rows\""),
    ("\"value\":1", "\"value\":2"),
    ("\"role\":\"host_ceiling\"", "\"role\":\"proven_upper_bound\""),
    ("actql.host.aggregate-array-items", "actql.host.artifact-rows"),
    ("\"kind\":\"host_policy\"", "\"kind\":\"program\""),
    ("\"op\":\"source\"", "\"op\":\"preserve\""),
    ("actql-bound-witness/0.1", "invalid"),
    ("\"value\":1,", ""),
    ("\"value\":1", "\"value\":null"),
    ("\"value\":1", "\"value\":\"1\""),
    ("\"value\":1", "\"extra\":1,\"value\":1"),
    ("\"policy_cid\":", "\"unknown_cid\":"),
  ]
  for (old, replacement) in mutations {
    let changed = text.replace(old~, new=replacement)
    assert_true(
      @capacity_host_witness.admit(@utf8.encode(changed), cid, p, limits())
      is Err(InvalidWitness),
    )
  }
  let source_cid = @policy.cid(p)
  let missing = text.replace(
    old="\"dependencies\":[\"" + source_cid + "\"]",
    new="\"dependencies\":[]",
  )
  assert_true(
    @capacity_host_witness.admit(@utf8.encode(missing), cid, p, limits())
    is Err(InvalidWitness),
  )
  let duplicate = text.replace(
    old="\"dependencies\":[\"" + source_cid + "\"]",
    new="\"dependencies\":[\"" + source_cid + "\",\"" + source_cid + "\"]",
  )
  assert_true(
    @capacity_host_witness.admit(@utf8.encode(duplicate), cid, p, limits())
    is Err(InvalidWitness),
  )
}

///|
test "self-consistent forged witness identity cannot override the governing unit" {
  let p = policy(fixture())
  // Node independently recomputed the preimage CID after replacing array_items
  // with rows. The claimed CID is internally correct but the law mapping is not.
  let text = "{\"dependencies\":[\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"],\"derivation\":{\"op\":\"source\"},\"law_id\":\"actql.host.aggregate-array-items\",\"role\":\"host_ceiling\",\"source\":{\"field\":\"max_aggregate_array_items\",\"kind\":\"host_policy\",\"policy_cid\":\"sha256:dfa8818d1752320593a6de63173a99ab23b8b17cd3786df87003aafcfbd04f63\"},\"unit\":\"rows\",\"value\":1,\"version\":\"actql-bound-witness/0.1\",\"witness_cid\":\"sha256:9a0e7c1509f4a60a751edb4af583db95869fb86e7f42f8c35aadc6a943b92df6\"}"
  let cid = "sha256:9a0e7c1509f4a60a751edb4af583db95869fb86e7f42f8c35aadc6a943b92df6"
  assert_true(
    @capacity_host_witness.admit(@utf8.encode(text), cid, p, limits())
    is Err(IdentityMismatch),
  )
}

///|
test "host witness admission requires the expected identity and exact source policy" {
  let p = policy(fixture())
  let (text, cid) = wire(p)
  assert_true(
    @capacity_host_witness.admit(
      @utf8.encode(text),
      "sha256:wrong",
      p,
      limits(),
    )
    is Err(IdentityMismatch),
  )
  let changed = policy(
    fixture().replace(old="\"max_graph_paths\":1", new="\"max_graph_paths\":2"),
  )
  assert_true(
    @capacity_host_witness.admit(@utf8.encode(text), cid, changed, limits())
    is Err(IdentityMismatch),
  )
  let other_field = text.replace(
    old="max_aggregate_array_items",
    new="max_artifact_rows",
  )
  assert_true(
    @capacity_host_witness.admit(@utf8.encode(other_field), cid, p, limits())
    is Err(IdentityMismatch),
  )
}

///|
test "host witness artifact encoding is checked without normalization repair" {
  let p = policy(fixture())
  let (text, cid) = wire(p)
  for
    changed in [
      " " + text,
      text + "\n",
      "\u{FEFF}" + text,
      text.replace(old="\"value\":1", new="\"value\":1.0"),
      text.replace(old="\"value\":1", new="\"value\":1e0"),
      text.replace(old="array_items", new="array_item\\u0073"),
      text.replace(old="\"value\":1", new="\"value\":1,\"value\":1"),
    ] {
    assert_true(
      @capacity_host_witness.admit(@utf8.encode(changed), cid, p, limits())
      is Err(InvalidWitness),
    )
  }
}

///|
test "wire admission separately caps complete bytes nodes and depth" {
  let p = policy(fixture())
  let (text, cid) = wire(p)
  let bytes = @utf8.encode(text)
  let exact : @capacity_host_witness.Limits = {
    max_bytes: bytes.length(),
    max_nodes: 15,
    max_depth: 2,
  }
  assert_true(@capacity_host_witness.admit(bytes, cid, p, exact) is Ok(_))
  assert_true(
    @capacity_host_witness.admit(bytes, cid, p, {
      ..exact,
      max_bytes: bytes.length() - 1,
    })
    is Err(BudgetExceeded),
  )
  assert_true(
    @capacity_host_witness.admit(bytes, cid, p, { ..exact, max_nodes: 14, })
    is Err(BudgetExceeded),
  )
  assert_true(
    @capacity_host_witness.admit(bytes, cid, p, { ..exact, max_depth: 1, })
    is Err(BudgetExceeded),
  )
  assert_true(
    @capacity_host_witness.admit(bytes, cid, p, { ..exact, max_depth: -1, })
    is Err(InvalidLimits),
  )
}
