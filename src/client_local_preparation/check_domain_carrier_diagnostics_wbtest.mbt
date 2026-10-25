///|
test "public check preserves closed operand domain requirements" {
  for format in ["sql", "aql-text"] {
    for
      (text, domain) in [
        (
          "SELECT 1 + 'private-domain-sentinel' AS value", "key_comparable_operands",
        ),
        (
          "SELECT 'private-domain-sentinel' + 'b' AS value", "matching_numeric_domains",
        ),
      ] {
      let report = binding_check_report(text, format)
      println("ACTQL_DOMAIN_CHECK_REPORT " + report)
      assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
      assert_true(
        report.contains("\"code\":\"expression_domain_mismatch\""),
        msg=report,
      )
      assert_true(report.contains("\"domain\":\"" + domain + "\""), msg=report)
      assert_true(!report.contains("expected_type"), msg=report)
      assert_true(!report.contains("private-domain-sentinel"), msg=report)
      // Generated lowerer paths must not become fabricated authored locations.
      assert_true(!report.contains("\"location\""), msg=report)
    }
    for text in ["SELECT 1 + 2 AS value", "SELECT 'a' = 'b' AS value"] {
      let report = binding_check_report(text, format)
      assert_true(report.contains("\"verdict\":\"verified\""), msg=report)
      assert_true(!report.contains("expression_domain_mismatch"), msg=report)
    }
    let scalar = binding_check_report("SELECT 1 / 'text' AS value", format)
    assert_true(
      scalar.contains("\"code\":\"expression_type_mismatch\""),
      msg=scalar,
    )
    assert_true(scalar.contains("\"expected_type\":\"number\""), msg=scalar)
    assert_true(!scalar.contains("expression_domain_mismatch"), msg=scalar)
  }
}

///|
test "public check preserves original vector operation carrier requirements" {
  for format in ["sql", "aql-text"] {
    for
      operation in [
        "score_vectors(query: [1, 0], metric: 'dot')", "normalize_vectors()",
      ] {
      let report = binding_check_report(
        "WITH private_carrier_sentinel AS (SELECT 1 AS item_id) FROM private_carrier_sentinel |> " +
        operation,
        format,
      )
      println("ACTQL_CARRIER_CHECK_REPORT " + report)
      assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
      assert_true(report.contains("\"code\":\"carrier_mismatch\""), msg=report)
      assert_true(
        report.contains("\"actual_carrier\":\"relation\""),
        msg=report,
      )
      assert_true(
        report.contains("\"expected_carrier\":\"vectors\""),
        msg=report,
      )
      assert_true(!report.contains("private_carrier_sentinel"), msg=report)
      assert_true(!report.contains("\"location\""), msg=report)
    }
  }
}

///|
fn domain_carrier_structured_report(document : String) -> String {
  client_program_check_program(
    document,
    binding_check_environment(),
    "{\"environmentCid\":\"sha256:ee8bc2292e30621d67ad36adb1a25987d113448e5b6dd333cbaf5511328e20dc\",\"aliases\":[]}",
    None,
    "ctx:independent",
    "rev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    None,
    "corr:independent",
    "bound_input",
    None,
  )
}

///|
test "structured arithmetic mismatch retains the original operand pointer" {
  // Independently authored Program input; no source lowering supplies the oracle.
  let document =
    #|{
    #|  "version": "actql/0.1",
    #|  "id": "review",
    #|  "stages": [
    #|    {
    #|      "id": "main",
    #|      "inputs": {},
    #|      "steps": [
    #|        {
    #|          "as": "records",
    #|          "values": {
    #|            "schema": {
    #|              "id": {
    #|                "type": "number",
    #|                "nullable": false
    #|              }
    #|            },
    #|            "rows": [
    #|              {
    #|                "id": 1
    #|              }
    #|            ]
    #|          }
    #|        },
    #|        {
    #|          "from": "records",
    #|          "derive": {
    #|            "bad": {
    #|              "add": [
    #|                {
    #|                  "field": "id"
    #|                },
    #|                {
    #|                  "literal": "text"
    #|                }
    #|              ]
    #|            }
    #|          },
    #|          "as": "derived"
    #|        }
    #|      ],
    #|      "results": {
    #|        "rows": {
    #|          "from": "derived",
    #|          "fields": [
    #|            "bad"
    #|          ]
    #|        }
    #|      }
    #|    }
    #|  ],
    #|  "results": {
    #|    "answer": {
    #|      "from": {
    #|        "stage": "main",
    #|        "result": "rows"
    #|      }
    #|    }
    #|  }
    #|}
  let report = domain_carrier_structured_report(document)
  assert_true(
    report.contains("\"code\":\"expression_domain_mismatch\""),
    msg=report,
  )
  assert_true(
    report.contains("\"domain\":\"key_comparable_operands\""),
    msg=report,
  )
  assert_true(
    report.contains("\"pointer\":\"/stages/0/steps/1/derive/bad/add/1\""),
    msg=report,
  )
  assert_true(
    report.contains(
      "\"revision\":\"rev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"",
    ),
    msg=report,
  )
  assert_true(report.contains("\"document_id\":\"program\""), msg=report)
  assert_true(report.contains("\"kind\":\"structured\""), msg=report)
  assert_true(!report.contains("\"start_byte\""), msg=report)
}

///|
test "structured to_vectors mismatch requires Relation rather than Vectors" {
  // Independently authored Program input; no source lowering supplies the oracle.
  let document =
    #|{
    #|  "version": "actql/0.1",
    #|  "id": "review",
    #|  "stages": [
    #|    {
    #|      "id": "main",
    #|      "inputs": {},
    #|      "steps": [
    #|        {
    #|          "as": "records",
    #|          "values": {
    #|            "schema": {
    #|              "id": {
    #|                "type": "number",
    #|                "nullable": false
    #|              },
    #|              "embedding": {
    #|                "type": "vector",
    #|                "dimensions": 2,
    #|                "nullable": false
    #|              }
    #|            },
    #|            "rows": [
    #|              {
    #|                "id": 1,
    #|                "embedding": [
    #|                  1,
    #|                  0
    #|                ]
    #|              }
    #|            ]
    #|          }
    #|        },
    #|        {
    #|          "from": "records",
    #|          "to_vectors": {
    #|            "id": "id",
    #|            "vector": "embedding"
    #|          },
    #|          "as": "vectors"
    #|        },
    #|        {
    #|          "from": "vectors",
    #|          "to_vectors": {
    #|            "id": "id",
    #|            "vector": "embedding"
    #|          },
    #|          "as": "again"
    #|        }
    #|      ],
    #|      "results": {
    #|        "rows": {
    #|          "from": "again",
    #|          "fields": [
    #|            "id"
    #|          ]
    #|        }
    #|      }
    #|    }
    #|  ],
    #|  "results": {
    #|    "answer": {
    #|      "from": {
    #|        "stage": "main",
    #|        "result": "rows"
    #|      }
    #|    }
    #|  }
    #|}
  let report = domain_carrier_structured_report(document)
  assert_true(report.contains("\"code\":\"carrier_mismatch\""), msg=report)
  assert_true(report.contains("\"actual_carrier\":\"vectors\""), msg=report)
  assert_true(report.contains("\"expected_carrier\":\"relation\""), msg=report)
  assert_true(
    report.contains("\"pointer\":\"/stages/0/steps/2/to_vectors\""),
    msg=report,
  )
  assert_true(
    report.contains(
      "\"revision\":\"rev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\"",
    ),
    msg=report,
  )
  assert_true(report.contains("\"document_id\":\"program\""), msg=report)
  assert_true(report.contains("\"kind\":\"structured\""), msg=report)
  assert_true(!report.contains("\"start_byte\""), msg=report)
}

///|
test "well typed vector roundtrip retains implementation coverage limit" {
  let report = client_program_check_program(
    "{\"version\":\"actql/0.1\",\"id\":\"review\",\"stages\":[{\"id\":\"main\",\"inputs\":{},\"steps\":[{\"as\":\"records\",\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false},\"embedding\":{\"type\":\"vector\",\"dimensions\":2,\"nullable\":false}},\"rows\":[{\"id\":1,\"embedding\":[1,0]}]}},{\"from\":\"records\",\"to_vectors\":{\"id\":\"id\",\"vector\":\"embedding\"},\"as\":\"vectors\"},{\"from\":\"vectors\",\"vectors\":true,\"as\":\"rows\"}],\"results\":{\"rows\":{\"from\":\"rows\",\"fields\":[\"id\",\"embedding\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"main\",\"result\":\"rows\"}}}}",
    binding_check_environment(),
    "{\"environmentCid\":\"sha256:ee8bc2292e30621d67ad36adb1a25987d113448e5b6dd333cbaf5511328e20dc\",\"aliases\":[]}",
    None,
    "ctx:independent",
    "rev:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    None,
    "corr:independent",
    "bound_input",
    None,
  )
  println("VALID_VECTOR " + report)
  // This fixture disables VecA support; do not manufacture a carrier error.
  assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
  assert_true(report.contains("\"code\":\"implementation_limit\""), msg=report)
  assert_true(!report.contains("carrier_mismatch"), msg=report)
}
