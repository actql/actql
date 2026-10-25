///|
test "public syntax diagnostics retain EOF and Unicode CRLF tab byte positions" {
  for
    (text, offset) in [
      ("SELECT", 6),
      ("SELECT 1 +", 10),
      ("SELECT (1", 9),
      ("SELECT '😀' AS label,\r\n\t(1 + ) AS n", 31),
    ] {
    let report = binding_check_report(text, "aql-text")
    assert_true(
      report.contains("\"code\":\"query_syntax_invalid\""),
      msg=report,
    )
    assert_true(
      report.contains("\"start_byte\":\{offset},") ||
      report.contains("\"start_byte\":\{offset}}"),
      msg=report,
    )
    assert_true(
      report.contains("\"end_byte\":\{offset},") ||
      report.contains("\"end_byte\":\{offset}}"),
      msg=report,
    )
    assert_true(report.contains("\"precision\":\"exact\""), msg=report)
    assert_true(report.contains("\"document_id\":\"source\""), msg=report)
  }
}

///|
test "public unknown-column diagnostics locate the authored typo without guessing a name" {
  let report = binding_check_report(
    "WITH records AS (SELECT 1 AS item_id) FROM records |> SELECT itemd_id", "aql-text",
  )
  assert_true(report.contains("\"issue\":\"unknown_reference\""), msg=report)
  assert_true(
    report.contains("\"start_byte\":61,") ||
    report.contains("\"start_byte\":61}"),
    msg=report,
  )
  assert_true(
    report.contains("\"end_byte\":69,") || report.contains("\"end_byte\":69}"),
    msg=report,
  )
  assert_true(!report.contains("\"fixes\""), msg=report)
  assert_true(
    binding_check_report(
      "WITH records AS (SELECT 1 AS item_id) FROM records |> SELECT item_id", "aql-text",
    ).contains("\"verdict\":\"verified\""),
  )
}

///|
test "public syntax and binding reasons coexist without echoing supplied values" {
  let report = client_program_check_source(
    "SELECT @n +",
    "aql-text",
    binding_check_environment(),
    "{\"environmentCid\":\"sha256:ee8bc2292e30621d67ad36adb1a25987d113448e5b6dd333cbaf5511328e20dc\",\"aliases\":[]}",
    Some("{\"n\":{\"type\":\"number\",\"nullable\":false}}"),
    Some("{\"n\":\"SYNTHETIC_DIAGNOSTIC_SECRET\"}"),
    "ctx:binding",
    "rev:source",
    Some("rev:declarations"),
    Some("rev:parameters"),
    "corr:binding",
    "bound_input",
    None,
  )
  assert_true(report.contains("\"code\":\"query_syntax_invalid\""), msg=report)
  assert_true(
    report.contains("\"code\":\"supplied_value_type_mismatch\""),
    msg=report,
  )
  assert_true(report.contains("\"actual_type\":\"string\""), msg=report)
  assert_true(report.contains("\"expected_type\":\"number\""), msg=report)
  assert_true(report.contains("\"pointer\":\"/n\""), msg=report)
  assert_true(!report.contains("SYNTHETIC_DIAGNOSTIC_SECRET"), msg=report)
}
