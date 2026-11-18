// Independent wire-shape fixtures. This enables no Native explain command,
// retained-facts supplier, current/egress authorization or capability.

///|
fn explanation_wire_fixture(
  original_ref : String,
  explanation : String,
) -> Json raise {
  @json.parse(
    "{\"version\":\"actql-run-explanation-view/0.1\",\"run_ref\":" +
    original_ref +
    ",\"explanation\":" +
    explanation +
    "}",
  ) catch {
    _ => fail("InvalidIndependentExplanationFixture")
  }
}

///|
let explanation_wire_original_ref : String =
  #|{"namespaceId":"workspace:wire-test","authorityScopeCid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","runDefinitionCid":"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"}

///|
test "Native Explanation view admits only the original closed not-projected reasons" {
  for reason in ["not_retained", "profile_not_supported"] {
    assert_true(
      wire_run_explanation_view_shape(
        explanation_wire_fixture(
          explanation_wire_original_ref,
          "{\"state\":\"not_projected\",\"reason\":\"" + reason + "\"}",
        ),
      ),
    )
  }
  for
    rejected in [
      "{\"state\":\"not_projected\",\"reason\":\"encoding_failed\"}", "{\"state\":\"not_projected\",\"reason\":\"not_retained\",\"facts\":{}}",
      "{\"state\":\"projected\"}", "{\"state\":\"projected\",\"facts\":null}",
    ] {
    assert_false(
      wire_run_explanation_view_shape(
        explanation_wire_fixture(explanation_wire_original_ref, rejected),
      ),
    )
  }
}

///|
test "Native Explanation view requires the complete closed original Run reference" {
  for
    rejected in [
      "{\"namespaceId\":\"workspace:wire-test\"}", "{\"namespaceId\":\"workspace:wire-test\",\"authorityScopeCid\":\"bad\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\"}",
      "{\"namespaceId\":\"workspace:wire-test\",\"authorityScopeCid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"runDefinitionCid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"control_revision\":1}",
    ] {
    assert_false(
      wire_run_explanation_view_shape(
        explanation_wire_fixture(
          rejected, "{\"state\":\"not_projected\",\"reason\":\"not_retained\"}",
        ),
      ),
    )
  }
}

///|
test "Native Explanation view admits structural facts shape without accepting raw disclosure fields" {
  let facts =
    #|{"version":"actql-explanation-facts/0.1","disclosure":"structural","program_definition_cid":"sha256:1111111111111111111111111111111111111111111111111111111111111111","parameter_values_cid":"sha256:2222222222222222222222222222222222222222222222222222222222222222","compiled_plan_cid":"sha256:3333333333333333333333333333333333333333333333333333333333333333","logical_map_cid":"sha256:4444444444444444444444444444444444444444444444444444444444444444","steps":[],"self_cid":"sha256:5555555555555555555555555555555555555555555555555555555555555555"}
  // Shape admission proves neither these independently authored CID preimages
  // nor compiler provenance, retention, budget or permission to disclose.
  assert_true(
    wire_run_explanation_view_shape(
      explanation_wire_fixture(
        explanation_wire_original_ref,
        "{\"state\":\"projected\",\"facts\":" + facts + "}",
      ),
    ),
  )
  for
    extra in [
      "\"raw_literal\":1", "\"value_cid\":\"hidden\"", "\"prompt\":\"hidden\"", "\"source_body\":\"hidden\"",
    ] {
    assert_false(
      wire_run_explanation_view_shape(
        explanation_wire_fixture(
          explanation_wire_original_ref,
          "{\"state\":\"projected\",\"facts\":" +
          facts.replace(old="\"steps\":[]", new="\"steps\":[]," + extra) +
          "}",
        ),
      ),
    )
    assert_false(
      wire_run_explanation_view_shape(
        explanation_wire_fixture(
          explanation_wire_original_ref,
          "{\"state\":\"projected\",\"facts\":" + facts + "," + extra + "}",
        ),
      ),
    )
  }
}
