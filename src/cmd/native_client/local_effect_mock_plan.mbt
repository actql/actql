///|
// Retained by the SAME command before fallible Scope completion/adoption.
// This is a caller record, never a new Request, grant or resource owner.
priv struct LocalNativeMockEffectPlan {
  first : LocalEffectFirstCompilation
  _retained_prepared : @run_host.PreparedClientEffectComputation
  _retained_plan : @local_values.ClientInstalledEffectManagedPlan
  graph : @run_host.ClientInferPlanGraph
  mut scope : @run_host.ClientModelReadScope?
  mut source_started_at : String?
  mut source_completed_at : String?
  mut prefix : @local_values.ClientOriginalComposedKeyedPrefix?
  mut lookup : @run_host.ClientKeyedLookupInput?
  mut model_read : @run_host.ClientModelReadPreparation?
  mut model_output : @execution.CompletedOutput?
  mut model_use : @infer.OutputUse?
  mut effect_host : @builtin.ConfiguredComputeHost[@strategy.RunIssue]?
  mut effect_capture : @strategy.CapturedEffectRunDAG?
  keyed_reads : Array[@local_values.ClientInstalledKeyedSourceRead]
  sources : Array[@row_file.NativeRelationFileCapture]
  source_failures : Array[@row_file.NativeRelationFileFailure]
  source_reads : Array[@local_values.ClientInstalledSourceRead]
  captured_inputs : Array[@row_host.RowCapturedInput]
  input_originals : Array[
    (@sourceviews.SourceAcquisition, @row_host.RowInputAcquisition),
  ]
}

///|
// The same two member and five row occurrences as the existing file UPDATE
// implementation. Read occurrences are physical here: this Native adapter
// performs its own file I/O rather than borrowing a separate reader service.
// Names select originals in the Plan; none is an Account permission or claim.
fn native_mock_effect_operations(
  prepared : @run_host.PreparedClientEffectComputation,
  mock : LocalProjectMockDeclarations,
) -> Array[@local_values.ClientInstalledEffectOperationDemand] raise ClientStop {
  let installations = mock.write_installations.unwrap_or_else(() => {
    stop("LocalOriginalEffectImplementationUnavailable")
  })
  let headers = @checked.effect_program_static_headers(
    @run_host.prepared_client_effect_computation_candidate(prepared),
  )
  let selected = []
  let policy = @run_host.client_standard_effect_computation_limits()
  let codec = policy.program.checking.compilation
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
      installation.write.mapping.write_fields.length(),
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let quantities = @local_values.installed_physical_write_recipe_capacities(
      codec.artifacts.bytes,
      policy.effects.max_admission_nodes,
      policy.effects.max_admission_depth,
      codec.artifacts.bytes,
      policy.effects.max_admission_nodes,
      policy.effects.max_admission_depth,
      binding.limits.page.max_bytes,
      codec.artifacts.bytes,
      codec.policy.bytes,
      Int::max(codec.artifacts.bytes, codec.policy.bytes),
      policy.effects.max_admission_nodes,
      policy.effects.max_admission_depth,
      physical,
      request_construction=Some(physical),
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let capture = @local_values.prepare_installed_effect_capture_recipe_extent(
      "native.mock.file.capture", quantities,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let recovery = @local_values.prepare_installed_effect_capture_recipe_extent(
      "native.mock.file.recovery", quantities,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let request = @local_values.prepare_installed_effect_operation_extent(
      "native.mock.file.request",
      quantities[2],
      0L,
      false,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let write = @local_values.prepare_installed_effect_operation_extent(
      "native.mock.file.write",
      quantities[3],
      2L * binding.limits.page.max_bytes.to_int64(),
      true,
    ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable"))
    let rows = [request, write]
    for phase in ["capture-target", "apply-target", "resume-target"] {
      rows.push(
        @local_values.prepare_installed_effect_operation_extent(
          "native.mock.file." + phase,
          physical,
          binding.limits.page.max_bytes.to_int64(),
          true,
        ).unwrap_or_else(() => stop("LocalOriginalEffectCapacityUnavailable")),
      )
    }
    selected.push(
      @local_values.prepare_installed_effect_operation_demand_with_controls(
        prepared,
        stage,
        id,
        [capture, recovery],
        rows,
        quantities[4],
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
  ).unwrap_or_else(() => stop("LocalOriginalEffectPlanUnavailable"))
  let operations = native_mock_effect_operations(prepared, mock)
  let assets = @run_host.client_local_product_assets()
  let sources = first._retained_sources
  // Whole-input occurrences have no Query contract input. If a different
  // checked Program selects Query, Core refuses these absent contracts;
  // this path never retries a refused Query as a whole input.
  @local_values.prepare_installed_effect_managed_source_plan(
    prepared,
    first.request,
    sources.map(value => value._retained_input),
    "",
    "",
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
    model=Some(model),
    runtime_admission=true,
    provider_factory=_ => [provider],
  ).unwrap_or_else(() => stop("LocalOriginalEffectPlanUnavailable"))
}

///|
fn LocalCommandBusinessPreparation::prepare_mock_effect_plan(
  self : LocalCommandBusinessPreparation,
  first : LocalEffectFirstCompilation,
) -> Unit raise ClientStop {
  guard self.original.business is Some(business) &&
    business.request_parent is Some(parent) &&
    business.request_input is Some(input) &&
    business.request_body is Some(body) &&
    body is @local_host.Effect(borrow) &&
    @initial_resources.preparation_body_borrow_value(borrow) is Some(prepared) &&
    business.request_run is None &&
    business.effect_model is None &&
    first._retained_models.length() == 1 &&
    business.model_work.length() == 1 &&
    self.original.project is Some(project) &&
    project.mock_declarations is Some(mock) else {
    stop("LocalOriginalEffectPlanUnavailable")
  }
  self.original.with_business_request(self.capture, () => {
    let selected = first._retained_models[0]
    let limits = selected._retained_limits
    let work = business.model_work[0]
    let provider = @infer.composed_local_provider(
      selected.graph.occurrence,
      limits,
      inputs => {
        // This Native root reads its captured inputs through the original
        // composed Source closure; unrelated external ports cannot replace it.
        if !inputs.is_empty() {
          return Err(@infer.InvalidAdvance)
        }
        work.borrow_opened_original_model().map_err(_ => @infer.InvalidAdvance)
      },
      _ => @compute_sdk.ComputeUnsupported,
    )
    let plan = native_mock_effect_managed_plan(
      prepared,
      first,
      mock,
      self.installed_contracts,
      provider,
    )
    let state : LocalNativeMockEffectPlan = {
      first,
      _retained_prepared: prepared,
      _retained_plan: plan,
      graph: selected.graph,
      scope: None,
      source_started_at: None,
      source_completed_at: None,
      prefix: None,
      lookup: None,
      model_read: None,
      model_output: None,
      model_use: None,
      effect_host: None,
      effect_capture: None,
      keyed_reads: [],
      sources: [],
      source_failures: [],
      source_reads: [],
      captured_inputs: [],
      input_originals: [],
    }
    business.effect_model = Some(state)
    // The original input borrow precedes Plan construction; return it before
    // Scope/census growth and final completion, never reconstruct that input.
    @local_host.return_native_client_submitted_request_body(body).unwrap_or_else(() => {
        stop("LocalOriginalEffectPlanUnavailable")
      },
    )
    |> ignore
    business.request_body = None
    let scope = @local_values.prepare_request_effect_model_read_scope(
      parent, input, plan,
    ).unwrap_or_else(() => stop("LocalOriginalModelScopeUnavailable"))
    state.scope = Some(scope)
    @local_values.complete_request_effect_preparation(parent, input, plan).unwrap_or_else(() => {
        stop("LocalOriginalEffectPlanUnavailable")
      },
    )
    let run = @local_values.begin_request_effect_model_managed_run(
      parent,
      first.request,
      scope,
    ).unwrap_or_else(() => stop("LocalOriginalEffectPlanUnavailable"))
    business.request_run = Some(run)
    business.request_parent = None
    business.request_initial = None
    business.request_input = None
    business.request_intent = None
  })
}
