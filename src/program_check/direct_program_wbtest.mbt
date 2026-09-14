///|
fn checked_direct_program_fixture(
  unused_source? : Bool = false,
  filter? : String = "",
  take? : String = "",
  imported? : Bool = false,
  append? : String = "",
  input_name? : String = "remote",
  set_operation? : String = "",
  duplicates? : String = "distinct",
  join_kind? : String = "",
  join_capacity? : Bool = true,
  generated_rows? : String = "",
  mix_generated? : Bool = false,
  local_input? : Bool = false,
  mix_local? : Bool = false,
  derive_body? : String = "",
  assertion_body? : String = "",
  group_body? : String = "",
  pivot_body? : String = "",
  analytic_body? : String = "",
  lag_body? : String = "",
  unpivot_body? : String = "",
  json_pick_path? : String = "",
  unnest_body? : String = "",
  array_expression? : String = "[id]",
  top_k_step? : String = "",
  watermark_body? : String = "",
  numeric_profile? : @numeric.Profile? = None,
) -> CheckedProgram raise {
  let original_text =
    #|{"version":"actql/0.1","id":"direct","stages":[{"id":"s","inputs":{"remote":{"connector":"crm/main","resource":"r","request":{"id":1,"tenant":null}}},"steps":[{"distinct":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"out":{"from":{"stage":"s","result":"out"}}}}
  let text = original_text.replace(
    old="\"remote\"",
    new="\"" + input_name + "\"",
  )
  let program = @syntax.parse(
    if local_input {
      let local_text = text.replace(
        old="\"inputs\":{\"remote\":",
        new="\"inputs\":{\"local\":{\"carrier\":\"relation\",\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"primary_key\":[\"id\"]},\"remote\":",
      )
      if mix_local {
        local_text.replace(
          old="\"steps\":[",
          new="\"steps\":[{\"from\":\"remote\",\"distinct\":[\"id\"],\"as\":\"remote_rows\"},{\"from\":\"local\",\"append\":{\"with\":\"remote_rows\"}},",
        )
      } else {
        local_text.replace(
          old="{\"distinct\":",
          new="{\"from\":\"local\",\"distinct\":",
        )
      }
    } else if generated_rows != "" {
      text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":" +
          generated_rows +
          "},\"as\":\"authored\"}," +
          (if mix_generated {
            "{\"from\":\"remote\",\"distinct\":[\"id\"],\"as\":\"remote_rows\"},{\"from\":\"authored\",\"append\":{\"with\":\"remote_rows\"}},"
          } else {
            ""
          }),
      )
    } else if join_kind != "" {
      text
      .replace(
        old="\"inputs\":{\"remote\":",
        new="\"inputs\":{\"right\":{\"connector\":\"crm/main\",\"resource\":\"r\",\"request\":{\"id\":2,\"tenant\":null},\"minimum_classification\":\"confidential\"},\"remote\":",
      )
      .replace(
        old="\"steps\":[",
        new="\"steps\":[{\"from\":\"remote\",\"distinct\":[\"id\"],\"as\":\"left_rows\"},{\"from\":\"right\",\"distinct\":[\"id\"],\"as\":\"right_rows\"},{\"from\":\"left_rows\",\"" +
          (if join_kind == "cross" { "cross_join" } else { "join" }) +
          "\":{\"with\":\"right_rows\"" +
          (if join_kind == "cross" {
            ""
          } else {
            ",\"kind\":\"" + join_kind + "\",\"on\":\"id\""
          }) +
          ",\"select\":{\"id\":\"left.id\"}}},",
      )
    } else if append != "" {
      text
      .replace(
        old="\"inputs\":{\"remote\":",
        new="\"inputs\":{\"right\":{\"connector\":\"crm/main\",\"resource\":\"r\",\"request\":{\"id\":2,\"tenant\":null},\"minimum_classification\":\"confidential\"},\"unused\":{\"connector\":\"crm/main\",\"resource\":\"r\",\"request\":{\"id\":3,\"tenant\":null},\"minimum_classification\":\"restricted\"},\"remote\":",
      )
      .replace(
        old="\"steps\":[",
        new="\"steps\":[{\"from\":\"remote\",\"" +
          (if set_operation == "" { "append" } else { set_operation }) +
          "\":{\"with\":\"" +
          append +
          "\"" +
          (if set_operation == "" {
            ""
          } else {
            ",\"duplicates\":\"" + duplicates + "\""
          }) +
          "}},",
      )
    } else if imported {
      text.replace(
        old="}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"out\"}}}}",
        new="},{\"id\":\"consumer\",\"inputs\":{\"imported\":{\"result\":{\"stage\":\"s\",\"result\":\"out\"}}},\"steps\":[],\"results\":{\"out\":{\"from\":\"imported\",\"fields\":[\"id\"]}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"consumer\",\"result\":\"out\"}}}}",
      )
    } else if watermark_body != "" {
      let watermarked = text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"distinct\":[\"id\"]},{\"sort\":[{\"id\":\"asc\"}]},{\"watermark_rows\":" +
          watermark_body +
          "},",
      )
      if watermark_body.contains("$param") {
        watermarked.replace(
          old="\"stages\":",
          new="\"params\":{\"threshold\":{\"type\":\"number\",\"default\":1}},\"stages\":",
        )
      } else {
        watermarked
      }
    } else if top_k_step != "" {
      let ranked = text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"distinct\":[\"id\"]}," + top_k_step + ",",
      )
      if top_k_step.contains("$param") {
        ranked.replace(
          old="\"stages\":",
          new="\"params\":{\"count\":{\"type\":\"number\",\"default\":2}},\"stages\":",
        )
      } else {
        ranked
      }
    } else if unnest_body != "" {
      text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"derive\":{\"items\":\"" +
          array_expression +
          "\"}},{\"unnest\":" +
          unnest_body +
          "},",
      )
    } else if json_pick_path != "" {
      text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"derive\":{\"payload\":{\"object\":{\"first\":{\"object\":{\"leaf\":\"id\"}}}}}},{\"json_pick\":{\"column\":\"payload\",\"path\":" +
          json_pick_path +
          ",\"output\":\"picked\"}},",
      )
    } else if unpivot_body != "" {
      text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"unpivot\":" + unpivot_body + "},",
      )
    } else if lag_body != "" {
      let navigation = text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"distinct\":[\"id\"]},{\"lag\":" + lag_body + "},",
      )
      if lag_body.contains("$param") {
        navigation.replace(
          old="\"stages\":",
          new="\"params\":{\"distance\":{\"type\":\"number\",\"default\":1}},\"stages\":",
        )
      } else {
        navigation
      }
    } else if analytic_body != "" {
      text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"distinct\":[\"id\"]},{\"analytic\":" +
          analytic_body +
          "},",
      )
    } else if pivot_body != "" {
      let pivoted = text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"derive\":{\"category\":\"to_string(id)\"}},{\"pivot\":" +
          pivot_body +
          "},",
      )
      if pivot_body.contains("\"$param\":\"threshold\"") {
        pivoted.replace(
          old="\"stages\":",
          new="\"params\":{\"threshold\":{\"type\":\"number\",\"default\":0}},\"stages\":",
        )
      } else {
        pivoted
      }
    } else if group_body != "" {
      text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"group\":" + group_body + "},",
      )
    } else if assertion_body != "" {
      text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"assert_rows\":" + assertion_body + "},",
      )
    } else if derive_body != "" {
      let derived = text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"derive\":" + derive_body + "},",
      )
      if derive_body.contains("$threshold") {
        derived.replace(
          old="\"stages\":",
          new="\"params\":{\"threshold\":{\"type\":\"number\",\"default\":0}},\"stages\":",
        )
      } else {
        derived
      }
    } else if take != "" {
      let sliced = text.replace(
        old="\"as\":\"selected\"}",
        new="\"as\":\"before_take\"},{\"take\":" +
          take +
          ",\"as\":\"selected\"}",
      )
      if take.contains("$param") {
        sliced.replace(
          old="\"stages\":",
          new="\"params\":{\"limit\":{\"type\":\"number\",\"default\":1}},\"stages\":",
        )
      } else {
        sliced
      }
    } else if filter != "" {
      let filtered = text.replace(
        old="\"steps\":[",
        new="\"steps\":[{\"filter\":" + filter + "},",
      )
      if filter.contains("$threshold") {
        filtered.replace(
          old="\"stages\":",
          new="\"params\":{\"threshold\":{\"type\":\"number\",\"default\":0}},\"stages\":",
        )
      } else {
        filtered
      }
    } else if unused_source {
      text
      .replace(
        old="\"inputs\":{\"remote\":",
        new="\"inputs\":{\"unused\":{\"connector\":\"crm/main\",\"resource\":\"r\",\"request\":{\"id\":2,\"tenant\":null},\"minimum_classification\":\"restricted\"},\"remote\":",
      )
      .replace(old="{\"distinct\":", new="{\"from\":\"remote\",\"distinct\":")
    } else {
      text
    },
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
  let environment = remote_environment_fixture(analytic=analytic_body != "")
  // No Program arithmetic assertion is needed: publication retains the Host
  // bound and distinct establishes its own key. Actual acquisition is not run.
  let mixed = @wire.check_mixed_claims([], [], {
    max_entities: 0,
    max_references: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let claims = @wire.check_mixed_program_claims(mixed, [], {
    max_witnesses: 0,
    max_references: 0,
  }).unwrap()
  let sources = @host.bind_claim_sources(claims, [], {
    max_entries: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }).unwrap()
  let sources = if join_kind != "" && join_capacity {
    local_join_capacity_fixture(environment, 1, 2)
  } else {
    sources
  }
  check(
    program,
    environment,
    None,
    if imported {
      [
        [@context.CapacityMaterial::{ sources, consumers: [], }],
        [
          @context.CapacityMaterial::{ sources, consumers: [], },
          @context.CapacityMaterial::{ sources, consumers: [], },
        ],
      ]
    } else {
      [
        [
          @context.CapacityMaterial::{
            sources,
            consumers: if join_kind != "" && join_capacity {
              [@capacity.Join(step=2, output=0)]
            } else {
              []
            },
          },
        ],
      ]
    },
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    source_limits_fixture(
      if join_kind != "" ||
        mix_generated ||
        mix_local ||
        pivot_body != "" ||
        analytic_body != "" ||
        lag_body != "" ||
        json_pick_path != "" ||
        unnest_body != "" ||
        top_k_step != "" ||
        watermark_body != "" {
        4
      } else {
        2
      },
    ),
    max_work=100000000,
    max_bytes=10000000,
    max_nodes=1000000,
    max_depth=100,
    numeric_profile~,
  )
}

///|
test "Local publication policy retains exact admission without borrowing an unused SourceView" {
  for mixed in [false, true] {
    let program = checked_direct_program_fixture(
      local_input=true,
      mix_local=mixed,
    )
    let policy = publication_source_policy(
      unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    assert_eq(
      publication_policy_source_count(policy),
      if mixed {
        1
      } else {
        0
      },
    )
    assert_eq(publication_policy_local_check_count(policy), 3)
    assert_eq(publication_policy_classification(policy), @environment.Unknown)
    let closure = @context.stage_requirement_inputs(requirements(program))
    for i in 0..<publication_policy_local_check_count(policy) {
      let check = publication_policy_local_check_at(policy, i).unwrap()
      assert_true(
        physical_equal(
          check,
          @context.local_input_closure_at(closure, i).unwrap(),
        ),
      )
      assert_eq(check.subject.name, "local")
      assert_true(
        physical_equal(check.subject.pipeline, program.units[0].pipeline),
      )
      assert_eq(
        @context.local_input_execution_phase(check),
        BeforeLocalInputUse,
      )
      assert_eq(@context.local_input_execution_failure(check), RejectLocalInput)
    }
    assert_eq(source_execution_count(program), 5)
    assert_eq(policy.prerequisite is None, !mixed)
  }
}

///|
test "Local policy selection does not accept another Program's admission closure" {
  let program = checked_direct_program_fixture(local_input=true)
  let other = checked_direct_program_fixture(local_input=true)
  let unit = program.units[0]
  let foreign = { ..unit, local_inputs: other.units[0].local_inputs, }
  let publication = @context.publication_row_limit_result(
    unit.publication_rows[0],
  )
  assert_true(
    prepare_publication_source_policy(foreign, publication, {
      work: 100000,
      bytes: 100000,
      nodes: 100000,
      depth: 100,
    })
    is None,
  )
}

///|
test "values policy preserves authored provenance without attributing unused sources" {
  for rows in ["[]", "[{\"id\":1}]"] {
    for mixed in [false, true] {
      let program = checked_direct_program_fixture(
        generated_rows=rows,
        mix_generated=mixed,
      )
      let policy = publication_source_policy(
        unit_publication_at(program, 0, 0).unwrap(),
      ).unwrap()
      assert_eq(
        publication_policy_source_count(policy),
        if mixed {
          1
        } else {
          0
        },
      )
      assert_eq(publication_policy_generator_count(policy), 1)
      let generator = publication_policy_generator_at(policy, 0).unwrap()
      assert_eq(generator.step, 0)
      assert_true(generator.operation is @pipeline.Values(_))
      guard generator.operation is @pipeline.Values(value) else {
        fail("missing values origin")
      }
      guard @pipeline.step_at(program.units[0].pipeline, 0).unwrap().operation
        is @pipeline.Values(original) else {
        fail("missing owned values")
      }
      assert_true(physical_equal(value, original))
      assert_eq(publication_policy_classification(policy), @environment.Unknown)
      assert_true(policy.unknown_provenance)
      assert_eq(source_execution_count(program), 5)
      if !mixed {
        let writer = @encode.writer(10000, 100, 10)
        emit_publication_source_policy(policy, writer)
        assert_eq(
          @encode.finish(writer),
          "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
        )
        assert_true(policy.prerequisite is None)
      }
      let closure = @context.stage_requirement_operations(requirements(program))
      let mut publications = 0
      for i in 0..<@context.operation_closure_count(closure) {
        if @context.operation_closure_at(closure, i)
          is Some(ExecutionCheck(ValuesPublication(check))) {
          assert_eq(check.site.step, 0)
          assert_true(
            physical_equal(check.site.pipeline, program.units[0].pipeline),
          )
          publications += 1
        }
      }
      assert_eq(publications, 1)
    }
  }
}

///|
test "source joins retain both input policies through flat publication" {
  for kind in ["inner", "left", "full", "semi", "anti", "cross"] {
    let program = checked_direct_program_fixture(join_kind=kind)
    let policy = publication_source_policy(
      unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    assert_eq(publication_policy_source_count(policy), 2)
    assert_eq(publication_policy_edge_count(policy), 5)
    assert_true(policy.policy is None)
    assert_true(policy.prerequisite is None)
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut limits = 0
    for i in 0..<@context.operation_closure_count(closure) {
      match @context.operation_closure_at(closure, i) {
        Some(ExecutionCheck(JoinOutputLimit(check))) => {
          assert_eq(check.site.step, 2)
          assert_true(
            physical_equal(
              @step_bounds.join_limit_pipeline(check.limit),
              program.units[0].pipeline,
            ),
          )
          limits += 1
        }
        Some(ExecutionCheck(CrossJoinRows(check))) if check.rule
          is CheckProductArithmetic => {
          assert_eq(check.site.step, 2)
          assert_true(
            physical_equal(
              @step_bounds.join_limit_pipeline(check.output_limit),
              program.units[0].pipeline,
            ),
          )
          limits += 1
        }
        _ => ()
      }
    }
    // Cross join additionally retains the product-arithmetic execution binding.
    assert_eq(limits, if kind == "cross" { 2 } else { 1 })
    try
      checked_direct_program_fixture(join_kind=kind, join_capacity=false)
    catch {
      Source(
        SourceView(
          Context(Stages(Capacity(0, 0, JoinCollection(MissingApplication(2)))))
        )
      ) => ()
      e => raise e
    } noraise {
      _ => fail("policy transfer bypassed join capacity closure")
    }
  }
}

///|
test "source set publication retains both comparison inputs and resource checks" {
  for operation in ["except", "intersect"] {
    for duplicates in ["all", "distinct"] {
      for right in ["right", "remote"] {
        let program = checked_direct_program_fixture(
          append=right,
          set_operation=operation,
          duplicates~,
        )
        let policy = publication_source_policy(
          unit_publication_at(program, 0, 0).unwrap(),
        ).unwrap()
        assert_eq(
          publication_policy_source_count(policy),
          if right == "right" {
            2
          } else {
            1
          },
        )
        assert_eq(publication_policy_edge_count(policy), 3)
        for i in 0..<publication_policy_source_count(policy) {
          let source = publication_policy_source_at(policy, i).unwrap()
          let name = @sourceviews.declaration(
              source_execution_subject(source).source,
            ).input_name
          assert_true(name == "remote" || (right == "right" && name == "right"))
        }
        let closure = @context.stage_requirement_operations(
          requirements(program),
        )
        let mut resources = 0
        for i in 0..<@context.operation_closure_count(closure) {
          if @context.operation_closure_at(closure, i)
            is Some(ExecutionCheck(SetRows(check))) &&
            check.rule is RequireComparisonResources {
            assert_eq(check.site.stage, 0)
            assert_eq(check.site.step, 0)
            assert_true(
              physical_equal(check.site.pipeline, program.units[0].pipeline),
            )
            resources += 1
          }
        }
        assert_eq(resources, 1)
      }
    }
  }
}

///|
test "publication policy charges long selected input names before comparison" {
  let short_program = checked_direct_program_fixture()
  let long_name = "x".repeat(4096)
  let long_program = checked_direct_program_fixture(input_name=long_name)
  let usage : Array[Int] = []
  let cids : Array[String] = []
  for program in [short_program, long_program] {
    let unit = program.units[0]
    let result = @context.publication_row_limit_result(unit.publication_rows[0])
    let measured = IdentityBudget::{
      work: 100000,
      bytes: 100000,
      nodes: 100000,
      depth: 100,
    }
    let policy = prepare_publication_source_policy(unit, result, measured).unwrap()
    let used = 100000 - measured.work
    usage.push(used)
    cids.push(policy.cid)
    let exact = IdentityBudget::{
      work: used,
      bytes: 100000,
      nodes: 100000,
      depth: 100,
    }
    let _ = prepare_publication_source_policy(unit, result, exact)
    assert_eq(exact.work, 0)
  }
  assert_eq(usage[1] - usage[0], long_name.length() - "remote".length())
  assert_eq(cids[0], cids[1])
  let unit = long_program.units[0]
  let result = @context.publication_row_limit_result(unit.publication_rows[0])
  try
    prepare_publication_source_policy(unit, result, {
      work: usage[0],
      bytes: 100000,
      nodes: 100000,
      depth: 100,
    })
  catch {
    BudgetExceeded => ()
    e => raise e
  } noraise {
    _ => fail("long name comparison escaped preparation budget")
  }
}

///|
test "source append policy follows both checked edges but excludes unused acquisitions" {
  for right in ["right", "remote"] {
    let program = checked_direct_program_fixture(append=right)
    let policy = publication_source_policy(
      unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    assert_eq(source_execution_count(program), 15)
    assert_eq(
      publication_policy_source_count(policy),
      if right == "right" {
        2
      } else {
        1
      },
    )
    assert_eq(
      effective_policy_occurrence_count(policy.effective),
      if right == "right" {
        2
      } else {
        1
      },
    )
    assert_eq(publication_policy_edge_count(policy), 3)
    let mut append_edges = 0
    for index in 0..<publication_policy_edge_count(policy) {
      let edge = publication_policy_edge_at(policy, index).unwrap()
      if edge.step == 0 {
        append_edges += 1
      }
    }
    assert_eq(append_edges, 2)
    for index in 0..<publication_policy_source_count(policy) {
      let source = publication_policy_source_at(policy, index).unwrap()
      let name = @sourceviews.declaration(
          source_execution_subject(source).source,
        ).input_name
      assert_true(name == "remote" || (right == "right" && name == "right"))
      assert_true(source_execution_kind(source) is CarrierResponse)
    }
    assert_eq(policy.policy is None, right == "right")
    assert_eq(policy.prerequisite is None, right == "right")
    let writer = @encode.hashing_writer(10000, 100, 10)
    emit_publication_source_policy(policy, writer)
    assert_eq("sha256:" + @encode.finish_hash(writer), policy.cid)
  }
}

///|
test "SourceView Result import retains the producer publication policy owner" {
  let program = checked_direct_program_fixture(imported=true)
  assert_eq(unit_count(program), 2)
  let producer = unit_publication_at(program, 0, 0).unwrap()
  let consumer = publication_source_policy(
    unit_publication_at(program, 1, 0).unwrap(),
  ).unwrap()
  let original = publication_source_policy(producer).unwrap()
  assert_true(physical_equal(consumer.imported_publication.unwrap(), producer))
  assert_true(
    physical_equal(
      consumer.prerequisite.unwrap(),
      original.prerequisite.unwrap(),
    ),
  )
  assert_eq(consumer.cid, original.cid)
  assert_eq(consumer.target, @pipeline.Input(0))
  assert_eq(source_execution_subject(consumer.prerequisite.unwrap()).stage, 0)
  assert_eq(publication_policy_import_count(consumer), 1)
  let imported = publication_policy_import_at(consumer, 0).unwrap()
  assert_eq(imported.input, 0)
  assert_true(physical_equal(imported.publication, producer))
}

///|
test "imported publication policy rejects foreign producers and bounds traversal" {
  let program = checked_direct_program_fixture(imported=true)
  let unit = program.units[1]
  let result = @context.publication_row_limit_result(unit.publication_rows[0])
  let foreign = checked_direct_program_fixture(imported=true)
  for producers in [[], [foreign.units[0]]] {
    try
      prepare_publication_source_policy(
        unit,
        result,
        { work: 100000, bytes: 100000, nodes: 100000, depth: 100, },
        producers=Some(producers),
      )
    catch {
      ForeignOwner => ()
      e => raise e
    } noraise {
      _ => fail("unowned producer accepted")
    }
  }
  let measured = IdentityBudget::{
    work: 100000,
    bytes: 100000,
    nodes: 100000,
    depth: 100,
  }
  let expected = prepare_publication_source_policy(
    unit,
    result,
    measured,
    producers=Some([program.units[0]]),
  ).unwrap()
  let used = 100000 - measured.work
  let exact = IdentityBudget::{
    work: used,
    bytes: 100000,
    nodes: 100000,
    depth: 100,
  }
  assert_eq(
    prepare_publication_source_policy(
      unit,
      result,
      exact,
      producers=Some([program.units[0]]),
    ).unwrap().cid,
    expected.cid,
  )
  assert_eq(exact.work, 0)
  try
    prepare_publication_source_policy(
      unit,
      result,
      { work: used - 1, bytes: 100000, nodes: 100000, depth: 100, },
      producers=Some([program.units[0]]),
    )
  catch {
    BudgetExceeded | Encoding(_) => ()
    e => raise e
  } noraise {
    _ => fail("partial imported policy escaped budget")
  }
}

///|
test "direct SourceView take retains selection controls and owned policy" {
  for count in ["1", "{\"$param\":\"limit\"}", "{\"count\":1,\"offset\":2}"] {
    let program = checked_direct_program_fixture(take=count)
    let policy = publication_source_policy(
      unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    assert_eq(publication_policy_slice_count(policy), 1)
    let slice = publication_policy_slice_at(policy, 0).unwrap()
    assert_eq(slice.step, 1)
    assert_eq(
      slice.offset,
      @relation.Literal(if count.contains("offset") { 2L } else { 0L }),
    )
    assert_eq(
      slice.count,
      if count.contains("$param") {
        @relation.Parameter("limit")
      } else {
        @relation.Literal(1L)
      },
    )
    guard @pipeline.step_at(program.units[0].pipeline, 1).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("expected take")
    }
    assert_true(physical_equal(slice.operation, operation))
    let closure = @context.stage_requirement_operations(requirements(program))
    let mut order_found = false
    for index in 0..<@context.operation_closure_count(closure) {
      if @context.operation_closure_at(closure, index)
        is Some(StaticResolution(Order(link))) &&
        link.site.stage == 0 &&
        link.site.step == 1 {
        assert_true(
          physical_equal(link.site.pipeline, program.units[0].pipeline),
        )
        order_found = true
      }
    }
    assert_true(order_found)
    assert_true(publication_policy_slice_at(policy, -1) is None)
    assert_true(publication_policy_slice_at(policy, 1) is None)
    assert_eq(publication_policy_classification(policy), @environment.Unknown)
    let writer = @encode.hashing_writer(10000, 100, 10)
    emit_publication_source_policy(policy, writer)
    assert_eq("sha256:" + @encode.finish_hash(writer), policy.cid)
  }
}

///|
test "filter publication retains its checked predicate and policy occurrence" {
  for predicate in ["\"id = id\"", "\"id > 0\"", "\"id > $threshold\""] {
    let program = checked_direct_program_fixture(filter=predicate)
    let policy = publication_source_policy(
      unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    assert_eq(publication_policy_predicate_count(policy), 1)
    let occurrence = publication_policy_predicate_at(policy, 0).unwrap()
    assert_eq(occurrence.step, 0)
    guard @pipeline.step_at(program.units[0].pipeline, 0).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("expected filter")
    }
    assert_true(
      physical_equal(
        occurrence.expression,
        @relation.binding_expression_at(operation, 0).unwrap(),
      ),
    )
    assert_eq(occurrence.unknown_provenance, predicate != "\"id = id\"")
    assert_eq(@typing.node_count(occurrence.expression), 3)
    assert_true(publication_policy_predicate_at(policy, -1) is None)
    assert_true(publication_policy_predicate_at(policy, 1) is None)
    let writer = @encode.writer(10000, 100, 10)
    emit_publication_source_policy(policy, writer)
    assert_eq(
      "sha256:" + @sha.text_hex(@encode.finish(writer)).unwrap(),
      policy.cid,
    )
    assert_true(policy.unknown_provenance)
    assert_true(
      source_execution_kind(policy.prerequisite.unwrap()) is CarrierResponse,
    )
  }
}

///|
test "filter and exact-copy derive policy transfer charge their complete traversal" {
  for
    program in [
      checked_direct_program_fixture(filter="\"id > $threshold\""),
      checked_direct_program_fixture(
        derive_body="[{\"x\":\"id\"},{\"y\":\"x\"}]",
      ),
      checked_direct_program_fixture(
        derive_body="[{\"x\":\"id + 1\"},{\"y\":\"x + $threshold\"}]",
      ),
      checked_direct_program_fixture(
        group_body="{\"by\":[\"id\"],\"aggregates\":{\"n\":{\"fn\":\"count\",\"expr\":\"1\",\"filter\":\"FALSE\"}}}",
      ),
      checked_direct_program_fixture(
        group_body="{\"by\":[\"id\"],\"aggregates\":{}}",
      ),
    ] {
    let unit = program.units[0]
    let publication = @context.publication_row_limit_result(
      unit.publication_rows[0],
    )
    let initial = 100000
    let measured = IdentityBudget::{
      work: initial,
      bytes: initial,
      nodes: initial,
      depth: 100,
    }
    let expected = prepare_publication_source_policy(
      unit, publication, measured,
    ).unwrap()
    let used = initial - measured.work
    let exact = IdentityBudget::{
      work: used,
      bytes: initial,
      nodes: initial,
      depth: 100,
    }
    let actual = prepare_publication_source_policy(unit, publication, exact).unwrap()
    assert_eq(actual.cid, expected.cid)
    assert_eq(exact.work, 0)
    let short = IdentityBudget::{
      work: used - 1,
      bytes: initial,
      nodes: initial,
      depth: 100,
    }
    try prepare_publication_source_policy(unit, publication, short) catch {
      BudgetExceeded | Encoding(_) => ()
      error => raise error
    } noraise {
      _ => fail("partial policy escaped preparation budget")
    }
  }
}

///|
test "empty and exact-copy derives retain owned publication policy mappings" {
  let baseline = checked_direct_program_fixture()
  let expected = publication_source_policy(
    unit_publication_at(baseline, 0, 0).unwrap(),
  ).unwrap()
  for
    body in [
      "{}", "{\"x\":\"id\"}", "[{\"id\":\"id\"}]", "[{\"x\":\"id\"},{\"y\":\"x\"}]",
    ] {
    let program = checked_direct_program_fixture(derive_body=body)
    let policy = publication_source_policy(
      unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    assert_eq(policy.cid, expected.cid)
    assert_eq(publication_policy_source_count(policy), 1)
    assert_eq(publication_policy_copy_count(policy), 1)
    let copy = publication_policy_copy_at(policy, 0).unwrap()
    assert_eq(copy.step, 0)
    guard @pipeline.step_at(program.units[0].pipeline, 0).unwrap().operation
      is @pipeline.Unary(operation) else {
      fail("missing owned derive")
    }
    assert_true(physical_equal(copy.operation, operation))
    assert_eq(
      @relation.binding_count(copy.operation),
      if body == "{}" {
        0
      } else if body == "[{\"x\":\"id\"},{\"y\":\"x\"}]" {
        2
      } else {
        1
      },
    )
    for i in 0..<@relation.binding_count(copy.operation) {
      assert_true(
        @relation.binding_copy_at(copy.operation, i).unwrap().input is Some(_),
      )
    }
    if @relation.binding_count(copy.operation) == 2 {
      assert_eq(
        @relation.binding_copy_at(copy.operation, 1).unwrap().input,
        Some(@relation.PriorSlot(0)),
      )
    }
    assert_true(publication_policy_copy_at(policy, -1) is None)
    assert_true(publication_policy_copy_at(policy, 1) is None)
  }
}

///|
test "publication policy follows the selected input rather than unused source policies" {
  let baseline = checked_direct_program_fixture()
  let baseline_policy = publication_source_policy(
    unit_publication_at(baseline, 0, 0).unwrap(),
  ).unwrap()
  let program = checked_direct_program_fixture(unused_source=true)
  assert_eq(source_execution_count(program), 10)
  let published = publication_source_policy(
    unit_publication_at(program, 0, 0).unwrap(),
  ).unwrap()
  let selected = source_execution_subject(published.prerequisite.unwrap())
  assert_eq(published.cid, baseline_policy.cid)
  assert_eq(
    published.policy.unwrap().response_cid,
    baseline_policy.policy.unwrap().response_cid,
  )
  // Equal policy identities do not make independently checked owners equal.
  assert_false(
    physical_equal(
      published.prerequisite.unwrap(),
      baseline_policy.prerequisite.unwrap(),
    ),
  )
  assert_eq(@sourceviews.declaration(selected.source).input_name, "remote")
  assert_true(published.policy.unwrap().response.minimum is None)
  let mut unused = 0
  for i in 0..<source_execution_count(program) {
    let check = source_execution_at(program, i).unwrap()
    let subject = source_execution_subject(check)
    if @sourceviews.declaration(subject.source).input_name == "unused" {
      unused += 1
      assert_true(subject.response_policy.minimum is Some("restricted"))
      assert_true(
        subject.response_policy_cid != published.policy.unwrap().response_cid,
      )
      assert_false(physical_equal(subject, selected))
    }
  }
  // Unused acquisition still has every mandatory check, but does not enter the
  // selected Result's effective policy or its response-admission prerequisite.
  assert_eq(unused, 5)
}

///|
test "direct SourceView closes through the public check entry" {
  let program = checked_direct_program_fixture()
  assert_eq(unit_count(program), 1)
  assert_eq(source_execution_count(program), 5)
  assert_eq(unit_publication_count(program, 0), Some(1))
  let publication = unit_publication_at(program, 0, 0).unwrap()
  let policy = publication_source_policy(publication).unwrap()
  assert_eq(policy.target, @pipeline.Step(0))
  assert_true(
    source_execution_kind(policy.prerequisite.unwrap()) is CarrierResponse,
  )
  let writer = @encode.hashing_writer(10000, 100, 10)
  emit_direct_source_policy(policy.policy.unwrap(), writer)
  assert_eq(policy.cid, "sha256:" + @encode.finish_hash(writer))
  assert_true(
    physical_equal(
      policy.policy.unwrap(),
      source_execution_subject(policy.prerequisite.unwrap()).direct_policy.unwrap(),
    ),
  )
  for index in 0..<source_execution_count(program) {
    let check = source_execution_at(program, index).unwrap()
    let subject = source_execution_subject(check)
    assert_true(physical_equal(subject.owner, source_identity(program)))
    assert_true(subject.direct_policy is Some(_))
    assert_eq(subject.stage, 0)
    assert_eq(subject.input, 0)
    for dependency in 0..<source_execution_prerequisite_count(check) {
      let prior = source_execution_prerequisite_at(check, dependency).unwrap()
      assert_true(physical_equal(source_execution_subject(prior), subject))
    }
  }
}

///|
test "computed derives retain Relation policy and owned value versions" {
  for
    body in [
      "{\"x\":\"id + id\"}", "{\"x\":\"id + 1\"}", "{\"x\":\"id + $threshold\"}",
      "[{\"x\":\"id + 1\"},{\"y\":\"x + id\"}]", "[{\"id\":\"0\"}]", "{\"x\":\"1 / 0\"}",
    ] {
    let program = checked_direct_program_fixture(derive_body=body)
    let policy = publication_source_policy(
      unit_publication_at(program, 0, 0).unwrap(),
    ).unwrap()
    assert_eq(publication_policy_derivation_count(policy), 1)
    assert_eq(publication_policy_copy_count(policy), 0)
    assert_eq(publication_policy_source_count(policy), 1)
    let derived = publication_policy_derivation_at(policy, 0).unwrap()
    assert_eq(derived.step, 0)
    assert_eq(derived.unknown_provenance, body != "{\"x\":\"id + id\"}")
    guard @pipeline.step_at(program.units[0].pipeline, 0).unwrap().operation
      is @pipeline.Unary(original) else {
      fail("missing derive")
    }
    assert_true(physical_equal(derived.operation, original))
    if @relation.binding_count(derived.operation) == 2 {
      let refs = @relation.references(
        @relation.binding_at(derived.operation, 1).unwrap(),
      )
      assert_eq(refs[0].target, @relation.PriorSlot(0))
    }
    assert_true(publication_policy_derivation_at(policy, -1) is None)
    assert_true(publication_policy_derivation_at(policy, 1) is None)
    // Dropping x/y, or replacing id, does not remove observed source policy.
    assert_eq(source_execution_count(program), 5)
  }
}

///|
test "direct source audit rejects missing foreign and disconnected checks atomically" {
  let program = checked_direct_program_fixture()
  let checks = program.units[0].source_execution
  let exact = IdentityBudget::{ work: 16, bytes: 0, nodes: 0, depth: 0, }
  audit_source_execution(program.contracts, checks, exact)
  assert_eq(exact.work, 0)
  let short = IdentityBudget::{ work: 15, bytes: 0, nodes: 0, depth: 0, }
  try audit_source_execution(program.contracts, checks, short) catch {
    BudgetExceeded => ()
    error => raise error
  } noraise {
    _ => fail("source audit escaped work budget")
  }
  let foreign = checked_direct_program_fixture().units[0].source_execution
  let missing = checks[:4].to_owned()
  let substituted = checks.copy()
  substituted[4] = foreign[4]
  let disconnected = checks.copy()
  disconnected[3] = { ..checks[3], prerequisites: [], }
  let duplicated = checks.copy()
  duplicated[2] = checks[1]
  for invalid in [missing, foreign, substituted, disconnected, duplicated] {
    try
      audit_source_execution(program.contracts, invalid, {
        work: 1000,
        bytes: 0,
        nodes: 0,
        depth: 0,
      })
    catch {
      ForeignOwner | UnclosedSourceExecution(_, _) => ()
      error => raise error
    } noraise {
      _ => fail("invalid source closure admitted")
    }
  }
}
