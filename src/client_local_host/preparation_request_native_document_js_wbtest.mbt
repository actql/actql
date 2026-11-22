///|
test "static native Request checks raw large JSON once and compiles only for explain" {
  let (environment, publication) = request_query_publication_fixture()
  let document = " ".repeat(70000) + native_driver_program
  let parameters = " ".repeat(70000) + "{\"n\":9}"
  let (owner, input) = native_driver_parent(document + parameters)
  prepare_request_native_document_check(
    owner,
    input,
    document,
    @frontend.Json,
    Some(parameters),
    None,
    environment,
    publication,
  ).unwrap()
  assert_true(owner.submitted_intent is None && owner.compiled_program is None)
  assert_true(
    owner.program_check.unwrap().check_outcome is Some(@checked.Checked(_)),
  )
  let program = owner.held_program.unwrap()
  let outcome = owner.program_check.unwrap().check_outcome.unwrap()
  let report = project_request_completed_check_outcome(
      owner,
      input,
      "{\"environmentCid\":\"" +
      @checked.checking_environment_cid(environment) +
      "\",\"aliases\":[]}",
      "ctx:" + "a".repeat(64),
      "program",
      "rev:" + "b".repeat(64),
      document.length(),
      None,
      0,
      Some("rev:" + "c".repeat(64)),
      parameters.length(),
      "corr:" + "d".repeat(32),
      None,
      original_parameters=Some(parameters),
    )
    .unwrap()
    .unwrap()
  assert_true(report.contains("\"verdict\":\"verified\""), msg=report)
  assert_true(
    physical_equal(owner.program_check.unwrap().check_outcome.unwrap(), outcome),
  )
  let plan = request_native_static_plan_view(
    owner,
    input,
    environment,
    publication,
    request_program_module_manifests(),
  ).unwrap()
  assert_true(plan.contains("actql-plan-view/0.1"), msg=plan)
  assert_true(physical_equal(owner.held_program.unwrap(), program))
  assert_true(
    owner.program_source_free is None && !owner.program_body_attempted,
  )
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_eq(@resources.ledger_usage(owner.ledger).live_reservations, 0)
}

///|
test "static native Request preserves Parameters-first malformed input and same typed refusal" {
  let (environment, publication) = request_query_publication_fixture()
  let (owner, input) = native_driver_parent("{ malformed input")
  let result = prepare_request_native_document_check(
    owner,
    input,
    "{ malformed input",
    @frontend.Json,
    Some("{ malformed Parameters"),
    None,
    environment,
    publication,
  )
  assert_true(
    result is Err(Preparation(Parameters(@local_preparation.SuppliedSyntax(_)))),
  )
  assert_true(owner.program_json is None && owner.program_check is None)
  assert_true(owner.query_syntax is None && owner.submitted_intent is None)
  abort_request_preparation_after_cleanup(owner).unwrap()
}

///|
test "static native Request keeps SQL Pipe originals configured primary and declarations" {
  let (environment, publication) = request_query_publication_fixture()
  for
    (document, format) in [
      ("SELECT @n AS id", @frontend.Sql),
      ("WITH seed AS (SELECT @n AS id) FROM seed |> SELECT id", @frontend.Text),
    ] {
    let (owner, input) = native_driver_parent(document)
    let checked = prepare_request_native_document_check(
      owner,
      input,
      document,
      format,
      Some("{\"n\":7}"),
      Some("{\"n\":{\"type\":\"number\"}}"),
      environment,
      publication,
    )
    match checked {
      Err(QuerySyntax(Frontend(@frontend.QuerySyntax(issue)))) =>
        fail(@debug.to_string(issue))
      Err(issue) => {
        let original : Error = issue
        fail(@debug.to_string(original))
      }
      Ok(_) => ()
    }
    checked.unwrap()
    let syntax = owner.query_syntax.unwrap().query.unwrap().unwrap()
    assert_true(owner.native_query_declarations is Some(_))
    let plan = request_native_static_plan_view(
      owner,
      input,
      environment,
      publication,
      request_program_module_manifests(),
    ).unwrap()
    assert_true(plan.contains("actql-plan-view/0.1"), msg=plan)
    assert_true(
      physical_equal(
        owner.query_syntax.unwrap().query.unwrap().unwrap(),
        syntax,
      ),
    )
    assert_true(owner.submitted_intent is None && !owner.program_body_attempted)
    abort_request_preparation_after_cleanup(owner).unwrap()
  }
}

///|
test "static native Request foreign input refuses before parser and capacity changes" {
  let (environment, publication) = request_query_publication_fixture()
  let (owner, input) = native_driver_parent("SELECT 2 AS id")
  let before = @resources.ledger_usage(owner.ledger)
  assert_true(
    prepare_request_native_document_check(
      owner,
      [1],
      "SELECT 2 AS id",
      @frontend.Sql,
      None,
      None,
      environment,
      publication,
    )
    is Err(Preparation(ForeignOriginal)),
  )
  assert_eq(@resources.ledger_usage(owner.ledger), before)
  assert_true(owner.query_syntax is None && owner.program_json is None)
  abort_request_preparation_after_cleanup(owner).unwrap()
  assert_true(
    prepare_request_native_document_check(
      owner,
      input,
      "SELECT 2 AS id",
      @frontend.Sql,
      None,
      None,
      environment,
      publication,
    )
    is Err(Preparation(WrongPhase)),
  )
}

///|
test "static native Request retains explicit root NULL as an invalid supplied original" {
  let (environment, publication) = request_query_publication_fixture()
  let (owner, input) = native_driver_parent(native_driver_program)
  let result = prepare_request_native_document_check(
    owner,
    input,
    native_driver_program,
    @frontend.Json,
    Some("null"),
    None,
    environment,
    publication,
  )
  assert_true(
    owner.native_parameters is Some(original) && @decode.is_null(original),
  )
  assert_true(result is Err(CheckOutcome(@checked.Rejected(_))))
  assert_true(owner.compiled_program is None && owner.submitted_intent is None)
  abort_request_preparation_after_cleanup(owner).unwrap()
}

///|
test "static native Request preserves original private Source and authored Effect reports" {
  let (environment, publication) = request_query_publication_fixture()
  let protected_document = "{\"version\":\"actql/0.1\",\"id\":\"static-private-source\",\"stages\":[{\"id\":\"s\",\"inputs\":{\"rows\":{\"connector\":\"private\",\"resource\":\"missing\",\"view\":\"v\"}},\"steps\":[{\"from\":\"rows\",\"select\":[\"id\"],\"as\":\"r\"}],\"results\":{\"out\":{\"from\":\"r\",\"fields\":[\"id\"]}}}],\"results\":{\"answer\":{\"from\":{\"stage\":\"s\",\"result\":\"out\"}}}}"
  let effect = native_driver_program.replace(
    old="\"results\":{\"rows\":",
    new="\"effects\":{\"save\":{\"create\":{\"target\":\"connector://private/missing\",\"mapping\":\"mapping:missing.v1\",\"from\":{\"result\":\"rows\"}}}},\"results\":{\"rows\":",
  )
  let wire = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  let context = "ctx:" + "a".repeat(64)
  let revision = "rev:" + "b".repeat(64)
  let correlation = "corr:" + "c".repeat(32)
  for document in [protected_document, effect] {
    let expected = @local_preparation.client_program_check_program(
      document,
      environment,
      wire,
      None,
      context,
      revision,
      None,
      correlation,
      "bound_input",
      None,
    )
    let (owner, input) = native_driver_parent(document)
    let checked = prepare_request_native_document_check(
      owner,
      input,
      document,
      @frontend.Json,
      None,
      None,
      environment,
      publication,
    )
    let actual = match checked {
      Ok(_) =>
        project_request_completed_check_outcome(
          owner,
          input,
          wire,
          context,
          "program",
          revision,
          @utf8.encode(document).length(),
          Some(revision),
          0,
          None,
          0,
          correlation,
          None,
          original_document=Some(document),
        )
        .unwrap()
        .unwrap()
      Err(issue) =>
        project_request_check_outcome(
          owner,
          input,
          issue,
          wire,
          context,
          "program",
          revision,
          @utf8.encode(document).length(),
          Some(revision),
          0,
          None,
          0,
          correlation,
          None,
          original_document=Some(document),
        )
        .unwrap()
        .unwrap()
    }
    assert_eq(actual, expected)
    assert_true(
      owner.compiled_program is None && owner.submitted_intent is None,
    )
    abort_request_preparation_after_cleanup(owner).unwrap()
  }
}

///|
fn static_native_effect_publication(
  environment : @checked.CheckEnvironment,
) -> (@source_publication.PreparedPublishedQueryEnvironment, String) {
  let wire = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[],\"updateTargets\":[{\"name\":\"crm.Account\",\"targetRef\":\"connector://crm/account\",\"installationBindingCid\":\"sha256:" +
    "d".repeat(64) +
    "\",\"installationOwnerCid\":\"sha256:" +
    "e".repeat(64) +
    "\"}]}"
  (
    @source_publication.prepare_published_query_environment(environment, wire).unwrap(),
    wire,
  )
}

///|
test "static Native UPDATE keeps one original semantic check and never compiles or constructs a Run" {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:40c45acbf81bdf192d79b7e8f65a5731ba6065b1d4b8cc7b4cab89ab4ac85c60",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let (publication, wire) = static_native_effect_publication(environment)
  for (assignment, valid) in [("amount", true), ("'wrong-type'", false)] {
    let document = "SELECT 1 AS id, 2 AS amount |> RESULT out |> EFFECT UPDATE crm.Account FROM RESULT out ID id SET (Name = " +
      assignment +
      ")"
    let (parent, input) = native_driver_parent(document)
    let outcome = prepare_request_native_document_check(
      parent,
      input,
      document,
      @frontend.Text,
      None,
      None,
      environment,
      publication,
    )
    let child = parent.program_check.unwrap()
    let original = child.static_effect_check.unwrap()
    let result = original.result.unwrap()
    let report = if valid {
      outcome.unwrap()
      assert_true(result is Ok(_))
      project_request_completed_check_outcome(
        parent,
        input,
        wire,
        "ctx:" + "a".repeat(64),
        "text",
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
    } else {
      guard outcome is Err(issue) &&
        issue
        is Preparation(
          ProgramCheck(EffectCompilation(Static(MappingLiterals(_))))
        ) else {
        fail("retain the actual static Mapping type error")
      }
      project_request_check_outcome(
        parent,
        input,
        issue,
        wire,
        "ctx:" + "a".repeat(64),
        "text",
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
    }
    assert_true(
      report.contains(
        if valid {
          "\"verdict\":\"verified\""
        } else {
          "\"verdict\":\"invalid\""
        },
      ),
      msg=report,
    )
    assert_eq(parent._observed_query_parse_calls, 1L)
    assert_eq(parent._observed_query_lower_calls, 1L)
    assert_eq(child._observed_semantic_check_calls, 1L)
    assert_eq(child._observed_program_compile_calls, 0L)
    assert_true(
      child.compiled_effect is None &&
      parent.compiled_effect is None &&
      parent.compiled_program is None &&
      parent.submitted_intent is None &&
      !parent.program_body_attempted,
    )
    assert_true(physical_equal(child.static_effect_check.unwrap(), original))
    assert_true(
      physical_equal(child.static_effect_check.unwrap().result.unwrap(), result),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_true(child.static_effect_check is None)
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "static Native unresolved UPDATE preserves independent prefix type failure and original cleanup" {
  let (environment, publication) = request_query_publication_fixture()
  let wire = "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  for (operand, invalid) in [("2", false), ("'text'", true)] {
    let document = "WITH unused AS (SELECT 1 + " +
      operand +
      " AS value) SELECT 1 AS id |> RESULT out |> EFFECT UPDATE hidden.Account FROM RESULT out ID id SET (Name = 1)"
    let (parent, input) = native_driver_parent(document)
    let outcome = prepare_request_native_document_check(
      parent,
      input,
      document,
      @frontend.Text,
      None,
      None,
      environment,
      publication,
    )
    guard outcome is Err(issue) else {
      fail("an unresolved target cannot issue a complete static check")
    }
    let report = project_request_check_outcome(
        parent,
        input,
        issue,
        wire,
        "ctx:" + "a".repeat(64),
        "text",
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
    if invalid {
      assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
      assert_true(report.contains("expression_domain_mismatch"), msg=report)
    } else {
      assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
      assert_true(report.contains("unresolved_protected"), msg=report)
    }
    assert_true(!report.contains("check_internal"), msg=report)
    assert_eq(parent._observed_query_parse_calls, 1L)
    assert_eq(parent._observed_query_lower_calls, 1L)
    assert_true(parent.program_check is None && parent.compiled_program is None)
    assert_true(
      parent.compiled_effect is None && parent.submitted_intent is None,
    )
    assert_true(!parent.program_body_attempted)
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "static Native UPDATE quote keeps its original before exact or one-short Mapping construction" {
  for short in [false, true] {
    for retention in [true, false] {
      let (parent, child, input, _) = request_effect_fixture(automatic=true)
      finish_request_computation_check(parent, input).unwrap()
      let candidate = child.effect_candidate.unwrap()
      let checked = @checked.effect_computation_checked_program(candidate)
      let environment = child.arguments.unwrap().environment
      let (publication, _) = static_native_effect_publication(environment)
      let bytes = program_check_data_extent_cost(child.check_data.unwrap()).unwrap() +
        sequence_demand_scalar_delta_bytes +
        program_effect_selection_extent_cost(
          @syntax.program_preparation_data(
            @checked.checked_source_program(checked),
          ).effect_members,
        ).unwrap()
      let (r, e) = @resources.preparation_capacity_working_extents(
        child.capacity,
        input,
      ).unwrap()
      let expected = (r + bytes, e + bytes)
      let limits = @resources.ledger_limits(parent.ledger)
      let blocker = @resources.reserve_capacity(
        parent.ledger,
        if retention {
          limits.retained_bytes - expected.0 + (if short { 1L } else { 0L })
        } else {
          0L
        },
        if retention {
          0L
        } else {
          limits.execution_bytes - expected.1 + (if short { 1L } else { 0L })
        },
      ).unwrap()
      let result = prepare_request_static_effect_check(
        parent, input, publication,
      )
      let original = child.static_effect_check.unwrap()
      assert_true(physical_equal(original.publication, publication))
      assert_eq(child.compilation_quote, Some(expected))
      assert_eq(child._observed_program_compile_calls, 0L)
      assert_true(child.compiled_effect is None && child.work is None)
      if short {
        assert_true(
          if retention {
            result
            is Err(
              Preparation(ProgramCheck(Capacity(Resource(RetentionLimit))))
            )
          } else {
            result
            is Err(
              Preparation(ProgramCheck(Capacity(Resource(ExecutionLimit))))
            )
          },
        )
        assert_true(original.result is None)
      } else {
        result.unwrap()
        assert_true(original.result is Some(Ok(_)))
      }
      @resources.settle_capacity(parent.ledger, blocker).unwrap()
      if short {
        prepare_request_static_effect_check(parent, input, publication).unwrap()
      }
      assert_true(physical_equal(child.static_effect_check.unwrap(), original))
      assert_true(physical_equal(child.effect_candidate.unwrap(), candidate))
      assert_eq(
        @resources.preparation_capacity_working_extents(child.capacity, input),
        Ok(expected),
      )
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
}

///|
test "static Effect report admits both findings per header before its exact original writer" {
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:40c45acbf81bdf192d79b7e8f65a5731ba6065b1d4b8cc7b4cab89ab4ac85c60",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let (publication, wire) = static_native_effect_publication(environment)
  let document = "SELECT 1 AS id, 2 AS amount |> RESULT out |> EFFECT UPDATE crm.Account FROM RESULT out ID id SET (Name = amount)"
  for short in [false, true] {
    for retention in [true, false] {
      let (parent, input) = native_driver_parent(document)
      prepare_request_native_document_check(
        parent,
        input,
        document,
        @frontend.Text,
        None,
        None,
        environment,
        publication,
      ).unwrap()
      let child = parent.program_check.unwrap()
      let selected = child.static_effect_check.unwrap()
      let result = selected.result.unwrap()
      // One authored header can add BOTH resolution-budget and protected
      // findings; four additional fixed findings cover the final result.
      // Header controls12H16R16W are448 bytes, independently pinned here.
      let bytes = 448L +
        request_check_observation_inventory_bytes(wire, 6L, 0L).unwrap()
      let (r, e) = @resources.preparation_capacity_working_extents(
        parent.capacity,
        input,
      ).unwrap()
      let limits = @resources.ledger_limits(parent.ledger)
      let blocker = @resources.reserve_capacity(
        parent.ledger,
        if retention {
          limits.retained_bytes - r - bytes + (if short { 1L } else { 0L })
        } else {
          0L
        },
        if retention {
          0L
        } else {
          limits.execution_bytes - e - bytes + (if short { 1L } else { 0L })
        },
      ).unwrap()
      let project = () => {
        project_request_completed_check_outcome(
          parent,
          input,
          wire,
          "ctx:" + "a".repeat(64),
          "text",
          "rev:" + "b".repeat(64),
          document.length(),
          None,
          0,
          None,
          0,
          "corr:" + "c".repeat(32),
          None,
        )
      }
      let projected = project()
      if short {
        assert_true(
          if retention {
            projected is Err(Capacity(Resource(RetentionLimit)))
          } else {
            projected is Err(Capacity(Resource(ExecutionLimit)))
          },
        )
        assert_eq(
          @resources.preparation_capacity_working_extents(
            parent.capacity,
            input,
          ),
          Ok((r, e)),
        )
      } else {
        assert_true(
          projected.unwrap().unwrap().contains("\"verdict\":\"verified\""),
        )
        assert_eq(
          @resources.preparation_capacity_working_extents(
            parent.capacity,
            input,
          ),
          Ok((r + bytes, e + bytes)),
        )
      }
      assert_true(physical_equal(child.static_effect_check.unwrap(), selected))
      assert_true(physical_equal(selected.result.unwrap(), result))
      assert_true(!child.busy && parent.phase == ProgramCheck)
      @resources.settle_capacity(parent.ledger, blocker).unwrap()
      if short {
        assert_true(
          project().unwrap().unwrap().contains("\"verdict\":\"verified\""),
        )
      }
      assert_eq(child._observed_semantic_check_calls, 1L)
      assert_eq(child._observed_program_compile_calls, 0L)
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
}
