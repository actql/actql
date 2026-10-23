///|
fn submitted_input(
  wire : String,
) -> Result[LocalSubmittedPreparation, LocalPreparationIssue] {
  let env = environment()
  prepare_local_submitted_input(
    wire,
    env,
    Some(bind_local_input_context(env, [], "python.local.text").unwrap()),
    @host.client_standard_program_preparation_limits(),
  )
}

///|
test "canonical and noncanonical submitted spelling keep the same checked originals" {
  let canonical = submitted_input(
    "{\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"},\"kind\":\"aql\",\"parameters\":null}",
  ).unwrap()
  let noncanonical = submitted_input(
    " {\"parameters\":null, \"kind\":\"aql\", \"input\":{\"text\":\"SELECT 1 AS n\", \"format\":\"sql\"}} ",
  ).unwrap()
  assert_eq(
    @host.client_submitted_intent_cid(canonical.intent),
    @host.client_submitted_intent_cid(noncanonical.intent),
  )
  assert_eq(
    local_prepared_document(canonical.input),
    local_prepared_document(noncanonical.input),
  )
  let first = @host.prepared_client_identity(
    local_prepared_program(canonical.input),
  )
  let next = @host.prepared_client_identity(
    local_prepared_program(noncanonical.input),
  )
  assert_eq(first.program_definition_cid, next.program_definition_cid)
  assert_eq(first.parameter_values_cid, next.parameter_values_cid)
  assert_true(
    physical_equal(
      canonical.intent,
      local_submitted_preparation_intent(canonical),
    ),
  )
  assert_true(
    physical_equal(
      canonical.input,
      local_submitted_preparation_input(canonical),
    ),
  )
}

///|
test "submitted optional restrictions remain on the same original preparation" {
  let body = "\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"},\"parameters\":null"
  let old = submitted_input("{" + body + "}").unwrap()
  let original_cid = @host.client_submitted_intent_cid(old.intent)
  for
    (suffix, read_only, stop) in [
      (",\"readOnly\":true", true, false),
      (",\"stopBefore\":\"commit\"", false, true),
      (",\"stopBefore\":\"commit\",\"readOnly\":true", true, true),
    ] {
    let value = submitted_input("{" + body + suffix + "}").unwrap()
    assert_eq(
      @host.client_submitted_intent_requests_read_only(value.intent),
      read_only,
    )
    assert_eq(
      @host.client_submitted_intent_requests_commit_stop(value.intent),
      stop,
    )
    assert_false(
      @host.client_submitted_intent_cid(value.intent) == original_cid,
    )
    assert_eq(
      @host.prepared_client_result_count(local_prepared_program(value.input)),
      1,
    )
  }
}

///|
test "submitted restriction false null and foreign spellings refuse before preparation" {
  let body = "\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"},\"parameters\":null"
  for
    suffix in [
      ",\"readOnly\":false", ",\"readOnly\":null", ",\"readonly\":true", ",\"read_only\":true",
      ",\"stopBefore\":null",
    ] {
    assert_true(
      submitted_input("{" + body + suffix + "}")
      is Err(SubmittedInput(@host.InvalidEnvelope)),
    )
  }
}

///|
test "submitted structured Program and explicit SQL AQL share original preparation Owner" {
  for
    wire in [
      "{\"kind\":\"program\",\"input\":" + program + ",\"parameters\":null}",
      "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"},\"parameters\":null}",
      "{\"kind\":\"aql\",\"input\":{\"format\":\"aql-text\",\"text\":\"WITH seed AS (SELECT 1 AS n) FROM seed |> SELECT n |> RESULT answer\"},\"parameters\":null}",
    ] {
    let value = submitted_input(wire).unwrap()
    let prepared = local_prepared_program(
      local_submitted_preparation_input(value),
    )
    assert_eq(@host.prepared_client_result_count(prepared), 1)
    assert_true(
      @strategy.graph_task_count(@host.prepared_client_graph(prepared)) > 0,
    )
    assert_true(
      physical_equal(local_submitted_preparation_intent(value), value.intent),
    )
    assert_true(
      physical_equal(local_submitted_preparation_input(value), value.input),
    )
  }
}

///|
test "submitted intent retains original Unicode CRLF and independently fixed CID" {
  let wire = "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"/*😀*/\\r\\nSELECT 1 AS n\"},\"parameters\":null}"
  let value = submitted_input(wire).unwrap()
  // Independent hashlib over the normative sorted intent/version preimage,
  // with the exact original text and no NFC or newline normalization.
  assert_eq(
    @host.client_submitted_intent_cid(value.intent),
    "sha256:8c4f70cd1eb0bfe127f3544bceb7fb2d6f1afabdfa158cb5e6208f06f3843749",
  )
  guard local_prepared_original(value.input) is Aql(text) else {
    fail("Expected original submitted text")
  }
  assert_eq(text, "/*😀*/\r\nSELECT 1 AS n")
}

///|
test "submitted declarations bindings NULL and absence use existing typed Checker outcomes" {
  let prefix = "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT @message AS message\",\"parameterDeclarations\":{\"message\":{\"type\":\"string\"}}},\"parameters\":"
  for parameters in ["null", "{}"] {
    assert_true(
      submitted_input(prefix + parameters + "}")
      is Err(Preparation(@host.NeedsInputs(_))),
    )
  }
  for parameters in ["{\"message\":null}", "{\"message\":1}"] {
    assert_true(
      submitted_input(prefix + parameters + "}")
      is Err(Preparation(@host.Check(_))),
    )
  }
  let identities : Array[String] = []
  for encoded in ["e\\u0301", "é", "\\r", "\\n", "\\r\\n"] {
    let value = submitted_input(prefix + "{\"message\":\"" + encoded + "\"}}").unwrap()
    let cid = @host.prepared_client_identity(
        local_prepared_program(value.input),
      ).parameter_values_cid
    assert_false(identities.contains(cid))
    identities.push(cid)
  }
  assert_eq(identities.length(), 5)
}

///|
test "submitted malformed envelope and foreign replacement fields are rejected before preparation" {
  for
    wire in [
      "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"}}",
      "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\"},\"parameters\":null,\"grant\":true}",
      "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"SELECT 1 AS n\",\"replacementProgram\":{}},\"parameters\":null}",
      "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":null},\"parameters\":null}",
      "{\"kind\":\"aql\",\"input\":{\"format\":\"json\",\"text\":\"{}\"},\"parameters\":null}",
    ] {
    assert_true(
      submitted_input(wire) is Err(SubmittedInput(@host.InvalidEnvelope)),
    )
  }
}

///|
test "submitted explicit SQL refuses a FROM-led query instead of format fallback" {
  assert_true(
    submitted_input(
      "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"FROM seed |> SELECT n |> RESULT answer\"},\"parameters\":null}",
    )
    is Err(Frontend(@frontend.WrongQueryForm)),
  )
  assert_true(
    submitted_input(
      "{\"kind\":\"aql\",\"input\":{\"format\":\"aql-text\",\"text\":\"{}\"},\"parameters\":null}",
    )
    is Err(Frontend(@frontend.WrongQueryForm)),
  )
}

///|
test "submitted input retains environment and common Checker budget boundaries" {
  let env = environment()
  let limited = @host.client_standard_program_preparation_limits()
  let context = Some(
    bind_local_input_context(env, [], "python.local.text").unwrap(),
  )
  assert_true(
    prepare_local_submitted_input(
      "{\"kind\":\"program\",\"input\":" + program + ",\"parameters\":null}",
      env,
      context,
      {
        ..limited,
        checking: {
          ..limited.checking,
          compilation: { ..limited.checking.compilation, work: 1, },
        },
      },
    )
    is Err(Preparation(_)),
  )
  assert_true(
    prepare_local_submitted_input(
      "{\"kind\":\"aql\",\"input\":{\"format\":\"sql\",\"text\":\"" +
      " ".repeat(65536) +
      "SELECT 1 AS n\"},\"parameters\":null}",
      env,
      context,
      limited,
    )
    is Err(SubmittedInput(@host.Limit)),
  )
}
