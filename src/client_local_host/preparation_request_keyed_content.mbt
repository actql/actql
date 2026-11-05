///|
// One actual installed Query material/requirement pair, shared by the actual
// Model capture and keyed Content constructors. Reuse the SAME issuer
// controls and existing writer/collection inventory; their finite envelope is
// charged once for this operation, not multiplied by Program tasks. Variable
// sequence/AST/schema DATA already has request_program_plan_quote backing.
// Provider constructor controls remain trusted fixed Host overhead. No rows,
// Provider read, execution capacity or successful admission is inferred here.
fn request_local_query_construction_bytes() -> Int64? {
  let limits = installed_local_query_material_limits()
  guard request_local_query_writer_construction_units(
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(writers) &&
    @shape.collection_construction_extent({
      records: limits.max_fields.to_int64(),
      record_references: 2L * limits.max_fields.to_int64(),
      record_words: 0L,
      reference_arrays: 3L,
      reference_items: 2L * limits.max_fields.to_int64() +
      limits.max_parameters.to_int64(),
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 1L,
      map_entries: limits.max_parameters.to_int64(),
    })
    is Some(collections) &&
    @execution.compose_preparation_representation([
      writers,
      {
        record_headers: collections.record_headers,
        reference_slots: collections.reference_slots,
        scalar_words: collections.scalar_words,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
      // Selected Plan/prefix/optional original and limit carriers. Original
      // Prepared, declarations, contracts and execution inputs are borrowed.
      {
        record_headers: 6L,
        reference_slots: 21L,
        scalar_words: 25L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      },
    ])
    is Some(units) else {
    return None
  }
  @execution.preparation_representation_cost(units)
}

///|
// The SAME canonical writer inventories as the original constructor quote.
// Output domains remain unchanged when only live cursor geometry is reduced.
fn request_local_query_writer_construction_units(
  nodes : Int,
  depth : Int,
) -> @execution.PreparationRepresentationUnits? {
  let limits = installed_local_query_material_limits()
  guard @encode.text_writer_construction_inventory(
      limits.max_bytes,
      nodes,
      depth,
    )
    is Some(text) &&
    @encode.hash_writer_construction_inventory(nodes, depth) is Some(hash) else {
    return None
  }
  Some({
    record_headers: 2L * text.record_headers + hash.record_headers,
    reference_slots: 2L * text.reference_slots + hash.reference_slots,
    scalar_words: 2L * text.scalar_words + hash.scalar_words,
    owned_utf16_units: 2L * text.owned_utf16_units,
    owned_wire_bytes: 2L * limits.max_bytes.to_int64(),
  })
}

///|
// Both QueryMaterial and QueryRequirement return immutable EncodedDocuments,
// never their writers/frames/key Maps. All text/wire output bounds, collection
// and original issuer controls remain charged. Six separate returned CID
// Strings (material's three plus requirement/schema's three) are kept too.
// Only completed writer traversal scratch is returned, never output backing.
fn request_local_query_finished_writer_bytes() -> Int64? {
  let limits = installed_local_query_material_limits()
  guard request_local_query_writer_construction_units(
      limits.max_nodes,
      limits.max_depth,
    )
    is Some(full) &&
    request_local_query_writer_construction_units(1, 0) is Some(closed) &&
    @execution.preparation_representation_cost(full) is Some(full_bytes) &&
    @execution.compose_preparation_representation([
      closed,
      {
        record_headers: 6L,
        reference_slots: 0L,
        scalar_words: 0L,
        owned_utf16_units: 6L * (7L + 64L),
        owned_wire_bytes: 0L,
      },
    ])
    is Some(retained) &&
    @execution.preparation_representation_cost(retained) is Some(retained_bytes) &&
    full_bytes >= retained_bytes else {
    return None
  }
  Some(full_bytes - retained_bytes)
}

///|
/// Construct the original direct Query/acquisition and keyed Content Plan only
/// after this SAME Request backs their constructor overlap. The generated
/// prefix/provider/capacity are retained once on that existing Plan; compiler,
/// physical Source and Store remain their actual original owners. No scalar
/// Ledger, capacity-only preparation or reconstructed prefix leaves this entry.
pub fn[I] prepare_request_keyed_content_plan(
  owner : ClientRequestPreparation[I],
  input : I,
  request : @publication_host.ClientRequestIdentity,
  keyed : @publication_host.ClientKeyedAcquisition,
  direct_declaration : @row_source_host.RowDeclaration,
  content_declaration : @row_source_host.RowDeclaration,
  row_limits : @row_source_host.RowKeyedLimits,
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  max_bytes : Int,
  max_work : Int,
  contracts : ClientInstalledSequenceContracts,
  task : Int,
  step : Int,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  workspace : @execution.ExecutionCapacity?,
) -> Result[
  ClientInstalledManagedKeyedPreparation,
  ClientRequestProgramPlanIssue,
] {
  guard owner.phase == ContentPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.compiled_program is Some(prepared) &&
    owner.program_capacity is Some(_) &&
    owner.program_compilation is None &&
    owner.program_content is NoContent &&
    owner.program_content_request is None &&
    !owner.program_body_attempted &&
    owner.program_domain_compilation_inputs
    is Some(RequestSerializationGraph(_, _, original_contracts, component)) &&
    physical_equal(original_contracts, contracts) &&
    physical_equal(component.owner, prepared) &&
    component.task == task &&
    component.step == step &&
    @publication_host.client_keyed_acquisition_matches_program(keyed, prepared) &&
    @publication_host.client_keyed_direct_acquisition_coordinates(keyed)
    is Some((stage, source_index, _)) &&
    transport_bytes.length() == 2 &&
    transport_execution_bytes.length() == 2 else {
    return Err(Preparation(ForeignOriginal))
  }
  let identity = @publication_host.prepared_client_identity(prepared)
  guard identity.program_definition_cid ==
    @publication_host.client_request_program_cid(request) &&
    identity.parameter_values_cid ==
    @publication_host.client_request_parameters_cid(request) else {
    return Err(Preparation(ForeignOriginal))
  }
  owner.phase = Selecting
  preparation_module_call(
    () => {
      guard request_local_query_construction_bytes() is Some(query) &&
        request_model_material_body_bytes(2, index => {
          if index == 0 {
            query_contract_body
          } else {
            evidence_contract_body
          }
        })
        is Some(protocols) &&
        @execution.checked_preparation_add_product(query, protocols, 1L)
        is Some(bytes) else {
        return Err(Preparation(Policy))
      }
      match
        reserve_request_domain_graph_construction(owner, input, prepared, bytes) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      let protocols = match
        @row_source_host.admit_row_acquisition_contracts(
          query_contract_body, evidence_contract_body,
        ) {
        Err(issue) => return Err(ContentSource(issue))
        Ok(value) => value
      }
      let requirement = match
        prepare_local_query_requirement(
          prepared,
          stage,
          source_index,
          contracts,
          contracts.original.values_body,
          contracts.original.fragment_body,
          contracts.original.ordered_body,
        ) {
        Err(issue) => return Err(ContentQuery(issue))
        Ok(value) => value
      }
      let source = match
        @row_source_host.prepare_row_source(requirement, direct_declaration) {
        Err(issue) => return Err(ContentSource(@row_source_host.Source(issue)))
        Ok(value) => value
      }
      let acquisition = match
        @row_source_host.prepare_declared_row_acquisition_with_contracts(
          source,
          direct_declaration.connector_registration,
          protocols,
        ) {
        Err(issue) => return Err(ContentSource(issue))
        Ok(value) => value
      }
      let direct = match installed_row_capture_capacity(acquisition) {
        None => return Err(Installed(Unsupported))
        Some(value) => value
      }
      guard serialization_prefix_provider(
          prepared,
          task,
          step,
          contracts,
          contracts.original.values_body,
          contracts.original.fragment_body,
          contracts.original.ordered_body,
          execution,
          measurement,
          acquired=true,
        )
        is Some((sequence, provider, prefix_capacity)) else {
        return Err(Installed(Unsupported))
      }
      let capacity = match workspace {
        None => prefix_capacity
        Some(workspace) =>
          match @execution.add_execution_capacity(prefix_capacity, workspace) {
            None => return Err(Installed(InsufficientCapacity))
            Some(value) => value
          }
      }
      let prefix = { sequence, provider, capacity, execution, measurement, }
      let selected = match
        prepare_installed_managed_keyed_content_owned(
          prepared,
          direct,
          keyed,
          content_declaration,
          row_limits,
          transport_bytes,
          transport_execution_bytes,
          max_bytes,
          max_work,
          contracts,
          contracts.original.values_body,
          contracts.original.fragment_body,
          contracts.original.ordered_body,
          task,
          step,
          @execution.execution_capacity_retained_bytes(capacity),
          @execution.execution_capacity_execution_bytes(capacity),
          Some(prefix),
          Some(requirement),
        ) {
        Err(issue) => return Err(Installed(issue))
        Ok(value) => value
      }
      // Closed synchronous constructors above invoke no current/Provider IO.
      // Retain this output BEFORE the compiler's next fallible callback.
      owner.program_content = KeyedContent(selected, None)
      owner.program_content_request = Some(request)
      guard owner.phase == Selecting &&
        owner.input is Some(same_input) &&
        physical_equal(same_input, input) &&
        owner.compiled_program is Some(same_prepared) &&
        physical_equal(same_prepared, prepared) else {
        return Err(Preparation(ForeignOriginal))
      }
      owner.program_domain_quote = None
      owner.phase = ContentPlanReserved
      Ok(selected)
    },
    () => if owner.phase == Selecting { owner.phase = ProgramBodyFailed },
  )
}
