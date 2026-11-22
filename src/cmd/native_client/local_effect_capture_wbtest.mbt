///|
test "Native Work capture exposes the original owner method without a supplied journal" {
  // This compiles the real Host method, not an uninstalled CLI adapter. It opens no Source, Store or Provider and
  // is not evidence that the Native physical component fixture executed.
  let caller = fn(
    work : @local_host.NativeClientEffectSourceWork,
    retention : @publication.PublicationContract,
    limits : @run_host.PublicationOutputExportLimits,
    max_bytes : Int,
    max_nodes : Int,
    max_depth : Int,
  ) {
    work.prepare_original_capture_context(
      retention, limits, max_bytes, max_nodes, max_depth,
    )
  }
  caller |> ignore
  assert_true(
    @local_host.NativeClientEffectCaptureIssue::Normalization(
      @run_host.MissingOriginalJournal,
    )
    is Normalization(@run_host.MissingOriginalJournal),
  )
}

///|
// Real Native Request/Plan/operation owners. No Source, Provider, Account,
// Journal or mutation is executed by this constructor-lifetime control.
fn with_native_mock_capture_construction(
  check : (LocalNativeMockEffectImportConstruction) -> Unit raise,
  max_retained? : Int64 = 10000L,
  max_execution? : Int64 = 20000L,
) -> Unit raise {
  let facility = native_mock_readme_request_facility()
  facility.arena.enter_domain_retained_execution(facility.physical).unwrap()
  let environment = @run_host.admit_client_check_environment(
    local_effect_prefix_fixture_environment_wire,
    "sha256:67979d9f5507bd9dd0809091d96b7dc96a1dce6e30df75ad0fac523f9c3ad808",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[],\"updateTargets\":[]}",
  ).unwrap()
  let intent = @run_host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" +
    local_effect_prefix_fixture_document +
    ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let (submitted, body) = @local_host.prepare_native_client_submitted_request_input(
    facility.parent,
    facility.input,
    intent,
    environment,
    publication,
  ).unwrap()
  guard @local_host.native_client_submitted_preparation(submitted)
    is EffectComputation(prepared) else {
    fail("original Effect preparation")
  }
  let first = local_effect_prefix_fixture_original(submitted) catch {
    ClientStop(message) => fail(message)
  }
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let initial = [
    @execution.execution_capacity(10L, 20L).unwrap(),
    @execution.execution_capacity(2L, 3L).unwrap(),
    empty,
    empty,
    empty,
    empty,
  ]
  let future = initial.copy()
  future[0] = @execution.execution_capacity(30L, 50L).unwrap()
  let maximum = initial.copy()
  maximum[0] = @execution.execution_capacity(max_retained, max_execution).unwrap()
  let capture = @local_values.prepare_installed_effect_staged_extent(
    @local_values.prepare_installed_effect_capture_recipe_extent(
      "native.mock.file.capture", initial,
    ).unwrap(),
    @local_values.prepare_installed_effect_capture_recipe_extent(
      "native.mock.file.capture", maximum,
    ).unwrap(),
  ).unwrap()
  let demand = @local_values.prepare_installed_effect_operation_demand(
    prepared,
    0,
    "save",
    [capture],
    [],
  ).unwrap()
  let assets = @run_host.client_local_product_assets()
  let contracts = @local_values.prepare_installed_sequence_contracts(
    assets.registry,
    assets.values,
    Some(assets.fragment),
    None,
  ).unwrap()
  let plan = @local_values.prepare_installed_effect_managed_plan(
    prepared,
    first.request,
    [],
    "",
    "",
    [],
    [],
    contracts,
    assets.values,
    Some(assets.fragment),
    None,
    [demand],
    provider_factory=_ => [],
  ).unwrap()
  @local_host.return_native_client_submitted_request_body(body).unwrap()
  |> ignore
  @local_values.complete_request_effect_preparation(
    facility.parent,
    facility.input,
    plan,
  ).unwrap()
  let run = @local_values.begin_request_effect_managed_run(
    facility.parent,
    first.request,
  ).unwrap()
  facility.run = Some(run)
  let child = native_mock_effect_capture_operation(
    run,
    prepared,
    first.request,
    plan,
    0,
  ).unwrap()
  let retained = [child]
  let entered = @local_values.begin_installed_effect_operation_input(
    child,
    @local_values.prepare_installed_effect_capture_recipe_extent(
      "native.mock.file.capture", initial,
    ).unwrap(),
  )
  let issue = match entered {
    Err(@local_values.ForeignOriginal) =>
      Some("old auto-started constructor refused InputBegin")
    Err(_) => Some("original Native InputBegin refused")
    Ok(_) => {
      assert_true(physical_equal(child, retained[0]))
      @local_values.grow_installed_effect_operation_input(
        retained[0],
        @local_values.prepare_installed_effect_capture_recipe_extent(
          "native.mock.file.capture", future,
        ).unwrap(),
      ).unwrap()
      let construction : LocalNativeMockEffectImportConstruction = {
        operation: child,
        recipe: future,
        retained: 0L,
        workspace: 20L,
        source_snapshot: None,
        source_copy: None,
      }
      check(construction)
      @local_values.complete_installed_effect_operation_construction(child).unwrap()
      None
    }
  }
  assert_true(
    @local_values.retire_installed_effect_operation(child, true).unwrap(),
  )
  @local_values.quiesce_installed_managed_run(run).unwrap()
  assert_true(@local_values.retire_installed_managed_run(run) is Err(_))
  facility.arena.leave_domain_retained_execution(facility.physical).unwrap()
  facility.arena.close_domain_retained_execution(facility.physical).unwrap()
  @local_values.retire_installed_managed_run(run).unwrap()
  facility.arena.close_domain_after_owner_ack(facility.domain).unwrap()
  facility.arena.try_close().unwrap()
  if issue is Some(message) {
    fail(message)
  }
}

///|
test "Native first member retains one original capture before input and full recipe growth" {
  with_native_mock_capture_construction(fn(construction) raise {
    construction.source_copy = Some(0L)
    construction.reserve_source_row_copy(40L, 20L).unwrap()
    assert_eq(construction.source_copy, Some(40L))
    assert_eq(construction.workspace, 60L)
    // The previous Source frame returned. The next copy begins at zero
    // and uses the same reservation, including its earlier execution peak.
    construction.source_copy = None
    construction.source_copy = Some(0L)
    construction.reserve_source_row_copy(30L, 20L).unwrap()
    assert_eq(construction.source_copy, Some(30L))
    assert_eq(construction.workspace, 60L)
    assert_eq(construction.retained, 0L)
    // Checked cap: 20000 E minus base 30, decoder 20, live copy 30.
    assert_true(
      construction.reserve_source_row_copy(19921L, 20L)
      is Err(Managed(InsufficientCapacity)),
    )
    assert_eq(construction.source_copy, Some(30L))
    assert_eq(construction.workspace, 60L)
    construction.reserve_source_row_copy(19920L, 20L).unwrap()
    assert_eq(construction.source_copy, Some(19950L))
    assert_eq(construction.workspace, 19970L)
    assert_eq(construction.retained, 0L)
    construction.source_copy = None
  })
}

///|
test "Native returned import funds next Model body on the exact original reservation" {
  let frame = @local_values.installed_effect_imported_model_evidence_frame_capacity(
    2L, 64, 8,
  ).unwrap()
  let writer = @encode.construction_measuring_writer(512, 64, 8)
  @encode.begin_object(writer)
  @encode.key(writer, "sources")
  @encode.begin_array(writer)
  @encode.end_array(writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-acquisition-scope/0.1")
  @encode.end_object(writer)
  let shape = @encode.finish_construction_measurement(writer)
  let frame_r = @execution.execution_capacity_retained_bytes(frame)
  let frame_scratch = @execution.execution_capacity_execution_bytes(frame) -
    frame_r
  let cid = "sha256:" + "1".repeat(64)
  let body = @local_values.installed_effect_imported_model_evidence_body_capacity(
    "acquisition_scope", shape, cid, frame_scratch,
  ).unwrap()
  let unshared_body = @local_values.installed_effect_imported_model_evidence_body_capacity(
    "acquisition_scope", shape, cid, 0L,
  ).unwrap()
  assert_eq(
    @execution.execution_capacity_execution_bytes(body) -
    @execution.execution_capacity_execution_bytes(unshared_body),
    frame_scratch,
  )
  let body_r = @execution.execution_capacity_retained_bytes(body)
  let body_scratch = @execution.execution_capacity_execution_bytes(body) -
    body_r
  // Original fixed 30 bytes, adopted import 10, then both new owners.
  let retained = 40L + frame_r + body_r
  let required = retained + body_scratch
  for max_execution in [required - 1L, required] {
    with_native_mock_capture_construction(
      max_retained=retained,
      max_execution~,
      fn(construction) raise {
        let operation = construction.operation
        construction
        .prepare_body_result(@execution.execution_capacity(10L, 40L))
        .unwrap()
        construction.yield_source_import_workspace().unwrap()
        assert_eq(construction.retained, 10L)
        assert_eq(construction.workspace, 0L)
        assert_eq(
          @execution.execution_capacity_execution_bytes(construction.recipe[0]),
          30L,
        )
        construction.prepare_body_result(Some(frame)).unwrap()
        let entered = construction.prepare_body_result(Some(body))
        assert_true(physical_equal(construction.operation, operation))
        if max_execution < required {
          assert_true(entered is Err(Managed(InsufficientCapacity)))
          assert_eq(construction.retained, 10L + frame_r)
          assert_eq(construction.workspace, frame_scratch)
        } else {
          entered.unwrap()
          assert_eq(construction.retained, 10L + frame_r + body_r)
          assert_eq(construction.workspace, body_scratch)
        }
      },
    )
  }
}

///|
test "Native Model Result Artifact reserves measured bodies beside its original census" {
  let cid = "sha256:" + "1".repeat(64)
  let measured = @publication.local_result_metadata_construction_geometry(
    cid,
    cid,
    cid,
    cid,
    cid,
    [cid],
    cid,
    cid,
    "actql-common-host",
    cid,
    cid,
    17,
    16384,
    1024,
    20,
  ).unwrap()
  let bodies = [
    ("derivation_evidence", measured[0]),
    ("ordering_evidence", measured[1]),
    ("result_artifact", measured[2]),
  ]
  let census = native_mock_effect_artifact_measurement_capacity(1L).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(census), 0L)
  let scratch = @execution.execution_capacity_execution_bytes(census)
  let quote = @local_values.installed_effect_model_result_artifact_capacity(
    bodies, cid, scratch,
  ).unwrap()
  let unshared = @local_values.installed_effect_model_result_artifact_capacity(
    bodies, cid, 0L,
  ).unwrap()
  let retained = @execution.execution_capacity_retained_bytes(quote)
  let execution = @execution.execution_capacity_execution_bytes(quote)
  assert_eq(retained, @execution.execution_capacity_retained_bytes(unshared))
  assert_eq(
    execution - @execution.execution_capacity_execution_bytes(unshared),
    scratch,
  )
  let original = 30L
  let imported = 10L
  let required = original + imported + execution
  for maximum in [required - 1L, required] {
    with_native_mock_capture_construction(
      max_retained=original + imported + retained,
      max_execution=maximum,
      fn(construction) raise {
        let operation = construction.operation
        construction
        .prepare_body_result(@execution.execution_capacity(imported, imported))
        .unwrap()
        construction.prepare_body_result(Some(census)).unwrap()
        let admission = construction.prepare_body_result(Some(quote))
        assert_true(physical_equal(operation, construction.operation))
        if maximum < required {
          assert_true(admission is Err(Managed(InsufficientCapacity)))
          assert_eq(construction.retained, imported)
          assert_eq(construction.workspace, scratch)
        } else {
          admission.unwrap()
          assert_eq(construction.retained, imported + retained)
          assert_eq(construction.workspace, execution - retained)
        }
      },
    )
  }
}

///|
test "Native Unit Result row funding keeps its own writer beside its decoder" {
  let fixed = 20L
  let first_writer = 47L
  let second_writer = 91L
  let decode = @local_values.installed_effect_capture_row_decode_workspace(
    96, 5, 3,
  ).unwrap()
  let decode_bytes = @execution.execution_capacity_execution_bytes(decode)
  let retained = 30L
  let required = retained + fixed + second_writer + decode_bytes
  for maximum in [required - 1L, required] {
    with_native_mock_capture_construction(
      max_retained=retained,
      max_execution=maximum,
      fn(construction) raise {
        let original = construction.operation
        let reports : Array[LocalNativeMockEffectProposalIssue] = []
        let report = issue => reports.push(issue)
        {
          let (emit, admit, observed) = construction.export_row_funding(
            fixed, report,
          )
          assert_true(
            emit(@execution.execution_capacity(0L, first_writer).unwrap()),
          )
          assert_true(admit(96, 5, 3))
          assert_eq(observed.val, fixed + first_writer + decode_bytes)
        }
        let (emit, admit, observed) = construction.export_row_funding(
          fixed, report,
        )
        assert_true(
          emit(@execution.execution_capacity(0L, second_writer).unwrap()),
        )
        let previous = construction.workspace
        let entered = admit(96, 5, 3)
        assert_true(physical_equal(original, construction.operation))
        assert_eq(construction.retained, 0L)
        if maximum == required {
          assert_true(entered && reports.is_empty())
          assert_eq(observed.val, required - retained)
          assert_eq(construction.workspace, required - retained)
        } else {
          assert_false(entered)
          assert_true(reports is [Managed(InsufficientCapacity)])
          assert_eq(observed.val, 0L)
          assert_eq(construction.workspace, previous)
        }
      },
    )
  }
}

///|
test "Native proposal return drops only its old workspace before the next construction" {
  with_native_mock_capture_construction(fn(construction) raise {
    let original_recipe = construction.recipe
    construction
    .prepare_body_result(@execution.execution_capacity(30L, 19970L))
    .unwrap()
    assert_eq(construction.retained, 30L)
    assert_eq(construction.workspace, 19940L)

    // The copied Source prefix still belongs to the live original phase.
    construction.source_copy = Some(0L)
    construction.reserve_source_row_copy(10L, 20L).unwrap()
    assert_true(construction.yield_returned_workspace() is Err(AlreadyBound))
    assert_eq(construction.workspace, 19940L)
    assert_eq(construction.source_copy, Some(10L))
    construction.source_copy = None

    construction.yield_returned_workspace().unwrap()
    assert_true(physical_equal(construction.recipe, original_recipe))
    assert_eq(construction.retained, 30L)
    assert_eq(construction.workspace, 0L)

    // Original maximum is 20000. Base and adopted retention total 60.
    // Another retained byte leaves 19939 for the new phase's scratch.
    assert_true(
      construction.prepare_body_result(
        @execution.execution_capacity(1L, 19941L),
      )
      is Err(Managed(InsufficientCapacity)),
    )
    assert_eq(construction.retained, 30L)
    assert_eq(construction.workspace, 0L)
    construction
    .prepare_body_result(@execution.execution_capacity(1L, 19940L))
    .unwrap()
    assert_eq(construction.retained, 31L)
    assert_eq(construction.workspace, 19939L)
  })
}

///|
test "Native proposal append reserves the returned strings and replacement slots" {
  // Base 30, first pair 3H+2R+2W+2 UTF16 units =84. Next pair has
  // three UTF16 units (two supplementary, one BMP), costing 86. Replacing
  // the one-slot backing with eight adds seven retained slots =56. The
  // co-held replaced backing (1H+1R) belongs only to execution.
  let exact = 30L + 84L + 86L + 56L
  for limit in [exact - 1L, exact] {
    with_native_mock_capture_construction(max_retained=limit, fn(
      construction,
    ) raise {
      let rows : Array[(String, String)] = Array(capacity=1)
      construction.append_proposal_row(rows, ("a", "b")).unwrap()
      assert_eq(rows.capacity(), 1)
      assert_eq(construction.retained, 84L)
      if limit < exact {
        assert_true(
          construction.append_proposal_row(rows, ("😀", "é"))
          is Err(Managed(InsufficientCapacity)),
        )
        assert_eq(rows, [("a", "b")])
        assert_eq(rows.capacity(), 1)
        assert_eq(construction.retained, 84L)
        assert_eq(construction.workspace, 20L)
      } else {
        construction.append_proposal_row(rows, ("😀", "é")).unwrap()
        assert_eq(rows, [("a", "b"), ("😀", "é")])
        assert_eq(rows.capacity(), 8)
        assert_eq(construction.retained, 84L + 86L + 56L)
        assert_eq(construction.workspace, 24L)
      }
    })
  }
}

///|
test "Native completed canonical dependencies retain data without accumulating parser scratch" {
  let wire = "{\"a\":[1,{\"key\":\"value\"}],\"text\":\"original\"}"
  let cid = "sha256:" + @sha.text_hex(wire).unwrap()
  let body = @publication.admit_hashed_effect_dependency_body(
    "schema_evidence", cid, wire, 16384, 1024, 20,
  ).unwrap()
  // The actual returned dependency keeps the original immutable text. Its
  // admission/identity rules are unchanged; a foreign identity still refuses.
  assert_eq(@publication.captured_effect_dependency_body_json(body), wire)
  assert_true(
    @publication.admit_hashed_effect_dependency_body(
      "schema_evidence",
      "sha256:" + "0".repeat(64),
      wire,
      16384,
      1024,
      20,
    )
    is Err(_),
  )
  let old = native_mock_effect_dependency_body_capacity(16384, 1024, 20).unwrap()
  let returned = native_mock_effect_canonical_body_capacity(16384, 1024, 20).unwrap()
  // Failure and callback-time backing keep the complete original peak. Only
  // nonescaping parser/index/Unicode families stop accumulating as outputs.
  assert_true(
    @execution.execution_capacity_execution_bytes(returned) >=
    @execution.execution_capacity_execution_bytes(old),
  )
  assert_true(
    @execution.execution_capacity_retained_bytes(returned) <
    @execution.execution_capacity_retained_bytes(old),
  )
  assert_true(native_mock_effect_canonical_body_capacity(0, 1024, 20) is None)
  assert_true(native_mock_effect_canonical_body_capacity(16384, 0, 20) is None)
  assert_true(
    native_mock_effect_canonical_body_capacity(16384, 1024, 0) is None,
  )
}

///|
test "Native serial capture retains every row and one original constructor workspace" {
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let fixed = @execution.execution_capacity(100L, 120L).unwrap()
  let row = @execution.execution_capacity(10L, 50L).unwrap()
  let physical = @execution.execution_capacity(11L, 17L).unwrap()
  let original = [fixed, row, empty, physical, empty, empty]
  let serial = native_mock_effect_serial_capture_recipe(original).unwrap()
  // Two retained rows still cost120. The selected Native serial decoder uses
  // one40-byte workspace, including the original20-byte fixed scratch.
  assert_eq(
    @execution.execution_capacity_retained_bytes(serial[0]) +
    2L * @execution.execution_capacity_retained_bytes(serial[1]),
    120L,
  )
  assert_eq(
    @execution.execution_capacity_execution_bytes(serial[0]) +
    2L * @execution.execution_capacity_execution_bytes(serial[1]),
    160L,
  )
  assert_true(physical_equal(serial[3], physical))
  // No mutation of the separate original cold-recovery recipe or IO roles.
  assert_true(physical_equal(original[0], fixed))
  assert_true(physical_equal(original[1], row))
  assert_true(native_mock_effect_serial_capture_recipe([]) is None)
}

///|
// Real checked Result declarations and Effect source, no Model, Source IO,
// Provider, Store or ordinary installation. Aliases of one port stay distinct.
test "Native complete Unit inventory keeps an unconsumed Result alias" {
  let environment = @run_host.admit_client_check_environment(
    local_effect_prefix_fixture_environment_wire,
    "sha256:67979d9f5507bd9dd0809091d96b7dc96a1dce6e30df75ad0fac523f9c3ad808",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let document = local_effect_prefix_fixture_document.replace(
    old="\"results\":{\"out\":",
    new="\"results\":{\"unused\":{\"fields\":[\"value\"],\"from\":\"selected\"},\"out\":",
  )
  let intent = @run_host.prepare_client_submitted_intent(
    "{\"kind\":\"program\",\"input\":" + document + ",\"parameters\":null}",
    65536,
    8192,
    64,
  ).unwrap()
  let submitted = @local_host.prepare_native_client_submitted_program(
    intent,
    environment,
    None,
    [],
    @run_host.client_standard_effect_computation_limits(),
  ).unwrap()
  guard @local_host.native_client_submitted_preparation(submitted)
    is EffectComputation(prepared) else {
    fail("original Effect owner")
  }
  assert_true(native_mock_effect_result_consumed(prepared, 0, "out"))
  assert_false(native_mock_effect_result_consumed(prepared, 0, "unused"))
  assert_false(native_mock_effect_result_consumed(prepared, 1, "out"))
  assert_eq(native_mock_effect_extra_unit_results(prepared, 0), 1)
  assert_eq(native_mock_effect_extra_unit_results(prepared, 1), 0)
}

///|
test "Native serial Source snapshots reuse the actual overlapping constructor peak" {
  let fixed = @execution.execution_capacity(100L, 120L).unwrap()
  // The 30-byte snapshot remains live beside the 50-byte decoder.
  let captured = native_mock_effect_import_workspace(fixed, 60L, 30L, 50L).unwrap()
  assert_eq(captured, 80L)
  // After the old bare wire and local aliases returned, the second Source
  // needs 65 bytes including its narrower decoder. The prior peak suffices.
  assert_eq(
    native_mock_effect_import_workspace(fixed, captured, 40L, 25L),
    Some(80L),
  )
  // The old high-water cannot replace live baseline+snapshot overlap.
  assert_eq(
    native_mock_effect_import_workspace(fixed, captured, 70L, 15L),
    Some(90L),
  )
  assert_true(
    native_mock_effect_import_workspace(
      fixed, captured, 9223372036854775807L, 1L,
    )
    is None,
  )
}
