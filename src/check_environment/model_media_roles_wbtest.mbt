///|
test "Model media role traversal has an independent exact work and node bound" {
  let wire =
    #|{"payload":{"classifications":["internal"],"complete":true,"egress_scope_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","max_bytes":4096,"max_frames":null,"max_pages":4,"media_type":"application/pdf","regions":["fixture-region"],"transfer_method":"inline_bytes"},"self_cid":"sha256:ece55a0064625c262ee09ae48b8293377848469876c77b1c19718dab759280fe","version":"actql-model-media-input/0.1"}
  let limits : Limits = {
    max_bytes: 420,
    max_nodes: 15,
    max_members: 1,
    max_depth: 10,
  }
  let original = read_model_dependency(
    ModelMediaInput("document"),
    @utf8.encode(wire),
    "sha256:ece55a0064625c262ee09ae48b8293377848469876c77b1c19718dab759280fe",
    limits,
    1615,
  ).unwrap()
  let item = @value_contract.content_reference_contract(
    Some("application/pdf"),
    nullable=true,
    max_name_bytes=15,
  ).unwrap()
  let input = @value_contract.object_contract(
    [("document", item)],
    nullable=false,
    max_fields=1,
    max_name_bytes=8,
  ).unwrap()
  // Role-map entry 9 + declared name 9 + type node 1 + MIME comparison
  // 15+15 = 49. Dependency-body work (1615) is separately bounded above.
  assert_true(
    validate_model_media_roles(
      input,
      [original],
      { ..limits, max_nodes: 1, },
      49,
    )
    is Ok(_),
  )
  assert_true(
    validate_model_media_roles(input, [original], limits, 48)
    is Err(Body(ModelMediaInput("document"), { kind: WorkLimit, .. })),
  )
  assert_true(
    validate_model_media_roles(
      input,
      [original],
      { ..limits, max_nodes: 0, },
      49,
    )
    is Err(Body(ModelMediaInput("document"), { kind: BodyLimit, .. })),
  )
  let array = @value_contract.array_contract(
    item,
    nullable=true,
    max_items=Some(2L),
  ).unwrap()
  let input = @value_contract.object_contract(
    [("document", array)],
    nullable=false,
    max_fields=1,
    max_name_bytes=8,
  ).unwrap()
  // The homogeneous item descriptor adds exactly one inspected node.
  assert_true(
    validate_model_media_roles(
      input,
      [original],
      { ..limits, max_nodes: 2, },
      50,
    )
    is Ok(_),
  )
  assert_true(
    validate_model_media_roles(input, [original], limits, 49)
    is Err(Body(ModelMediaInput("document"), { kind: WorkLimit, .. })),
  )
  assert_true(
    validate_model_media_roles(
      input,
      [original],
      { ..limits, max_nodes: 1, },
      50,
    )
    is Err(Body(ModelMediaInput("document"), { kind: BodyLimit, .. })),
  )
}
