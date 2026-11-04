///|
// Sequence/schema/Plan DATA already has the original request_program_plan_quote
// debit. Add only the actual module's snapshot/selection containers and the
// six simultaneous sequence/dispatch arrays. Fixed family constructor controls
// remain trusted installed Host work; no Provider payload or IO allowance is
// inferred from its count. Node supplies its compiled composition count, RelA0.
fn request_model_module_container_bytes(
  tasks : Int,
  captures : Int,
  installed_providers : Int,
  provider_captures? : Int = 0,
  input_segments? : Int = 0,
  model_components? : Int = 0,
) -> Int64? {
  // A captured Stage can also own the serialized Model continuation. Its
  // Compute tail is then empty, but the module's fixed containers still exist.
  guard tasks > 0 &&
    tasks >= captures &&
    captures >= 0 &&
    installed_providers >= 0 &&
    provider_captures >= 0 &&
    provider_captures <= captures &&
    input_segments >= 0 &&
    model_components >= 0 &&
    model_components <= tasks &&
    input_segments.to_int64() <= 2L * tasks.to_int64() &&
    @local.local_module_container_inventory(
      tasks - captures,
      installed_providers,
    )
    is Some(containers) &&
    @execution.compose_preparation_representation([
      containers,
      // Only the plural constructor owns this extra ordered Array and its
      // original prefix/suffix pair records. Singles keep their old fields.
      closed_values_program_arrays(
        if model_components > 1 {
          1L
        } else {
          0L
        },
        if model_components > 1 {
          model_components.to_int64()
        } else {
          0L
        },
        true,
      ),
      {
        record_headers: if model_components > 1 {
          model_components.to_int64() + 1L
        } else {
          0L
        },
        reference_slots: if model_components > 1 {
          2L * model_components.to_int64() + 1L
        } else {
          0L
        },
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      // The two actual optional module fields and each retained Some carrier.
      {
        record_headers: input_segments.to_int64(),
        reference_slots: (if captures == 0 { 0L } else { 2L }) +
        input_segments.to_int64(),
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      closed_values_program_arrays(6L, 6L * tasks.to_int64(), true),
      closed_values_program_arrays(
        if captures == 0 {
          0L
        } else {
          3L + (if provider_captures == 0 { 0L } else { 1L })
        },
        3L * captures.to_int64() + provider_captures.to_int64(),
        true,
      ),
    ])
    is Some(units) else {
    return None
  }
  @execution.preparation_representation_cost(units)
}

///|
fn[I] begin_request_model_module(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  compilation : @publication_host.ClientTaskCompilation,
  contracts : ClientInstalledSequenceContracts,
  captures : Int,
  installed_providers : Int,
  query_time : @publication_host.ClientQueryTimePreparation?,
  provider_captures? : Int = 0,
  source_free_component? : Bool = false,
) -> Result[
  @publication_host.PreparedClientProgram,
  ClientRequestProgramPlanIssue,
] {
  let retained_graphs = match owner.program_domain_compilation_inputs {
    Some(RequestModelCompilation(_, _, original_contracts, original)) => {
      guard physical_equal(original_contracts, contracts) &&
        compilation.infers.length() == 1 &&
        physical_equal(compilation.infers[0], original) else {
        return Err(Preparation(ForeignOriginal))
      }
      compilation.infers
    }
    Some(RequestModelsCompilation(_, _, original_contracts, originals)) => {
      guard physical_equal(original_contracts, contracts) &&
        originals.length() > 1 &&
        originals.length() == compilation.infers.length() else {
        return Err(Preparation(ForeignOriginal))
      }
      for index, original in originals {
        if !physical_equal(original, compilation.infers[index]) {
          return Err(Preparation(ForeignOriginal))
        }
      }
      originals
    }
    _ => return Err(Preparation(ForeignOriginal))
  }
  guard retained_graphs.length() > 0 else {
    return Err(Preparation(ForeignOriginal))
  }
  let graph = retained_graphs[0]
  guard owner.phase == ModelPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_capacity is Some(capacity) &&
    owner.program_compilation is Some(@publication_host.Tasks(artifact)) &&
    physical_equal(artifact, compilation) &&
    owner.program_source_free is None &&
    owner.program_captured is None &&
    owner.program_model is None &&
    !owner.program_body_attempted &&
    @publication_host.client_compiled_run_matches_tasks(
      compiled, prepared, compilation,
    ) &&
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Ok(_) else {
    return Err(Preparation(ForeignOriginal))
  }
  let identity = @publication_host.prepared_client_identity(prepared)
  guard identity.program_definition_cid ==
    @publication_host.client_request_program_cid(request) &&
    identity.parameter_values_cid ==
    @publication_host.client_request_parameters_cid(request) &&
    installed_mock_model_compilation_matches(prepared, compilation) else {
    return Err(Preparation(ForeignOriginal))
  }
  // A serialized Model cannot construct its module before the original
  // same-Request prefix has retained its compiler and constructor output.
  guard (match (graph.serialization, owner.program_content) {
    (None, NoContent) => true
    (Some(component), SerializationContent(prefix)) =>
      physical_equal(prefix.prepared, prepared) &&
      physical_equal(prefix.request, request) &&
      physical_equal(prefix._observed_compiled, compiled) &&
      physical_equal(prefix._observed_definition, definition) &&
      @publication_host.client_task_compilation_serialization(compilation)
      is Some(original) &&
      physical_equal(original, component)
    _ => false
  }) else {
    return Err(Preparation(ForeignOriginal))
  }
  if query_time is Some(original) {
    match
      @publication_host.client_query_time_preparation_context_for_run(
        original, prepared, compiled, definition, request,
      ) {
      Err(issue) => return Err(QueryTime(issue))
      Ok(_) => ()
    }
  }
  let dag = @publication_host.prepared_client_graph(prepared)
  let mut input_segments = 0L
  if source_free_component {
    for original in retained_graphs {
      if original.serialization is None {
        input_segments += if @publication_host.client_infer_occurrence_terminal(
            original.occurrence,
          ) {
          1L
        } else {
          2L
        }
      }
    }
  } else if captures == 1 && graph.serialization is None {
    input_segments = if @publication_host.client_infer_occurrence_terminal(
        graph.occurrence,
      ) {
      1L
    } else {
      2L
    }
  }
  if input_segments > 2147483647L {
    return Err(Preparation(Policy))
  }
  guard @strategy.graph_captured_prefix(dag) == captures &&
    (captures == 0 || captures == 1 || captures == 2) &&
    owner.program_plan_quote is Some((quoted_r, quoted_e)) &&
    request_model_module_container_bytes(
      @strategy.graph_task_count(dag),
      captures,
      installed_providers,
      provider_captures~,
      input_segments=input_segments.to_int(),
      model_components=if source_free_component {
        retained_graphs.length()
      } else {
        0
      },
    )
    is Some(bytes) else {
    return Err(Installed(Unsupported))
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Preparation(Capacity(issue)))
    Ok(value) => value
  }
  // Every earlier Graph/compiler/material grow is retained, including the
  // original variable Plan debit. Never apply that older absolute quote again.
  guard r >= quoted_r && e >= quoted_e else { return Err(Preparation(Policy)) }
  owner.phase = Selecting
  match
    reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(prepared)
  }
}

///|
// The actual existing input/suffix lowering, selected by the SAME checked
// occurrence. Each constructor grows the same Request before invoking it.
fn[I] construct_request_source_free_model_input(
  owner : ClientRequestPreparation[I],
  input : I,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  graph : @publication_host.ClientInferPlanGraph,
  contracts : ClientInstalledSequenceContracts,
  query_time : @publication_host.ClientQueryTimePreparation?,
) -> Result[
  (@execution.GeneratedSequence, @execution.GeneratedSequence?),
  ClientRequestProgramPlanIssue,
] {
  let mut input_prefix = None
  let mut input_suffix = None
  if graph.serialization is Some(_) {
    return Err(Installed(Unsupported))
  }
  let input_calls = if @publication_host.client_infer_occurrence_terminal(
      graph.occurrence,
    ) {
    1L
  } else {
    2L
  }
  guard owner.program_data is Some(data) &&
    program_check_data_extent_cost(data) is Some(variable) &&
    @execution.checked_preparation_add_product(0L, variable, input_calls)
    is Some(bytes) else {
    return Err(Preparation(Policy))
  }
  match
    reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // The actual Model input and suffix precede their one deferred
  // provider. They replace the legacy early lowering, not its originals.
  let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
    graph.occurrence,
  )
  let prefix = match
    prepare_client_local_sequences_owned(
      Pure(prepared),
      contracts,
      contracts.original.values_body,
      contracts.original.fragment_body,
      contracts.original.ordered_body,
      selected_task=Some(task),
      infer_prefix=Some((task, step - 1)),
      query_time=query_time.map(original => (original, request)),
    ) {
    Err(issue) => return Err(Installed(issue))
    Ok(value) => value
  }
  guard prefix.get(0) is Some(original_prefix) else {
    return Err(Installed(Unsupported))
  }
  input_prefix = Some(original_prefix)
  if input_calls == 2L {
    let suffix = match
      prepare_client_local_sequences_owned(
        Pure(prepared),
        contracts,
        contracts.original.values_body,
        contracts.original.fragment_body,
        contracts.original.ordered_body,
        selected_task=Some(task),
        infer_suffix=Some((task, step)),
        query_time=query_time.map(original => (original, request)),
      ) {
      Err(issue) => return Err(Installed(issue))
      Ok(value) => value
    }
    guard suffix.get(0) is Some(original_suffix) else {
      return Err(Installed(Unsupported))
    }
    input_suffix = Some(original_suffix)
  }
  guard input_prefix is Some(prefix) else { return Err(Installed(Unsupported)) }
  Ok((prefix, input_suffix))
}

///|
/// Construct the original configured module on this SAME Request, after its
/// variable Plan debit and actual module containers are backed. The returned
/// module is retained before any later Plan/Scope/current callback can fail.
pub fn[I] prepare_request_model_source_free_module(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  compilation : @publication_host.ClientTaskCompilation,
  contracts : ClientInstalledSequenceContracts,
  retained_output : Bool,
  installed_providers : Int,
  provider_factory : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
  component_factory? : ((
    @execution.ExecutionCapacity,
    @execution.GeneratedSequence,
    @execution.GeneratedSequence?,
  ) -> @local.ManagedProvider)? = None,
  components_factory? : ((
    Int,
    @execution.ExecutionCapacity,
    @execution.GeneratedSequence,
    @execution.GeneratedSequence?,
  ) -> @local.ManagedProvider)? = None,
) -> Result[
  ClientInstalledManagedSourceFreePreparation,
  ClientRequestProgramPlanIssue,
] {
  if (
      component_factory is Some(_) &&
      (compilation.infers.length() != 1 || components_factory is Some(_))
    ) ||
    (components_factory is Some(_) && compilation.infers.length() < 2) {
    return Err(Preparation(ForeignOriginal))
  }
  // The plural callback contributes one actual provider per compiler member.
  // Add that inventory HERE, once, beside its checked module construction;
  // the higher bridge supplies only its existing fixed family provider count.
  let installed_providers = if components_factory is Some(_) {
    guard @execution.checked_preparation_add_product(
        installed_providers.to_int64(),
        compilation.infers.length().to_int64(),
        1L,
      )
      is Some(total) &&
      total <= 2147483647L else {
      return Err(Installed(InsufficientCapacity))
    }
    total.to_int()
  } else {
    installed_providers
  }
  preparation_module_call(
    () => {
      let prepared = match
        begin_request_model_module(
          owner,
          input,
          request,
          compiled,
          definition,
          compilation,
          contracts,
          0,
          installed_providers,
          query_time,
          source_free_component=component_factory is Some(_) ||
            components_factory is Some(_),
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      let mut input_prefix = None
      let mut input_suffix = None
      let mut component_inputs = None
      if component_factory is Some(_) {
        let (prefix, suffix) = match
          construct_request_source_free_model_input(
            owner,
            input,
            prepared,
            request,
            compilation.infers[0],
            contracts,
            query_time,
          ) {
          Err(issue) => return Err(issue)
          Ok(value) => value
        }
        input_prefix = Some(prefix)
        input_suffix = suffix
      } else if components_factory is Some(_) {
        let inputs = []
        for graph in compilation.infers {
          let original = match
            construct_request_source_free_model_input(
              owner, input, prepared, request, graph, contracts, query_time,
            ) {
            Err(issue) => return Err(issue)
            Ok(value) => value
          }
          inputs.push(original)
        }
        component_inputs = Some(inputs)
      }
      let original = match
        prepare_installed_mock_model_source_free_with_contracts(
          prepared,
          compilation,
          contracts,
          contracts.original.values_body,
          contracts.original.fragment_body,
          contracts.original.ordered_body,
          retained_output~,
          provider_factory=capacity => {
            let providers = provider_factory(capacity)
            if component_factory is Some(construct) &&
              input_prefix is Some(prefix) {
              providers.push(construct(capacity, prefix, input_suffix))
            } else if components_factory is Some(construct) &&
              component_inputs is Some(inputs) {
              for index, original in inputs {
                providers.push(
                  construct(index, capacity, original.0, original.1),
                )
              }
            }
            providers
          },
          query_time=query_time.map(value => (value, request)),
        ) {
        Err(issue) => return Err(Installed(issue))
        Ok(value) => value
      }
      // The existing parent owns this output even if an original callback has
      // invalidated the continuation. It has no physical child to acknowledge.
      owner.program_source_free = Some(original)
      guard owner.phase == Selecting &&
        owner.input is Some(same_input) &&
        physical_equal(same_input, input) &&
        owner.compiled_program is Some(same_prepared) &&
        physical_equal(same_prepared, prepared) else {
        return Err(Preparation(ForeignOriginal))
      }
      owner.program_domain_quote = None
      owner.phase = ModelPlanReserved
      Ok(original)
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
/// The actual Query originals, acquisitions and configured module are
/// constructed once inside the already held Request. No JS requirement or
/// provider is reconstructed later. Contract parses coexist with all captures
/// and their module, and their input-derived debit precedes the first parse.
pub fn[I] prepare_request_model_capture_module(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  compilation : @publication_host.ClientTaskCompilation,
  declarations : Array[@row_source_host.RowDeclaration],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  contracts : ClientInstalledSequenceContracts,
  retained_output : Bool,
  installed_providers : Int,
  provider_factory : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
  providers? : Array[@execution.ExecutionCapacity?]? = None,
  component_factory? : ((
    @execution.ExecutionCapacity,
    @execution.GeneratedSequence,
    @execution.GeneratedSequence?,
  ) -> @local.ManagedProvider)? = None,
) -> Result[ClientInstalledManagedCapturePlan, ClientRequestProgramPlanIssue] {
  let count = declarations.length()
  if (count != 1 && count != 2) ||
    transport_bytes.length() != count ||
    transport_execution_bytes.length() != count ||
    (
      providers is Some(originals) &&
      (originals.length() != count || originals.any(value => value is None))
    ) {
    return Err(Installed(Unsupported))
  }
  if component_factory is Some(_) && compilation.infers.length() != 1 {
    return Err(Preparation(ForeignOriginal))
  }
  preparation_module_call(
    () => {
      let prepared = match
        begin_request_model_module(
          owner,
          input,
          request,
          compiled,
          definition,
          compilation,
          contracts,
          count,
          installed_providers,
          query_time,
          provider_captures=if providers is Some(_) { count } else { 0 },
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
      guard request_model_material_body_bytes(2, index => {
          if index % 2 == 0 {
            query_contract_body
          } else {
            evidence_contract_body
          }
        })
        is Some(protocol_bytes) &&
        request_local_query_construction_bytes() is Some(query_bytes) &&
        @execution.checked_preparation_add_product(
          protocol_bytes,
          query_bytes,
          count.to_int64(),
        )
        is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      let model = compilation.infers[0]
      let input_calls = if count == 1 && model.serialization is None {
        if @publication_host.client_infer_occurrence_terminal(model.occurrence) {
          1L
        } else {
          2L
        }
      } else {
        0L
      }
      let bytes = if input_calls == 0L {
        bytes
      } else {
        guard owner.program_data is Some(data) &&
          program_check_data_extent_cost(data) is Some(variable) &&
          @execution.checked_preparation_add_product(
            bytes, variable, input_calls,
          )
          is Some(complete) else {
          return Err(Preparation(Policy))
        }
        complete
      }
      match
        reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      // Lower the actual Model input once before its provider factory. This
      // pure output coexists with module/configuration and remains on that
      // same original. Pass the bound invocation, never sample another clock.
      let mut input_prefix = None
      let mut input_suffix = None
      if input_calls > 0L {
        let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
          model.occurrence,
        )
        let prefix = match
          prepare_client_local_sequences_owned(
            Pure(prepared),
            contracts,
            contracts.original.values_body,
            contracts.original.fragment_body,
            contracts.original.ordered_body,
            selected_task=Some(task),
            infer_prefix=Some((task, step - 1)),
            query_time=query_time.map(original => (original, request)),
          ) {
          Err(issue) => return Err(Installed(issue))
          Ok(value) => value
        }
        guard prefix.get(0) is Some(original_prefix) else {
          return Err(Installed(Unsupported))
        }
        input_prefix = Some(original_prefix)
        if input_calls == 2L {
          let suffix = match
            prepare_client_local_sequences_owned(
              Pure(prepared),
              contracts,
              contracts.original.values_body,
              contracts.original.fragment_body,
              contracts.original.ordered_body,
              selected_task=Some(task),
              infer_suffix=Some((task, step)),
              query_time=query_time.map(original => (original, request)),
            ) {
            Err(issue) => return Err(Installed(issue))
            Ok(value) => value
          }
          guard suffix.get(0) is Some(original_suffix) else {
            return Err(Installed(Unsupported))
          }
          input_suffix = Some(original_suffix)
        }
      }
      if component_factory is Some(_) && input_prefix is None {
        return Err(Installed(Unsupported))
      }
      // The actual Query/material constructors and their protocol overlap
      // are backed before the first parse/Query call on this SAME Request.
      // Every acquisition borrows these SAME admitted protocol originals. Do
      // not parse/check the identical installation bodies for a second Source.
      let protocols = match
        @row_source_host.admit_row_acquisition_contracts(
          query_contract_body, evidence_contract_body,
        ) {
        Err(issue) => return Err(ModelSource(issue))
        Ok(value) => value
      }
      let direct = match installed_direct_occurrences_owned(Pure(prepared)) {
        Ok(value) => value
        Err(issue) => return Err(Installed(issue))
      }
      if @publication_host.client_direct_acquisition_occurrence_count(direct) !=
        count {
        return Err(Installed(ForeignOriginal))
      }
      let captures = []
      for index in 0..<count {
        guard @publication_host.client_direct_acquisition_occurrence_at(
            direct, index,
          )
          is Some((stage, source_input, task)) &&
          task == index else {
          return Err(Installed(ForeignOriginal))
        }
        let requirement = match
          (match query_time {
            Some(original) =>
              prepare_local_query_requirement_at_query_time(
                prepared,
                stage,
                source_input,
                original,
                request,
                contracts,
                contracts.original.values_body,
                contracts.original.fragment_body,
                contracts.original.ordered_body,
              )
            None =>
              prepare_local_query_requirement(
                prepared,
                stage,
                source_input,
                contracts,
                contracts.original.values_body,
                contracts.original.fragment_body,
                contracts.original.ordered_body,
              )
          }) {
          Err(issue) => return Err(ModelQuery(issue))
          Ok(value) => value
        }
        let source = match
          @row_source_host.prepare_row_source(requirement, declarations[index]) {
          Err(issue) => return Err(ModelSource(@row_source_host.Source(issue)))
          Ok(value) => value
        }
        let acquisition = match
          @row_source_host.prepare_declared_row_acquisition_with_contracts(
            source,
            declarations[index].connector_registration,
            protocols,
          ) {
          Err(issue) => return Err(ModelSource(issue))
          Ok(value) => value
        }
        let capacity = match
          (match providers {
            Some(originals) =>
              installed_provider_row_capture_capacity(
                acquisition,
                originals[index],
              )
            None => installed_row_capture_capacity(acquisition)
          }) {
          None => return Err(Installed(Unsupported))
          Some(value) => value
        }
        captures.push(capacity)
      }
      let original = match
        prepare_installed_mock_model_capture_plan(
          prepared,
          request,
          compilation,
          captures,
          transport_bytes,
          transport_execution_bytes,
          contracts,
          contracts.original.values_body,
          contracts.original.fragment_body,
          contracts.original.ordered_body,
          retained_output~,
          provider_factory=capacity => {
            let providers = provider_factory(capacity)
            if component_factory is Some(construct) &&
              input_prefix is Some(prefix) {
              providers.push(construct(capacity, prefix, input_suffix))
            }
            providers
          },
          query_time~,
          direct_occurrences=Some(direct),
        ) {
        Err(issue) => return Err(Installed(issue))
        Ok(value) => value
      }
      original.model_input_prefix = input_prefix
      original.model_input_suffix = input_suffix
      owner.program_captured = Some(original)
      guard owner.phase == Selecting &&
        owner.input is Some(same_input) &&
        physical_equal(same_input, input) &&
        owner.compiled_program is Some(same_prepared) &&
        physical_equal(same_prepared, prepared) else {
        return Err(Preparation(ForeignOriginal))
      }
      owner.program_domain_quote = None
      owner.phase = ModelPlanReserved
      Ok(original)
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}

///|
/// Pure reads of this exact Request module's retained input. They issue no
/// Scope, read, execution or reconstruction from an equal Graph/sequence.
pub fn prepared_request_model_input_prefix(
  original : ClientInstalledManagedCapturePlan,
) -> Result[@execution.GeneratedSequence, ClientInstalledManagedRunIssue] {
  guard original.compilation is Some(@publication_host.Tasks(compilation)) &&
    installed_mock_model_compilation_matches(original.prepared, compilation) &&
    compilation.infers[0].serialization is None &&
    original.model_input_prefix is Some(prefix) else {
    return Err(ForeignOriginal)
  }
  Ok(prefix)
}

///|
pub fn prepared_request_model_input_suffix(
  original : ClientInstalledManagedCapturePlan,
) -> Result[@execution.GeneratedSequence?, ClientInstalledManagedRunIssue] {
  match prepared_request_model_input_prefix(original) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  Ok(original.model_input_suffix)
}
