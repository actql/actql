///|
/// Installation DATA only. The Plan binds these existing originals to each
/// checked direct occurrence; this description issues no read or resource.
enum ClientInstalledEffectSourceInput {
  InstalledEffectRowSource(
    @row_source_host.RowDeclaration,
    @execution.ExecutionCapacity?
  )
  InstalledEffectDuckDBSource(String, String, String, String, String, String)
}

///|
pub fn prepare_installed_effect_row_source_input(
  declaration : @row_source_host.RowDeclaration,
  provider : @execution.ExecutionCapacity?,
) -> Result[ClientInstalledEffectSourceInput, ClientInstalledManagedRunIssue] {
  Ok(InstalledEffectRowSource(declaration, provider))
}

///|
pub fn prepare_installed_effect_duckdb_source_input(
  source_ref : String,
  database_schema : String,
  table : String,
  query_contract : String,
  evidence_contract : String,
  two_receipt_contract : String,
) -> Result[ClientInstalledEffectSourceInput, ClientInstalledManagedRunIssue] {
  if source_ref.is_empty() || database_schema.is_empty() || table.is_empty() {
    return Err(Unsupported)
  }
  Ok(
    InstalledEffectDuckDBSource(
      source_ref, database_schema, table, query_contract, evidence_contract, two_receipt_contract,
    ),
  )
}

///|
pub fn prepare_installed_effect_managed_source_plan(
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  inputs : Array[ClientInstalledEffectSourceInput],
  query_contract_body : String,
  evidence_contract_body : String,
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
  selected_operations : Array[ClientInstalledEffectOperationDemand],
  provider_factory~ : (@execution.ExecutionCapacity) -> Array[
    @local.ManagedProvider,
  ],
  query_time? : @publication_host.ClientQueryTimePreparation? = None,
  model? : ClientInstalledEffectModelDemand? = None,
  content? : ClientInstalledEffectContentPreparation? = None,
  runtime_admission? : Bool = false,
) -> Result[ClientInstalledEffectManagedPlan, ClientInstalledManagedRunIssue] {
  prepare_installed_effect_managed_plan_owned(
    prepared,
    request,
    [],
    query_contract_body,
    evidence_contract_body,
    transport_bytes,
    transport_execution_bytes,
    installed_contracts,
    values_body,
    fragment_body,
    ordered_body,
    selected_operations,
    provider_factory~,
    query_time~,
    model~,
    content~,
    source_inputs=Some(inputs),
    runtime_admission~,
  )
}

///|
// Prepare each checked Query once. Row arrays remain compact and preserve
// their old order; captures retain the complete checked occurrence order.
fn prepare_installed_effect_source_inputs(
  prepared : @publication_host.PreparedClientEffectComputation,
  inputs : Array[ClientInstalledEffectSourceInput],
  query_contract : String,
  evidence_contract : String,
  contracts : ClientInstalledSequenceContracts,
  values : String,
  fragment : String?,
  ordered : String?,
  occurrences : @publication_host.ClientDirectAcquisitionOccurrences?,
  transport_execution : Array[Int64],
  sequences : Array[@execution.GeneratedSequence],
  invocation : (
    @publication_host.ClientQueryTimePreparation,
    @publication_host.ClientRequestIdentity,
  )?,
) -> Result[
  (
    Array[@row_source_host.RowDeclaration],
    Array[@row_source_host.RowAcquisition],
    Array[ClientInstalledCaptureCapacity],
    Array[
      (@row_source_host.RowDeclaration, ClientInstalledWholeSourceCapacity)?,
    ],
  ),
  ClientInstalledManagedRunIssue,
] {
  let count = occurrences
    .map(value => {
      @publication_host.client_direct_acquisition_occurrence_count(value)
    })
    .unwrap_or(0)
  if inputs.length() != count || transport_execution.length() != count {
    return Err(ForeignOriginal)
  }
  if count == 0 {
    return Ok(([], [], [], []))
  }
  guard occurrences is Some(selected) &&
    installed_direct_occurrences_match_owner(selected, Effect(prepared)) &&
    @publication_host.client_direct_acquisition_occurrence_count(selected) ==
    count else {
    return Err(ForeignOriginal)
  }
  let declarations = []
  let acquisitions = []
  let captures = []
  let whole_sources = []
  for index, input in inputs {
    guard @publication_host.client_direct_acquisition_occurrence_at(
        selected, index,
      )
      is Some((stage, ordinal, _)) else {
      return Err(ForeignOriginal)
    }
    let route = match
      select_installed_source_input_graph(
        installed_managed_owner_graph(Effect(prepared)),
        stage,
        ordinal,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if route is @sourceviews.WholeInputRoute(original) {
      guard input is InstalledEffectRowSource(declaration, provider) else {
        return Err(Unsupported)
      }
      let capacity = match
        prepare_installed_effect_whole_source_capacity(
          prepared,
          stage,
          ordinal,
          original,
          declaration,
          contracts,
          provider,
          transport_execution[index],
          sequences,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      whole_sources.push(Some((declaration, capacity)))
      continue
    }
    whole_sources.push(None)
    let requirement = match
      prepare_local_query_requirement_owned(
        Effect(prepared),
        stage,
        ordinal,
        contracts,
        values,
        fragment,
        ordered,
        query_time=invocation,
      ) {
      Ok(value) => value
      Err(_) => return Err(Unsupported)
    }
    match input {
      InstalledEffectRowSource(declaration, provider) => {
        let acquisition = match
          @row_source_host.prepare_row_acquisition(
            declaration, requirement, query_contract, evidence_contract,
          ) {
          Ok(value) => value
          Err(_) => return Err(Unsupported)
        }
        let selected = match provider {
          None => installed_row_capture_capacity(acquisition)
          Some(_) =>
            installed_provider_row_capture_capacity(acquisition, provider)
        }
        guard selected is Some(capacity) else { return Err(Unsupported) }
        declarations.push(declaration)
        acquisitions.push(acquisition)
        captures.push(capacity)
      }
      InstalledEffectDuckDBSource(
        source_ref,
        schema,
        table,
        query,
        evidence,
        receipts
      ) => {
        if @planning.query_requirement_source(requirement).0 != source_ref {
          return Err(ForeignOriginal)
        }
        let pending = match
          prepare_client_duckdb_capture_capacity(
            requirement, schema, table, query, evidence, receipts,
          ) {
          Ok(value) => value
          Err(_) => return Err(Unsupported)
        }
        captures.push(installed_pending_duckdb_capture_capacity(pending))
      }
    }
  }
  Ok((declarations, acquisitions, captures, whole_sources))
}

///|
fn installed_effect_source_row_index(
  plan : ClientInstalledEffectManagedPlan,
  occurrence : Int,
) -> Int? {
  guard installed_effect_source_capture_index(plan, occurrence)
    is Some(capture_index) &&
    plan.captures.get(capture_index) is Some(capacity) &&
    capacity.original_input else {
    return None
  }
  let mut row = 0
  for index in 0..<capture_index {
    if plan.captures[index].original_input {
      row += 1
    }
  }
  Some(row)
}

///|
/// Borrow the same opaque native capture. Cross current once, then fence the
/// retained originals without calling a callback or manufacturing a Row read.
pub fn installed_effect_managed_duckdb_capture(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  occurrence : Int,
) -> Result[
  (@planning.QueryRequirement, ClientInstalledCaptureCapacity),
  ClientInstalledManagedRunIssue,
] {
  guard owner.preparation is Some(PlannedEffectManaged(_, plan)) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) &&
    physical_equal(owner.request, request) &&
    installed_effect_source_capture_index(plan, occurrence)
    is Some(capture_index) &&
    plan.captures.get(capture_index) is Some(capacity) &&
    !capacity.original_input &&
    capacity.acquisition is None &&
    capacity.provider is None else {
    return Err(ForeignOriginal)
  }
  match require_installed_managed_run(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.preparation is Some(PlannedEffectManaged(_, original)) &&
    physical_equal(original, plan) &&
    physical_equal(owner.request, request) else {
    return Err(ForeignOriginal)
  }
  Ok((capacity.requirement, capacity))
}

///|
fn prepare_installed_effect_whole_source_capacity(
  prepared : @publication_host.PreparedClientEffectComputation,
  stage : Int,
  ordinal : Int,
  original : @sourceviews.SourceAcquisition,
  declaration : @row_source_host.RowDeclaration,
  contracts : ClientInstalledSequenceContracts,
  provider : @execution.ExecutionCapacity?,
  transport_execution : Int64,
  sequences : Array[@execution.GeneratedSequence],
) -> Result[ClientInstalledWholeSourceCapacity, ClientInstalledManagedRunIssue] {
  if transport_execution <= 0L {
    return Err(Unsupported)
  }
  let page_bytes = Int64::min(transport_execution, 1000000L).to_int()
  let graph = installed_managed_owner_graph(Effect(prepared))
  guard @publication_host.client_source_acquisition_matches_effect_program(
      prepared, stage, ordinal, original,
    ) &&
    @strategy.graph_stage_operation_task(graph, stage, 0) is Some(task) &&
    @strategy.graph_task_owner(graph, task) is Some(owner) else {
    return Err(ForeignOriginal)
  }
  guard sequences.get(task) is Some(generated) &&
    physical_equal(@execution.generated_sequence_owner(generated), owner) else {
    return Err(ForeignOriginal)
  }
  let sequence = @execution.generated_prepared_sequence(generated)
  let acquisition = match
    @row_source_host.prepare_row_input_acquisition(
      original,
      @checked.source_identity(@strategy.graph_program(graph)),
      sequence,
      contracts.original.value.contracts,
      declaration,
      {
        max_rows: 100,
        page: {
          max_bytes: page_bytes,
          max_nodes: 100000,
          max_depth: 100,
          max_rows: 100,
        },
        retention: {
          max_nodes: 100000,
          max_text_bytes: 500000,
          max_depth: 100,
          max_work: 20000000,
        },
        wire: {
          max_columns: 100,
          max_order_work: 100000,
          max_bytes: 1000000,
          max_nodes: 100000,
          max_depth: 100,
        },
      },
    ) {
    Ok(value) => value
    Err(_) => return Err(Unsupported)
  }
  match
    installed_whole_source_capture_capacity(original, acquisition, provider) {
    Some(value) => Ok(value)
    None => Err(Unsupported)
  }
}

///|
/// Borrow the exact retained complete input. No read/current callback occurs.
pub fn prepared_installed_effect_managed_whole_source(
  plan : ClientInstalledEffectManagedPlan,
  occurrence : Int,
) -> Result[
  (
    @sourceviews.SourceAcquisition,
    @row_source_host.RowInputAcquisition,
    ClientInstalledWholeSourceCapacity,
  ),
  ClientInstalledManagedRunIssue,
] {
  guard plan.whole_sources.get(occurrence) is Some(Some((_, source))) else {
    return Err(ForeignOriginal)
  }
  Ok((source.original, source.acquisition, source))
}

///|
fn installed_effect_source_capture_index(
  plan : ClientInstalledEffectManagedPlan,
  occurrence : Int,
) -> Int? {
  guard plan.whole_sources.get(occurrence) is Some(None) else { return None }
  let mut index = 0
  for slot in 0..<occurrence {
    if plan.whole_sources[slot] is None {
      index += 1
    }
  }
  Some(index)
}
