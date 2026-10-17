///|
test "public check locates the existing Graph expectation query violation" {
  for format in ["sql", "aql-text"] {
    let report = binding_check_report(
      "WITH e AS (SELECT 1 AS id) FROM GRAPH e", format,
    )
    assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
    assert_true(report.contains("\"code\":\"query_invalid\""), msg=report)
    assert_true(report.contains("\"start_byte\":38"), msg=report)
    assert_true(report.contains("\"end_byte\":39"), msg=report)
    assert_true(
      report.contains(
        "rev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      ),
      msg=report,
    )
    assert_true(!report.contains("\"expected_type\""), msg=report)
    assert_true(!report.contains("source_unresolved"), msg=report)
  }
}
