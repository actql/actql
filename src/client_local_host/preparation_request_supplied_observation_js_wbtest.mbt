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

///|
// The same ordinary remaining checker has already collected this declared
// input. Reporting borrows it once and applies fresh disclosure metadata;
// no registration phase, second collector/check or execution is added here.
test "Request missing values keeps original Source inputs while fresh disclosure still protects them" {
  let declaration = pure_provider_declaration()
  let environment = pure_provider_environment(declaration)
  let document =
    #|{"version":"actql/0.1","id":"missing-visible","params":{"minimum":{"type":"number"}},"stages":[{"id":"main","inputs":{"rows":{"connector":"pure-provider","resource":"records","view":"records"}},"steps":[{"filter":"id >= $minimum","as":"filtered"},{"select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"out":{"from":{"stage":"main","result":"out"}}}}
  let program_limits = @publication_host.client_standard_program_preparation_limits()
  let (parent, child, source, input) = registration_parent_fixture(
    text=document,
    environment=Some(environment),
    computation_limits=Some(
      (
        program_limits,
        @publication_host.client_standard_effect_computation_limits(),
      ),
    ),
  )
  let terminal = match finish_request_computation_check(parent, input) {
    Err(issue) => issue
    Ok(_) => fail("the same original requires its missing parameter")
  }
  assert_true(child.check_outcome.unwrap() is @checked.NeedsInputs(_))
  assert_true(child.source_registration is None)
  let original_inputs = @checked.parsed_check_collected_source_inputs(
    child.check_registry.unwrap(),
  ).unwrap()
  assert_true(physical_equal(@sourceview_input.source(original_inputs), source))
  assert_eq(@sourceview_input.count(original_inputs), 1)
  for visible in [true, false] {
    let aliases = if visible {
      "[{\"name\":\"records\",\"sourceRef\":\"connector://pure-provider/records#records\"}]"
    } else {
      "[]"
    }
    let publication = "{\"environmentCid\":\"" +
      @checked.checking_environment_cid(environment) +
      "\",\"aliases\":" +
      aliases +
      "}"
    let report = project_request_check_outcome(
        parent,
        input,
        terminal,
        publication,
        "ctx:" + "a".repeat(64),
        "program",
        "rev:" + "b".repeat(64),
        document.length(),
        None,
        0,
        None,
        0,
        "corr:" + "c".repeat(32),
        None,
      )
      .unwrap()
      .unwrap()
    assert_true(report.contains("\"verdict\":\"undetermined\""))
    assert_true(report.contains("parameter_value_required"))
    assert_true(report.contains("bound_values_missing"))
    assert_eq(report.contains("unresolved_protected"), !visible)
    assert_true(
      physical_equal(
        @checked.parsed_check_collected_source_inputs(
          child.check_registry.unwrap(),
        ).unwrap(),
        original_inputs,
      ),
    )
  }
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  assert_true(
    project_request_check_outcome(
      parent,
      input,
      terminal,
      "{}",
      "ctx:" + "a".repeat(64),
      "program",
      "rev:" + "b".repeat(64),
      document.length(),
      None,
      0,
      None,
      0,
      "corr:" + "c".repeat(32),
      None,
    ).unwrap()
    is None,
  )
}

///|
test "Request original supplied locations use the matching representation without rechecking" {
  let limits = @publication_host.client_standard_program_preparation_limits()
  for raw in ["wrong", "K", "\u{212a}"] {
    let canonical = if raw == "wrong" { "wrong" } else { "K" }
    let document = "{\"version\":\"actql/0.1\",\"id\":\"protected-location\",\"params\":{\"missing\":{\"type\":\"number\"},\"" +
      canonical +
      "\":{\"type\":\"number\"}},\"stages\":[{\"id\":\"main\",\"inputs\":{\"rows\":{\"connector\":\"crm/main\",\"resource\":\"r\",\"view\":\"v\"}},\"steps\":[{\"select\":[\"private_field\"],\"as\":\"selected\"}],\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"private_field\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"main\",\"result\":\"out\"}}}}"
    let supplied_text = "{\"" + raw + "\":\"caller-private\"}"
    let supplied = @local_preparation.admit_captured_local_parameters(
      request_native_test_value(supplied_text),
      native_json_reader,
    ).unwrap()
    let (parent, child, _, input) = registration_parent_fixture(
      text=document,
      supplied=Some(supplied),
      computation_limits=Some(
        (limits, @publication_host.client_standard_effect_computation_limits()),
      ),
    )
    let terminal = match finish_request_computation_check(parent, input) {
      Err(issue) => issue
      Ok(_) => fail("the original protected Source must remain unresolved")
    }
    let original = child.check_outcome.unwrap()
    let project = (body : String?) => {
      project_request_check_outcome(
        parent,
        input,
        terminal,
        request_observation_publication(child),
        "ctx:" + "a".repeat(64),
        "program",
        "rev:" + "b".repeat(64),
        @utf8.encode(document).length(),
        None,
        0,
        Some("rev:" + "d".repeat(64)),
        @utf8.encode(supplied_text).length(),
        "corr:" + "c".repeat(32),
        None,
        original_parameters=body,
      )
    }
    let absent = project(None).unwrap().unwrap()
    assert_false(absent.contains("\"pointer\":\"/" + raw + "\""))
    let pointer_bytes = request_check_observation_bytes(
      child,
      child.arguments.unwrap().source_preparation.unwrap(),
      original,
      request_observation_publication(child),
      0L,
      Some(supplied_text),
    ).unwrap()
    let (retained, _) = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let policy = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      policy.retained_bytes - retained - pointer_bytes + 1L,
      0L,
    ).unwrap()
    assert_true(project(Some(supplied_text)) is Err(Capacity(_)))
    assert_true(physical_equal(child.check_outcome.unwrap(), original))
    assert_true(parent.phase == ProgramCheck && !child.busy)
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    let other = if raw == "wrong" {
      "other"
    } else if raw == "K" {
      "Z"
    } else {
      "Ω"
    }
    let moved = project(Some("{\"" + other + "\":\"caller-private\"}"))
      .unwrap()
      .unwrap()
    assert_false(moved.contains("\"pointer\":\"/" + other + "\""))
    assert_false(moved.contains("\"pointer\":\"/" + raw + "\""))
    let present = project(Some(supplied_text)).unwrap().unwrap()
    assert_true(present.contains("supplied_value_type_mismatch"))
    assert_true(present.contains("\"pointer\":\"/" + raw + "\""))
    assert_true(present.contains("unresolved_protected"))
    assert_false(present.contains("caller-private"))
    assert_false(present.contains("private_field"))
    assert_true(physical_equal(child.check_outcome.unwrap(), original))
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}
