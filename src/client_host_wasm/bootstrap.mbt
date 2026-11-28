///|
/// Original first-adoption metadata and its input/output loans only.
/// This record does not adopt a Host, issue authority or represent durable state.
priv struct StoredBootstrap {
  input : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut produced : Bool
  mut output_closed : Bool
  mut sdk_profile : Bool?
  mut project : BootstrapProject?
  mut project_funding : ProjectBootstrapFunding?
  mut account_loan : @buffers.BufferBorrow?
}

///|
priv enum BootstrapProject {
  MockBootstrapProject(Int, Int?)
  FileBootstrapProject(Int)
  ProtectedAccountBootstrap(Int)
}

///|
priv struct ProjectBootstrapFunding {
  capacity : @resources.CapacityReservation
  mut retained : Int64
  mut execution : Int64
}

///|
pub fn reserve_bootstrap(
  nonce : Int64,
  input : Int,
  physical_ticket : Int,
  physical_copy_bytes : Int64,
) -> Int {
  guard selected(nonce) is Some(value) &&
    value.copies.get(input) is Some((input_slot, physical)) else {
    return -2
  }
  if value.closing || value.runtime_closing {
    return -5
  }
  if physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) {
    return -3
  }
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 1048576, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(value) => value
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  let borrow = @buffers.borrow_buffer(value.pool, input_slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
  value.bootstraps[handle] = {
    input,
    borrow,
    slot,
    invoked: false,
    produced: false,
    output_closed: false,
    sdk_profile: None,
    project: None,
    project_funding: None,
    account_loan: None,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn produce_bootstrap(nonce : Int64, handle : Int) -> Int {
  produce_bootstrap_profile(nonce, handle, false)
}

///|
pub fn produce_sdk_bootstrap(nonce : Int64, handle : Int) -> Int {
  produce_bootstrap_profile(nonce, handle, true)
}

///|
fn project_bootstrap_funding_cost(
  extent : @authorization.AccountConfigurationConstructionUnits,
) -> Int64? {
  @execution.preparation_representation_cost({
    record_headers: extent.record_headers,
    reference_slots: extent.reference_slots,
    scalar_words: extent.scalar_words,
    owned_utf16_units: extent.owned_utf16_units,
    owned_wire_bytes: extent.owned_wire_bytes,
  })
}

///|
fn prepare_project_bootstrap_funding(
  value : Instance,
  funding : ProjectBootstrapFunding,
  request : @authorization.AccountConfigurationConstruction,
) -> Bool {
  guard project_bootstrap_funding_cost(request.retained) is Some(retained) &&
    project_bootstrap_funding_cost(request.execution) is Some(execution) &&
    @execution.checked_preparation_add_product(funding.retained, retained, 1L)
    is Some(retained) &&
    @execution.checked_preparation_add_product(funding.execution, execution, 1L)
    is Some(execution) &&
    @resources.grow_capacity_reservation(
      value.root,
      funding.capacity,
      retained,
      execution,
    )
    is Ok(_) else {
    return false
  }
  funding.retained = retained
  funding.execution = execution
  true
}

///|
fn reserve_project_bootstrap_funding(
  value : Instance,
  record : StoredBootstrap,
  project : BootstrapProject,
) -> Result[ProjectBootstrapFunding, Int] {
  let capacity = match @resources.reserve_capacity(value.root, 0L, 0L) {
    Ok(capacity) => capacity
    Err(_) => return Err(-4)
  }
  let funding = { capacity, retained: 0L, execution: 0L, }
  record.project = Some(project)
  record.project_funding = Some(funding)
  Ok(funding)
}

///|
// Use only the prepared record-file Project original on this fresh SDK
// adoption entrance. Model locators cannot stand in for installed providers.
fn produce_project_mock_bootstrap(
  value : Instance,
  record : StoredBootstrap,
  handle : Int,
  bootstrap_handle : Int,
  root : String,
  at : String,
  attestation : Int?,
) -> Result[@host.ClientLocalProductSDKBootstrapOriginals, Int] {
  guard value.original_metadata.get(handle) is Some(project) &&
    project.kind == 6 &&
    project.produced &&
    !project.output_closed &&
    project.project is Some(MockInputs(original)) &&
    original.inputs is Some(inputs) &&
    original_mock_project_selection(value, original.parent) is Some(_) &&
    inputs.registry.map(registry => registry.task_count()).unwrap_or(0) == 0 &&
    inputs.sources.all(source => {
      source.relation.views.all(view => {
        source.rows.any(row => physical_equal(row.view, view))
      })
    }) else {
    return Err(-31)
  }
  let funding = match
    reserve_project_bootstrap_funding(
      value,
      record,
      MockBootstrapProject(handle, attestation),
    ) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  let refused = Ref(false)
  let prepare = request => {
    let admitted = prepare_project_bootstrap_funding(value, funding, request)
    if !admitted {
      refused.val = true
    }
    admitted
  }
  let (subjects, targets) = match
    @host.client_project_mock_account_subjects(
      inputs.sources,
      source => source.connection,
      source => source.relation,
      source => source.writes,
      0,
      _ => None,
      prepare,
    ) {
    Some(Ok(result)) => result
    Some(Err(_)) => return Err(-31)
    None => return Err(-4)
  }
  // The current SDK installation identifies its control connection as local.
  // Use the same disjointness check as Native and refuse a profile requiring
  // a different installed control identity on this SDK entrance.
  match
    @authorization.local_mock_control_connection_prepared(
      subjects.control_connection,
      None,
      None,
      subjects.sources,
      targets,
      prepare,
    ) {
    Some(Ok(control)) if control == subjects.control_connection => ()
    Some(_) => return Err(-31)
    None => return Err(-4)
  }
  let subjects = match attestation {
    None => subjects
    Some(input) => {
      guard input != record.input &&
        value.copies.get(input) is Some((slot, physical)) &&
        slot.wire_length > 0 &&
        slot.wire_length <= 65536 else {
        return Err(-31)
      }
      let size = slot.wire_length.to_int64()
      guard @host.client_protocol_metadata_construction_bytes(
          size.to_int(),
          128L,
          copies=2,
        )
        is Some((scratch, _)) &&
        @resources.grow_capacity_reservation(
          value.root,
          funding.capacity,
          funding.retained,
          funding.execution + scratch,
        )
        is Ok(_) else {
        return Err(-4)
      }
      funding.execution += scratch
      let loan = match
        @buffers.borrow_filled_payload_input(value.pool, slot, () => {
          physical_reader_stop(physical, bootstrap_handle) == 0
        }) {
        Ok(value) => value
        Err(issue) => return Err(issue_code(issue))
      }
      record.account_loan = Some(loan)
      guard input_cursor(value, loan.slot) is Some(cursor) &&
        @decode.closed_object(cursor, ["operator", "host_attestation"])
        is Ok(provisioned) &&
        required_text(provisioned, "operator") is Some(operator_wire) &&
        @host.admit_client_host_signer_configuration(operator_wire, {
          max_wire_bytes: 8192,
          max_nodes: 64,
          max_depth: 8,
          max_signers: 1,
        })
        is Ok(operator) &&
        !operator.has_explicit_signers() &&
        required_text(provisioned, "host_attestation") is Some(wire) &&
        @host.admit_client_local_effect_attestation_selection(
          wire,
          subjects.principal,
          subjects.control_connection,
        )
        is Some(selected) &&
        selected.resource == "key/initial-host-attestation" else {
        return Err(-31)
      }
      { ..subjects, signing_key_resource: Some(selected.resource), }
    }
  }
  match
    @host.client_local_product_sdk_mock_bootstrap_originals(
      root, at, subjects, targets, prepare,
    ) {
    Ok(value) => Ok(value)
    Err(_) => Err(if refused.val { -4 } else { -31 })
  }
}

///|
fn produce_project_file_bootstrap(
  value : Instance,
  record : StoredBootstrap,
  handle : Int,
  root : String,
  at : String,
) -> Result[@host.ClientLocalProductSDKBootstrapOriginals, Int] {
  guard original_local_project_inputs(value, handle) is Some(original) else {
    return Err(-31)
  }
  let funding = match
    reserve_project_bootstrap_funding(
      value,
      record,
      FileBootstrapProject(handle),
    ) {
    Ok(value) => value
    Err(code) => return Err(code)
  }
  let refused = Ref(false)
  let prepare = request => {
    let admitted = prepare_project_bootstrap_funding(value, funding, request)
    if !admitted {
      refused.val = true
    }
    admitted
  }
  let result = @host.client_local_product_sdk_file_bootstrap_originals(
    root,
    at,
    original.catalogs,
    prepare,
  )
  guard original_local_project_inputs(value, handle) is Some(active) &&
    physical_equal(active, original) else {
    return Err(-32)
  }
  result.map_err(issue => {
    if refused.val || issue is ConfigurationLimit {
      -4
    } else {
      -31
    }
  })
}

///|
fn produce_selected_account_bootstrap(
  value : Instance,
  record : StoredBootstrap,
  handle : Int,
  input : Int,
  root : String,
  at : String,
) -> Result[@host.ClientLocalProductSDKBootstrapOriginals, Int] {
  guard input != record.input &&
    value.copies.get(input) is Some((slot, ticket)) &&
    slot.wire_length > 0 &&
    slot.wire_length <= 65536 else {
    return Err(-31)
  }
  // The original input reservation holds the bytes. Before decoding, fund
  // its UTF-16 destination and control records. The same bootstrap child
  // retains the Account constructor's additional per-phase budget.
  guard @execution.preparation_representation_cost({
      record_headers: 16L,
      reference_slots: 24L,
      scalar_words: 20L,
      owned_utf16_units: 2L * slot.wire_length.to_int64(),
      owned_wire_bytes: 0L,
    })
    is Some(prefix) else {
    return Err(-4)
  }
  let capacity = match @resources.reserve_capacity(value.root, prefix, prefix) {
    Ok(capacity) => capacity
    Err(_) => return Err(-4)
  }
  let funding : ProjectBootstrapFunding = {
    capacity,
    retained: prefix,
    execution: prefix,
  }
  record.project_funding = Some(funding)
  let loan = match
    @buffers.borrow_filled_payload_input(value.pool, slot, () => {
      physical_reader_stop(ticket, handle) == 0
    }) {
    Ok(loan) => loan
    Err(issue) => return Err(issue_code(issue))
  }
  record.account_loan = Some(loan)
  guard @buffers.filled_payload_input_bytes(value.pool, loan) is Some(account) else {
    return Err(-31)
  }
  match
    @host.client_local_product_sdk_bootstrap_with_account(root, at, account, request => {
      prepare_project_bootstrap_funding(value, funding, request)
    }) {
    Ok(original) => Ok(original)
    Err(@host.ConfigurationLimit) => Err(-4)
    Err(_) => Err(-31)
  }
}

///|
fn produce_bootstrap_profile(nonce : Int64, handle : Int, sdk : Bool) -> Int {
  guard selected(nonce) is Some(value) &&
    value.bootstraps.get(handle) is Some(record) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.output_closed {
    return -5
  }
  if record.sdk_profile is Some(previous) && previous != sdk {
    return -3
  }
  if record.produced {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  record.sdk_profile = Some(sdk)
  let borrow = match record.borrow {
    Ok(value) => value
    Err(issue) => return issue_code(issue)
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) else { return -31 }
  let (object, project) = match
    @decode.closed_object(cursor, ["configuration_root", "observed_at"]) {
    Ok(object) => (object, None)
    Err(_) => {
      if !sdk {
        return -31
      }
      if @decode.closed_object(cursor, [
          "configuration_root", "observed_at", "mock_project",
        ])
        is Ok(object) &&
        required_int32(object, "mock_project") is Some(handle) {
        (object, Some(MockBootstrapProject(handle, None)))
      } else if @decode.closed_object(cursor, [
          "configuration_root", "observed_at", "mock_project", "mock_host_attestation",
        ])
        is Ok(object) &&
        required_int32(object, "mock_project") is Some(handle) &&
        required_int32(object, "mock_host_attestation") is Some(attestation) {
        (object, Some(MockBootstrapProject(handle, Some(attestation))))
      } else if @decode.closed_object(cursor, [
          "configuration_root", "observed_at", "local_project",
        ])
        is Ok(object) &&
        required_int32(object, "local_project") is Some(handle) {
        (object, Some(FileBootstrapProject(handle)))
      } else if @decode.closed_object(cursor, [
          "configuration_root", "observed_at", "account_original",
        ])
        is Ok(object) &&
        required_int32(object, "account_original") is Some(input) {
        (object, Some(ProtectedAccountBootstrap(input)))
      } else {
        return -31
      }
    }
  }
  guard required_text(object, "configuration_root") is Some(root) &&
    required_text(object, "observed_at") is Some(at) else {
    return -31
  }
  let (originals, extra) = if project is Some(FileBootstrapProject(handle)) {
    match produce_project_file_bootstrap(value, record, handle, root, at) {
      Ok(value) => (value.original, Some((value.profile, value.read)))
      Err(code) => return code
    }
  } else if project is Some(MockBootstrapProject(project, attestation)) {
    match
      produce_project_mock_bootstrap(
        value, record, project, handle, root, at, attestation,
      ) {
      Ok(value) => (value.original, Some((value.profile, value.read)))
      Err(code) => return code
    }
  } else if project is Some(ProtectedAccountBootstrap(input)) {
    match
      produce_selected_account_bootstrap(value, record, handle, input, root, at) {
      Ok(value) => (value.original, Some((value.profile, value.read)))
      Err(code) => return code
    }
  } else if sdk {
    match @host.client_local_product_sdk_bootstrap_originals(root, at) {
      Ok(value) => (value.original, Some((value.profile, value.read)))
      Err(_) => return -31
    }
  } else {
    match @host.client_local_product_bootstrap_originals(root, at) {
      Ok(value) => (value, None)
      Err(_) => return -31
    }
  }
  let wire = try {
    let writer = @encode.writer(1048576, 32, 2)
    @encode.begin_object(writer)
    for
      (key, bytes) in [
        ("account", originals.common.account),
        ("retention_dependencies", originals.common.retention_dependencies),
        ("retention_policy", originals.common.retention_policy),
        ("store", originals.common.store),
        ("result_policy", originals.common.result_policy),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, @utf8.decode(bytes))
    }
    for
      (key, text) in [
        ("environment", originals.environment),
        ("compute", originals.compute),
      ] {
      @encode.key(writer, key)
      @encode.string_value(writer, text)
    }
    if extra is Some((profile, read)) {
      @encode.key(writer, "run_policy_profile")
      @encode.string_value(
        writer,
        @host.client_local_run_policy_profile_wire(profile),
      )
      @encode.key(writer, "sdk_read")
      @encode.string_value(
        writer,
        @publication.local_sdk_result_read_selection_wire(read),
      )
    }
    @encode.end_object(writer)
    @encode.finish(writer)
  } catch {
    _ => return -34
  }
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, @utf8.encode(wire)),
  )
  if result == 0 {
    record.produced = true
  }
  result
}

///|
pub fn bootstrap_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.bootstraps.get(handle) is Some(record) &&
    record.produced &&
    !record.output_closed else {
    return -33
  }
  match @buffers.buffer_length(value.pool, record.slot) {
    Some(length) => length
    None => -33
  }
}

///|
pub fn close_bootstrap(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.bootstraps.get(handle) is Some(record) else {
    return -2
  }
  if !record.output_closed {
    let result = status(@buffers.close_buffer(value.pool, record.slot))
    if result != 0 {
      return result
    }
    record.output_closed = true
  }
  if record.account_loan is Some(account) {
    let result = status(@buffers.return_buffer_borrow(value.pool, account))
    if result != 0 {
      return result
    }
    record.account_loan = None
  }
  let result = match record.borrow {
    Ok(borrow) => status(@buffers.return_buffer_borrow(value.pool, borrow))
    Err(_) => 0
  }
  if result == 0 {
    if record.project_funding is Some(funding) {
      guard @resources.settle_capacity(value.root, funding.capacity) is Ok(_) else {
        return -4
      }
      record.project_funding = None
    }
    value.bootstraps.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
