///|
test "measured original dependency keeps exact encoder bytes and nodes and full raw identity admission" {
  let writer = @encode.writer(1000, 100, 16)
  @encode.begin_object(writer)
  @encode.key(writer, "value")
  @encode.string_value(writer, "fixture")
  @encode.end_object(writer)
  let (wire, bytes, nodes, depth) = @encode.finish_text_usage(writer)
  // Independent canonical text, dimensions and SHA256; no expected value is
  // obtained by parsing or hashing the body's returned token.
  let cid = "sha256:bc2674594440583782c17d5cf875c88037498d39f5661b6a5962dcf6089752c0"
  assert_eq(wire, "{\"value\":\"fixture\"}")
  assert_eq((bytes, nodes, depth), (19, 2, 1))
  let calls = Ref(0)
  let before = (b : Int, n : Int, d : Int) => {
    calls.val += 1
    b == 19 && n == 2 && d == 1
  }
  let (body, received) = admit_client_effect_dependency_capture_body(
    "request_values",
    Some(cid),
    wire,
    1000,
    100,
    16,
    Some(before),
    () => true,
    wire_extent=Some((bytes, nodes)),
    wire_depth=Some(depth),
    enforce_extent=true,
  ).unwrap()
  assert_eq(calls.val, 1)
  assert_eq(received, 19)
  assert_eq(@publication.captured_effect_dependency_body_cid(body), cid)
  assert_eq(@publication.captured_effect_dependency_body_json(body), wire)
  assert_true(
    admit_client_effect_dependency_capture_body(
      "request_values",
      Some(cid),
      wire,
      1000,
      100,
      16,
      Some(before),
      () => true,
      wire_extent=Some((18, 2)),
      wire_depth=Some(1),
    )
    is Err(Dependency(@publication.InvalidBody)),
  )
  assert_eq(calls.val, 1)
  // Equal byte/node/depth dimensions never attest another body's identity.
  assert_true(
    admit_client_effect_dependency_capture_body(
      "request_values",
      Some(cid),
      "{\"value\":\"changed\"}",
      1000,
      100,
      16,
      Some(before),
      () => true,
      wire_extent=Some((19, 2)),
      wire_depth=Some(1),
    )
    is Err(Dependency(@publication.InvalidBody)),
  )
  assert_eq(calls.val, 2)
  // This independently valid body has the same 19 bytes but six value
  // nodes. Giving it its own hash cannot bypass the actual two-node parse cap.
  let wider = "{\"value\":[0,1,2,3]}"
  let wider_cid = "sha256:9c62762382e05db7e18c1200dbf308a3d37771879e5b5b3f64131a86fd56ba13"
  assert_true(
    admit_client_effect_dependency_capture_body(
      "request_values",
      Some(wider_cid),
      wider,
      1000,
      100,
      16,
      None,
      () => true,
    )
    is Ok(_),
  )
  assert_true(
    admit_client_effect_dependency_capture_body(
      "request_values",
      Some(wider_cid),
      wider,
      1000,
      100,
      16,
      Some(before),
      () => true,
      wire_extent=Some((19, 2)),
      wire_depth=Some(1),
      enforce_extent=true,
    )
    is Err(Dependency(@publication.InvalidBody)),
  )
  assert_eq(calls.val, 3)
  let fallback = Ref((0, 0))
  admit_client_effect_dependency_capture_body(
    "request_values",
    Some(cid),
    wire,
    1000,
    100,
    16,
    Some((b, n, _) => {
      fallback.val = (b, n)
      true
    }),
    () => true,
  ).unwrap()
  |> ignore
  assert_eq(fallback.val, (19, 19))
}

///|
test "funded typed dependency preserves original edges and checks currentness after funding" {
  let source = "sha256:" + "1".repeat(64)
  let request = "sha256:" + "2".repeat(64)
  let contract = @publication.issue_single_source_acquisition_scope(
    source, request, 10000, 100, 10,
  ).unwrap()
  let (bytes, nodes, depth) = @publication.publication_contract_wire_usage(
    contract,
  ).unwrap()
  let charges : Array[(Int, Int, Int)] = []
  let current_checks = Ref(0)
  let available = Ref(true)
  let accept = (b, n, d) => {
    charges.push((b, n, d))
    true
  }
  let original = () => {
    current_checks.val += 1
    available.val
  }
  assert_true(
    capture_client_effect_publication_dependency(
      "acquisition_scope",
      contract,
      bytes - 1,
      nodes,
      depth,
      Some(accept),
      original,
    )
    is Err(Dependency(@publication.ByteLimit)),
  )
  assert_true(charges.is_empty())
  assert_eq(current_checks.val, 0)
  assert_true(
    capture_client_effect_publication_dependency(
      "acquisition_scope",
      contract,
      bytes,
      nodes,
      depth,
      Some((_, _, _) => false),
      original,
    )
    is Err(ConstructionRefused),
  )
  assert_eq(current_checks.val, 0)
  assert_true(
    capture_client_effect_publication_dependency(
      "acquisition_scope",
      contract,
      bytes,
      nodes,
      depth,
      Some((b, n, d) => {
        available.val = false
        accept(b, n, d)
      }),
      original,
    )
    is Err(ForeignInput),
  )
  assert_eq(current_checks.val, 1)
  available.val = true
  let (body, charged) = capture_client_effect_publication_dependency(
    "acquisition_scope",
    contract,
    bytes,
    nodes,
    depth,
    Some(accept),
    original,
  ).unwrap()
  assert_eq(charges, [(bytes, nodes, depth), (bytes, nodes, depth)])
  assert_eq(current_checks.val, 2)
  assert_eq(charged, bytes)
  assert_eq(
    @publication.captured_effect_dependency_body_json(body),
    @publication.publication_contract_json(contract),
  )
  assert_eq(
    @publication.captured_effect_dependency_body_cid(body),
    @publication.publication_contract_identity(contract),
  )
  assert_eq(
    @publication.captured_effect_dependency_body_references(body, 2),
    Some([("source_contract", source), ("request_values", request)]),
  )
}

///|
test "original LocalContracts funds the same 2791 bytes with 40 nodes and depth 2" {
  let writer = @encode.writer(10000, 100, 16)
  @encode.begin_object(writer)
  @encode.key(writer, "contracts")
  @encode.begin_array(writer)
  for index in 1..<=37 {
    let number = index.to_string()
    @encode.string_value(
      writer,
      "sha256:" + "0".repeat(64 - number.length()) + number,
    )
  }
  @encode.end_array(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-local-contracts/0.1")
  @encode.end_object(writer)
  let (wire, bytes, nodes, depth) = @encode.finish_text_usage(writer)
  assert_eq((bytes, nodes, depth), (2791, 40, 2))
  let cid = "sha256:6bb6fc58f3cecbc07db4220a007d6bd7fb2f0a714c1e60e127141b2c6caa354b"
  let fund = (b : Int, n : Int, d : Int) => b == 2791 && n == 40 && d == 2
  assert_true(
    admit_client_effect_dependency_capture_body(
      "local_contracts",
      Some(cid),
      wire,
      10000,
      10000,
      100,
      Some(fund),
      () => true,
    )
    is Err(ConstructionRefused),
  )
  let (body, bytes) = admit_client_effect_dependency_capture_body(
    "local_contracts",
    Some(cid),
    wire,
    10000,
    10000,
    100,
    Some(fund),
    () => true,
    wire_extent=Some((bytes, nodes)),
    wire_depth=Some(depth),
    enforce_extent=true,
  ).unwrap()
  assert_eq(bytes, 2791)
  assert_eq(@publication.captured_effect_dependency_body_json(body), wire)
  assert_eq(@publication.captured_effect_dependency_body_cid(body), cid)
}

///|
test "funded Relation dependency includes the wrapper before construction" {
  let rows = "[{\"id\":\"雪\"}]"
  let wire = "{\"sort\":\"relation\",\"value\":[{\"id\":\"雪\"}]}"
  let cid = "sha256:ad23cae212b01f4bc53937fc70023b972788c8145a35df63cd0ecd3f2e2f8540"
  let calls : Array[(Int, Int, Int)] = []
  let original_checks = Ref(0)
  let current = Ref(true)
  let limit = Ref(42)
  let before = (bytes, nodes, depth) => {
    calls.push((bytes, nodes, depth))
    bytes <= limit.val
  }
  let original = () => {
    original_checks.val += 1
    current.val
  }
  let admit = budget => {
    admit_client_effect_dependency_capture_body(
      "relation_value",
      Some(cid),
      rows,
      budget,
      5,
      3,
      Some(before),
      original,
      wire_extent=Some((42, 5)),
      wire_depth=Some(3),
      enforce_extent=true,
      wrap_relation_rows=true,
    )
  }
  assert_true(admit(41) is Err(Dependency(@publication.ByteLimit)))
  assert_eq(calls.length(), 0)
  limit.val = 41
  assert_true(admit(42) is Err(ConstructionRefused))
  assert_eq(original_checks.val, 0)
  limit.val = 42
  current.val = false
  assert_true(admit(42) is Err(ForeignInput))
  current.val = true
  let (body, bytes) = admit(42).unwrap()
  assert_eq(calls, [(42, 5, 3), (42, 5, 3), (42, 5, 3)])
  assert_eq(original_checks.val, 2)
  assert_eq(bytes, 42)
  assert_eq(@publication.captured_effect_dependency_body_bytes(body), 42)
  assert_eq(@publication.captured_effect_dependency_body_json(body), wire)
  assert_eq(@publication.captured_effect_dependency_body_cid(body), cid)
}
