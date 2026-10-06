// Generated from independent fixed vectors. Do not edit.

///|
test "typed JSON wire identity: null" {
  let checked = @value_admission.admit_json_literal("null", { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }).unwrap().0
  let writer = @encode.writer(10000, 1000, 100)
  @value_admission.emit_checked_wire_value(checked, writer)
  let wire = @encode.finish(writer)
  assert_eq(wire, "{\"$json\":null}")
  let canonical = @identity.from_json(@json.parse(wire), 1000, 100, 10000, data_keys=true)
  assert_eq(@identity.cid_value(canonical, 10000, 1000, 100), "sha256:aa360d94d0b538decb764fbc2de710774e1dfda38a271ee0e1c82a505cd3d771")
}

///|
test "typed JSON wire identity: boolean" {
  let checked = @value_admission.admit_json_literal("true", { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }).unwrap().0
  let writer = @encode.writer(10000, 1000, 100)
  @value_admission.emit_checked_wire_value(checked, writer)
  let wire = @encode.finish(writer)
  assert_eq(wire, "{\"$json\":true}")
  let canonical = @identity.from_json(@json.parse(wire), 1000, 100, 10000, data_keys=true)
  assert_eq(@identity.cid_value(canonical, 10000, 1000, 100), "sha256:ebcc8c9872ab3149f2cff1a9e6a0f811f3fd504ddecd147cf378e482651e7a56")
}

///|
test "typed JSON wire identity: number" {
  let checked = @value_admission.admit_json_literal("1.5", { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }).unwrap().0
  let writer = @encode.writer(10000, 1000, 100)
  @value_admission.emit_checked_wire_value(checked, writer)
  let wire = @encode.finish(writer)
  assert_eq(wire, "{\"$json\":1.5}")
  let canonical = @identity.from_json(@json.parse(wire), 1000, 100, 10000, data_keys=true)
  assert_eq(@identity.cid_value(canonical, 10000, 1000, 100), "sha256:96b7dfc3ad84543b5db520f81522f1e0f0e5cd467f5a356d3f5a249432f20d31")
}

///|
test "typed JSON wire identity: string" {
  let checked = @value_admission.admit_json_literal("\"x\"", { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }).unwrap().0
  let writer = @encode.writer(10000, 1000, 100)
  @value_admission.emit_checked_wire_value(checked, writer)
  let wire = @encode.finish(writer)
  assert_eq(wire, "{\"$json\":\"x\"}")
  let canonical = @identity.from_json(@json.parse(wire), 1000, 100, 10000, data_keys=true)
  assert_eq(@identity.cid_value(canonical, 10000, 1000, 100), "sha256:275255d222f15f030ac5a71592a0467f0aced782968a5c38aa801af671408705")
}

///|
test "typed JSON wire identity: array" {
  let checked = @value_admission.admit_json_literal("[null,1]", { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }).unwrap().0
  let writer = @encode.writer(10000, 1000, 100)
  @value_admission.emit_checked_wire_value(checked, writer)
  let wire = @encode.finish(writer)
  assert_eq(wire, "{\"$json\":[null,1]}")
  let canonical = @identity.from_json(@json.parse(wire), 1000, 100, 10000, data_keys=true)
  assert_eq(@identity.cid_value(canonical, 10000, 1000, 100), "sha256:df8666272b216c22231d08fb96fd452359ee635b4b9d63aff7d9aaf50ad82601")
}

///|
test "typed JSON wire identity: object" {
  let checked = @value_admission.admit_json_literal("{\"k\":null}", { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }).unwrap().0
  let writer = @encode.writer(10000, 1000, 100)
  @value_admission.emit_checked_wire_value(checked, writer)
  let wire = @encode.finish(writer)
  assert_eq(wire, "{\"$json\":{\"k\":null}}")
  let canonical = @identity.from_json(@json.parse(wire), 1000, 100, 10000, data_keys=true)
  assert_eq(@identity.cid_value(canonical, 10000, 1000, 100), "sha256:9ed71d4590342a34d015a7916b0bb7bbe017fa42ee85a2967082659f8a2f8cc4")
}

///|
test "typed JSON wire identity: duplicate-first" {
  let checked = @value_admission.admit_json_literal("{\"a\":1,\"a\":2}", { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }).unwrap().0
  let writer = @encode.writer(10000, 1000, 100)
  @value_admission.emit_checked_wire_value(checked, writer)
  let wire = @encode.finish(writer)
  assert_eq(wire, "{\"$json\":{\"a\":1}}")
  let canonical = @identity.from_json(@json.parse(wire), 1000, 100, 10000, data_keys=true)
  assert_eq(@identity.cid_value(canonical, 10000, 1000, 100), "sha256:9d25f323f3b8b1ab7a41327dc14abd754e8d5876fc1db1eb7bca0b1778e12514")
}

///|
test "typed JSON wire identity: tag-is-data" {
  let checked = @value_admission.admit_json_literal("{\"$json\":null}", { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }).unwrap().0
  let writer = @encode.writer(10000, 1000, 100)
  @value_admission.emit_checked_wire_value(checked, writer)
  let wire = @encode.finish(writer)
  assert_eq(wire, "{\"$json\":{\"$json\":null}}")
  let canonical = @identity.from_json(@json.parse(wire), 1000, 100, 10000, data_keys=true)
  assert_eq(@identity.cid_value(canonical, 10000, 1000, 100), "sha256:02ed4c7beb6613df21f71514bb9d4dc4ad28c9cc1b1497f04b2ec6406a872b6a")
}

///|
test "typed JSON wire identity: unicode-keys" {
  let checked = @value_admission.admit_json_literal("{\"\u{e9}\":1,\"e\\u0301\":2}", { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }).unwrap().0
  let writer = @encode.writer(10000, 1000, 100)
  @value_admission.emit_checked_wire_value(checked, writer)
  let wire = @encode.finish(writer)
  assert_eq(wire, "{\"$json\":{\"e\u{301}\":2,\"\u{e9}\":1}}")
  let canonical = @identity.from_json(@json.parse(wire), 1000, 100, 10000, data_keys=true)
  assert_eq(@identity.cid_value(canonical, 10000, 1000, 100), "sha256:ae31ee7e369e869996dfc4293a638c8c635e283b8a254a9a9236765cf1c9d1b1")
}

///|
test "typed JSON wire identity: crlf" {
  let checked = @value_admission.admit_json_literal("\"\\r\\n\"", { max_nodes: 1000, max_depth: 100, max_text_bytes: 10000, }).unwrap().0
  let writer = @encode.writer(10000, 1000, 100)
  @value_admission.emit_checked_wire_value(checked, writer)
  let wire = @encode.finish(writer)
  assert_eq(wire, "{\"$json\":\"\\r\\n\"}")
  let canonical = @identity.from_json(@json.parse(wire), 1000, 100, 10000, data_keys=true)
  assert_eq(@identity.cid_value(canonical, 10000, 1000, 100), "sha256:9257b47ad4078cbb2778923bbc94d551b8cf19806014426497f003a925a79f6f")
}
