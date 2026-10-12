///|
fn content_test_schema(conditional? : Bool = false) -> @schema.Schema {
  @schema.from_presence_fields(
    [
      (
        @schema.Unqualified("id"),
        @contract.primitive(@contract.NumberType, nullable=false),
        @schema.Required,
      ),
      (
        @schema.Unqualified("value"),
        @contract.primitive(@contract.StringType, nullable=true),
        if conditional {
          @schema.Conditional
        } else {
          @schema.Required
        },
      ),
    ],
    max_fields=2,
    max_name_bytes=64,
  ).unwrap()
}

///|
fn content_test_limits() -> ContentProfileLimits {
  {
    max_fields: 10,
    max_name_bytes: 256,
    max_work: 1000,
    max_options_bytes: 4096,
    max_options_nodes: 100,
    max_options_depth: 8,
  }
}

///|
fn content_test_profile(
  format : ContentFormat,
  options : String,
  conditional? : Bool = false,
) -> ContentSerializationProfile {
  prepare_content_serialization_profile(
    format,
    content_test_schema(conditional~),
    ["id", "value"],
    options,
    content_test_limits(),
  ).unwrap()
}

///|
fn content_test_encoder(
  profile : ContentSerializationProfile,
  bytes? : Int = 4096,
) -> ContentByteEncoder {
  start_content_byte_encoder(
    profile,
    max_rows=10,
    max_bytes=bytes,
    max_value_nodes=100,
    max_value_depth=8,
    max_frames=20,
  ).unwrap()
}

///|
fn drain_content_test(
  owner : ContentByteEncoder,
  quantum : Int,
) -> (String, Int) raise {
  let output = StringBuilder()
  let mut work = 0
  for _ in 0..<10000 {
    match advance_content_bytes(owner, quantum) {
      ContentBytesContinue(piece, work=used) => {
        assert_true(used > 0 && used <= quantum)
        output.write_string(piece)
        work += used
      }
      ContentBytesReady(piece, work=used) => {
        output.write_string(piece)
        work += used
        return (output.to_string(), work)
      }
      ContentBytesFailed(_, ..) => abort("unexpected content byte failure")
    }
  }
  abort("bounded content fixture did not complete")
}

///|
fn content_test_row(
  owner : ContentByteEncoder,
  id : Int,
  value : String?,
) -> Unit {
  let schema = content_test_schema()
  let id_contract = @schema.field_at(schema, 0).unwrap().contract
  let value_contract = @schema.field_at(schema, 1).unwrap().contract
  let id_value = @admitted.checked_number_value(id.to_double(), id_contract).unwrap()
  let content_value = match value {
    None => @admitted.checked_null_value(value_contract).unwrap()
    Some(text) =>
      @admitted.recheck_runtime_value(
        @admitted.text_value(text, 4096).unwrap(),
        value_contract,
        { max_nodes: 1, max_depth: 0, max_text_bytes: 4096, },
      ).unwrap()
  }
  start_content_byte_row(owner, column => {
    if column == 0 {
      Some(id_value)
    } else {
      Some(content_value)
    }
  }).unwrap()
}

///|
test "Content runtime rows retain absence NULL values and quantum invariant work" {
  let expected = "{\"id\":1}\n{\"id\":2,\"value\":null}\n{\"id\":3,\"value\":\"ok\"}\n"
  let mut total : Int? = None
  for quantum in [1, 7, 64] {
    let profile = content_test_profile(
      ContentJsonl,
      "{\"name\":\"sparse.jsonl\"}",
      conditional=true,
    )
    let encoder = content_test_encoder(profile)
    let output = StringBuilder()
    let (header, initial) = drain_content_test(encoder, quantum)
    output.write_string(header)
    let mut work = initial
    for index in 0..<3 {
      start_content_runtime_row(
        encoder,
        column => {
          if column == 0 {
            ContentPresent(
              @admitted.number_value((index + 1).to_double()).unwrap(),
            )
          } else if index == 0 {
            ContentAbsent
          } else if index == 1 {
            ContentPresent(@admitted.null_value())
          } else {
            ContentText("ok")
          }
        },
        () => true,
      ).unwrap()
      let (piece, used) = drain_content_test(encoder, quantum)
      work += used
      output.write_string(piece)
    }
    assert_eq(output.to_string(), expected)
    let completion = finish_content_bytes(encoder).unwrap()
    assert_eq(completion.row_count, 3)
    assert_eq(completion.size_bytes, @utf8.encode(expected).length())
    if total is Some(value) {
      assert_eq(work, value)
    } else {
      total = Some(work)
    }
  }
}

///|
test "Content runtime read failure and mid-row retirement are not absence" {
  let profile = content_test_profile(
    ContentJsonl,
    "{\"name\":\"sparse.jsonl\"}",
    conditional=true,
  )
  let encoder = content_test_encoder(profile)
  ignore(drain_content_test(encoder, 1))
  start_content_runtime_row(encoder, _ => ContentInputUnavailable, () => true).unwrap()
  ignore(advance_content_bytes(encoder, 1)) // opening object
  assert_true(
    advance_content_bytes(encoder, 1)
    is ContentBytesFailed(ContentInputUnavailableIssue, work=1),
  )
  assert_true(
    finish_content_bytes(encoder) is Err(ContentInputUnavailableIssue),
  )
  let encoder = content_test_encoder(profile)
  ignore(drain_content_test(encoder, 1))
  let live = Ref(true)
  start_content_runtime_row(
    encoder,
    _ => ContentPresent(@admitted.null_value()),
    () => live.val,
  ).unwrap()
  ignore(advance_content_bytes(encoder, 1))
  live.val = false
  assert_true(
    advance_content_bytes(encoder, 1)
    is ContentBytesFailed(ContentInputUnavailableIssue, work=0),
  )
  assert_true(
    finish_content_bytes(encoder) is Err(ContentInputUnavailableIssue),
  )
  cancel_content_byte_encoder(encoder)
  assert_true(
    finish_content_bytes(encoder) is Err(ContentInputUnavailableIssue),
  )
}

///|
test "Content CSV generates independent 55-byte golden across quanta" {
  let profile = content_test_profile(
    ContentCsv,
    "{\"name\":\"data.csv\",\"header\":true,\"null_marker\":\"\\\\N\",\"line_ending\":\"crlf\"}",
  )
  let expected = "id,value\r\n1,\"a,b\"\r\n2,\"\"\r\n3,\\N\r\n4,\"\\N\"\r\n5,\"say \"\"hi\"\"\"\r\n"
  // Independent reviewed vector: framing is intentionally unlike Result CSV.
  assert_eq(@utf8.encode(expected).length(), 55)
  let mut baseline : Int? = None
  for quantum in [1, 7, 64] {
    let owner = content_test_encoder(profile, bytes=55)
    let output = StringBuilder()
    let (header, initial_work) = drain_content_test(owner, quantum)
    let mut work = initial_work
    output.write_string(header)
    for
      index, value in [
        Some("a,b"),
        Some(""),
        None,
        Some("\\N"),
        Some("say \"hi\""),
      ] {
      content_test_row(owner, index + 1, value)
      let (piece, used) = drain_content_test(owner, quantum)
      output.write_string(piece)
      work += used
    }
    assert_eq(output.to_string(), expected)
    let complete = finish_content_bytes(owner).unwrap()
    assert_eq(complete.size_bytes, 55)
    assert_eq(complete.row_count, 5)
    // 23 header/framing transitions, 15 + 12 + 13 + 14 + 20 row units.
    // Unlike the quantum comparison, this independent total detects omitted
    // field admission, framing or scalar escape accounting.
    assert_eq(work, 97)
    assert_eq(
      complete.content_cid,
      "sha256:aa2bb909ccb50ddaf18f1d13f8d21ba63debd305896032eb072aefbcc0e250e5",
    )
    if baseline is Some(expected_work) {
      assert_eq(work, expected_work)
    } else {
      baseline = Some(work)
    }
    assert_true(finish_content_bytes(owner) is Err(ContentClosed))
  }
}

///|
fn content_value_cursor(wire : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 8192,
      max_nodes: 200,
      max_depth: 16,
    }).unwrap(),
    {
      max_nodes: 200,
      max_depth: 16,
      max_string_bytes: 4096,
      max_total_string_bytes: 8192,
    },
  ).unwrap()
}

///|
test "Content nested typed JSON exact decimals and special headers share common emitters" {
  let decimal = @contract.decimal_contract(4, 2, nullable=false).unwrap()
  let json = @contract.primitive(@contract.JsonType, nullable=false)
  let schema = @schema.from_fields(
    [(@schema.Unqualified("a,b"), decimal), (@schema.Unqualified("q\"x"), json)],
    max_fields=2,
    max_name_bytes=64,
  ).unwrap()
  let amount = @admitted.admit(decimal, content_value_cursor("\"-1.20\""), {
    max_nodes: 1,
    max_depth: 0,
    max_text_bytes: 32,
  }).unwrap()
  let data = @admitted.admit(
    json,
    content_value_cursor("{\"e\\u0301\":[1,null,\"x\"]}"),
    { max_nodes: 20, max_depth: 4, max_text_bytes: 128, },
  ).unwrap()
  for
    (format, expected) in [
      (
        ContentCsv,
        "\"q\"\"x\",\"a,b\"\n\"{\"\"$json\"\":{\"\"e\u{301}\"\":[1,null,\"\"x\"\"]}}\",-1.20\n",
      ),
      (
        ContentJsonl,
        "{\"q\\\"x\":{\"$json\":{\"e\u{301}\":[1,null,\"x\"]}},\"a,b\":\"-1.20\"}\n",
      ),
    ] {
    let options = if format == ContentCsv {
      "{\"name\":\"nested\",\"header\":true,\"null_marker\":\"\"}"
    } else {
      "{\"name\":\"nested\"}"
    }
    let profile = prepare_content_serialization_profile(
      format,
      schema,
      ["q\"x", "a,b"],
      options,
      content_test_limits(),
    ).unwrap()
    for quantum in [1, 7, 64] {
      let owner = content_test_encoder(
        profile,
        bytes=@utf8.encode(expected).length(),
      )
      let before = drain_content_test(owner, quantum).0
      start_content_byte_row(owner, column => {
        if column == 0 {
          Some(amount)
        } else {
          Some(data)
        }
      }).unwrap()
      let after = drain_content_test(owner, quantum).0
      assert_eq(before + after, expected)
      assert_eq(
        finish_content_bytes(owner).unwrap().size_bytes,
        @utf8.encode(expected).length(),
      )
    }
  }
}

///|
test "Content row cap empty and live cancellation do not grant completion" {
  let profile = content_test_profile(ContentJsonl, "{\"name\":\"x\"}")
  let zero = start_content_byte_encoder(
    profile,
    max_rows=0,
    max_bytes=0,
    max_value_nodes=10,
    max_value_depth=4,
    max_frames=10,
  ).unwrap()
  ignore(drain_content_test(zero, 1))
  let called = Ref(false)
  assert_true(
    start_content_byte_row(zero, _ => {
      called.val = true
      None
    })
    is Err(ContentRowLimit),
  )
  assert_false(called.val)
  assert_true(finish_content_bytes(zero) is Err(ContentRowLimit))
  let owner = content_test_encoder(profile)
  ignore(drain_content_test(owner, 1))
  content_test_row(owner, 1, Some(String::make(1000, 'x')))
  let mut progressed = false
  for _ in 0..<50 {
    ignore(advance_content_bytes(owner, 1))
    if owner.wire is Some(_) && owner.bytes > 80 {
      progressed = true
      break
    }
  }
  assert_true(progressed)
  let before = owner.bytes
  cancel_content_byte_encoder(owner)
  assert_true(owner.wire is None && owner.writer is None && owner.cells is None)
  assert_true(finish_content_bytes(owner) is Err(ContentClosed))
  assert_true(
    advance_content_bytes(owner, 1) is ContentBytesFailed(ContentClosed, work=0),
  )
  cancel_content_byte_encoder(owner)
  assert_eq(owner.bytes, before)
}

///|
test "Content canonical reference cells preserve envelope and reject revoked authority" {
  // An existing independent ContentRef fixture, not an envelope manufactured
  // from the byte encoder or permission obtained from parsing alone.
  let wire = "{\"$actql_ref\":\"content\",\"content_ref_cid\":\"sha256:15e902418023a2de574d29d716f3b643825e19afa1fa3a5a46e049ffb1606eff\",\"media_type\":\"application/json\",\"metadata\":{\"availability_evidence_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"capture_authority\":\"read_content\",\"content_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"content_store_id\":\"fixture\",\"data_classification\":\"internal\",\"effective_data_policy_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"issuer_evidence\":{},\"media_type\":\"application/json\",\"retention_class\":\"fixture\",\"size_bytes\":3,\"storage_scope\":\"workspace\",\"truncated\":false},\"version\":\"actql-content-ref/0.1\"}"
  let contract = @contract.read_author(
    content_value_cursor(
      "{\"type\":\"content_ref\",\"nullable\":false,\"media_type\":\"application/json\"}",
    ),
    { max_nodes: 10, max_depth: 2, max_text_bytes: 100, },
  ).unwrap()
  let schema = @schema.from_fields(
    [(@schema.Unqualified("content"), contract)],
    max_fields=1,
    max_name_bytes=32,
  ).unwrap()
  let profile = prepare_content_serialization_profile(
    ContentJsonl,
    schema,
    ["content"],
    "{\"name\":\"reference.jsonl\"}",
    content_test_limits(),
  ).unwrap()
  let live = Ref(true)
  let issuances = Ref(0)
  let issuer = @admitted.bind_reference_issuer(
    (_, candidate) => {
      issuances.val += 1
      candidate == wire
    },
    _ => live.val,
  )
  let checked = @admitted.issue_reference(issuer, contract, wire, {
    max_bytes: 2048,
    max_nodes: 100,
    max_depth: 8,
    max_text_units: 4096,
  }).unwrap()
  let owner = content_test_encoder(profile)
  ignore(drain_content_test(owner, 1))
  start_content_byte_row(owner, _ => Some(checked)).unwrap()
  assert_eq(drain_content_test(owner, 1).0, "{\"content\":" + wire + "}\n")
  ignore(finish_content_bytes(owner).unwrap())
  assert_eq(issuances.val, 1) // Serialization never reissues or dereferences it.
  let revoked = content_test_encoder(profile)
  ignore(drain_content_test(revoked, 1))
  start_content_byte_row(revoked, _ => Some(checked)).unwrap()
  live.val = false
  let mut rejected = false
  for _ in 0..<100 {
    match advance_content_bytes(revoked, 1) {
      ContentBytesFailed(ContentReferenceUnavailable, ..) => {
        rejected = true
        break
      }
      ContentBytesFailed(_, ..) => abort("wrong reference refusal")
      _ => ()
    }
  }
  assert_true(rejected)
  assert_true(finish_content_bytes(revoked) is Err(ContentReferenceUnavailable))
  assert_eq(issuances.val, 1)
}

///|
test "Content JSONL preserves missing NULL and values without normalization" {
  let profile = content_test_profile(
    ContentJsonl,
    "{\"name\":\"data.jsonl\"}",
    conditional=true,
  )
  for quantum in [1, 7, 64] {
    let owner = content_test_encoder(profile)
    assert_eq(drain_content_test(owner, quantum).0, "")
    content_test_row(owner, 1, Some("e\u{301}\r\n"))
    assert_eq(
      drain_content_test(owner, quantum).0,
      "{\"id\":1,\"value\":\"e\u{301}\\r\\n\"}\n",
    )
    content_test_row(owner, 2, None)
    assert_eq(
      drain_content_test(owner, quantum).0,
      "{\"id\":2,\"value\":null}\n",
    )
    let id = @admitted.checked_number_value(
      3.0,
      @contract.primitive(@contract.NumberType, nullable=false),
    ).unwrap()
    start_content_byte_row(owner, column => {
      if column == 0 {
        Some(id)
      } else {
        None
      }
    }).unwrap()
    assert_eq(drain_content_test(owner, quantum).0, "{\"id\":3}\n")
    assert_eq(finish_content_bytes(owner).unwrap().row_count, 3)
  }
}

///|
test "Content options reject absent CSV requirements legacy names and Conditional input" {
  for
    (wire, expected) in [
      ("{\"name\":\"x\",\"null_marker\":\"\"}", ContentMissingOption("header")),
      ("{\"name\":\"x\",\"header\":false}", ContentMissingOption("null_marker")),
      (
        "{\"name\":\"x\",\"header\":false,\"null_marker\":\"NULL\"}",
        ContentInvalidOption("null_marker"),
      ),
      (
        "{\"name\":\"x\",\"header\":false,\"null_marker\":\"\",\"field_delimiter\":\"|\"}",
        ContentInvalidOption("field_delimiter"),
      ),
      ("{\"name\":\"x\",\"csv\":{}}", ContentUnknownOption("csv")),
      (
        "{\"name\":\"x\",\"logical_name\":\"y\"}",
        ContentUnknownOption("logical_name"),
      ),
    ] {
    guard prepare_content_serialization_profile(
        ContentCsv,
        content_test_schema(),
        ["id", "value"],
        wire,
        content_test_limits(),
      )
      is Err(actual) else {
      abort("invalid content options accepted")
    }
    assert_eq(actual, expected)
  }
  assert_true(
    prepare_content_serialization_profile(
      ContentCsv,
      content_test_schema(conditional=true),
      ["id", "value"],
      "{\"name\":\"x\",\"header\":false,\"null_marker\":\"\"}",
      content_test_limits(),
    )
    is Err(ContentConditionalCsv("value")),
  )
  assert_true(
    prepare_content_serialization_profile(
      ContentJsonl,
      content_test_schema(),
      ["id"],
      "{\"name\":\"x\",\"header\":false}",
      content_test_limits(),
    )
    is Err(ContentUnknownOption("header")),
  )
}

///|
test "Content uppercase profile tokens resolve commonly without normalizing data" {
  for (encoding, ending) in [("UTF-8", "CRLF"), ("utf-8", "crlf")] {
    let profile = content_test_profile(
      ContentCsv,
      "{\"name\":\"e\\u0301.csv\",\"header\":true,\"null_marker\":\"\\\\N\",\"encoding\":\"" +
      encoding +
      "\",\"line_ending\":\"" +
      ending +
      "\"}",
    )
    assert_eq(profile.name, "e\u0301.csv")
    let encoder = content_test_encoder(profile)
    assert_eq(drain_content_test(encoder, 1).0, "id,value\r\n")
    content_test_row(encoder, 1, Some("e\u0301\r\n"))
    assert_eq(drain_content_test(encoder, 7).0, "1,\"e\u0301\r\n\"\r\n")
    content_test_row(encoder, 2, None)
    assert_eq(drain_content_test(encoder, 7).0, "2,\\N\r\n")
  }
  let encoder = content_test_encoder(
    content_test_profile(
      ContentJsonl,
      "{\"name\":\"empty\",\"encoding\":\"UTF-8-BOM\",\"line_ending\":\"LF\"}",
    ),
  )
  assert_eq(drain_content_test(encoder, 1).0, "\u{feff}")
  assert_eq(finish_content_bytes(encoder).unwrap().row_count, 0)
}

///|
test "Content empty BOM header delimiter and ordinary string byte laws" {
  for
    (format, wire, expected) in [
      (ContentCsv, "{\"name\":\"x\",\"header\":false,\"null_marker\":\"\"}", ""),
      (
        ContentCsv,
        "{\"name\":\"x\",\"header\":true,\"null_marker\":\"\",\"field_delimiter\":\";\",\"encoding\":\"utf-8-bom\"}",
        "\u{feff}id;value\n",
      ),
      (
        ContentJsonl,
        "{\"name\":\"x\",\"encoding\":\"utf-8-bom\",\"line_ending\":\"crlf\"}",
        "\u{feff}",
      ),
    ] {
    let owner = content_test_encoder(
      content_test_profile(format, wire),
      bytes=@utf8.encode(expected).length(),
    )
    assert_eq(drain_content_test(owner, 1).0, expected)
    let complete = finish_content_bytes(owner).unwrap()
    assert_eq(complete.row_count, 0)
    assert_eq(complete.size_bytes, @utf8.encode(expected).length())
  }
  let owner = content_test_encoder(
    content_test_profile(
      ContentCsv,
      "{\"name\":\"x\",\"header\":false,\"null_marker\":\"\",\"field_delimiter\":\";\"}",
    ),
  )
  ignore(drain_content_test(owner, 7))
  content_test_row(owner, 1, Some("plain"))
  assert_eq(drain_content_test(owner, 7).0, "1;\"plain\"\n")
  content_test_row(owner, 2, Some("é😀\r\n"))
  assert_eq(drain_content_test(owner, 7).0, "2;\"é😀\r\n\"\n")
}

///|
test "Content byte one-short wrong contract missing required and cancellation never complete" {
  let profile = content_test_profile(
    ContentCsv,
    "{\"name\":\"x\",\"header\":false,\"null_marker\":\"\"}",
  )
  for mode in 0..<4 {
    let owner = content_test_encoder(
      profile,
      bytes=if mode == 0 { 4 } else { 100 },
    )
    ignore(drain_content_test(owner, 1))
    if mode == 0 {
      content_test_row(owner, 1, Some("")) // Five bytes: 1,"" plus LF.
    } else if mode == 1 {
      let wrong = @admitted.checked_text_value(
        "wrong",
        @contract.primitive(@contract.StringType, nullable=false),
      ).unwrap()
      start_content_byte_row(owner, _ => Some(wrong)).unwrap()
    } else if mode == 2 {
      start_content_byte_row(owner, _ => None).unwrap()
    } else {
      content_test_row(owner, 1, Some(String::make(1000, 'x')))
      assert_true(
        advance_content_bytes(owner, 7) is ContentBytesContinue(_, work=7),
      )
      cancel_content_byte_encoder(owner)
    }
    let mut failed = false
    for _ in 0..<100 {
      if advance_content_bytes(owner, 1) is ContentBytesFailed(_, ..) {
        failed = true
        break
      }
    }
    assert_true(failed)
    assert_true(finish_content_bytes(owner) is Err(_))
    assert_true(
      owner.cells is None &&
      owner.cell is None &&
      owner.wire is None &&
      owner.text is None,
    )
    cancel_content_byte_encoder(owner)
  }
}
