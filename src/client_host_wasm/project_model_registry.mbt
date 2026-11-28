///|
priv struct StoredProjectModelRegistry {
  mut parent : Int
  capacity : @resources.CapacityReservation
  mut charged : Int64
  mut document : @buffers.BufferBorrow?
  mut registry : @host.ClientProjectModelRegistry?
}

///|
// Admit the registry under the retained physical Project preparation. No
// provider, credential or Task configuration is opened by this step.
fn prepare_original_project_model_registry(
  value : Instance,
  record : StoredOriginalMetadata,
  handle : Int,
  slot : @buffers.BufferSlot,
) -> Int {
  // The existing Project descriptor quote covers this smaller two-field
  // descriptor and its registry holder and callbacks.
  guard @buffers.buffer_length(value.pool, slot) is Some(bytes) &&
    original_mock_project_input_capacity(bytes) is Some(prefix) else {
    return -4
  }
  let capacity = match @resources.reserve_capacity(value.root, prefix, prefix) {
    Ok(value) => value
    Err(_) => return -4
  }
  let original : StoredProjectModelRegistry = {
    parent: 0,
    capacity,
    charged: prefix,
    document: None,
    registry: None,
  }
  record.project = Some(ModelRegistry(original))
  guard @buffers.buffer_source(value.pool, slot) is Some(source) &&
    @decode.admit(source, {
      max_nodes: 3,
      max_depth: 2,
      max_string_bytes: bytes,
      max_total_string_bytes: bytes,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, ["project", "registry"]) is Ok(object) &&
    required_int32(object, "project") is Some(parent) &&
    original_model_project_selection(value, parent) is Some(project) &&
    project.configuration is Some(configuration) &&
    configuration.model_tasks_file() is Some(_) &&
    project.selection.selected_profile() is Ok(profile) &&
    profile != Some("mock") &&
    required_int32(object, "registry") is Some(input) &&
    input != record.input &&
    !value.original_metadata
    .values()
    .any(child => {
      child.project is Some(ModelRegistry(held)) && held.parent == parent
    }) else {
    return -31
  }
  // An admitted child keeps its exact parent until cleanup, including a
  // partial loan, parsing refusal or failed projection.
  original.parent = parent
  let grow = units => {
    guard @execution.preparation_representation_cost(units) is Some(cost) &&
      @execution.checked_preparation_add_product(original.charged, 1L, cost)
      is Some(next) else {
      return Err(-4)
    }
    guard @resources.grow_capacity_reservation(value.root, capacity, next, next)
      is Ok(_) else {
      return Err(-4)
    }
    original.charged = next
    Ok(())
  }
  let wire = match
    read_original_project_document(value, handle, input, grow, borrow => {
      original.document = Some(borrow)
    }) {
    Ok(value) => value
    Err(code) => return code
  }
  let registry = match
    @host.admit_funded_client_project_model_registry(
      wire,
      grow,
      _ => -31,
      settle=Some(scratch => {
        let retained = original.charged - scratch
        guard @resources.shrink_capacity_reservation(
            value.root,
            capacity,
            retained,
            retained,
          )
          is Ok(_) else {
          return Err(-4)
        }
        original.charged = retained
        Ok(())
      }),
    ) {
    Ok(value) => value
    Err(code) => return code
  }
  original.registry = Some(registry)
  project_model_task_locators(
    value,
    capacity,
    original.charged,
    original.registry.unwrap(),
    record.slot,
  )
}

///|
fn close_original_project_model_registry(
  value : Instance,
  original : StoredProjectModelRegistry,
) -> Int {
  original.registry = None
  if original.document is Some(document) {
    let closed = status(@buffers.return_buffer_borrow(value.pool, document))
    if closed != 0 {
      return closed
    }
    original.document = None
  }
  match @resources.settle_capacity(value.root, original.capacity) {
    Ok(_) => 0
    Err(_) => -4
  }
}

///|
priv struct StoredProjectModelTaskInput {
  mut parent : Int
  mut index : Int
  capacity : @resources.CapacityReservation
  mut document : @buffers.BufferBorrow?
  mut _task : (
    @environment.PublicModelTaskDeclaration,
    @host.ClientProjectModelTaskSelection,
  )?
}

///|
fn prepare_original_project_model_task(
  value : Instance,
  record : StoredOriginalMetadata,
  handle : Int,
  slot : @buffers.BufferSlot,
) -> Int {
  // The same Project descriptor quote covers this three-field input and its
  // holder. The original physical Task bytes are funded by their own loan.
  guard @buffers.buffer_length(value.pool, slot) is Some(bytes) &&
    original_mock_project_input_capacity(bytes) is Some(prefix) else {
    return -4
  }
  let capacity = match @resources.reserve_capacity(value.root, prefix, prefix) {
    Ok(value) => value
    Err(_) => return -4
  }
  let original : StoredProjectModelTaskInput = {
    parent: 0,
    index: -1,
    capacity,
    document: None,
    _task: None,
  }
  record.project = Some(ModelTask(original))
  guard @buffers.buffer_source(value.pool, slot) is Some(source) &&
    @decode.admit(source, {
      max_nodes: 4,
      max_depth: 2,
      max_string_bytes: bytes,
      max_total_string_bytes: bytes,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, ["registry", "index", "task"]) is Ok(object) &&
    required_int32(object, "registry") is Some(parent) &&
    value.original_metadata.get(parent) is Some(registry_record) &&
    registry_record.kind == 11 &&
    registry_record.produced &&
    !registry_record.output_closed &&
    registry_record.project is Some(ModelRegistry(selected)) &&
    original_model_project_selection(value, selected.parent) is Some(_) &&
    selected.registry is Some(registry) &&
    required_int32(object, "index") is Some(index) &&
    registry.task_at(index) is Some((name, path)) &&
    required_int32(object, "task") is Some(input) &&
    input != record.input &&
    input != registry_record.input &&
    !value.original_metadata
    .values()
    .any(child => {
      child.project is Some(ModelTask(held)) &&
      held.parent == parent &&
      held.index == index
    }) else {
    return -31
  }
  original.parent = parent
  original.index = index
  let limits = project_model_task_limits()
  guard value.copies.get(input) is Some((task_slot, ticket)) &&
    task_slot.wire_length <= limits.bodies.max_bytes &&
    selected.document is Some(registry_document) &&
    !physical_equal(task_slot, registry_document.slot) else {
    return -31
  }
  let loan = match
    @buffers.borrow_filled_payload_input(value.pool, task_slot, () => {
      physical_reader_stop(ticket, handle) == 0
    }) {
    Ok(loan) => loan
    Err(issue) => return issue_code(issue)
  }
  original.document = Some(loan)
  match
    read_funded_project_model_task(
      value, capacity, prefix, loan, registry, name, path, limits,
    ) {
    Err(code) => return code
    Ok((task, binding, _)) => original._task = Some((task, binding))
  }
  0
}

///|
fn close_original_project_model_task(
  value : Instance,
  original : StoredProjectModelTaskInput,
) -> Int {
  original._task = None
  if original.document is Some(document) {
    let closed = status(@buffers.return_buffer_borrow(value.pool, document))
    if closed != 0 {
      return closed
    }
    original.document = None
  }
  match @resources.settle_capacity(value.root, original.capacity) {
    Ok(_) => 0
    Err(_) => -4
  }
}

///|
// Use the Native Project's public Task document limits for the same inputs.
fn project_model_task_limits() -> @environment.ModelTaskLimits {
  {
    bodies: {
      max_bytes: 65536,
      max_nodes: 4096,
      max_depth: 16,
      max_members: 4096,
    },
    contracts: { max_nodes: 4096, max_depth: 16, max_text_bytes: 65536, },
    max_work: 1000000,
  }
}

///|
fn project_model_document_format(path : String) -> String {
  if path.has_suffix(".json") {
    "json"
  } else {
    "yaml"
  }
}

///|
// Both Project profiles borrow the same Task file and use the same Common
// declaration parser and provider selection before provider installation.
fn read_funded_project_model_task(
  value : Instance,
  capacity : @resources.CapacityReservation,
  prefix : Int64,
  task_loan : @buffers.BufferBorrow,
  registry : @host.ClientProjectModelRegistry,
  task_name : String,
  task_path : String,
  task_limits : @environment.ModelTaskLimits,
) -> Result[
  (
    @environment.PublicModelTaskDeclaration,
    @host.ClientProjectModelTaskSelection,
    Int64,
  ),
  Int,
] {
  // The input loan covers the mutable/immutable byte overlap. Pay for the
  // UTF-16 decoder's temporary array and returned String separately.
  guard @execution.checked_preparation_add_product(
      prefix,
      4L,
      task_loan.slot.wire_length.to_int64(),
    )
    is Some(decode_peak) &&
    @resources.grow_capacity_reservation(
      value.root,
      capacity,
      prefix,
      decode_peak,
    )
    is Ok(_) else {
    return Err(-4)
  }
  guard @buffers.filled_payload_input_bytes(value.pool, task_loan) is Some(raw) else {
    return Err(-31)
  }
  let wire = @utf8.decode(raw) catch { _ => return Err(-31) }
  let format = project_model_document_format(task_path)
  guard @environment.public_model_task_document_construction_extent(
      wire, format, task_limits,
    )
    is Some(extent) else {
    return Err(-31)
  }
  let count = registry.task_count().to_int64() +
    registry.provider_count().to_int64()
  guard @execution.preparation_representation_cost({
      // Include the bounded Task selection and its registry scan controls.
      record_headers: extent.record_headers + 32L + 3L * count,
      reference_slots: extent.reference_slots + 44L + 6L * count,
      scalar_words: extent.scalar_words + 56L + 3L * count,
      owned_utf16_units: extent.owned_utf16_units,
      owned_wire_bytes: extent.owned_wire_bytes,
    })
    is Some(construction) &&
    @execution.checked_preparation_add_product(decode_peak, 1L, construction)
    is Some(peak) &&
    @resources.grow_capacity_reservation(value.root, capacity, peak, peak)
    is Ok(_) else {
    return Err(-4)
  }
  guard @environment.read_public_model_task_document(wire, format, task_limits)
    is Ok(task) &&
    @environment.public_model_task_declaration_identity(task).0 == task_name &&
    @host.select_client_project_model_task(registry, task, task_limits.max_work)
    is Ok(binding) else {
    return Err(-31)
  }
  Ok((task, binding, peak))
}

///|
// Only the admitted registry selects task locators. The output is used by the
// original physical Project to capture those files relative to that registry.
fn project_model_task_locators(
  value : Instance,
  capacity : @resources.CapacityReservation,
  charged : Int64,
  registry : @host.ClientProjectModelRegistry,
  slot : @buffers.BufferSlot,
) -> Int {
  // The slot funds the returned Bytes. The text writer and UTF-8 conversion
  // have their own synchronous overlap before those bytes transfer to it.
  guard @encode.text_writer_live_key_inventory(65536, 0, 2) is Some(writer) &&
    @execution.preparation_representation_cost({
      record_headers: writer.record_headers + 8L,
      reference_slots: writer.reference_slots + 12L,
      scalar_words: writer.scalar_words + 10L,
      owned_utf16_units: writer.owned_utf16_units,
      owned_wire_bytes: 0L,
    })
    is Some(scratch) &&
    @execution.checked_preparation_add_product(charged, 1L, scratch)
    is Some(peak) &&
    @resources.grow_capacity_reservation(value.root, capacity, charged, peak)
    is Ok(_) else {
    return -4
  }
  let bytes = try {
    let writer = @encode.writer(65536, 8192, 2)
    @encode.begin_array(writer)
    for index in 0..<registry.task_count() {
      guard registry.task_at(index) is Some((task, path)) else { return -31 }
      @encode.begin_array(writer)
      @encode.string_value(writer, task)
      @encode.string_value(writer, path)
      @encode.end_array(writer)
    }
    @encode.end_array(writer)
    @utf8.encode(@encode.finish(writer))
  } catch {
    _ => return -34
  }
  let supplied = status(@buffers.supply_buffer_output(value.pool, slot, bytes))
  if supplied != 0 {
    return supplied
  }
  match
    @resources.shrink_capacity_reservation(
      value.root,
      capacity,
      charged,
      charged,
    ) {
    Ok(_) => 0
    Err(_) => -4
  }
}
