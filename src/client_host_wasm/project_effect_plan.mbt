///|
// The same nominal Project check and its one filled file supply all selected
// occurrences. No Source attempt or Plan adoption happens during construction.
priv struct StoredMockProjectEffectPlan {
  plan : @local_host.ClientInstalledEffectManagedPlan
  request : @host.ClientRequestIdentity
  mut ready : Bool
  mut sdk_run : Int?
  mut journal : StoredMockEffectJournal?
  file : StoredProjectInputPreparation
  data : Bytes
  sources : Array[StoredMockEffectSourceSelection]
}

///|
priv struct StoredMockEffectSourceSelection {
  source : StoredMockProjectSource
  row : @row_host.ProjectMockRowSelection
}

///|
fn select_mock_effect_source(
  sources : Array[StoredMockProjectSource],
  connection : String,
  resource : String,
  view : String,
  remaining : Ref[Int],
) -> Result[StoredMockEffectSourceSelection, Int] {
  let mut selected : StoredMockEffectSourceSelection? = None
  for source in sources {
    if remaining.val == 0 {
      return Err(-10)
    }
    remaining.val -= 1
    if source.connection != connection {
      continue
    }
    for row in source.rows {
      if remaining.val == 0 {
        return Err(-10)
      }
      remaining.val -= 1
      if row.view.resource == resource && row.view.view_cid == view {
        if selected is Some(_) {
          return Err(-2)
        }
        selected = Some({ source, row, })
      }
    }
  }
  match selected {
    Some(original) => Ok(original)
    None => Err(-2)
  }
}

///|
// These are quantities of the held declaration and actual input, not a
// second parser or a looser file limit. UTF-8 has at most three bytes per
// UTF-16 unit. Every admitted JSON node occupies at least one input byte.
fn mock_project_record_read_limits(
  source : StoredMockProjectSource,
  selection : @row_host.ProjectMockRowSelection,
  bytes : Int,
  profile : @row_host.RowPageLimits,
) -> @row_host.RowPageLimits {
  let mut units = selection.view.resource.length().to_int64() +
    selection.primary_identity.length().to_int64()
  for wire in source.relation.view_bodies {
    units += wire.length().to_int64()
  }
  for wire in source.relation.contracts {
    units += wire.length().to_int64()
  }
  for item in selection.items_path {
    units += item.length().to_int64()
  }
  for item in selection.key_path {
    units += item.length().to_int64()
  }
  let bound = Int64::min(
    profile.max_bytes.to_int64(),
    Int64::max(Int::max(1, bytes).to_int64(), 3L * units),
  ).to_int()
  {
    ..profile,
    max_bytes: bound,
    max_nodes: Int::min(profile.max_nodes, bound),
  }
}

///|
fn prepare_original_mock_effect_target_contract(
  value : Instance,
  check : StoredMockProjectCheck,
  original : StoredMockProjectWriteTarget,
  data : Bytes,
) -> Result[StoredMockProjectTargetContract, Int] {
  if original.preparation is Some(prepared) {
    return if physical_equal(prepared.data, data) {
      Ok(prepared)
    } else {
      Err(-32)
    }
  }
  let resource = original.write.mapping.resource
  guard original.source.rows
    .iter()
    .find_first(row => row.view.resource == resource)
    is Some(row) else {
    return Err(-2)
  }
  let previous = check.charged
  guard grow_mock_project_check(
    value,
    check,
    mock_effect_target_geometry_inventory(data.length()),
  ) else {
    return Err(-4)
  }
  guard mock_effect_target_mapping_limits(
      original.source,
      row,
      data,
      mock_project_record_read_limits(
        original.source,
        row,
        data.length(),
        @row_host.project_mock_row_page_limits(),
      ),
    )
    is Some((limits, raw_limits)) else {
    return Err(-31)
  }
  guard @row_host.relation_document_mapping_construction_inventory(limits)
    is Some(quote) &&
    grow_mock_project_check(value, check, quote) else {
    return Err(-4)
  }
  let prepared = assemble_original_mock_effect_target_contract(
    original, row, limits, raw_limits, data,
  )
  let (prepared, backing) = match prepared {
    Err(code) => return Err(code)
    Ok(result) => result
  }
  guard @execution.checked_preparation_add_product(previous, 1L, backing)
    is Some(retained) &&
    retained <= check.charged &&
    @resources.shrink_capacity_reservation(
      value.root,
      check.capacity,
      retained,
      retained,
    )
    is Ok(_) else {
    return Err(-4)
  }
  check.charged = retained
  original.preparation = Some(prepared)
  Ok(prepared)
}

///|
fn assemble_original_mock_effect_target_contract(
  original : StoredMockProjectWriteTarget,
  row : @row_host.ProjectMockRowSelection,
  limits : @row_host.RowPageLimits,
  raw_limits : @row_host.RowPageLimits,
  data : Bytes,
) -> Result[(StoredMockProjectTargetContract, Int64), Int] {
  guard @row_host.prepare_relation_document_contract(
      original.source.relation,
      original.write.mapping.resource,
      row.primary_identity,
      limits,
    )
    is Ok(contract) else {
    return Err(-31)
  }
  let page = @row_host.project_mock_row_page_limits()
  let typed = @row_host.relation_document_prepared_contract(contract)
  guard @row_host.relation_target_write_wire_construction(
      typed,
      page,
      data.length(),
      0,
      deleting=false,
    )
    is Some(initial) &&
    @row_host.relation_target_write_wire_construction(
      typed,
      page,
      page.max_bytes,
      page.max_bytes,
      deleting=false,
    )
    is Some(maximum) &&
    @local_host.prepare_installed_file_update_wire_extent(initial)
    is Ok(initial) &&
    @local_host.prepare_installed_file_update_wire_extent(maximum)
    is Ok(maximum) &&
    @local_host.prepare_installed_effect_staged_extent(initial, maximum)
    is Ok(extent) else {
    return Err(-4)
  }
  // The two operation extents and their capacity pairs are immutable scalars
  // retained with the checked Contract. Their names borrow installed code.
  guard @row_host.relation_document_prepared_contract_retained_inventory(
      contract,
    ).bind(@execution.preparation_representation_cost)
    is Some(typed_backing) &&
    @execution.preparation_representation_cost({
      record_headers: 11L,
      reference_slots: 25L,
      scalar_words: 32L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }).bind(bytes => {
      @execution.checked_preparation_add_product(typed_backing, 1L, bytes)
    })
    is Some(backing) else {
    return Err(-4)
  }
  Ok(({ data, row, limits, raw_limits, contract, extent, }, backing))
}

///|
fn prepare_mock_project_effect_plan(
  value : Instance,
  configuration : StoredRunConfiguration,
  check : StoredMockProjectCheck,
  prepared : @host.PreparedClientEffectComputation,
  snapshot : @host.ClientSavedSubmissionSnapshot,
) -> Result[StoredMockProjectEffectPlan, Int] {
  guard value.original_metadata.get(check.project) is Some(record) &&
    record.produced &&
    !record.output_closed &&
    record.project is Some(MockInputs(file)) &&
    file.data is Some(_) &&
    file.data_body is Some(data) &&
    file.inputs is Some(inputs) &&
    configuration.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(current) &&
    current.account is Some(account) else {
    return Err(-2)
  }
  let page = @row_host.project_mock_row_page_limits()
  let bytes = data.length()
  guard bytes > 0 && bytes <= page.max_bytes else { return Err(-4) }
  guard @host.prepared_client_effect_infer_count(prepared) == Some(0) &&
    @host.prepared_client_effect_update_target_count(prepared) is Some(targets) else {
    return Err(-20)
  }
  let work = @host.client_standard_effect_computation_limits().effects.max_work
  let occurrences = match
    @host.select_client_effect_direct_acquisition_occurrences(prepared, work) {
    Err(WorkLimit) => return Err(-10)
    Err(ForeignRequest | DuplicateCapture | MissingCapture) => return Err(-2)
    Err(_) => return Err(-20)
    Ok(original) => original
  }
  let count = @host.client_direct_acquisition_occurrence_count(occurrences)
  let remaining = Ref(work - count)
  let sources = Array(capacity=count)
  let source_inputs = Array(capacity=count)
  let extents = Array(capacity=count)
  let limits = @local_host.installed_row_input_policy(
    page.max_rows,
    bytes,
    Int::min(bytes, page.max_nodes),
    page.max_depth,
    page.max_rows,
  )
  for index in 0..<count {
    guard @host.client_direct_acquisition_occurrence_subject(occurrences, index)
      is Some(subject) else {
      return Err(-2)
    }
    let declaration = @sourceviews.declaration(subject.source)
    let selected = match
      select_mock_effect_source(
        inputs.sources,
        declaration.connector,
        declaration.resource,
        @sourceviews.selected_cid(subject.source),
        remaining,
      ) {
      Err(code) => return Err(code)
      Ok(original) => original
    }
    guard @authorization.evaluate_account(account, {
        principal: configuration.tuple.principal,
        connection: selected.source.connection,
        resource: selected.row.view.resource,
        operation: "read",
      })
      is Allow(_) else {
      return Err(-20)
    }
    match
      @local_host.prepare_installed_effect_row_source_input(
        selected.source.relation,
        None,
        input_limits=Some(limits),
      ) {
      Err(_) => return Err(-20)
      Ok(input) => source_inputs.push(input)
    }
    sources.push(selected)
    // The same immutable Bytes are held once. Each occurrence still owes its
    // own later transfer/capture accounting and current source observation.
    extents.push(bytes.to_int64())
  }
  let demands = FixedArray::make(targets, None)
  let result = check_mock_project_effect_plan_targets(
    value,
    configuration,
    check,
    prepared,
    (target, original) => {
      let extent = match
        prepare_original_mock_effect_target_contract(
          value, check, original, data,
        ) {
        Err(code) => return code
        Ok(prepared) => prepared.extent
      }
      let demand = match
        @local_host.prepare_installed_effect_operation_demand(
          prepared,
          target.stage_index,
          target.effect_id,
          [],
          [extent],
        ) {
        Err(ForeignOriginal) => return -2
        Err(_) => return -4
        Ok(demand) => demand
      }
      guard @local_host.installed_effect_operation_demand_original_index(
          demand,
          prepared,
          target.stage_index,
          target.effect_id,
        )
        is Some(index) &&
        index >= 0 &&
        index < targets &&
        demands[index] is None else {
        return -2
      }
      demands[index] = Some(demand)
      0
    },
  )
  if result != 0 {
    return Err(result)
  }
  let operations = Array(capacity=targets)
  for demand in demands {
    guard demand is Some(original) else { return Err(-2) }
    operations.push(original)
  }
  guard @host.prepare_client_submitted_effect_request_identity(
      prepared,
      configuration.authority_scope_cid,
      snapshot,
    )
    is Ok(request) else {
    return Err(-32)
  }
  let assets = @host.client_local_product_assets()
  let plan = match
    @local_host.prepare_installed_effect_managed_source_plan(
      prepared,
      request,
      source_inputs,
      "",
      "",
      extents,
      extents,
      value.installed_sequences.contracts,
      assets.values,
      Some(assets.fragment),
      assets.ordered,
      operations,
      provider_factory=_ => [],
      runtime_admission=true,
    ) {
    Err(InsufficientCapacity) => return Err(-4)
    Err(ForeignOriginal) => return Err(-2)
    Err(_) => return Err(-20)
    Ok(plan) => plan
  }
  Ok({
    plan,
    request,
    ready: false,
    sdk_run: None,
    journal: None,
    file,
    data,
    sources,
  })
}

///|
// A successful Request still owes the original Project generation after
// returning its construction loan and observing currentness again.
fn mock_project_effect_plan_current(
  value : Instance,
  check : StoredMockProjectCheck,
  effect : StoredMockProjectEffectPlan,
) -> Int {
  guard value.original_metadata.get(check.project) is Some(record) &&
    record.produced &&
    !record.output_closed &&
    record.project is Some(MockInputs(file)) &&
    physical_equal(file, effect.file) &&
    file.data is Some(_) &&
    file.data_body is Some(body) &&
    physical_equal(body, effect.data) else {
    return -2
  }
  for index in 0..<effect.sources.length() {
    if @local_host.prepared_installed_effect_managed_whole_source(
        effect.plan,
        index,
      )
      is Err(_) {
      return -20
    }
  }
  0
}
