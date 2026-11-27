///|
priv struct StoredProjectModelHttpTask {
  mut parent : Int
  mut host_current : Int?
  capacity : @resources.CapacityReservation
  documents : Array[@buffers.BufferBorrow]
  mut _tls_ca : (String, String)?
  mut source_policy : StoredPortableLocalSourcePolicy?
  mut _configured : (
    @model.PortableModelHttpChatTask,
    @environment.ModelResponseProfileInstallation,
    @model.StructuredModelCapability,
  )?
  mut execution : (
    Bytes,
    @resources.QuantityAmounts,
    @host.ClientInferEgressObservation,
  )?
}

///|
fn project_model_http_task_capacity(bytes : Int) -> Int64? {
  // Root, 14 root values, and 3 + 4 + 2 + 2 nested values.
  guard @decode.preserving_json_admission_construction_inventory(bytes, 26, 2)
    is Some(parser) &&
    @decode.closed_object_field_construction_extent(Some(14), 14, 0L)
    is Some(fields) &&
    @decode.closed_object_field_construction_extent(Some(2), 2, 2L)
    is Some(ca_fields) &&
    @decode.closed_object_field_construction_extent(Some(3), 3, 0L)
    is Some(attempt_fields) &&
    @decode.closed_object_field_construction_extent(Some(4), 4, 0L)
    is Some(egress_fields) else {
    return None
  }
  // Include the physical installation record, capability, provider and
  // retained tuple of original references alongside their construction controls.
  @execution.preparation_representation_cost({
    // The physical attempt and egress observation retain their closed views,
    // admitted records, selected tuple and option. The region string is
    // supplied by the bounded preserving parse.
    record_headers: parser.record_headers +
    fields.record_headers +
    attempt_fields.record_headers +
    egress_fields.record_headers +
    ca_fields.record_headers +
    64L,
    reference_slots: parser.reference_slots +
    fields.reference_slots +
    attempt_fields.reference_slots +
    egress_fields.reference_slots +
    ca_fields.reference_slots +
    127L,
    scalar_words: parser.scalar_words +
    fields.scalar_words +
    attempt_fields.scalar_words +
    egress_fields.scalar_words +
    ca_fields.scalar_words +
    70L,
    // Conservatively hold the selected two ASCII strings through adoption.
    owned_utf16_units: parser.owned_utf16_units + 199L,
    owned_wire_bytes: 0L,
  })
}

///|
fn installed_portable_model_attempt(
  cursor : @decode.Cursor,
) -> @resources.QuantityAmounts? {
  guard @decode.closed_object(cursor, ["tokens", "cost_units", "duration_ms"])
    is Ok(fields) &&
    @decode.lookup(fields, "tokens") is Some(tokens) &&
    @decode.safe_integer(tokens) is Ok(tokens) &&
    tokens > 0L &&
    @decode.lookup(fields, "cost_units") is Some(cost_units) &&
    @decode.safe_integer(cost_units) is Ok(cost_units) &&
    cost_units >= 0L &&
    @decode.lookup(fields, "duration_ms") is Some(duration_ms) &&
    @decode.safe_integer(duration_ms) is Ok(duration_ms) &&
    duration_ms > 0L &&
    duration_ms <= 2147483647L else {
    return None
  }
  Some({ tokens, cost_units, duration_ms, })
}

///|
// Installation observations enter the existing occurrence policy. The
// author Program and its Model Task cannot supply these physical facts.
fn installed_portable_model_egress(
  cursor : @decode.Cursor,
) -> @host.ClientInferEgressObservation? {
  guard @decode.closed_object(cursor, [
      "classification", "region", "provider_retention", "training_use",
    ])
    is Ok(fields) &&
    required_text(fields, "region") is Some(region) &&
    !region.is_empty() &&
    region.length() <= 256 &&
    @decode.lookup(fields, "provider_retention") is Some(retention) &&
    @decode.boolean(retention) is Ok(provider_retention) &&
    @decode.lookup(fields, "training_use") is Some(training) &&
    @decode.boolean(training) is Ok(training_use) else {
    return None
  }
  let classification : @environment.DataClassification = match
    required_text(fields, "classification") {
    Some("public") => Public
    Some("internal") => Internal
    Some("confidential") => Confidential
    Some("restricted") => Restricted
    _ => return None
  }
  Some({ classification, region, provider_retention, training_use, })
}

///|
fn installed_portable_model_tls_ca(
  cursor : @decode.Cursor,
  credential_file : String,
) -> (String, String)? {
  guard @decode.closed_object(cursor, ["file", "sha256"]) is Ok(fields) &&
    required_text(fields, "file") is Some(file) &&
    file.length() > 0 &&
    file.length() <= 128 &&
    file != "." &&
    file != ".." &&
    file != credential_file &&
    required_text(fields, "sha256") is Some(digest) &&
    digest.length() == 71 &&
    digest.has_prefix("sha256:") else {
    return None
  }
  for index = 0; index < file.length(); index = index + 1 {
    let c = file[index]
    if !((c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '-' ||
      c == '.' ||
      c == '_') {
      return None
    }
  }
  for index = 7; index < digest.length(); index = index + 1 {
    let c = digest[index]
    if !((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
      return None
    }
  }
  Some((file, digest))
}

///|
// The Host supplies four independently held, nonsecret installation original
// inputs. No source bytes from a Task or Project can become a credential grant.
fn prepare_original_project_model_http_task(
  value : Instance,
  record : StoredOriginalMetadata,
  handle : Int,
  slot : @buffers.BufferSlot,
) -> Int {
  guard @buffers.buffer_length(value.pool, slot) is Some(bytes) &&
    project_model_http_task_capacity(bytes) is Some(prefix) else {
    return -4
  }
  let capacity = match @resources.reserve_capacity(value.root, prefix, prefix) {
    Ok(value) => value
    Err(_) => return -4
  }
  let original : StoredProjectModelHttpTask = {
    parent: 0,
    host_current: None,
    capacity,
    documents: Array(capacity=6),
    _tls_ca: None,
    source_policy: None,
    _configured: None,
    execution: None,
  }
  record.project = Some(ModelHttpTask(original))
  guard @buffers.buffer_source(value.pool, slot) is Some(source) &&
    @decode.admit(source, {
      max_nodes: 26,
      max_depth: 2,
      max_string_bytes: bytes,
      max_total_string_bytes: bytes,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "task", "installation", "contract", "provider", "response", "profile_cid",
      "credential_file", "current", "execution", "attempt", "egress", "runtime_artifact_cid",
      "tls_ca", "source_catalog",
    ])
    is Ok(object) &&
    required_int32(object, "current") is Some(current) &&
    required_int32(object, "task") is Some(parent) &&
    value.original_metadata.get(parent) is Some(task_record) &&
    task_record.kind == 12 &&
    task_record.produced &&
    !task_record.output_closed &&
    task_record.project is Some(ModelTask(typed)) &&
    typed._task is Some((task, selection)) &&
    typed.document is Some(task_document) &&
    value.original_metadata.get(typed.parent) is Some(registry_record) &&
    registry_record.kind == 11 &&
    registry_record.produced &&
    !registry_record.output_closed &&
    registry_record.project is Some(ModelRegistry(registered)) &&
    registered.registry is Some(registry) &&
    registered.document is Some(registry_document) &&
    original_portable_model_project_selection(value, registered.parent) &&
    required_int32(object, "installation") is Some(installation) &&
    required_int32(object, "contract") is Some(contract) &&
    required_int32(object, "provider") is Some(provider) &&
    required_int32(object, "response") is Some(response) &&
    required_text(object, "profile_cid") is Some(profile_cid) &&
    required_text(object, "credential_file") is Some(credential_file) &&
    required_text(object, "runtime_artifact_cid") is Some(runtime_artifact_cid) &&
    !value.original_metadata
    .values()
    .any(child => {
      child.project is Some(ModelHttpTask(candidate)) &&
      candidate.parent == parent
    }) else {
    return -31
  }
  let tls_ca = match @decode.lookup(object, "tls_ca") {
    None => None
    Some(cursor) => {
      guard installed_portable_model_tls_ca(cursor, credential_file)
        is Some(selected) else {
        return -31
      }
      Some(selected)
    }
  }
  let status = validate_host_current(value.nonce, current)
  if status != 0 {
    return status
  }
  original.parent = parent
  original.host_current = Some(current)
  let selected_execution = match
    (
      @decode.lookup(object, "execution"),
      @decode.lookup(object, "attempt"),
      @decode.lookup(object, "egress"),
    ) {
    (None, None, None) => None
    (Some(execution), Some(attempt), Some(egress)) => {
      guard @decode.int32(execution) is Ok(input) &&
        installed_portable_model_attempt(attempt) is Some(quantities) &&
        installed_portable_model_egress(egress) is Some(observed) else {
        return -31
      }
      Some((input, quantities, observed))
    }
    _ => return -31
  }
  let limits = project_model_task_limits()
  let bodies : Array[Bytes] = Array(capacity=4)
  let inputs = [installation, contract, provider, response]
  if selected_execution is Some((input, _, _)) {
    inputs.push(input)
  }
  let source_catalog = match @decode.lookup(object, "source_catalog") {
    None => None
    Some(cursor) => {
      guard selected_execution is Some(_) &&
        original_project_input_selection(value, registered.parent) is Some(_) &&
        @decode.closed_object(cursor, ["input", "sha256"]) is Ok(fields) &&
        required_int32(fields, "input") is Some(input) &&
        !inputs.contains(input) &&
        required_text(fields, "sha256") is Some(digest) &&
        valid_portable_local_source_policy_digest(digest) else { return -31 }
      inputs.push(input)
      Some((input, digest))
    }
  }
  let mut component_prefix = prefix
  for index, input in inputs {
    guard input != record.input &&
      value.copies.get(input) is Some((document, ticket)) &&
      document.wire_length <= limits.bodies.max_bytes &&
      !physical_equal(document, task_document.slot) &&
      !physical_equal(document, registry_document.slot) &&
      !original.documents.any(loan => physical_equal(loan.slot, document)) else {
      return -31
    }
    let loan = match
      @buffers.borrow_filled_payload_input(value.pool, document, () => {
        physical_reader_stop(ticket, handle) == 0
      }) {
      Ok(value) => value
      Err(issue) => return issue_code(issue)
    }
    original.documents.push(loan)
    guard @buffers.filled_payload_input_bytes(value.pool, loan) is Some(body) else {
      return -31
    }
    if source_catalog is Some((policy_input, expected)) && input == policy_input {
      if body.length() <= 0 || body.length() > 8192 { return -31 }
      guard portable_local_source_policy_capacity(body.length()) is Some(extra) &&
        @execution.checked_preparation_add_product(prefix, extra, 1L) is Some(peak) &&
        @resources.grow_capacity_reservation(value.root, capacity, peak, peak) is Ok(_) else {
        return -4
      }
      guard "sha256:" + @sha.hex(body) == expected &&
        admit_portable_local_source_policy(body) is Some(policy) else { return -31 }
      original.source_policy = Some(policy)
      component_prefix = peak
    } else if index == 4 {
      guard selected_execution is Some((_, quantities, observed)) else {
        return -31
      }
      original.execution = Some((body, quantities, observed))
    } else {
      bodies.push(body)
    }
  }
  let configured = match
    @model.prepare_portable_model_http_chat_task(
      registry,
      task,
      selection,
      bodies[0],
      bodies[1],
      bodies[2],
      bodies[3],
      profile_cid,
      credential_file,
      limits,
      extra => {
        guard @execution.checked_preparation_add_product(component_prefix, 1L, extra)
          is Some(peak) else {
          return false
        }
        @resources.grow_capacity_reservation(value.root, capacity, peak, peak)
        is Ok(_)
      },
    ) {
    Ok(value) => value
    Err(@model.Capacity) => return -4
    Err(_) => return -31
  }
  let physical : @environment.ModelResponseProfileInstallation = {
    builder_id: "actql/python-portable-chat",
    builder_revision: "1",
    codec_id: "actql/openai-chat-envelope",
    codec_revision: "1",
    build_artifact_cid: runtime_artifact_cid,
    sdk: None,
    endpoint: configured.route.endpoint,
    http_method: "POST",
    streaming: false,
    validator_id: "actql/openai-chat-envelope",
    validator_revision: "1",
    validator_artifact_cid: runtime_artifact_cid,
    completion_basis: "generation_finish",
  }
  let capability = match
    @model.install_portable_model_http_chat_capability(configured, physical) {
    Ok(value) => value
    Err(_) => return -31
  }
  guard @execution.checked_preparation_add_product(
      component_prefix,
      1L,
      configured.retained_bytes,
    )
    is Some(retained) &&
    @resources.shrink_capacity_reservation(
      value.root,
      capacity,
      retained,
      retained,
    )
    is Ok(_) else {
    return -4
  }
  let status = validate_host_current(value.nonce, current)
  if status != 0 {
    return status
  }
  original._tls_ca = tls_ca
  original._configured = Some((configured, physical, capability))
  0
}

///|
// Borrow the installed configuration and its execution binding from the same
// live Project chain pinned by the Run configuration.
fn installed_portable_model_task(
  value : Instance,
  handle : Int,
  current : Int,
) -> StoredProjectModelHttpTask? {
  guard value.original_metadata.get(handle) is Some(record) &&
    record.kind == 13 &&
    record.produced &&
    !record.output_closed &&
    record.project is Some(ModelHttpTask(held)) &&
    held.host_current == Some(current) &&
    held._configured is Some(_) &&
    value.host_currents.get(current) is Some(owner) &&
    !owner.closing &&
    value.original_metadata.get(held.parent) is Some(task) &&
    task.kind == 12 &&
    task.produced &&
    !task.output_closed &&
    task.project is Some(ModelTask(typed)) &&
    typed._task is Some(_) &&
    value.original_metadata.get(typed.parent) is Some(registry) &&
    registry.kind == 11 &&
    registry.produced &&
    !registry.output_closed &&
    registry.project is Some(ModelRegistry(selected)) &&
    selected.registry is Some(_) &&
    original_portable_model_project_selection(value, selected.parent) else {
    return None
  }
  Some(held)
}

///|
fn close_original_project_model_http_task(
  value : Instance,
  original : StoredProjectModelHttpTask,
) -> Int {
  original._configured = None
  original.execution = None
  original.source_policy = None
  while original.documents.last() is Some(document) {
    let closed = status(@buffers.return_buffer_borrow(value.pool, document))
    if closed != 0 {
      return closed
    }
    ignore(original.documents.pop())
  }
  match @resources.settle_capacity(value.root, original.capacity) {
    Ok(_) => 0
    Err(_) => -4
  }
}
