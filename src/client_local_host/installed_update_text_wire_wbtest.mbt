///|
fn installed_update_text_test_wire(
  value : Json,
  extent : InstalledUpdateTextWireExtent,
) -> (String, String) raise {
  let writer = @encode.writer(extent.bytes.to_int(), 32, 4)
  @encode.emit_json(value, writer)
  let wire = @encode.finish(writer)
  assert_eq(wire.length().to_int64(), extent.utf16_units)
  assert_eq(@utf8.encode(wire).length().to_int64(), extent.bytes)
  let hasher = @encode.hashing_writer(extent.bytes.to_int(), 32, 4)
  @encode.emit_json(value, hasher)
  (wire, "sha256:" + @encode.finish_hash(hasher))
}

///|
test "nullable UPDATE quotes explicit null with its own request and recovery identity" {
  let extent = installed_update_text_wire_extents(
    "ticket_key",
    "memo",
    "ac-7",
    "",
    "tickets",
    "boundary",
    "effect",
    1,
    "mapping",
    explicit_null=true,
  ).unwrap()
  let (body, _) = installed_update_text_test_wire(
    { "memo": Json::null() },
    extent.body,
  )
  assert_eq(body, "{\"memo\":null}")
  let (_, preimage_cid) = installed_update_text_test_wire(
    {
      "body": body,
      "boundaryCid": "boundary",
      "memo": Json::null(),
      "ticket_key": "ac-7",
      "version": "tickets",
    },
    extent.request_cid_preimage,
  )
  ignore(
    installed_update_text_test_wire(
      { "body": body, "memo": Json::null(), "ticket_key": "ac-7" },
      extent.request,
    ),
  )
  let (recovery, recovery_cid) = installed_update_text_test_wire(
    ["boundary", ["effect", 1, "mapping"], "ac-7", Json::null()],
    extent.recovery,
  )
  let (body_cap, request_cap, preimage_cap, recovery_cap) = (
    extent.body.bytes.to_int(),
    extent.request.bytes.to_int(),
    extent.request_cid_preimage.bytes.to_int(),
    extent.recovery.bytes.to_int(),
  )
  let constructed = construct_installed_update_text_request(
    "ticket_key",
    "memo",
    "ac-7",
    "",
    "tickets",
    "boundary",
    body_cap,
    request_cap,
    preimage_cap,
    explicit_null=true,
  ).unwrap()
  assert_eq(constructed.body, body)
  assert_eq(constructed.request_cid, preimage_cid)
  assert_eq(
    construct_installed_update_text_recovery(
      "boundary",
      "effect",
      1,
      "mapping",
      "ac-7",
      "",
      recovery_cap,
      explicit_null=true,
    ),
    Some((recovery, recovery_cid)),
  )
  for
    (b, r, p) in [
      (body_cap - 1, request_cap, preimage_cap),
      (body_cap, request_cap - 1, preimage_cap),
      (body_cap, request_cap, preimage_cap - 1),
    ] {
    assert_true(
      construct_installed_update_text_request(
        "ticket_key",
        "memo",
        "ac-7",
        "",
        "tickets",
        "boundary",
        b,
        r,
        p,
        explicit_null=true,
      )
      is None,
    )
  }
  assert_true(
    construct_installed_update_text_recovery(
      "boundary",
      "effect",
      1,
      "mapping",
      "ac-7",
      "",
      recovery_cap - 1,
      explicit_null=true,
    )
    is None,
  )
  assert_true(
    construct_installed_update_text_recovery(
      "boundary",
      "effect",
      1,
      "mapping",
      "ac-7",
      "null",
      recovery_cap,
      explicit_null=true,
    )
    is None,
  )
}

///|
test "standard UPDATE quotes exact escaped body request CID and historic recovery independently" {
  let target = "a".repeat(32)
  let note = "\u0001".repeat(64)
  let domain = "external-event-update"
  let boundary = "sha256:" + "f".repeat(64)
  let mapping = "sha256:" + "c".repeat(64)
  let effect = "a".repeat(128)
  let extent = installed_update_text_wire_extents(
    "id", "note", target, note, domain, boundary, effect, 0, mapping,
  ).unwrap()
  assert_eq(
    installed_update_text_request_bounds("id", "note", domain, boundary, 32, 64),
    Some((395, 908, 1030)),
  )
  assert_eq(extent.body, { bytes: 395L, utf16_units: 395L, })
  assert_eq(extent.request, { bytes: 908L, utf16_units: 908L, })
  assert_eq(extent.request_cid_preimage, { bytes: 1030L, utf16_units: 1030L, })
  assert_eq(extent.recovery, { bytes: 706L, utf16_units: 706L, })
  assert_true(installed_update_text_wire_fits(extent, 395L, 908L, 1030L, 706L))
  for
    (body, request, preimage, recovery) in [
      (394L, 908L, 1030L, 706L),
      (395L, 907L, 1030L, 706L),
      (395L, 908L, 1029L, 706L),
      (395L, 908L, 1030L, 705L),
    ] {
    assert_false(
      installed_update_text_wire_fits(extent, body, request, preimage, recovery),
    )
  }
  let (body, body_cid) = installed_update_text_test_wire(
    { "note": note },
    extent.body,
  )
  let (_, request_cid) = installed_update_text_test_wire(
    { "body": body, "id": target, "note": note },
    extent.request,
  )
  let (_, preimage_cid) = installed_update_text_test_wire(
    {
      "body": body,
      "boundaryCid": boundary,
      "id": target,
      "note": note,
      "version": domain,
    },
    extent.request_cid_preimage,
  )
  let (recovery_wire, recovery_cid) = installed_update_text_test_wire(
    [boundary, [effect, 0, mapping], target, note],
    extent.recovery,
  )
  let request = construct_installed_update_text_request(
    "id", "note", target, note, domain, boundary, 395, 908, 1030,
  ).unwrap()
  assert_eq(request.body, body)
  assert_eq(request.request_cid, preimage_cid)
  assert_eq(
    construct_installed_update_text_recovery(
      boundary, effect, 0, mapping, target, note, 706,
    ),
    Some((recovery_wire, recovery_cid)),
  )
  for
    (body, request, preimage) in [
      (394, 908, 1030),
      (395, 907, 1030),
      (395, 908, 1029),
    ] {
    assert_true(
      construct_installed_update_text_request(
        "id", "note", target, note, domain, boundary, body, request, preimage,
      )
      is None,
    )
  }
  assert_true(
    construct_installed_update_text_recovery(
      boundary, effect, 0, mapping, target, note, 705,
    )
    is None,
  )
  assert_true(
    construct_installed_update_text_request(
      "id", "body", target, note, domain, boundary, 395, 908, 1030,
    )
    is None,
  )
  assert_eq(
    body_cid, "sha256:b5d3717e1f0277fd9eab6b04eb806042613ade6b499728b26b2f80cc135a600c",
  )
  assert_eq(
    request_cid, "sha256:23c6da9b0ed912a72b02f9969cee63b5d5b015ea5d862496a17e621fc4bee04b",
  )
  assert_eq(
    preimage_cid, "sha256:c3d07198ad25b08a5e33022451d8bf0a00e07a7e761c6ec13c063c4561b2f735",
  )
  assert_eq(
    recovery_cid, "sha256:a87ccd569db1dce1ce201bb649e5fb7c952eea754cbb8b82a5b39c297f5512d0",
  )
}

///|
test "standard UPDATE quote preserves short escapes Unicode and actual recovery ordinal" {
  let target = "œ😀"
  let note = "\"\\\n日e\u0301"
  let extent = installed_update_text_wire_extents(
    "id", "note", target, note, "domain", "boundary", "effect", 127, "mapping",
  ).unwrap()
  let (body, _) = installed_update_text_test_wire({ "note": note }, extent.body)
  ignore(
    installed_update_text_test_wire(
      { "body": body, "id": target, "note": note },
      extent.request,
    ),
  )
  ignore(
    installed_update_text_test_wire(
      {
        "body": body,
        "boundaryCid": "boundary",
        "id": target,
        "note": note,
        "version": "domain",
      },
      extent.request_cid_preimage,
    ),
  )
  ignore(
    installed_update_text_test_wire(
      ["boundary", ["effect", 127, "mapping"], target, note],
      extent.recovery,
    ),
  )
  assert_true(extent.request.bytes > extent.request.utf16_units)
}
