///|
let yaml_check_values : String =
  #|version: actql/0.1
  #|id: yaml.same-owner
  #|stages:
  #|  - id: main
  #|    inputs: {}
  #|    steps:
  #|      - values:
  #|          schema:
  #|            n: {type: number, nullable: false}
  #|          rows: [{n: 1}]
  #|        as: rows
  #|    results:
  #|      r: {from: rows, fields: [n]}
  #|results:
  #|  answer: {from: {stage: main, result: r}}

///|
fn yaml_check_report(
  document : String,
  format? : String = "yaml",
  supplied? : String? = None,
  scope? : String = "bound_input",
) -> String {
  let original = environment()
  let publication = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(original) +
    "\",\"aliases\":[]}"
  client_program_check_program_with_format(
    document,
    format,
    original,
    publication,
    supplied,
    "ctx:" + "a".repeat(64),
    "rev:" + "b".repeat(64),
    supplied.map(_ => "rev:" + "c".repeat(64)),
    "corr:yaml-original",
    scope,
    None,
  )
}

///|
test "original YAML check uses the same static Owner and preserves source bytes" {
  let body = "# é 😀\n" + yaml_check_values
  let body = body.replace_all(old="\n", new="\r\n")
  let report = yaml_check_report(body)
  assert_true(report.contains("\"verdict\":\"verified\""), msg=report)
  assert_true(
    report.contains("\"runnable\":{\"reasons\":[],\"verdict\":\"yes\"}"),
    msg=report,
  )
  assert_true(report.contains("\"kind\":\"structured\""), msg=report)
  assert_true(
    report.contains("\"revision\":\"rev:" + "b".repeat(64) + "\""),
    msg=report,
  )
  // Fixed separately from the product's UTF-8 length projection.
  assert_true(report.contains("\"byte_length\":334"), msg=report)
  assert_true(!report.contains("\"prepared\""), msg=report)
}

///|
test "original YAML check retains semantic and malformed-source refusals" {
  let wrong = yaml_check_values.replace(
    old="rows: [{n: 1}]",
    new="rows: [{n: true}]",
  )
  for
    body in [
      wrong, "version: [unterminated", "version: actql/0.1\nstages: []\nid: broken",
    ] {
    let report = yaml_check_report(body)
    assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
    assert_true(!report.contains("\"verdict\":\"verified\""), msg=report)
  }
  for format in ["auto", "YAML", "sql", ""] {
    let report = yaml_check_report(yaml_check_values, format~)
    assert_true(
      report.contains("\"code\":\"check_request_invalid\""),
      msg=report,
    )
  }
}

///|
fn yaml_check_parameter_program() -> String {
  yaml_check_values
  .replace(
    old="stages:",
    new="params:\n  x: {type: number, nullable: false}\nstages:",
  )
  .replace(
    old="    results:",
    new="      - derive: {value: 'n + $x'}\n        as: derived\n    results:",
  )
  .replace(
    old="r: {from: rows, fields: [n]}",
    new="r: {from: derived, fields: [value]}",
  )
}

///|
test "original YAML check keeps supplied JSON absence NULL and wrong-type distinctions" {
  let body = yaml_check_parameter_program()
  let missing = yaml_check_report(body)
  assert_true(
    missing.contains("\"code\":\"parameter_value_required\""),
    msg=missing,
  )
  for supplied in ["{\"x\":null}", "{\"x\":\"wrong\"}"] {
    let report = yaml_check_report(body, supplied=Some(supplied))
    assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
    assert_true(
      !report.contains("\"code\":\"parameter_value_required\""),
      msg=report,
    )
  }
  let valid = yaml_check_report(body, supplied=Some("{\"x\":2}"))
  assert_true(valid.contains("\"verdict\":\"verified\""), msg=valid)
  // Program syntax does not change the separately closed JSON Parameters body.
  let yaml_parameters = yaml_check_report(body, supplied=Some("x: 2"))
  assert_true(
    yaml_parameters.contains("\"verdict\":\"invalid\""),
    msg=yaml_parameters,
  )
  let template = yaml_check_report(
    body,
    supplied=Some("{}"),
    scope="template_only",
  )
  assert_true(
    template.contains("\"code\":\"check_request_invalid\""),
    msg=template,
  )
}

///|
test "original YAML default diagnostics retain the admitted declaration and pointer" {
  for key in ["x", "'x'", "\"x\""] {
    let body = yaml_check_parameter_program().replace(
      old="x: {type: number, nullable: false}",
      new=key + ": {type: number, nullable: false, default: wrong}",
    )
    let report = yaml_check_report(body)
    assert_true(
      report.contains("\"code\":\"parameter_default_type_mismatch\""),
      msg=report,
    )
    assert_true(
      report.contains("\"pointer\":\"/params/x/default\""),
      msg=report,
    )
  }
  let nullable = yaml_check_parameter_program().replace(
    old="x: {type: number, nullable: false}",
    new="x: {type: number, nullable: true, default: null}",
  )
  let report = yaml_check_report(nullable)
  assert_true(report.contains("\"verdict\":\"verified\""), msg=report)
}

///|
test "original YAML pointers preserve plain quoted Unicode keys and missing parents" {
  for key in ["é/😀~", "'é/😀~'", "\"é/😀~\""] {
    let body = "stages: [{}]\n" + key + ": null\n"
    assert_eq(
      check_program_original_pointer(body, [Key("é/😀~")], format=Yaml),
      Some("/é~1😀~0"),
    )
    assert_eq(
      check_program_original_pointer(
        body,
        [Key("stages"), Index(0), Key("steps")],
        format=Yaml,
      ),
      Some("/stages/0"),
    )
    assert_eq(
      check_program_original_pointer(body, [Key("missing")], format=Yaml),
      Some(""),
    )
  }
  let literal = yaml_check_values.replace(
    old="stages:",
    new="params:\n  x: {type: object, fields: {}, default: {\"é/😀~\": wrong}}\nstages:",
  )
  let parsed = @syntax.parse(
    literal,
    @host.client_standard_program_preparation_limits().checking.input,
    format=Yaml,
  ).unwrap()
  // Declaration defaults keep the original parser's identifier-key domain.
  assert_eq(
    check_program_original_pointer(
      literal,
      [Key("params"), Key("x"), Key("default"), Key("é/😀~")],
      format=Yaml,
      original_body=Some(@syntax.program_body(parsed)),
    ),
    Some("/params/x/default/é~1😀~0"),
  )
  let effect = yaml_check_values.replace(
    old="    results:",
    new="    effects: {write: {update: {set: {n: {literal: {\"é/😀~\": 1}}}}}}\n    results:",
  )
  let parsed = @syntax.parse(
    effect,
    @host.client_standard_program_preparation_limits().checking.input,
    format=Yaml,
  ).unwrap()
  // Only the existing Program Owner's declared Effect literal slots preserve
  // value-data keys. Parsing syntax here neither checks nor authorizes an Effect.
  assert_eq(
    check_program_original_pointer(
      effect,
      [
        Key("stages"),
        Index(0),
        Key("effects"),
        Key("write"),
        Key("update"),
        Key("set"),
        Key("n"),
        Key("literal"),
        Key("é/😀~"),
      ],
      format=Yaml,
      original_body=Some(@syntax.program_body(parsed)),
    ),
    Some("/stages/0/effects/write/update/set/n/literal/é~1😀~0"),
  )
}

///|
test "original YAML check preserves protected Source and foreign nominal range refusals" {
  let secret = yaml_check_values.replace(
    old="inputs: {}",
    new="inputs: {remote: {connector: hidden, resource: private, view: records}}",
  )
  let report = yaml_check_report(secret)
  assert_true(
    report.contains("\"reason\":\"unresolved_protected\""),
    msg=report,
  )
  assert_true(!report.contains("hidden"), msg=report)
  assert_true(!report.contains("private"), msg=report)
  let original = environment()
  let publication = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(original) +
    "\",\"aliases\":[]}"
  let range = client_program_check_source_selector_range(original, []).unwrap()
  let proof = client_program_check_source_selector_namespace(
    range,
    "original",
    "sha256:" + "d".repeat(64),
    "ctx:" + "a".repeat(64),
    "rev:" + "b".repeat(64),
  ).unwrap()
  for
    (owner, context, revision) in [
      (environment(), "ctx:" + "a".repeat(64), "rev:" + "b".repeat(64)),
      (original, "ctx:" + "c".repeat(64), "rev:" + "b".repeat(64)),
      (original, "ctx:" + "a".repeat(64), "rev:" + "c".repeat(64)),
    ] {
    let refused = client_program_check_program_with_format(
      yaml_check_values,
      "yaml",
      owner,
      publication,
      None,
      context,
      revision,
      None,
      "corr:foreign",
      "bound_input",
      Some(proof),
    )
    assert_true(
      refused.contains("\"code\":\"check_context_invalid\""),
      msg=refused,
    )
  }
}

///|
test "original YAML port leaves legacy JSON outcomes byte identical" {
  let owner = environment()
  let publication = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(owner) +
    "\",\"aliases\":[]}"
  for body in [program, "{}", "{"] {
    let previous = client_program_check_program(
      body,
      owner,
      publication,
      None,
      "ctx:" + "a".repeat(64),
      "rev:" + "b".repeat(64),
      None,
      "corr:json",
      "bound_input",
      None,
    )
    let selected = client_program_check_program_with_format(
      body,
      "json",
      owner,
      publication,
      None,
      "ctx:" + "a".repeat(64),
      "rev:" + "b".repeat(64),
      None,
      "corr:json",
      "bound_input",
      None,
    )
    assert_eq(selected, previous)
  }
}

///|
test "original Program parse refusal projects the first typed issue without checking again" {
  for
    (document, format) in [
      ("{\"version\":", @syntax.Json),
      ("version: [unterminated", @syntax.Yaml),
      ("{\"version\":\"actql/0.1\",\"stages\":false}", @syntax.Json),
    ] {
    let checking = @host.client_standard_program_preparation_limits().checking
    let issue = @syntax.parse(document, checking.input, format~).unwrap_err()
    let diagnostic = @checked.program_input_diagnostic(issue)
    let expected : Array[CheckFinding] = []
    let expected_stop = check_program_diagnostic(
      expected,
      diagnostic,
      document,
      None,
      None,
      _ => (),
      format~,
    )
    let actual : Array[CheckFinding] = []
    let actual_stop = check_program_findings(
      actual,
      document,
      environment(),
      "{\"aliases\":[]}",
      None,
      _ => (),
      BoundInput,
      None,
      format,
    )
    // Compare complete findings and stop kinds, including retained source
    // locations. Neither branch may turn malformed input into an exception.
    assert_true(actual_stop is Report && expected_stop is Report)
    let documents : CheckDocuments = {
      scope: BoundInput,
      structured_program: true,
      program_pointer: None,
      source_revision: "rev:" + "b".repeat(64),
      source_bytes: @utf8.encode(document).length(),
      declarations_revision: None,
      declarations_bytes: 0,
      parameters_revision: None,
      parameters_bytes: 0,
    }
    assert_eq(
      check_outcome_json(
        actual, actual_stop, "ctx:original", "corr:original", documents,
      ),
      check_outcome_json(
        expected, expected_stop, "ctx:original", "corr:original", documents,
      ),
    )
  }
}
