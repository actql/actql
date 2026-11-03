///|
// Actual retained Request/check/report owners, with an unresolved Source.
// No second checker or mutable caller packet supplies these findings.
test "Request original protected Source report retains independent supplied type failure" {
  let document =
    #|{"version":"actql/0.1","id":"protected","params":{"missing":{"type":"number"},"wrong":{"type":"number"}},"stages":[{"id":"main","inputs":{"rows":{"connector":"crm/main","resource":"r","view":"v"}},"steps":[{"select":["private_field"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["private_field"]}}}],"results":{"out":{"from":{"stage":"main","result":"out"}}}}
  let program_limits = @publication_host.client_standard_program_preparation_limits()
  for
    (supplied_text, invalid) in [
      ("{\"wrong\":7}", false),
      ("{\"wrong\":\"private-supplied\"}", true),
    ] {
    let supplied = request_native_test_value(supplied_text)
    let supplied = @local_preparation.admit_captured_local_parameters(
      supplied, native_json_reader,
    ).unwrap()
    let (parent, child, _, input) = registration_parent_fixture(
      text=document,
      supplied=Some(supplied),
      computation_limits=Some(
        (
          program_limits,
          @publication_host.client_standard_effect_computation_limits(),
        ),
      ),
    )
    let terminal = match finish_request_computation_check(parent, input) {
      Err(issue) => issue
      Ok(_) => fail("an unresolved Source cannot become a checked execution")
    }
    let original = child.check_outcome.unwrap()
    assert_true(
      original is @checked.Rejected(diagnostic) &&
      @checked.diagnostic_cause(diagnostic)
      is Source(Registration(Selection(_))),
    )
    let program = parent.held_program.unwrap()
    assert_eq(
      @checked.independent_supplied_binding_issue(
        original,
        program,
        Some(supplied),
      )
      is Some(_),
      invalid,
    )
    let other_supplied = @local_preparation.admit_captured_local_parameters(
      request_native_test_value(supplied_text),
      native_json_reader,
    ).unwrap()
    assert_true(
      @checked.independent_supplied_binding_issue(
        original,
        program,
        Some(other_supplied),
      )
      is None,
    )
    assert_true(
      @checked.independent_supplied_binding_issue(original, program, None)
      is None,
    )
    let other_program = @syntax.parse(document, program_limits.checking.input).unwrap()
    assert_true(
      @checked.independent_supplied_binding_issue(
        original,
        other_program,
        Some(supplied),
      )
      is None,
    )
    assert_true(
      physical_equal(child.arguments.unwrap().supplied.unwrap(), supplied),
    )
    let report = project_request_check_outcome(
      parent,
      input,
      terminal,
      request_observation_publication(child),
      "ctx:" + "a".repeat(64),
      "program",
      "rev:" + "b".repeat(64),
      document.length(),
      None,
      0,
      Some("rev:" + "d".repeat(64)),
      supplied_text.length(),
      "corr:" + "c".repeat(32),
      None,
    )
    assert_true(physical_equal(child.check_outcome.unwrap(), original))
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    let report = report.unwrap().unwrap()
    assert_true(report.contains("\"reason\":\"unresolved_protected\""))
    assert_false(report.contains("private_field"))
    assert_false(report.contains("private-supplied"))
    if invalid {
      assert_true(report.contains("\"verdict\":\"invalid\""))
      assert_true(report.contains("supplied_value_type_mismatch"))
      // This original native Cursor retains normalized keys, not the raw key
      // spelling or authored source spans. Keep the established projection's
      // omission; the separate public text-input pointer oracle is unchanged.
      assert_false(report.contains("\"pointer\":\"/wrong\""))
    } else {
      assert_true(report.contains("\"verdict\":\"undetermined\""))
      assert_false(report.contains("supplied_value_type_mismatch"))
    }
  }
}
