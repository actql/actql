///|
fn timestamp_pattern_check_environment() -> @checked.CheckEnvironment {
  // Explicit independently hashed test profile, not operational funding.
  let wire =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:cb359594d618dc1c5e5a77f83aa7a4f85cfd30550bd376efa2add397cee3bf0c","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"text_time_evaluation":{"max_input_codepoints":64,"max_input_utf8_bytes":256,"max_output_bytes":64,"max_pattern_bytes":100,"max_replacements":1,"version":"actql-text-time-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  @host.admit_client_check_environment(
    wire,
    "sha256:cb359594d618dc1c5e5a77f83aa7a4f85cfd30550bd376efa2add397cee3bf0c",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn timestamp_pattern_check_report(
  sql : String,
  policy? : Bool = true,
) -> String {
  let original = if policy {
    timestamp_pattern_check_environment()
  } else {
    environment()
  }
  client_program_check_source(
    sql,
    "sql",
    original,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(original) +
    "\",\"aliases\":[]}",
    None,
    None,
    "ctx:timestamp-pattern",
    "rev:" + "a".repeat(64),
    None,
    None,
    "corr:timestamp-pattern",
    "bound_input",
    None,
  )
}

///|
test "original invalid timestamp patterns are named input refusals, not Unknown" {
  for
    sql in [
      "SELECT FORMAT_TIMESTAMP('%Y', CAST('2026-01-02T00:00:00.000Z' AS TIMESTAMP)) AS x",
      "SELECT PARSE_TIMESTAMP('%Y-%m-%d', '2026-01-02') AS x",
    ] {
    let report = timestamp_pattern_check_report(sql)
    println("ACTQL_TIMESTAMP_PATTERN_CHECK_REPORT " + report)
    assert_true(report.contains("\"outcome\":\"completed\""), msg=report)
    assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
    assert_true(
      report.contains("\"code\":\"query_expression_invalid\""),
      msg=report,
    )
    assert_true(report.contains("\"issue\":\"invalid_arguments\""), msg=report)
    assert_true(!report.contains("check_unclassified"), msg=report)
    assert_true(!report.contains("\"location\""), msg=report)
  }
}

///|
test "timestamp pattern diagnosis preserves valid modes and missing original profile" {
  for
    sql in [
      "SELECT FORMAT_TIMESTAMP('yyyy', CAST('2026-01-02T00:00:00.000Z' AS TIMESTAMP)) AS x",
      "SELECT PARSE_TIMESTAMP('yyyy-MM-dd', '2026-01-02') AS x",
    ] {
    let report = timestamp_pattern_check_report(sql)
    assert_true(report.contains("\"verdict\":\"verified\""), msg=report)
  }
  let missing = timestamp_pattern_check_report(
    "SELECT PARSE_TIMESTAMP('%Y', '2026') AS x",
    policy=false,
  )
  assert_true(missing.contains("\"verdict\":\"undetermined\""), msg=missing)
  assert_true(!missing.contains("invalid_timestamp_pattern"), msg=missing)
}

///|
test "Text-time Check reports the original input, output and replacement ceiling" {
  for
    (sql, code) in [
      (
        "SELECT REGEXP_CONTAINS('" + "a".repeat(65) + "', 'a') AS x",
        "text_time_input_ceiling",
      ),
      ("SELECT ACTQL.NFKC('ＡＫ') AS x", "text_time_output_ceiling"),
      (
        "SELECT REGEXP_REPLACE('a', 'a', 'b') AS x", "text_time_replacement_ceiling",
      ),
    ] {
    let report = timestamp_pattern_check_report(sql)
    assert_true(report.contains("\"outcome\":\"completed\""), msg=report)
    assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
    assert_true(
      report.contains(
        "\"runnable\":{\"reasons\":[{\"code\":\"" +
        code +
        "\"}],\"verdict\":\"no\"}",
      ),
      msg=report,
    )
    assert_true(
      report.contains("\"limits\":[{\"code\":\"" + code + "\"}]"),
      msg=report,
    )
    assert_true(!report.contains("check_unclassified"), msg=report)
    assert_true(!report.contains("\"location\""), msg=report)
  }
  let exact = timestamp_pattern_check_report(
    "SELECT REGEXP_REPLACE('', 'a', 'b') AS x",
  )
  assert_true(exact.contains("\"verdict\":\"verified\""), msg=exact)
}

///|
test "structured text-time Check preserves the replacement ceiling without a private witness" {
  let original = timestamp_pattern_check_environment()
  let document =
    #|{"version":"actql/0.1","id":"text-time-limit","stages":[{"id":"main","inputs":{},"steps":[{"as":"input","values":{"schema":{"text":{"type":"string","nullable":false}},"rows":[{"text":"private-text-marker"}]}},{"from":"input","as":"done","derive":{"output":"regex_replace(text, 'a', '$$')"}}],"results":{"r":{"from":"done","fields":["output"]}}}],"results":{"answer":{"from":{"stage":"main","result":"r"}}}}
  let report = client_program_check_program(
    document,
    original,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(original) +
    "\",\"aliases\":[]}",
    None,
    "ctx:timestamp-pattern",
    "rev:" + "a".repeat(64),
    None,
    "corr:timestamp-pattern",
    "bound_input",
    None,
  )
  assert_true(report.contains("\"outcome\":\"completed\""), msg=report)
  assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
  assert_true(
    report.contains(
      "\"runnable\":{\"reasons\":[{\"code\":\"text_time_replacement_ceiling\"}],\"verdict\":\"no\"}",
    ),
    msg=report,
  )
  assert_true(
    report.contains("\"limits\":[{\"code\":\"text_time_replacement_ceiling\"}]"),
    msg=report,
  )
  assert_true(!report.contains("private-text-marker"), msg=report)
  assert_true(!report.contains("\"location\""), msg=report)
}
