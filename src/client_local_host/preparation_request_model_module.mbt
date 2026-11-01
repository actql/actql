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
) -> Int64? {
  guard tasks > captures &&
    captures >= 0 &&
    installed_providers >= 0 &&
    @local.local_module_container_inventory(
      tasks - captures,
      installed_providers,
    )
    is Some(containers) &&
    @execution.compose_preparation_representation([
      containers,
      closed_values_program_arrays(6L, 6L * tasks.to_int64(), true),
      closed_values_program_arrays(
        if captures == 0 {
          0L
        } else {
          3L
        },
        3L * captures.to_int64(),
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
) -> Result[
  @publication_host.PreparedClientProgram,
  ClientRequestProgramPlanIssue,
] {
  guard owner.phase == ModelPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_capacity is Some(capacity) &&
    owner.program_compilation is Some(@publication_host.Tasks(artifact)) &&
    physical_equal(artifact, compilation) &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelCompilation(_, _, original_contracts, graph)) &&
    physical_equal(original_contracts, contracts) &&
    compilation.infers.length() == 1 &&
    physical_equal(compilation.infers[0], graph) &&
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
  guard @strategy.graph_captured_prefix(dag) == captures &&
    (
      captures == 0 ||
      captures == 2 ||
      (captures == 1 && graph.serialization is Some(_))
    ) &&
    owner.program_plan_quote is Some((quoted_r, quoted_e)) &&
    request_model_module_container_bytes(
      @strategy.graph_task_count(dag),
      captures,
      installed_providers,
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
) -> Result[
  ClientInstalledManagedSourceFreePreparation,
  ClientRequestProgramPlanIssue,
] {
  preparation_module_call(
    () => {
      let prepared = match
        begin_request_model_module(
          owner, input, request, compiled, definition, compilation, contracts, 0,
          installed_providers, query_time,
        ) {
        Err(issue) => return Err(issue)
        Ok(value) => value
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
          provider_factory~,
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
) -> Result[ClientInstalledManagedCapturePlan, ClientRequestProgramPlanIssue] {
  let count = declarations.length()
  if (count != 1 && count != 2) ||
    transport_bytes.length() != count ||
    transport_execution_bytes.length() != count {
    return Err(Installed(Unsupported))
  }
  preparation_module_call(
    () => {
      let prepared = match
        begin_request_model_module(
          owner, input, request, compiled, definition, compilation, contracts, count,
          installed_providers, query_time,
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
      match
        reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      // The actual Query/material constructors and their protocol overlap
      // are backed before the first parse/Query call on this SAME Request.
      // Both acquisitions borrow these SAME admitted protocol originals. Do
      // not parse/check the identical installation bodies for a second Source.
      let protocols = match
        @row_source_host.admit_row_acquisition_contracts(
          query_contract_body, evidence_contract_body,
        ) {
        Err(issue) => return Err(ModelSource(issue))
        Ok(value) => value
      }
      let captures = []
      for stage in 0..<count {
        let requirement = match
          (match query_time {
            Some(original) =>
              prepare_local_query_requirement_at_query_time(
                prepared,
                stage,
                0,
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
                0,
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
          @row_source_host.prepare_row_source(requirement, declarations[stage]) {
          Err(issue) => return Err(ModelSource(@row_source_host.Source(issue)))
          Ok(value) => value
        }
        let acquisition = match
          @row_source_host.prepare_declared_row_acquisition_with_contracts(
            source,
            declarations[stage].connector_registration,
            protocols,
          ) {
          Err(issue) => return Err(ModelSource(issue))
          Ok(value) => value
        }
        let capacity = match installed_row_capture_capacity(acquisition) {
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
          provider_factory~,
          query_time~,
        ) {
        Err(issue) => return Err(Installed(issue))
        Ok(value) => value
      }
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
