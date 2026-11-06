///|
fn check_display_fixture(source : String) -> String {
  @preparation.client_program_check_source(
    source,
    "sql",
    explain_fixture_environment(),
    "{\"aliases\":[],\"environmentCid\":\"" +
    @checked.checking_environment_cid(explain_fixture_environment()) +
    "\"}",
    None,
    None,
    "ctx:display",
    "rev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    None,
    None,
    "corr:display",
    "bound_input",
    None,
  )
}

///|
test "Human check reports validity and runnable separately without wire identities" {
  let source = "SELECT 1 AS n"
  let wire = check_display_fixture(source)
  let display = local_check_reply(wire, false, source)
  assert_true(
    display.has_prefix(
      "ActQL CHECK\nValidation: Valid\nRunnable: yes\nScope: bound input\n",
    ),
    msg=display,
  )
  assert_false(display.contains("sha256:"))
  assert_false(display.contains("ctx:"))
  assert_false(display.contains("rev:"))
  assert_true(display.contains("not execution permission"))
  assert_eq(local_check_reply(wire, true, source), wire)
  assert_false(local_check_invalid_exit(wire))
}

///|
test "Human check explains invalid input and its original source location" {
  let source = "SELECT\n)"
  let wire = check_display_fixture(source)
  let display = local_check_reply(wire, false, source)
  assert_true(
    display.contains("Validation: Invalid\nRunnable: no\n"),
    msg=display,
  )
  assert_true(
    display.contains("query_syntax_invalid: The query syntax is invalid."),
    msg=display,
  )
  assert_true(display.contains("At source: line 2, byte 1"), msg=display)
  assert_true(local_check_invalid_exit(wire))
  assert_eq(local_check_reply(wire, true, source), wire)
}

///|
test "Human check uses catalog variants and leaves unknown reason codes intact" {
  assert_eq(
    local_check_reason_presentation(
      "query_expression_invalid",
      Map([("issue", Json::string("expected_boolean"))]),
    ),
    Some(
      (
        "A predicate must have Boolean type.", "Use a Boolean condition, such as a comparison, in the predicate.",
      ),
    ),
  )
  assert_eq(
    local_check_reason_presentation("not_a_known_reason", Map([])),
    None,
  )
  let output = { body: StringBuilder(), remaining: 65536, }
  local_check_reason(
    output,
    Json::object(
      Map([
        ("code", Json::string("future_reason")),
        (
          "facts",
          Json::object(Map([("parameter", Json::string("x\n\u001b[31m"))])),
        ),
      ]),
    ),
    "",
  )
  let text = output.body.to_string()
  assert_true(text.contains("future_reason"))
  assert_true(text.contains("\\n\\u001b[31m"))
  assert_false(text.contains("\u001b"))
}

///|
test "Human check does not invent a verdict for unavailable observations" {
  let wire = @preparation.client_program_check_unavailable("corr:display")
  let display = local_check_reply(wire, false, "")
  assert_true(
    display.contains("Check: unavailable (no complete validation verdict)"),
    msg=display,
  )
  assert_false(display.contains("Validation:"))
  assert_eq(local_check_reply(wire, true, ""), wire)
}

///|
test "Human check rejects malformed shapes and preserves exact byte limits" {
  let wire = check_display_fixture("SELECT 1 AS n")
  let display = local_check_reply(wire, false, "SELECT 1 AS n")
  let bytes = @utf8.encode(display).length()
  assert_eq(
    local_check_reply(wire, false, "SELECT 1 AS n", max_bytes=bytes),
    display,
  )
  for bound in [0, bytes - 1] {
    let issue = try {
      ignore(local_check_reply(wire, false, "SELECT 1 AS n", max_bytes=bound))
      "accepted"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(issue, "LocalCheckDisplayLimit")
  }
  for
    invalid in [
      "{}",
      wire.replace(old="\"verdict\":\"verified\"", new="\"verdict\":\"other\""),
    ] {
    let issue = try {
      ignore(local_check_reply(invalid, false, "SELECT 1 AS n"))
      "accepted"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(issue, "LocalCheckDisplayUnavailable")
  }
}

///|
test "Human check preserves verified but not runnable and undetermined boundaries" {
  let wire = check_display_fixture("SELECT 1 AS n")
  let value = @json.parse(wire) catch { _ => fail("invalid fixture") }
  guard value is Object(root) && root["report"] is Object(report) else {
    fail("missing report")
  }
  report["scope"] = Json::object(Map([("kind", Json::string("template_only"))]))
  report["runnable"] = Json::object(
    Map([
      ("verdict", Json::string("no")),
      (
        "reasons",
        Json::array([
          Json::object(Map([("code", Json::string("bound_values_missing"))])),
        ]),
      ),
    ]),
  )
  let template = encode_request_json(value, 65536)
  let text = local_check_reply(template, false, "SELECT 1 AS n")
  assert_true(
    text.contains("Validation: Valid\nRunnable: no\nScope: template only"),
  )
  assert_true(text.contains("Required bound inputs are missing."))
  assert_false(local_check_invalid_exit(template))
  report["verdict"] = Json::string("undetermined")
  report["coverage"] = Json::object(
    Map([
      (
        "limits",
        Json::array([
          Json::object(
            Map([("code", Json::string("analysis_budget_exhausted"))]),
          ),
        ]),
      ),
      ("unresolved", Json::array([])),
    ]),
  )
  let undetermined = encode_request_json(value, 65536)
  let text = local_check_reply(undetermined, false, "SELECT 1 AS n")
  assert_true(text.contains("Validation: Undetermined (not verified)"))
  assert_true(text.contains("Analysis limits (1):"))
  assert_true(text.contains("The analysis budget was exhausted."))
  assert_false(local_check_invalid_exit(undetermined))
  assert_eq(
    local_check_reply(undetermined, true, "SELECT 1 AS n"),
    undetermined,
  )
}

///|
test "Human check names structured locations and counts UTF8 source bytes honestly" {
  let structured = Json::object(
    Map([
      ("document_id", Json::string("parameters")),
      ("kind", Json::string("structured")),
      ("pointer", Json::string("/name\u001b[31m")),
    ]),
  )
  assert_eq(
    local_check_location(structured, ""),
    "parameters pointer \"/name\\u001b[31m\"",
  )
  let location = Json::object(
    Map([
      ("document_id", Json::string("source")),
      ("kind", Json::string("text")),
      ("start_byte", Json::number(8)),
      ("end_byte", Json::number(8)),
      ("precision", Json::string("approximate")),
    ]),
  )
  assert_eq(
    local_check_location(location, "α\r\n中x"),
    "source: line 2, byte 5 (approximate; bytes 8..8)",
  )
}

///|
test "Human check counts CR LF and CRLF as original line breaks" {
  for source in ["SELECT\r)", "SELECT\n)", "SELECT\r\n)"] {
    let wire = check_display_fixture(source)
    let text = local_check_reply(wire, false, source)
    assert_true(text.contains("At source: line 2, byte 1"), msg=text)
  }
  let source = "SELECT\r\n\r\n\r\n)"
  let text = local_check_reply(check_display_fixture(source), false, source)
  assert_true(text.contains("At source: line 4, byte 1"), msg=text)
}

///|
test "Human check qualifies a failed observation and its partial report" {
  let source = "SELECT )"
  let value = @json.parse(check_display_fixture(source)) catch {
    _ => fail("invalid fixture")
  }
  guard value is Object(root) else { fail("missing outcome") }
  let report = root["report"]
  root.remove("report")
  root["partial_report"] = report
  root["outcome"] = Json::string("failed")
  root["correlation_ref"] = Json::string("corr:display")
  root["problem"] = Json::object(
    Map([("code", Json::string("check_context_invalid"))]),
  )
  let wire = encode_request_json(value, 65536)
  let text = local_check_reply(wire, false, source)
  assert_true(text.contains("Check: failed (no complete validation verdict)"))
  assert_true(text.contains("Partial report only:\nValidation: Invalid"))
  assert_eq(local_check_reply(wire, true, source), wire)
}
