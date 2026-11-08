///|
// One joined physical Source component on the actual README Request/Plan.
// The metadata authority and future UPDATE provider remain explicit ports;
// neither is an ordinary CLI/Account/Journal/Model-send qualification.
test "Native original README joins its two physical Sources and original keyed Content Store" {
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
    content_join=true,
  )
}

///|
test "Native original README retains both keyed Content originals for its Model input" {
  assert_eq(@env.get_env_var("ACTQL_TEST_NATIVE_CONTENT_LOOKUPS"), Some("2"))
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
    content_join=true,
  )
}

///|
test "Native README Source originals retain the keyed Model closure" {
  assert_eq(
    @env.get_env_var("ACTQL_TEST_NATIVE_MODEL_SOURCE_CLOSURE"),
    Some("1"),
  )
  assert_eq(@env.get_env_var("ACTQL_TEST_NATIVE_CONTENT_LOOKUPS"), Some("2"))
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
    content_join=true,
    static_policy=true,
  )
}

///|
test "Native README original file Effect Plan admits actual operations before children" {
  assert_eq(@env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_PLAN_ONLY"), Some("1"))
  native_project_mock_model_backed_read(
    false,
    readme_request=true,
    effect_compilation=true,
    effect_source_inputs=true,
    content_join=true,
    static_policy=true,
  )
}

///|
fn[T, E] Result::native_content_join_stage(
  self : Result[T, E],
  label : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(_) => fail(label)
  }
}

///|
fn native_mock_readme_content_join(
  facility : NativeMockReadmeRequestFacility,
  original : LocalProjectMockDeclarations,
  prepared : @run_host.PreparedClientEffectComputation,
  first : LocalEffectFirstCompilation,
  contracts : @local_values.ClientInstalledSequenceContracts,
  graph : @run_host.ClientInferPlanGraph,
) -> Unit raise {
  let occurrence = graph.occurrence
  let limits = @infer.prepared_composed_bounds(occurrence, graph).native_content_join_stage(
    "original prepared Model bounds",
  )
  let compiled = first.model_compiled.unwrap()
  if @env.get_env_var("ACTQL_TEST_NATIVE_EFFECT_PLAN_ONLY") == Some("1") {
    let provider = @infer.composed_local_provider(
      occurrence,
      limits,
      _ => Err(@infer.InvalidAdvance),
      _ => @compute_sdk.ComputeUnsupported,
    )
    let selected = native_mock_effect_managed_plan(
      prepared, first, original, contracts, provider,
    ) catch {
      ClientStop(message) => fail(message)
    }
    let scope = @local_values.prepare_request_effect_model_read_scope(
      facility.parent,
      facility.input,
      selected,
    ).native_content_join_stage("actual Native file Plan Scope")
    @local_values.complete_request_effect_preparation(
      facility.parent,
      facility.input,
      selected,
    ).native_content_join_stage("actual Native file Plan completion")
    let run = @local_values.begin_request_effect_model_managed_run(
      facility.parent,
      first.request,
      scope,
    ).native_content_join_stage("actual Native file Plan adoption")
    facility.run = Some(run)
    for index in 0..<first._retained_sources.length() {
      assert_eq(
        @local_values.installed_effect_managed_source_input_kind(
          run,
          prepared,
          first.request,
          index,
        ).native_content_join_stage("actual file Plan Source kind"),
        "whole-input",
      )
    }
    @local_values.quiesce_installed_managed_run(run).native_content_join_stage(
      "quiesce same original file Effect Plan",
    )
    assert_true(
      @run_host.finish_client_model_read_scope(
        scope,
        compiled,
        first.definition,
        graph,
        true,
      ).native_content_join_stage("actual file Plan Scope cleanup"),
    )
    match @local_values.retire_installed_managed_run(run) {
      Err(@local_values.Resource(@initial_resources.Unavailable)) => ()
      Err(_) => fail("unexpected file Plan retirement refusal")
      Ok(_) => fail("Core cannot ACK a still-entered Native frame")
    }
    return
  }
  // Explicit finite component read-window selection, not the ordinary Host's
  // as-yet-unqualified constructor backing. Its SAME Request must admit the
  // entire Plan/Scope and the Native capture reserves every actual child.
  let model = @local_values.prepare_installed_effect_model_demand(
    prepared,
    compiled,
    first.allowed.compilation,
    first.definition,
    occurrence,
    graph,
    limits.model.ledger,
    134217728L,
    134217728L,
    64,
    64,
    0,
  ).native_content_join_stage("original Model demand")
  let header = @syntax.effect_header_at(
    @checked.effect_program_static_headers(
      @run_host.prepared_client_effect_computation_candidate(prepared),
    ),
    0,
  ).unwrap()
  // The component never invokes a future operation; this original selected
  // provider refuses rather than manufacturing permission or a write result.
  let extent = @local_values.prepare_installed_effect_operation_extent(
    "unexecuted-native-component-operation",
    @execution.execution_capacity(3L, 5L).unwrap(),
    7L,
    true,
  ).unwrap()
  let operation = @local_values.prepare_installed_effect_operation_demand(
    prepared,
    @syntax.effect_header_stage(header),
    @syntax.effect_header_id(header),
    [extent],
    [extent],
  ).native_content_join_stage("original Effect member")
  let assets = @run_host.client_local_product_assets()
  let inputs = first._retained_sources
  assert_eq(inputs.length(), 2)
  let page = local_project_mock_file_limits().page
  // Consume each original preselected Query/Whole route. The actual checked
  // Source chooses it; a caller must not replace it by a whole-input fallback.
  let query_contract = @env.get_env_var("ACTQL_TEST_NATIVE_QUERY_CONTRACT").unwrap()
  let evidence_contract = @env.get_env_var(
    "ACTQL_TEST_NATIVE_EVIDENCE_CONTRACT",
  ).unwrap()
  let plan = @local_values.prepare_installed_effect_managed_source_plan(
    prepared,
    first.request,
    inputs.map(value => value._retained_input),
    query_contract,
    evidence_contract,
    [page.max_bytes.to_int64(), page.max_bytes.to_int64()],
    [page.max_bytes.to_int64(), page.max_bytes.to_int64()],
    contracts,
    assets.values,
    Some(assets.fragment),
    assets.ordered,
    [operation],
    model=Some(model),
    // This is the actual preparation-owned Run entrance: runtime children
    // reserve on its SAME finite Ledger, rather than requiring a legacy
    // whole-Run maximum quote before those original children exist.
    runtime_admission=true,
    provider_factory=capacity => {
      [
        @local_compute.managed_provider(_ => true, _ => Some(capacity), (
          _,
          _,
          _,
          _,
          _,
        ) => Err(@compute_sdk.ComputeUnsupported)),
      ]
    },
  ).native_content_join_plan()
  let scope = @local_values.prepare_request_effect_model_read_scope(
    facility.parent,
    facility.input,
    plan,
  ).native_content_join_stage("same Request Model Scope")
  @local_values.complete_request_effect_preparation(
    facility.parent,
    facility.input,
    plan,
  ).native_content_join_stage("same Request Plan completion")
  // The existing Native caller returned its SAME input body borrow before
  // this Plan construction; adoption consumes that original parent.
  native_mock_readme_content_join_adopt(
    facility, original, prepared, first, graph, compiled, scope, limits,
  )
}

///|
fn native_mock_readme_content_join_adopt(
  facility : NativeMockReadmeRequestFacility,
  original : LocalProjectMockDeclarations,
  prepared : @run_host.PreparedClientEffectComputation,
  first : LocalEffectFirstCompilation,
  graph : @run_host.ClientInferPlanGraph,
  compiled : @run_host.ClientCompiledRun,
  scope : @run_host.ClientModelReadScope,
  limits : @infer.Limits,
) -> Unit raise {
  let owner = @local_values.begin_request_effect_model_managed_run(
    facility.parent,
    first.request,
    scope,
  ).native_content_join_stage("same Request managed Run")
  // Retain the actual adopted Run in the existing OUTER Native control before
  // any fallible child. Its final retirement follows the real frame close.
  facility.run = Some(owner)
  let native_children : Array[@row_file.NativeRelationFileCapture] = []
  let captures : Array[@row_host.RowCapturedInput] = []
  let source_originals : Array[NativeMockSourceEvidenceOriginal] = []
  let source_identities = []
  let source_logicals = []
  let source_observations = []
  let source_authority = "sha256:" + "8".repeat(64)
  let source_completed = "2026-10-12T00:00:01.000Z"
  let collect_closure = @env.get_env_var(
      "ACTQL_TEST_NATIVE_MODEL_SOURCE_CLOSURE",
    ) ==
    Some("1")
  for index, input in first._retained_sources {
    let declaration = input._retained_source._retained_declaration
    let kind = @local_values.installed_effect_managed_source_input_kind(
      owner,
      prepared,
      first.request,
      index,
    ).unwrap()
    let mut evidence_original : NativeMockSourceEvidenceOriginal? = None
    let capture = if kind == "whole-input" {
      let (read, original, acquisition, capacity) = @local_values.begin_installed_effect_managed_whole_source_read(
        owner,
        prepared,
        first.request,
        declaration,
        index,
      ).native_content_join_stage("original whole Source read")
      evidence_original = Some(Whole(original, acquisition))
      match input._retained_reader {
        Rows(binding) =>
          @row_file.prepare_native_managed_relation_file_input_capture(
            facility.arena,
            facility.physical,
            declaration,
            read,
            capacity,
            binding.provider.capacity(),
            "native-readme-records",
            binding._retained_selection,
            binding.limits,
            prepared_provider=Some(binding.provider),
          )
        Files(_, listing) =>
          @row_file.prepare_native_managed_relation_file_listing_capture(
            facility.arena,
            facility.physical,
            read,
            capacity,
            listing,
            "native-readme-files",
          )
      }
    } else {
      assert_eq(kind, "query")
      let (read, _, acquisition, _) = @local_values.begin_installed_effect_managed_source_read(
        owner, declaration, index,
      ).native_content_join_stage("original Query Source read")
      evidence_original = Some(Query(acquisition))
      match input._retained_reader {
        Rows(binding) =>
          @row_file.prepare_native_managed_relation_file_query_capture(
            facility.arena,
            facility.physical,
            declaration,
            read,
            acquisition,
            binding.provider.capacity(),
            "native-readme-records",
            binding._retained_selection,
            binding.limits,
            prepared_provider=Some(binding.provider),
          )
        Files(_, listing) =>
          @row_file.prepare_native_managed_relation_file_query_listing_capture(
            facility.arena,
            facility.physical,
            read,
            acquisition,
            listing,
            "native-readme-files",
          )
      }
    }
    let capture = capture.native_content_physical_stage(
      "original Native Source child " + index.to_string(),
    )
    native_children.push(capture)
    let mut done = false
    for _ in 0..<100000 {
      if capture
        .advance(31)
        .native_content_physical_stage("original Native Source advance") {
        done = true
        break
      }
    }
    assert_true(done)
    let captured = capture.capture().unwrap()
    captures.push(@row_host.row_capture_input(captured).unwrap())
    if collect_closure {
      let source = @row_host.row_capture_source(captured).unwrap()
      let identity = @test_query.identify_captured_source_relation(
        source,
        limits.identity.rows,
        limits.output_values,
        limits.identity.wire,
        limits.identity.logical_wire,
        limits.identity.schema,
        limits.identity.wire.max_bytes,
      ).native_content_join_stage("actual captured Source identity")
      let dag = @strategy.checked_effect_computation_graph(
        @run_host.prepared_client_effect_computation_graph(prepared),
      )
      let same_original = evidence_original.unwrap()
      let (logical, observation) = match same_original {
        Whole(original, acquisition) => {
          let logical = @run_host.issue_captured_whole_source_input_logical(
            dag,
            source,
            identity,
            original,
            task=input._retained_coordinates.2,
          ).native_content_join_stage("actual whole Source logical")
          let facts = @row_host.row_input_acquisition_facts(acquisition)
          let observation = @row_host.issue_row_input_source_evidence(
            acquisition,
            captured,
            identity,
            logical,
            source_authority,
            facts.source_data_policy_cid,
            source_completed,
          ).native_content_join_stage("actual whole Source observation")
          (logical, observation)
        }
        Query(acquisition) => {
          let requirement = @row_host.row_acquisition_requirement(acquisition)
          let sequence = @test_planning.query_material_owner(
            @test_planning.query_requirement_material(requirement),
          )
          let coordinates = input._retained_coordinates
          assert_true(
            @run_host.client_query_requirement_matches_effect_program(
              prepared,
              coordinates.0,
              coordinates.1,
              requirement,
            ),
          )
          assert_true(
            @test_query.captured_source_matches_query(source, sequence),
          )
          let program = @checked.source_identity(@strategy.graph_program(dag))
          assert_true(
            physical_equal(
              @test_planning.query_requirement_program(requirement),
              program,
            ),
          )
          assert_true(
            @test_query.captured_source_matches(
              source,
              program,
              @test_query.query_sequence_owner(sequence),
            ),
          )
          let full_task = @strategy.graph_task_owner(dag, coordinates.2).unwrap()
          assert_true(
            @test_query.captured_source_matches(source, program, full_task),
          )
          let logical = @run_host.issue_captured_source_input_logical(
            dag,
            source,
            identity,
            requirement,
            task=input._retained_coordinates.2,
          ).native_source_logical_stage("actual Query Source logical")
          let facts = @test_planning.query_requirement_source_evidence_facts(
            requirement,
          ).unwrap()
          let observation = (if @row_host.row_acquisition_is_listing(
              acquisition,
            ) {
            @row_host.issue_row_listing_source_evidence(
              acquisition,
              captured,
              identity,
              logical,
              source_authority,
              facts.source_data_policy_cid,
              source_completed,
            )
          } else {
            @row_host.issue_row_source_evidence(
              acquisition,
              captured,
              identity,
              logical,
              source_authority,
              facts.source_data_policy_cid,
              source_completed,
            )
          }).native_content_join_stage("actual Query Source observation")
          (logical, observation)
        }
      }
      source_originals.push(same_original)
      source_identities.push(identity)
      source_logicals.push(logical)
      source_observations.push(observation)
    }
  }
  let keyed = @run_host.select_client_effect_composed_model_keyed_acquisition(
      prepared, graph,
    )
    .unwrap()
    .unwrap()
  let prefix_result = @local_values.start_installed_original_composed_keyed_input_prefix(
    owner,
    scope,
    compiled,
    first.definition,
    graph,
    keyed,
    captures,
    limits.input,
    limits.measurement,
  )
  let prefix = match prefix_result {
    Ok(value) => value
    Err(issue) => {
      let label = match issue {
        @local_values.Unavailable => "Unavailable"
        @local_values.Original(value) => "Original: " + @debug.to_string(value)
        @local_values.Physical(value) => "Physical: " + @debug.to_string(value)
        @local_values.Provider(_) => "Provider"
        @local_values.Capture(
          @test_query.Binding(@execution.ProducerBindingMismatch)
        ) => "Capture: ProducerBindingMismatch"
        @local_values.Capture(
          @test_query.Binding(@execution.ProducerOwnerMismatch)
        ) => "Capture: ProducerOwnerMismatch"
        @local_values.Capture(
          @test_query.Binding(@execution.ProducerTargetMismatch)
        ) => "Capture: ProducerTargetMismatch"
        @local_values.Capture(_) => "Capture"
        @local_values.ProducerRead(_) => "ProducerRead"
      }
      fail("same two Source prefix: " + label)
    }
  }
  let mut done = false
  for _ in 0..<100000 {
    match
      @local_values.advance_client_original_composed_keyed_prefix(prefix, 31).native_content_join_stage(
        "same prefix advance",
      ) {
      @local_compute.Complete(_, ..) => {
        done = true
        break
      }
      @local_compute.Continue(..) => ()
      _ => fail("original prefix did not complete")
    }
  }
  assert_true(done)
  let left = @local_values.complete_client_original_composed_keyed_prefix(
    prefix, 10000, 4096,
  ).native_content_join_stage("original keyed left")
  let ledger = facility.arena
    .borrow_domain_retained_execution_ledger(facility.physical)
    .unwrap()
  let requests = if @env.get_env_var("ACTQL_TEST_NATIVE_CONTENT_LOOKUPS") ==
    Some("2") {
    2
  } else {
    1
  }
  let keyed_capacity = @sourceviews.keyed_source_capacity(
    @run_host.client_keyed_acquisition_facts(keyed),
  )
  let response_bytes = @compiler_environment.lookup_capacity_response_bytes_per_page(
    keyed_capacity,
  )
  assert_true(response_bytes > 0L && response_bytes <= 2147483647L)
  let assembly_bytes = if requests == 2 {
    // The actual left original, rather than a checked estimate or another
    // Source scan, supplies this assembly's maximum number of response rows.
    let rows = @run_host.client_keyed_left_read_rows(left).unwrap()
    assert_eq(rows, 2)
    @execution.checked_preparation_add_product(
      0L,
      rows.to_int64(),
      response_bytes,
    ).unwrap()
  } else {
    4096L
  }
  assert_true(assembly_bytes > 0L && assembly_bytes <= 2147483647L)
  let lookup = @run_host.start_client_keyed_lookup_input(
    left,
    ledger,
    assembly_bytes.to_int(),
    10000,
  ).native_content_join_stage("original keyed lookup")
  let mut measured_text = 0L
  let content_children : Array[@row_file.NativeRelationFileCapture] = []
  let library = @local_sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
  ).native_content_join_stage("original SQLite component")
  let root = @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT").unwrap()
  let authority = "sha256:" + "8".repeat(64)
  let store = @local_store.open_store_with_custody(
    library,
    root,
    authority,
    1048576L,
    8L,
    65536L,
    diagnostic_ceiling=Some(4096),
  ).native_content_join_stage("same bounded Content Store")
  let facts = @run_host.client_keyed_acquisition_source_evidence_facts(keyed).unwrap()
  let binding_wire = local_project_mock_relation_wire({
    "content_store_id": "native-readme-component",
    "content_store_cid": Json::string(authority),
    "workspace_scope_cid": Json::string("sha256:" + "9".repeat(64)),
    "storage_scope": "workspace",
    "retention_class": "component",
    "expires_at": "2099-01-01T00:00:00.000Z",
    "availability_evidence_cid": Json::string("sha256:" + "a".repeat(64)),
    "effective_data_policy_cid": Json::string(facts.source_data_policy_cid),
    "data_classification": Json::string(facts.data_classification),
    "issuer_contract_cid": Json::string("sha256:" + "b".repeat(64)),
    "capture_authority_cid": Json::string("sha256:" + "c".repeat(64)),
  }).unwrap()
  for row in 0..<requests {
    let preparation = @run_host.start_client_keyed_lookup_request(lookup, row).unwrap()
    let mut request = None
    for _ in 0..<100000 {
      match @run_host.advance_client_keyed_lookup_request(lookup, preparation) {
        @run_host.ClientKeyedRequestContinue(..) => ()
        @run_host.ClientKeyedRequestComplete(value, ..) => {
          request = Some(value)
          break
        }
        _ => fail("original keyed request did not complete")
      }
    }
    let request = request.unwrap()
    // Select the original assembly's cache slot BEFORE opening a new read.
    // -1 is this fresh request's real miss; it is not a guessed permission.
    assert_eq(
      @run_host.find_client_keyed_lookup_response(lookup, request).unwrap(),
      -1,
    )
    let request_value = @run_host.client_keyed_request_value(request, keyed).unwrap()
    let file = original.file_sources.unwrap()[0]
    let binding = file._retained_listings[0].1
    let physical = binding._retained_provider
    // The public keyed response's original checked catalogue has its own
    // admitted per-page ceiling. Raw physical file limits remain unchanged.
    let read = @local_values.begin_installed_managed_model_keyed_source_read(
      owner,
      keyed,
      request,
      original.sources[1]._retained_declaration,
      {
        page: {
          max_bytes: response_bytes.to_int(),
          max_nodes: 4096,
          max_depth: 32,
          max_rows: 1,
        },
        retention: {
          max_nodes: 4096,
          max_depth: 32,
          max_text_bytes: 1048576,
          max_work: 16777216,
        },
        request: {
          max_work: 16777216,
          max_pairs: 4,
          values: { max_nodes: 4096, max_depth: 32, max_text_bytes: 1048576, },
        },
        wire: {
          max_bytes: 1048576,
          max_nodes: 4096,
          max_depth: 32,
          max_columns: 3,
          max_order_work: 16777216,
        },
      },
    ).native_content_read_stage("same Model keyed Read")
    let acquisition = @local_values.installed_keyed_source_read_acquisition(
      read,
    ).unwrap()
    let input = @row_file.prepare_native_relation_file_content_input(
      compiled,
      first.definition,
      keyed,
      request,
      store,
      {
        name: binding._retained_name,
        version: binding._retained_version,
        media_type: binding._retained_media_type,
        path: binding._retained_path,
      },
      binding._retained_content_utf8,
      binding_wire,
      {
        max_bytes: 65536,
        max_nodes: 4096,
        max_depth: 32,
        max_text_units: 65536,
      },
      1048576,
      local_status_watch_now_ffi,
      () => "2026-10-10T00:00:01.000Z",
      reference => (file._retained_resolve_identity)(binding, reference),
    ).native_content_join_stage("original keyed Content input")
    let content = @row_file.prepare_native_managed_relation_file_keyed_capture(
      facility.arena,
      facility.physical,
      original.sources[1]._retained_declaration,
      binding.content.source_ref,
      read,
      acquisition,
      physical,
      file._retained_issuer,
      "native-readme-content",
      content=Some(input),
    ).native_content_physical_stage(
      "original keyed Native child row " + row.to_string(),
    )
    let mut done = false
    for _ in 0..<100000 {
      let before = @initial_resources.ledger_usage(ledger)
      if content
        .advance(31)
        .native_content_physical_stage("original keyed Content advance") {
        let after = @initial_resources.ledger_usage(ledger)
        // The SAME original frame contracts only after actual I/O/parser/page
        // retirement. Both nominal references must remain usable below. No
        // send/work/attempt/byte history or reservation identity is refunded.
        assert_true(
          after.reserved_retention_bytes < before.reserved_retention_bytes,
        )
        assert_true(
          after.reserved_execution_bytes < before.reserved_execution_bytes,
        )
        // The RowRun settles its one response reservation into its actual
        // retained holding; the Native capacity token remains live.
        assert_eq(after.live_reservations, before.live_reservations - 1)
        assert_eq(after.planning_work, before.planning_work)
        assert_eq(after.attempts, before.attempts)
        assert_eq(after.transferred_bytes, before.transferred_bytes)
        assert_eq(
          after.uncertain_transfer_bytes,
          before.uncertain_transfer_bytes,
        )
        done = true
        break
      }
    }
    assert_true(done)
    let captured = content
      .keyed_capture()
      .native_content_join_stage("original keyed capture")
    assert_true(
      @row_host.keyed_row_capture_matches_request(captured, request_value),
    )
    // Independent Node SHA-256 of the selected original authored UTF8 field.
    // The issuer/Store must return a nominal Content value, never a String.
    let response = @row_host.keyed_row_capture_read(captured).unwrap()
    assert_eq(@execution.supplied_relation_read_row_count(response), 1)
    let resource = @sourceviews.keyed_row_request_field(
      request_value, "resource",
    ).unwrap()
    guard resource.value is @admitted.Reference(resource_reference) else {
      fail("original ResourceRef required")
    }
    let identity = (file._retained_resolve_identity)(
      binding, resource_reference,
    ).unwrap()
    guard @json.parse(
        @env.get_env_var("ACTQL_TEST_NATIVE_CONTENT_DIGESTS").unwrap(),
      )
      is Object(expected) &&
      expected.get(identity) is Some(String(digest)) else {
      fail("independent original content digest required")
    }
    let mut content_values = 0
    for column in 0..<3 {
      if @execution.supplied_relation_read_cell(response, 0, column)
        is Some(@admitted.Reference(reference)) &&
        @admitted.reference_content_metadata(reference)
        is Some((media, metadata)) {
        assert_eq(media, "text/plain")
        guard @canonical.object_field(metadata, "content_cid")
          is Some(@canonical.String(actual_digest)) else {
          fail("issued Content metadata digest required")
        }
        assert_eq(actual_digest, digest)
        assert_true(@admitted.reference_available(reference))
        content_values += 1
      }
    }
    assert_eq(content_values, 1)
    let mut row_text = 0L
    for column in 0..<3 {
      match @execution.supplied_relation_read_cell(response, 0, column) {
        Some(@admitted.Text(text)) =>
          row_text += @utf8.encode(text).length().to_int64()
        Some(@admitted.Reference(reference)) =>
          row_text += @utf8.encode(@admitted.reference_wire(reference))
            .length()
            .to_int64()
        _ =>
          fail(
            "original keyed response has only two references and its version Text",
          )
      }
    }
    assert_true(row_text <= response_bytes)
    measured_text += row_text
    if requests == 2 && row == 1 {
      // Establish the original 4096-byte fixture mismatch explicitly. The
      // Source policy/Ledger do not change: its two checked page allowances
      // already supply this finite assembly construction envelope.
      assert_true(measured_text > 4096L)
      assert_true(measured_text <= assembly_bytes)
    }
    content_children.push(content)
    @local_values.begin_client_original_keyed_lookup_response(
      keyed, lookup, request, captured,
    ).native_content_join_stage("original response handoff")
    if requests == 2 {
      let mut copied = false
      for _ in 0..<100000 {
        if @run_host.advance_client_keyed_lookup_input(lookup, 31).native_content_lookup_stage(
            "original keyed row copy " + row.to_string(),
          ) {
          copied = true
          break
        }
      }
      assert_true(copied)
    }
  }
  if requests == 2 {
    let complete = @run_host.finish_client_keyed_lookup_input(lookup).native_content_join_stage(
      "both original keyed responses",
    )
    assert_eq(@execution.supplied_relation_read_row_count(complete), 2)
    let mut content_values = 0
    for row in 0..<2 {
      for column in 0..<3 {
        if @execution.supplied_relation_read_cell(complete, row, column)
          is Some(@admitted.Reference(reference)) &&
          @admitted.reference_content_metadata(reference) is Some((media, _)) {
          assert_eq(media, "text/plain")
          assert_true(@admitted.reference_available(reference))
          content_values += 1
        }
      }
    }
    assert_eq(content_values, 2)
    // Borrow the original Plan's sequence, never compile or prepare a second
    // prefix. The completed lookup supplies its SAME checked left/right reads.
    let selected = @local_values.installed_effect_managed_operation_plan(
      owner,
      prepared,
      first.request,
    ).native_content_join_stage("original Model Plan sequence owner")
    let sequence = @local_values.prepared_installed_effect_model_sequence(
      selected, graph,
    ).native_content_join_stage("retained original Model sequence")
    assert_true(
      physical_equal(
        sequence,
        @local_values.prepared_installed_effect_model_sequence(selected, graph).unwrap(),
      ),
    )
    let model_lookup = if collect_closure {
      let selected_sources = captures.map(value => {
        @row_host.row_captured_input_source(value).unwrap()
      })
      let keyed_observation = @run_host.issue_client_keyed_lookup_observation(
        lookup, source_authority, source_completed,
      ).native_content_join_stage("actual keyed Source observation")
      let admit = (
        selected,
        originals : Array[NativeMockSourceEvidenceOriginal],
        keyed,
      ) => {
        // Consume the actual preselected acquisition originals, never try a
        // Query refusal and then substitute a whole-input fallback. The old
        // generated TRUE filter selected Query; an absent predicate now keeps
        // its existing unfiltered whole-input path and its own evidence API.
        if originals.all(original => original is Query(_)) {
          @run_host.admit_client_infer_composed_sources(
            graph.occurrence,
            selected,
            source_identities,
            originals.map(original => {
              guard original is Query(acquisition) else {
                fail("selected original Query acquisition")
              }
              @row_host.row_acquisition_requirement(acquisition)
            }),
            source_logicals,
            source_observations,
            source_authority,
            "2026-10-12T00:00:00.000Z",
            source_completed,
            keyed~,
          )
        } else {
          assert_true(originals.all(original => original is Whole(_, _)))
          @run_host.admit_client_infer_composed_whole_sources(
            graph.occurrence,
            selected,
            source_identities,
            originals.map(original => {
              guard original is Whole(value, _) else {
                fail("selected original whole-input acquisition")
              }
              value
            }),
            source_logicals,
            source_observations,
            source_authority,
            "2026-10-12T00:00:00.000Z",
            source_completed,
            keyed~,
          )
        }
      }
      assert_true(admit(selected_sources, source_originals, None) is Err(_))
      assert_true(
        admit(
          [selected_sources[1], selected_sources[0]],
          source_originals,
          Some(keyed_observation),
        )
        is Err(_),
      )
      assert_true(
        admit(
          selected_sources,
          [source_originals[1], source_originals[0]],
          Some(keyed_observation),
        )
        is Err(_),
      )
      let closure = admit(
        selected_sources,
        source_originals,
        Some(keyed_observation),
      ).native_content_join_stage("actual Source Model closure")
      assert_true(
        @run_host.client_infer_composed_sources_matches(
          closure,
          graph.occurrence,
        ),
      )
      assert_eq(
        @run_host.client_infer_composed_source_observations(closure).length(),
        3,
      )
      let original = @run_host.client_infer_composed_keyed_lookup(
        closure,
        graph.occurrence,
      ).unwrap()
      assert_true(physical_equal(original, lookup))
      original
    } else {
      lookup
    }
    let model_input = @local_values.start_client_composed_infer_input(
      graph.occurrence,
      sequence,
      [],
      limits.input,
      limits.measurement,
      limits.mapping,
      keyed=Some(model_lookup),
    ).native_content_join_stage("same original keyed Model input")
    let mut mapped = None
    for _ in 0..<100000 {
      match
        @local_values.advance_client_infer_input(model_input, 31).native_content_join_stage(
          "actual keyed Model mapping",
        ) {
        @local_values.Complete(rows, ..) => {
          mapped = Some(rows)
          break
        }
        @local_values.Continue(..) => ()
        _ => fail("original keyed Model mapping did not complete")
      }
    }
    let rows = mapped.unwrap()
    assert_eq(@execution.prepared_infer_rows_count(rows), 2)
    for row in 0..<2 {
      let expected_key = if row == 0 { "006Acme" } else { "006Globex" }
      guard @execution.prepared_infer_rows_key(rows, row, 0).unwrap().value
        is @admitted.Text(key) else {
        fail("original sole Model key")
      }
      assert_eq(key, expected_key)
      let mut notes = 0
      let mut stage = 0
      let mut next = 0
      for field in 0..<3 {
        match
          @execution.prepared_infer_rows_value(rows, row, field).unwrap().value {
          @admitted.Reference(reference) => {
            assert_true(
              @admitted.reference_content_metadata(reference)
              is Some(("text/plain", _)),
            )
            assert_true(@admitted.reference_available(reference))
            notes += 1
          }
          @admitted.Null if row == 0 => next += 1
          @admitted.Text(text) if text ==
            (if row == 0 { "Proposal" } else { "Negotiation" }) => stage += 1
          @admitted.Text("Legal review") if row == 1 => next += 1
          _ => fail("original typed README Model input")
        }
      }
      assert_eq((notes, stage, next), (1, 1, 1))
    }
    assert_true(
      @local_values.cleanup_client_infer_input(model_input).native_content_join_stage(
        "same Model input cleanup",
      ),
    )
  }
  // The original response copy still borrows each nominal Content issuer.
  // Keep both actual captures, then retire the same children before the Store.
  for content in content_children {
    assert_true(
      content.close().native_content_join_stage("Content first physical close"),
    )
  }
  assert_true(
    store.close().native_content_join_stage("Content Store first close"),
  )
  assert_true(library.close_checked() is Err(@local_sqlite.Physical(_)))
  assert_true(
    @run_host.cleanup_client_keyed_lookup_input(lookup, 10000).unwrap(),
  )
  assert_true(
    @local_values.cleanup_client_serialization_prefix(
      @local_values.client_original_composed_keyed_prefix_execution(prefix),
    ).unwrap(),
  )
  for index, child in native_children {
    let mut closed = false
    let mut pending = false
    // Existing Native close is a bounded same-child protocol. A listing may
    // reclaim one retained report at a time. Pending is NOT physical ACK.
    for _ in 0..<10000 {
      match child.close() {
        Ok(true) => {
          closed = true
          break
        }
        Ok(false)
        | Err(
          @row_file.ManagedRead(
            @local_values.Acquisition(@row_host.InvalidState)
          )
        ) => pending = true
        Err(_) => fail("original Native Source cleanup failed")
      }
    }
    assert_true(closed)
    if index == 1 && source_originals[index] is Query(_) {
      // This original Query listing reclaims one retained report per close.
      // Whole input uses its own close protocol and need not invent Pending.
      assert_true(pending)
    }
  }
  @local_values.quiesce_installed_managed_run(owner).native_content_join_stage(
    "same Run quiesce",
  )
  assert_true(
    @run_host.finish_client_model_read_scope(
      scope,
      compiled,
      first.definition,
      graph,
      true,
    ).native_content_join_stage("original Model Scope finish"),
  )
  match @local_values.retire_installed_managed_run(owner) {
    // The actual Native initializer cannot return its holder while this SAME
    // frame is still entered. Preserve that observed refusal as NOT an ACK;
    // the outer caller must close the physical frame and retire this exact Run.
    Err(@local_values.Resource(@initial_resources.Unavailable)) => ()
    Err(@local_values.Resource(issue)) =>
      fail("original Native frame retirement: " + @debug.to_string(issue))
    Err(_) => fail("unexpected original Run retirement refusal")
    Ok(_) => fail("Core cannot ACK a still-entered Native frame")
  }
}

///|
fn Result::native_content_join_plan(
  self : Result[
    @local_values.ClientInstalledEffectManagedPlan,
    @local_values.ClientInstalledManagedRunIssue,
  ],
) -> @local_values.ClientInstalledEffectManagedPlan raise {
  match self {
    Ok(value) => value
    Err(issue) => {
      let label = match issue {
        @local_values.ForeignOriginal => "ForeignOriginal"
        @local_values.Unsupported => "Unsupported"
        @local_values.InsufficientCapacity => "InsufficientCapacity"
        @local_values.SourceAcquisition(_) => "SourceAcquisition"
        @local_values.SourceRoute(_) => "SourceRoute"
        @local_values.Sequence(_) => "Sequence"
        @local_values.Preparation(_) => "Preparation"
        @local_values.Resource(_) => "Resource"
        @local_values.Ledger(_) => "Ledger"
        @local_values.ModelRead(_) => "ModelRead"
        @local_values.ModelLayout(_) => "ModelLayout"
        @local_values.SerializationPrefix(_) => "SerializationPrefix"
        @local_values.MetadataCapacityUnavailable =>
          "MetadataCapacityUnavailable"
        @local_values.AlreadyBound => "AlreadyBound"
        @local_values.Retired => "Retired"
        @local_values.CleanupPending => "CleanupPending"
      }
      fail("same Request whole Source Plan: " + label)
    }
  }
}

///|
fn[T] Result::native_content_physical_stage(
  self : Result[T, @row_file.NativeRelationFileFailure],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(failure) => {
      let label = match failure.issue() {
        @row_file.InvalidInput => "InvalidInput"
        @row_file.Unavailable => "Unavailable"
        @row_file.ForeignOriginal => "ForeignOriginal"
        @row_file.Capacity => "Capacity"
        @row_file.FileLimit => "FileLimit"
        @row_file.Filesystem(_) => "Filesystem"
        @row_file.Execution(_) => "Execution"
        @row_file.Resource(issue) => "Resource: " + @debug.to_string(issue)
        @row_file.Row(issue) => "Row: " + native_content_row_issue(issue)
        @row_file.Document(_) => "Document"
        @row_file.Mapping(_) => "Mapping"
        @row_file.ManagedRead(@local_values.Acquisition(issue)) =>
          "ManagedRead/Acquisition: " + native_content_row_issue(issue)
        @row_file.ManagedRead(@local_values.ForeignOriginal) =>
          "ManagedRead/ForeignOriginal"
        @row_file.ManagedRead(_) => "ManagedRead"
        @row_file.Content(issue) => "Content: " + @debug.to_string(issue)
        @row_file.Store(_) => "Store"
        @row_file.Lookup(_) => "Lookup"
      }
      let cleanup = match failure.retry_cleanup() {
        Ok(true) => "returned"
        Ok(false) => "pending"
        Err(_) => "refused"
      }
      fail(stage + ": " + label + "; original cleanup=" + cleanup)
    }
  }
}

///|
fn native_content_row_issue(issue : @row_host.RowHostIssue) -> String {
  match issue {
    @row_host.InvalidSpecification => "InvalidSpecification"
    @row_host.Declaration(_) => "Declaration"
    @row_host.ForeignDeclaration => "ForeignDeclaration"
    @row_host.Source(@row_host.KeyedLimit(label)) =>
      "Source/KeyedLimit: " + label
    @row_host.Source(@row_host.UndeclaredSource) => "Source/UndeclaredSource"
    @row_host.Source(@row_host.KeyedOwner(_)) => "Source/KeyedOwner"
    @row_host.Source(_) => "Source"
    @row_host.InvalidContracts => "InvalidContracts"
    @row_host.Registration => "Registration"
    @row_host.Candidate => "Candidate"
    @row_host.Selection => "Selection"
    @row_host.Evidence(_) => "Evidence"
    @row_host.Attempt(_) => "Attempt"
    @row_host.Consumer(_) => "Consumer"
    @row_host.SourceEvidence(_) => "SourceEvidence"
    @row_host.Physical(original) => "Physical: " + @debug.to_string(original)
    @row_host.Residual(_) => "Residual"
    @row_host.ResidualWork(_) => "ResidualWork"
    @row_host.InputValidationWork(_) => "InputValidationWork"
    @row_host.InputKeys(_) => "InputKeys"
    @row_host.InputScores(_) => "InputScores"
    @row_host.InvalidState => "InvalidState"
  }
}

///|
fn[T] Result::native_content_read_stage(
  self : Result[T, @local_values.ClientInstalledSourceReadIssue],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(issue) => {
      let label = match issue {
        @local_values.ForeignOriginal => "ForeignOriginal"
        @local_values.AlreadyBound => "AlreadyBound"
        @local_values.AlreadyStarted => "AlreadyStarted"
        @local_values.Unbound => "Unbound"
        @local_values.Retired => "Retired"
        @local_values.CleanupPending => "CleanupPending"
        @local_values.Import(_) => "Import"
        @local_values.Resource(value) => "Resource: " + @debug.to_string(value)
        @local_values.Acquisition(value) =>
          "Acquisition: " + native_content_row_issue(value)
        @local_values.ManagedRun(_) => "ManagedRun"
      }
      fail(stage + ": " + label)
    }
  }
}

///|
fn[T] Result::native_content_lookup_stage(
  self : Result[T, @run_host.ClientKeyedRequestIssue],
  stage : String,
) -> T raise {
  match self {
    Ok(value) => value
    Err(issue) => {
      let label = match issue {
        @run_host.ForeignLeft => "ForeignLeft"
        @run_host.Capture(_) => "Capture"
        @run_host.Read(_) => "Read"
        @run_host.Input(_) => "Input"
        @run_host.Request(_) => "Request"
        @run_host.Wire(_) => "Wire"
        @run_host.LookupLimit(name) => "LookupLimit: " + name
        @run_host.LookupIncomplete => "LookupIncomplete"
        @run_host.InvalidObservation => "InvalidObservation"
        @run_host.Assembly(name) => "Assembly: " + name
        @run_host.Physical(value) => "Physical: " + @debug.to_string(value)
        @run_host.Row(value) => "Row: " + @debug.to_string(value)
        @run_host.InputCapture(value) =>
          "InputCapture: " + @debug.to_string(value)
      }
      fail(stage + ": " + label)
    }
  }
}

///|
priv enum NativeMockSourceEvidenceOriginal {
  Query(@row_host.RowAcquisition)
  Whole(@sourceviews.SourceAcquisition, @row_host.RowInputAcquisition)
}

///|
fn Result::native_source_logical_stage(
  self : Result[
    @publication.RunEvidenceValue,
    @run_host.ClientCapturedSourceLogicalIssue,
  ],
  label : String,
) -> @publication.RunEvidenceValue raise {
  match self {
    Ok(value) => value
    Err(issue) => {
      let cause = match issue {
        ForeignPrepared => "ForeignPrepared"
        ForeignIdentity => "ForeignIdentity"
        ForeignRequirement => "ForeignRequirement"
        Encoding(_) => "Encoding"
        Evidence(_) => "Evidence"
        Admission(_) => "Admission"
      }
      fail(label + ": " + cause)
    }
  }
}
