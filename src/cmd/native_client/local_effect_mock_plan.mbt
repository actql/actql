///|
// Retained by the SAME command before fallible Scope completion/adoption.
// This is a caller record, never a new Request, grant or resource owner.
priv struct LocalNativeMockEffectPlan {
  first : LocalEffectFirstCompilation
  _retained_prepared : @run_host.PreparedClientEffectComputation
  _retained_plan : @local_values.ClientInstalledEffectManagedPlan
  _retained_import_recipes : Array[Array[@execution.ExecutionCapacity]]
  mut source_start : @local_host.NativeClientWorkFirstStart?
  mut scope : @run_host.ClientModelReadScope?
  mut source_started_at : String?
  mut source_completed_at : String?
  mut prefix : @local_values.ClientOriginalComposedKeyedPrefix?
  mut lookup : @run_host.ClientKeyedLookupInput?
  mut model_read : LocalNativeMockModelRead?
  mut model_output : @execution.CompletedOutput?
  mut direct_sources : LocalNativeMockEffectDirectSources?
  mut _retained_local_model_observation : @publication.CapturedEffectDependencyBody?
  mut _retained_local_model_dependencies : Array[(String, String, String)]?
  mut model_use : @infer.OutputUse?
  mut effect_host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]?
  mut effect_capture : @strategy.CapturedEffectRunDAG?
  mut suffix : @local_values.LocalValuesExecution?
  mut suffix_failure : @local_values.LocalValuesExecutionFailure?
  mut proposals : LocalNativeMockEffectProposals?
  mut preview : LocalNativeMockEffectPreview?
  mut computation : LocalNativeMockEffectComputation?
  mut source_review : @local_host.NativeMockEffectReview?
  targets : Array[LocalNativeMockEffectTarget]
  keyed_reads : Array[@local_values.ClientInstalledKeyedSourceRead]
  sources : Array[@row_file.NativeRelationFileCapture]
  source_failures : Array[@row_file.NativeRelationFileFailure]
  source_reads : Array[@local_values.ClientInstalledSourceRead]
  captured_inputs : Array[@row_host.RowCapturedInput]
  input_originals : Array[LocalNativeMockEffectSourceOriginal]
}

///|
fn LocalNativeMockEffectPlan::model_graph(
  self : Self,
) -> @run_host.ClientInferPlanGraph {
  self.first._retained_models[0].graph
}

///|
fn retain_native_mock_effect_plan(
  first : LocalEffectFirstCompilation,
  prepared : @run_host.PreparedClientEffectComputation,
  plan : @local_values.ClientInstalledEffectManagedPlan,
  capture_recipes : Array[Array[@execution.ExecutionCapacity]],
) -> LocalNativeMockEffectPlan {
  {
    first,
    _retained_prepared: prepared,
    _retained_plan: plan,
    _retained_import_recipes: capture_recipes,
    source_start: None,
    scope: None,
    source_started_at: None,
    source_completed_at: None,
    prefix: None,
    lookup: None,
    model_read: None,
    model_output: None,
    direct_sources: None,
    _retained_local_model_observation: None,
    _retained_local_model_dependencies: None,
    model_use: None,
    effect_host: None,
    effect_capture: None,
    suffix: None,
    suffix_failure: None,
    proposals: None,
    preview: None,
    computation: None,
    source_review: None,
    targets: [],
    keyed_reads: [],
    sources: [],
    source_failures: [],
    source_reads: [],
    captured_inputs: [],
    input_originals: [],
  }
}

///|
// Complete canonical request preimage, including the original full before.
// This bound funds construction before the existing later wire-size refusal.
fn native_mock_effect_request_bytes(
  wire : @execution.RowWireLimits,
  page_bytes : Int,
  binding : String,
  mapping : String,
) -> Int? {
  let bytes = 2L * wire.max_bytes.to_int64() +
    page_bytes.to_int64() +
    6L * (binding.length().to_int64() + mapping.length().to_int64() + 71L) +
    128L
  if bytes > 2147483647L {
    None
  } else {
    Some(bytes.to_int())
  }
}

///|
// Same original constructor family as the existing file implementation, using
// the actual Native consumers' already selected bounds. In particular the raw
// saved response is Bytes, while its projected control is the closed Native
// receipt decoder. Program compilation limits cannot describe either one.
fn native_mock_effect_recipe_capacities(
  wire : @execution.RowWireLimits,
  record_bytes : Int,
  request_bytes : Int,
  physical : @execution.ExecutionCapacity,
) -> Result[
  Array[@execution.ExecutionCapacity],
  @local_values.ClientInstalledManagedRunIssue,
] {
  let policy = @run_host.client_standard_effect_computation_limits().effects
  let stored = @local_host.native_client_effect_storage_limits()
  @local_values.installed_physical_write_recipe_capacities(
    wire.max_bytes,
    wire.max_nodes,
    wire.max_depth,
    record_bytes,
    policy.max_admission_nodes,
    policy.max_admission_depth,
    request_bytes,
    record_bytes,
    stored.receipt.max_wire_bytes,
    stored.response_bytes,
    Int::max(stored.ledger.max_nodes, stored.receipt.max_nodes),
    Int::max(stored.ledger.max_depth, stored.receipt.max_depth),
    physical,
    control_wire_bytes=Some(
      Int::max(stored.ledger.max_wire_bytes, stored.receipt.max_wire_bytes),
    ),
    request_construction=Some(physical),
  )
}

///|
// This Native caller decodes/projections one proposal at a time, returns its
// row Strings, and constructs Preview only after that loop has returned. Keep
// every row's retained output, but one maximum synchronous workspace alongside
// the fixed capture. Recovery retains its independently selected old recipe.
fn native_mock_effect_serial_capture_recipe(
  original : Array[@execution.ExecutionCapacity],
) -> Array[@execution.ExecutionCapacity]? {
  if original.length() != 6 {
    return None
  }
  let fixed = original[0]
  let row = original[1]
  let retained = @execution.execution_capacity_retained_bytes(fixed)
  let workspace = Int64::max(
    @execution.execution_capacity_execution_bytes(fixed) - retained,
    @execution.execution_capacity_execution_bytes(row) -
    @execution.execution_capacity_retained_bytes(row),
  )
  guard @execution.checked_preparation_add_product(retained, workspace, 1L)
    is Some(execution) else {
    return None
  }
  let recipe = original.copy()
  recipe[0] = @execution.execution_capacity(retained, execution).unwrap()
  let row_retained = @execution.execution_capacity_retained_bytes(row)
  recipe[1] = @execution.execution_capacity(row_retained, row_retained).unwrap()
  Some(recipe)
}

///|
// Warm target observations close each physical child before the next row.
// The request operation owns the before/version input and returned request
// wire. Only its caller reference persists on this control for every row.
// Keep one full original constructor peak for the serial observation, even
// on failure. The Saved application funds its own response and receipt sinks
// after approval; no write response is retained by this warm control.
fn native_mock_effect_target_control_capacity(
  original : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity? {
  guard @execution.preparation_representation_cost({
      record_headers: 0L,
      reference_slots: 1L,
      scalar_words: 0L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(slot) &&
    @execution.checked_preparation_add_product(
      slot,
      @execution.execution_capacity_execution_bytes(original),
      1L,
    )
    is Some(execution) else {
    return None
  }
  @execution.execution_capacity(slot, execution)
}

///|
// The same two member and five row occurrences as the existing file UPDATE
// implementation. Read occurrences are physical here: this Native adapter
// performs its own file I/O rather than borrowing a separate reader service.
// Names select originals in the Plan; none is an Account permission or claim.
fn native_mock_effect_operations(
  prepared : @run_host.PreparedClientEffectComputation,
  mock : LocalProjectMockDeclarations,
  wire : @execution.RowWireLimits,
  record_bytes : Int,
  capture_recipes : Array[Array[@execution.ExecutionCapacity]],
) -> Array[@local_values.ClientInstalledEffectOperationDemand] raise ClientStop {
  let installations = mock.write_installations.unwrap_or_else(() => {
    stop("LocalOriginalEffectImplementationUnavailable")
  })
  let headers = @checked.effect_program_static_headers(
    @run_host.prepared_client_effect_computation_candidate(prepared),
  )
  let selected = []
  let policy = @run_host.client_standard_effect_computation_limits()
  let imports = native_mock_effect_import_construction(prepared, wire)
  for index in 0..<@syntax.effect_header_count(headers) {
    let header = @syntax.effect_header_at(headers, index).unwrap()
    let stage = @syntax.effect_header_stage(header)
    let id = @syntax.effect_header_id(header)
    let descriptor = @run_host.client_effect_member_descriptor(
      prepared,
      stage,
      id,
      policy.effects.max_work,
    ).unwrap_or_else(() => stop("LocalOriginalEffectImplementationUnavailable"))
    guard descriptor.2 == "update" &&
      installations
      .iter()
      .find_first(value => {
        value.target == descriptor.3 &&
        value.write.mapping.mapping_ref == descriptor.4 &&
        value.write.mapping.mapping_cid == descriptor.5
      })
      is Some(installation) &&
      installation._retained_source._retained_rows
      .iter()
      .find_first(value => {
        value.view.resource == installation.write.mapping.resource
      })
      is Some(binding) else {
      stop("LocalOriginalEffectImplementationUnavailable")
    }
    let physical = @row_file.native_relation_file_target_io_capacity(
      binding.provider,
      installation.write.writable_fields.length(),
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    // The operation consumes this original completed-row writer, this
    // installation's private review record, and Native Journal codecs. The
    // static Program compiler's 10MiB artifact ceiling is not their input.
    // Include the complete canonical request prefix before its later check:
    // target + changes + full before, six-byte JSON escaping for original
    // binding/Mapping metadata, the original 71-unit version and punctuation.
    let request_bytes = native_mock_effect_request_bytes(
      wire,
      binding.limits.page.max_bytes,
      installation.binding,
      installation.write.mapping.mapping_cid,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let original_capture = native_mock_effect_recipe_capacities(
      wire, record_bytes, request_bytes, physical,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let warm_capture = native_mock_effect_serial_capture_recipe(
      original_capture,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    // Retain the SAME initial recipe. The first capture grows only for its
    // actual original bodies; its maximum is a refusal bound, not a grant.
    let quantities = warm_capture.copy()
    let maximum = warm_capture.copy()
    if index == 0 {
      if @execution.execution_capacity_retained_bytes(imports.0) > 0L {
        quantities[0] = imports.0
        quantities[1] = @execution.execution_capacity(0L, 0L).unwrap()
      }
    }
    maximum[0] = @execution.add_execution_capacity(maximum[0], imports.1).unwrap_or_else(() => {
        stop("LocalOriginalEffectCapacityUnavailable")
      },
    )
    let initial = @local_values.prepare_installed_effect_capture_recipe_extent(
      "native.mock.file.capture", quantities,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let capture = if index == 0 {
      capture_recipes.push(quantities)
      capture_recipes.push(warm_capture)
      @local_values.prepare_installed_effect_staged_extent(
        initial,
        @local_values.prepare_installed_effect_capture_recipe_extent(
          "native.mock.file.capture", maximum,
        ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable")),
      ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    } else {
      initial
    }
    let recovery = @local_values.prepare_installed_effect_capture_recipe_extent(
      "native.mock.file.recovery", original_capture,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let read_initial = @row_file.native_relation_file_target_read_io_capacity(
      binding.provider,
      installation.write.writable_fields.length(),
      response_bytes=Some(0),
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let read_maximum = @row_file.native_relation_file_target_read_io_capacity(
      binding.provider,
      installation.write.writable_fields.length(),
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let read_maximum = native_mock_effect_capacity_envelope(
      physical, read_maximum,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    // Initial fixed controls/replacement slots, not another Target document.
    // Actual original changes/before/version refine this SAME staged extent.
    let request_initial = native_mock_effect_changes_input_capacity(
      binding.limits.page,
      installation.write.mapping.write_fields.length(),
      "",
      "",
      "",
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let request_maximum = native_mock_effect_capacity_envelope(
      quantities[2],
      request_initial,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let request = @local_values.prepare_installed_effect_staged_extent(
      @local_values.prepare_installed_effect_operation_extent(
        "native.mock.file.request", request_initial, 0L, false,
      ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable")),
      @local_values.prepare_installed_effect_operation_extent(
        "native.mock.file.request", request_maximum, 0L, false,
      ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable")),
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let write = @local_values.prepare_installed_effect_operation_extent(
      "native.mock.file.write",
      quantities[3],
      2L * binding.limits.page.max_bytes.to_int64(),
      true,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let rows = [request, write]
    for phase in ["capture-target", "apply-target", "resume-target"] {
      let operation = "native.mock.file." + phase
      let maximum = @local_values.prepare_installed_effect_operation_extent(
        operation,
        if phase == "capture-target" {
          read_maximum
        } else {
          physical
        },
        binding.limits.page.max_bytes.to_int64(),
        true,
      ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
      let extent = if phase == "capture-target" {
        @local_values.prepare_installed_effect_staged_extent(
          @local_values.prepare_installed_effect_operation_extent(
            operation,
            read_initial,
            binding.limits.page.max_bytes.to_int64(),
            true,
          ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable")),
          maximum,
        ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
      } else {
        maximum
      }
      rows.push(extent)
    }
    let controls_per_row = native_mock_effect_target_control_capacity(
      quantities[4],
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    selected.push(
      @local_values.prepare_installed_effect_operation_demand_with_controls(
        prepared,
        stage,
        id,
        [capture, recovery],
        rows,
        controls_per_row,
      ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable")),
    )
  }
  selected
}

///|
fn native_mock_effect_managed_plan(
  prepared : @run_host.PreparedClientEffectComputation,
  first : LocalEffectFirstCompilation,
  mock : LocalProjectMockDeclarations,
  contracts : @local_values.ClientInstalledSequenceContracts,
  provider : @local_compute.ManagedProvider,
  publication : @execution.ExecutionCapacity,
  record_bytes : Int,
  capture_recipes? : Array[Array[@execution.ExecutionCapacity]] = [],
) -> @local_values.ClientInstalledEffectManagedPlan raise ClientStop {
  guard first._retained_models.length() == 1 else {
    stop("LocalOriginalEffectPlanUnavailable")
  }
  let selected = first._retained_models[0]
  let limits = selected._retained_limits
  let compiled = first.model_compiled.unwrap_or_else(() => {
    stop("LocalOriginalEffectPlanUnavailable")
  })
  // Read ONLY the already retained selected bounds. These are the same
  // existing read/bootstrap fields projected by the common consumer bridge;
  // no Node-specific physical layout or spare Model allowance is inferred.
  let retained = limits.mapping.logical.max_live_value_bytes
  let execution = limits.identity.wire.max_bytes.to_int64()
  let suffix = @local_values.retained_effect_local_tasks_control_capacity(
    @strategy.checked_effect_computation_graph(
      @run_host.prepared_client_effect_computation_graph(prepared),
    ),
  ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
  let publication = @execution.add_execution_capacity(publication, suffix).unwrap_or_else(() => {
      stop("LocalOriginalEffectCapacityUnavailable")
    },
  )
  let model = @local_values.prepare_installed_effect_model_demand(
    prepared,
    compiled,
    first.allowed.compilation,
    first.definition,
    selected.graph.occurrence,
    selected.graph,
    limits.model.ledger,
    retained,
    execution,
    limits.input.rows.operation_entries,
    limits.input.rows.retained_entries,
    limits.input.rows.metadata_entries,
    bootstrap=Some((retained, execution)),
    publication=Some(publication),
  ).unwrap_or_else(() => stop("LocalOriginalEffectPlanUnavailable"))
  native_mock_effect_source_plan(
    prepared,
    first,
    mock,
    contracts,
    limits.identity.wire,
    record_bytes,
    capture_recipes,
    model=Some(model),
    provider_factory=_ => [provider],
  )
}

///|
fn native_mock_effect_source_plan(
  prepared : @run_host.PreparedClientEffectComputation,
  first : LocalEffectFirstCompilation,
  mock : LocalProjectMockDeclarations,
  contracts : @local_values.ClientInstalledSequenceContracts,
  wire : @execution.RowWireLimits,
  record_bytes : Int,
  capture_recipes : Array[Array[@execution.ExecutionCapacity]],
  model? : @local_values.ClientInstalledEffectModelDemand? = None,
  query_contracts? : (String, String)? = None,
  report? : (@local_values.ClientInstalledManagedRunIssue) -> Unit = _ => (),
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local_compute.ManagedProvider,
  ],
) -> @local_values.ClientInstalledEffectManagedPlan raise ClientStop {
  let operations = native_mock_effect_operations(
    prepared, mock, wire, record_bytes, capture_recipes,
  )
  let assets = @run_host.client_local_product_assets()
  let sources = first._retained_sources
  // The checked occurrence chooses the route. Only the direct Source path
  // supplies the installed Runtime's Query protocol, and Whole inputs ignore it.
  let (query, evidence) = query_contracts.unwrap_or(("", ""))
  match
    @local_values.prepare_installed_effect_managed_source_plan(
      prepared,
      first.request,
      sources.map(value => value._retained_input),
      query,
      evidence,
      sources.map(value => {
        match value._retained_reader {
          Rows(row) => row.limits.page.max_bytes.to_int64()
          Files(_, _) =>
            local_project_mock_file_limits().page.max_bytes.to_int64()
        }
      }),
      sources.map(value => {
        match value._retained_reader {
          Rows(row) => row.limits.page.max_bytes.to_int64()
          Files(_, _) =>
            local_project_mock_file_limits().page.max_bytes.to_int64()
        }
      }),
      contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      operations,
      model~,
      runtime_admission=true,
      provider_factory~,
    ) {
    Ok(plan) => plan
    Err(issue) => {
      report(issue)
      stop("LocalOriginalEffectPlanUnavailable")
    }
  }
}

///|
fn LocalCommandBusinessPreparation::prepare_mock_effect_plan(
  self : LocalCommandBusinessPreparation,
  first : LocalEffectFirstCompilation,
  installation : LocalRunInstallation,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    self.original.journal is Some(journal) &&
    physical_equal(journal, self.capture) &&
    self.original.journal_read_open &&
    !business.active &&
    business.request_parent is Some(parent) &&
    business.request_input is Some(input) &&
    business.request_body is Some(body) &&
    body is @local_host.Effect(borrow) &&
    @initial_resources.preparation_body_borrow_value(borrow) is Some(prepared) &&
    business.request_run is None &&
    business.effect_model is None &&
    first._retained_models.length() == business.model_work.length() &&
    (
      first._retained_models.length() == 1 ||
      (
        first._retained_models.is_empty() &&
        first.model_compiled is None &&
        !first._retained_sources.is_empty()
      )
    ) &&
    self.original.project is Some(project) &&
    project.mock_declarations is Some(mock) else {
    stop("LocalOriginalEffectPlanUnavailable")
  }
  // Borrow the immutable protocol bodies while the original Journal Read is
  // entered. Request entry suspends that Read, so only the borrowed DATA may
  // cross into the Request. Common still selects the route from the Program.
  let query_contracts = if first._retained_models.is_empty() {
    guard self.original.runtime is Some(runtime) else {
      stop("PackagedLocalRuntimeChanged")
    }
    match runtime.query_contract_assets() {
      Ok(contracts) => contracts
      Err(issue) => {
        self.original.retain_primary(CommandRuntime(issue))
        stop("PackagedLocalRuntimeChanged")
      }
    }
  } else {
    None
  }
  self.original.with_business_request(self.capture, () => {
    let capture_recipes = []
    let plan = if first._retained_models.is_empty() {
      let file_limits = local_project_mock_file_limits()
      native_mock_effect_source_plan(
        prepared,
        first,
        mock,
        self.installed_contracts,
        {
          max_columns: 100,
          max_order_work: file_limits.max_work,
          max_bytes: file_limits.page.max_bytes,
          max_nodes: file_limits.page.max_nodes,
          max_depth: file_limits.page.max_depth,
        },
        native_mock_effect_record_bytes(installation),
        capture_recipes,
        query_contracts~,
        report=issue => {
          self.original.retain_primary(
            CommandBusinessEffectProposals(Managed(issue)),
          )
        },
        provider_factory=native_request_provider_factory,
      )
    } else {
      let selected = first._retained_models[0]
      let limits = selected._retained_limits
      let work = business.model_work[0]
      let provider = @infer.composed_local_provider(
        selected.graph.occurrence,
        limits,
        inputs => {
          // This Native root reads its captured inputs through the original
          // composed Source closure; unrelated external ports cannot replace it.
          if !inputs.is_empty() || business.model_work.length() != 1 {
            return Err(@infer.InvalidAdvance)
          }
          // The SAME command slot owns this original Work through its real
          // cleanup ACK. Retained provider metadata must not independently pin
          // the closed Work/Journal after that slot has retired.
          business.model_work[0]
          .borrow_opened_original_model()
          .map_err(_ => @infer.InvalidAdvance)
        },
        _ => @compute_sdk.ComputeUnsupported,
      )
      native_mock_effect_managed_plan(
        prepared,
        first,
        mock,
        self.installed_contracts,
        provider,
        work
        .observation_capacity(
          first.request,
          first.model_compiled.unwrap(),
          first.definition,
          selected.graph,
        )
        .unwrap_or_else(() => {
          stop("LocalOriginalModelPublicationCapacityUnavailable")
        }),
        native_mock_effect_record_bytes(installation),
        capture_recipes~,
      )
    }
    let state = retain_native_mock_effect_plan(
      first, prepared, plan, capture_recipes,
    )
    business.effect_model = Some(state)
    // The original input borrow precedes Plan construction; return it before
    // Scope/census growth and final completion, never reconstruct that input.
    @local_host.return_native_client_submitted_request_body(body).unwrap_or_else(() => {
        stop("LocalOriginalEffectPlanUnavailable")
      },
    )
    |> ignore
    business.request_body = None
    if !first._retained_models.is_empty() {
      state.scope = Some(
        @local_values.prepare_request_effect_model_read_scope(
          parent, input, plan,
        ).unwrap_or_else(() => stop("LocalOriginalModelScopeUnavailable")),
      )
    }
    @local_values.complete_request_effect_preparation(parent, input, plan).unwrap_or_else(() => {
        stop("LocalOriginalEffectPlanUnavailable")
      },
    )
    let run = (match state.scope {
      Some(scope) =>
        @local_values.begin_request_effect_model_managed_run(
          parent,
          first.request,
          scope,
        )
      None =>
        @local_values.begin_request_effect_managed_run(parent, first.request)
    }).unwrap_or_else(() => stop("LocalOriginalEffectPlanUnavailable"))
    business.request_run = Some(run)
    business.request_parent = None
    business.request_initial = None
    business.request_input = None
    business.request_intent = None
  })
}

///|
// Additional immutable producer/import metadata, before the actual SAME Plan
// capture operation is borrowed. The existing JSON constructor owns parser,
// Unicode and wire backing; zero here is its additive non-physical basis, not
// a Provider, a spare allowance or a claim of physical Source backing.
fn native_mock_effect_import_construction(
  prepared : @run_host.PreparedClientEffectComputation,
  wire : @execution.RowWireLimits,
) -> (@execution.ExecutionCapacity, @execution.ExecutionCapacity) raise ClientStop {
  let empty = @execution.execution_capacity(0L, 0L).unwrap()
  let candidate = @run_host.prepared_client_effect_computation_candidate(
    prepared,
  )
  let program = @checked.effect_program_static_checked_computation(candidate)
  let model = @run_host.prepared_client_effect_infer_occurrence(prepared)
  let unit = match model {
    Some(occurrence) =>
      @run_host.client_infer_occurrence_coordinates(occurrence).1
    None => {
      let headers = @checked.effect_program_static_headers(candidate)
      guard @syntax.effect_header_at(headers, 0) is Some(header) else {
        return (empty, empty)
      }
      @syntax.effect_header_stage(header)
    }
  }
  let imports = @checked.unit_result_import_count(program, unit)
    .unwrap_or(0)
    .to_int64()
  if model is Some(_) && imports == 0L {
    return (empty, empty)
  }
  let direct = @run_host.select_client_effect_direct_acquisition_occurrences(
    prepared, 1000000,
  ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
  let units = @run_host.client_direct_acquisition_occurrence_count(direct).to_int64()
  if model is None && units == 0L {
    return (empty, empty)
  }
  // The Model import route retains its existing composed reader admission.
  if units < 1L || (model is Some(_) && units > 2L) {
    stop("LocalOriginalEffectCapacityUnavailable")
  }
  let mut results = 0L
  let stages = @checked.checked_stage_results(program)
  if model is None {
    let declarations = @stage_results.stage_at(stages, unit).unwrap_or_else(() => {
      stop("LocalOriginalEffectCapacityUnavailable")
    })
    results = @results.count(declarations).to_int64()
    // The Source-only Query route can import a prior completed Source Unit.
    // Size the full producer Manifest and all its Results beside the Effect
    // Unit. The actual import proof still has to select that same producer.
    if imports == 1L &&
      units == 1L &&
      @run_host.client_direct_acquisition_occurrence_at(direct, 0)
      is Some((source_stage, _, _)) &&
      source_stage != unit &&
      @stage_results.stage_at(stages, source_stage) is Some(producer) {
      results += @results.count(producer).to_int64()
    }
  } else {
    for index in 0..<units.to_int() {
      let (stage, _, _) = @run_host.client_direct_acquisition_occurrence_at(
        direct, index,
      ).unwrap()
      let declarations = @stage_results.stage_at(stages, stage).unwrap_or_else(() => {
        stop("LocalOriginalEffectCapacityUnavailable")
      })
      results += @results.count(declarations).to_int64()
    }
  }
  // The Model path additionally retains its independent boundary Result.
  let extra_results = if model is Some(_) {
    native_mock_effect_extra_unit_results(prepared, unit).to_int64()
  } else {
    0L
  }
  results += extra_results
  // Per Result: Definition/Artifact/Derivation/Ordering. Per import: original
  // observation and derived Relation. Per producer: Invocation/full Manifest.
  // The imported combined scope and semantic Invocation add two bodies; the
  // once-selected original-observation retention projection adds one more.
  // Whole-input producers additionally retain their request, source policy,
  // Relation, Ordering and Scope; keyed callers borrow those same bodies.
  let documents = 4L * results + 2L * imports + 8L * units + 3L
  let json = @local_values.installed_json_effect_response_construction_capacity(
    empty, 16384, 1024, 20,
  ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
  let r = @execution.checked_preparation_add_product(
    0L,
    @execution.execution_capacity_retained_bytes(json),
    Int64::max(6L, imports + 2L),
  ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
  let arrays = @execution.preparation_array_representation(
    // Five additional public-evidence vectors retain borrowed original
    // contracts/schema/codec references; no second bodies or rows are made.
    3L * units + 8L,
    units + 8L * results + imports + extra_results,
    true,
  ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
  let controls = @execution.preparation_representation_cost(
    @execution.compose_preparation_representation([
      arrays,
      {
        // The Source snapshot phase adds one bounded optional extent and
        // one local constructor closure. Also cover a transient emitted
        // usage tuple and the current body's extent and depth options.
        // The scoped Source copy adds its old and new optional counters and
        // the synchronous bridge callback's startup flag and captured slot.
        record_headers: 12L +
        extra_results +
        5L * units +
        5L * results +
        3L * imports +
        4L * 4096L * results,
        reference_slots: 27L +
        9L * extra_results +
        40L * units +
        24L * results +
        20L * imports +
        8L * 4096L * results,
        // A checked static dependency entry holds its three encoder
        // dimensions until that Result's complete static list is consumed.
        scalar_words: 2L * documents +
        extra_results +
        15L +
        3L * 4096L * results,
        // All static emitted Strings precede their parse callback. Their
        // existing shared byte budget bounds their total original text.
        owned_utf16_units: results * wire.max_bytes.to_int64(),
        owned_wire_bytes: results * wire.max_bytes.to_int64(),
      },
    ]).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable")),
  ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
  let retained = @execution.checked_preparation_add_product(r, controls, 1L).unwrap_or_else(() => {
      stop("LocalOriginalEffectCapacityUnavailable")
    },
  )
  let workspace = @execution.execution_capacity_execution_bytes(json) -
    @execution.execution_capacity_retained_bytes(json)
  let initial = @execution.execution_capacity(retained, retained + workspace).unwrap_or_else(() => {
      stop("LocalOriginalEffectCapacityUnavailable")
    },
  )
  // Each Result's complete dependency set shares max_bytes. Every parsed
  // node consumes a byte. The extra one-byte envelopes bound per-body fixed
  // parser controls/depth stacks (at most the existing 4096 body limit), not
  // another logical byte allowance. This ceiling is never reserved eagerly.
  let maximum_body = native_mock_effect_dependency_body_capacity(
    wire.max_bytes,
    wire.max_bytes,
    wire.max_depth,
  ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
  let fixed_body = native_mock_effect_dependency_body_capacity(
    1,
    1,
    wire.max_depth,
  ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
  let metadata = native_mock_effect_dependency_body_capacity(16384, 1024, 20).unwrap_or_else(() => {
      stop("LocalOriginalEffectCapacityUnavailable")
    },
  )
  let retained_max = @execution.checked_preparation_add_product(
    retained,
    @execution.execution_capacity_retained_bytes(metadata),
    documents,
  ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
  let max_r = @execution.checked_preparation_add_product(
    retained_max,
    @execution.execution_capacity_retained_bytes(maximum_body) +
    4096L * @execution.execution_capacity_retained_bytes(fixed_body),
    2L * results,
  ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
  let max_e = @execution.checked_preparation_add_product(
    max_r,
    @execution.execution_capacity_execution_bytes(maximum_body) -
    @execution.execution_capacity_retained_bytes(maximum_body) +
    workspace,
    1L,
  ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
  (
    // Direct starts with the existing warm recipe and grows on actual bodies.
    if model is Some(_) {
      initial
    } else {
      empty
    },
    @execution.execution_capacity(max_r, max_e).unwrap_or_else(() => {
      stop("LocalOriginalEffectCapacityUnavailable")
    }),
  )
}
