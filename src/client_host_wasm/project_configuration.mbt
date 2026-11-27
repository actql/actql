///|
/// Original project/profile metadata under the existing input loan. Locators
/// are DATA; they do not supply an installed Source, permission or capacity.
priv struct StoredProjectConfiguration {
  configuration : @host.ClientProjectConfiguration?
  requested : String?
  selection : @host.ClientProjectProfileSelection
}

///|
fn prepare_original_project_configuration(
  object : @decode.ObjectView,
) -> StoredProjectConfiguration? {
  let configuration = match @decode.lookup(object, "configuration") {
    Some(value) if @decode.is_null(value) => None
    Some(value) => {
      guard @decode.text(value) is Ok(wire) &&
        @host.admit_client_project_configuration(wire) is Ok(configuration) else {
        return None
      }
      Some(configuration)
    }
    None => return None
  }
  let requested = match @decode.lookup(object, "profile") {
    Some(value) if @decode.is_null(value) => None
    Some(value) => {
      guard @decode.text(value) is Ok(profile) else { return None }
      Some(profile)
    }
    None => return None
  }
  guard @host.select_client_project_profile(configuration, requested, 65536)
    is Ok(selection) else {
    return None
  }
  Some({ configuration, requested, selection, })
}

///|
fn project_optional_text(
  writer : @encode.Writer,
  key : String,
  value : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, key)
  match value {
    Some(text) => @encode.string_value(writer, text)
    None => @encode.null_value(writer)
  }
}

///|
/// Project only the same nominal choice. A serialized copy of these locators
/// cannot replace the retained selection when the Host installs a profile.
fn original_project_configuration_body(
  original : StoredProjectConfiguration,
) -> Bytes? {
  if !@host.client_project_profile_matches(
      original.selection,
      original.configuration,
      original.requested,
    ) {
    return None
  }
  guard original.selection.selected_profile() is Ok(profile) &&
    original.selection.mock_catalog_file() is Ok(mock_catalog) &&
    original.selection.mock_data_file() is Ok(mock_data) &&
    original.selection.mock_answer_count() is Ok(answer_count) else {
    return None
  }
  let configuration = original.configuration
  try {
    let writer = @encode.writer(65536, 8192, 8)
    @encode.begin_object(writer)
    project_optional_text(
      writer,
      "connectors",
      configuration.map(value => value.connectors_file()).unwrap_or(None),
    )
    project_optional_text(
      writer,
      "lock",
      configuration.map(value => value.lock_file()).unwrap_or(None),
    )
    @encode.key(writer, "mock_answers")
    @encode.begin_array(writer)
    for index in 0..<answer_count {
      guard original.selection.mock_answer_at(index) is Ok(Some((task, path))) else {
        return None
      }
      @encode.begin_array(writer)
      @encode.string_value(writer, task)
      @encode.string_value(writer, path)
      @encode.end_array(writer)
    }
    @encode.end_array(writer)
    project_optional_text(writer, "mock_catalog", mock_catalog)
    project_optional_text(writer, "mock_data", mock_data)
    project_optional_text(
      writer,
      "model_tasks",
      configuration.map(value => value.model_tasks_file()).unwrap_or(None),
    )
    project_optional_text(writer, "profile", profile)
    @encode.key(writer, "state_dir")
    @encode.string_value(
      writer,
      configuration.map(value => value.state_directory()).unwrap_or("./.actql"),
    )
    @encode.end_object(writer)
    Some(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => None
  }
}

///|
priv struct StoredMockProjectSource {
  connection : String
  provider : String
  entry : String
  relation : @row_host.RowDeclaration
  writes : Array[@row_host.ProjectMockWriteDeclaration]
  rows : Array[@row_host.ProjectMockRowSelection]
}

///|
priv struct StoredMockProjectInputs {
  _connections : @host.ClientProjectConnections
  catalog : @host.ClientProjectCatalog
  registry : @host.ClientProjectModelRegistry?
  sources : Array[StoredMockProjectSource]
}

///|
priv struct StoredProjectInputPreparation {
  mut parent : Int
  capacity : @resources.CapacityReservation
  mut charged : Int64
  documents : Array[@buffers.BufferBorrow]
  mut data_attempted : Bool
  mut data : @buffers.BufferBorrow?
  mut data_body : Bytes?
  mut inputs : StoredMockProjectInputs?
  mut local_inputs : StoredLocalProjectInputs?
}

///|
priv enum StoredProjectMetadata {
  Selection(StoredProjectConfiguration)
  ProjectInputsPending(StoredProjectInputPreparation)
  LocalInputs(StoredProjectInputPreparation)
  MockInputs(StoredProjectInputPreparation)
  PreparingProjectCheck(StoredMockProjectCheck)
  MockCheck(StoredMockProjectCheck)
  LocalCheck(StoredMockProjectCheck)
  PortableModelCheck(StoredMockProjectCheck)
  MockEffectCapture(StoredMockEffectCapture)
  FileCapture(StoredMockEffectCapture)
  MockEffectReviewRead(Int)
  MockEffectWaiting(StoredMockEffectWaiting)
  MockEffectWaitingField(Int)
  LocalCsvOffer(Int)
  LocalCsvResponse(Int)
  ModelRegistry(StoredProjectModelRegistry)
  ModelTask(StoredProjectModelTaskInput)
  ModelHttpTask(StoredProjectModelHttpTask)
}

///|
// The input pool owns the preserving parser tree. Account separately for the
// indexed Read, its closed objects and all retained Project borrow controls.
fn original_mock_project_input_capacity(
  bytes : Int,
  check_installation? : Bool = false,
) -> Int64? {
  let (nodes, depth, fields) = if check_installation { (7, 3, 5) } else { (7, 2, 6) }
  let extents = @decode.closed_object_field_construction_extent(Some(fields), fields, 0L)
  guard @decode.preserving_json_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(admission) &&
    extents is Some(object) else {
    return None
  }
  let attachment = if check_installation { 1L } else { 0L }
  let local_input_slot = if check_installation { 0L } else { 1L }
  @execution.preparation_representation_cost({
    record_headers: admission.record_headers +
    object.record_headers +
    61L +
    attachment * 16L,
    reference_slots: admission.reference_slots +
    object.reference_slots +
    91L +
    local_input_slot +
    attachment * 33L,
    scalar_words: admission.scalar_words +
    object.scalar_words +
    72L +
    attachment * 24L,
    owned_utf16_units: admission.owned_utf16_units,
    owned_wire_bytes: 0L,
  })
}

///|
// Only a successfully produced original kind-5 selection can parent these
// inputs. Neither an equal config nor its returned locator wire is accepted.
fn original_project_configuration(
  value : Instance,
  handle : Int,
) -> StoredProjectConfiguration? {
  guard value.original_metadata.get(handle) is Some(record) &&
    record.kind == 5 &&
    record.produced &&
    !record.output_closed &&
    record.project is Some(Selection(original)) &&
    original.configuration is Some(_) &&
    @host.client_project_profile_matches(
      original.selection,
      original.configuration,
      original.requested,
    ) else {
    return None
  }
  Some(original)
}

///|
fn original_project_input_selection(
  value : Instance,
  handle : Int,
) -> StoredProjectConfiguration? {
  guard original_project_configuration(value, handle) is Some(original) &&
    original.configuration is Some(configuration) &&
    configuration.connectors_file() is Some(_) else {
    return None
  }
  Some(original)
}

///|
fn original_model_project_selection(
  value : Instance,
  handle : Int,
) -> StoredProjectConfiguration? {
  guard original_project_configuration(value, handle) is Some(original) &&
    original.configuration is Some(configuration) &&
    original.selection.selected_profile() is Ok(profile) &&
    profile != Some("mock") &&
    configuration.model_tasks_file() is Some(_) &&
    configuration.lock_file() is None else {
    return None
  }
  Some(original)
}

///|
fn original_portable_model_project_selection(
  value : Instance,
  handle : Int,
) -> Bool {
  original_model_project_selection(value, handle) is Some(original) &&
  original.configuration is Some(configuration) &&
    (configuration.connectors_file() is None ||
      original.selection.selected_profile() == Ok(None))
}

///|
fn original_mock_project_selection(
  value : Instance,
  handle : Int,
) -> StoredProjectConfiguration? {
  guard original_project_input_selection(value, handle) is Some(original) &&
    original.configuration is Some(configuration) &&
    original.selection.selected_profile() == Ok(Some("mock")) &&
    configuration.lock_file() is None &&
    original.selection.mock_catalog_file() is Ok(Some(_)) &&
    original.selection.mock_data_file() is Ok(Some(_)) else {
    return None
  }
  Some(original)
}

///|
fn grow_original_project_input(
  value : Instance,
  original : StoredProjectInputPreparation,
  units : @execution.PreparationRepresentationUnits,
) -> Result[Unit, Int] {
  guard @execution.preparation_representation_cost(units) is Some(cost) else {
    return Err(-4)
  }
  grow_original_project_input_bytes(value, original, cost)
}

///|
fn grow_original_project_input_bytes(
  value : Instance,
  original : StoredProjectInputPreparation,
  cost : Int64,
) -> Result[Unit, Int] {
  guard @execution.checked_preparation_add_product(original.charged, 1L, cost)
    is Some(next) else {
    return Err(-4)
  }
  match
    @resources.grow_capacity_reservation(
      value.root,
      original.capacity,
      next,
      next,
    ) {
    Ok(_) => {
      original.charged = next
      Ok(())
    }
    Err(_) => Err(-4)
  }
}

///|
// The existing Mapping quote separates returned roots from its synchronous
// parser/encoder workspace. Keep the exact child reservation across both.
// Refusal leaves the same charged token and borrows for child-first cleanup.
fn construct_original_mock_project_mapping(
  value : Instance,
  original : StoredProjectInputPreparation,
  capacity : @execution.ExecutionCapacity,
  construct : () -> Result[@row_host.RowMapping, @row_host.RowMappingIssue],
) -> Result[@row_host.RowMapping, Int] {
  guard @execution.checked_preparation_add_product(
      original.charged,
      1L,
      @execution.execution_capacity_retained_bytes(capacity),
    )
    is Some(retention) &&
    @execution.checked_preparation_add_product(
      original.charged,
      1L,
      @execution.execution_capacity_execution_bytes(capacity),
    )
    is Some(execution) &&
    @resources.grow_capacity_reservation(
      value.root,
      original.capacity,
      retention,
      execution,
    )
    is Ok(_) else {
    return Err(-4)
  }
  guard construct() is Ok(mapping) else { return Err(-31) }
  if @resources.shrink_capacity_reservation(
      value.root,
      original.capacity,
      retention,
      retention,
    )
    is Err(_) {
    return Err(-4)
  }
  original.charged = retention
  Ok(mapping)
}

///|
fn original_project_input_wire(
  value : Instance,
  original : StoredProjectInputPreparation,
  child : Int,
  input : Int,
) -> Result[String, Int] {
  read_original_project_document(
    value,
    child,
    input,
    units => grow_original_project_input(value, original, units),
    borrow => original.documents.push(borrow),
  )
}

///|
fn read_original_project_document(
  value : Instance,
  child : Int,
  input : Int,
  grow : (@execution.PreparationRepresentationUnits) -> Result[Unit, Int],
  retain : (@buffers.BufferBorrow) -> Unit,
) -> Result[String, Int] {
  guard value.copies.get(input) is Some((slot, physical)) &&
    @buffers.buffer_source(value.pool, slot) is Some(_) &&
    @buffers.buffer_length(value.pool, slot) is Some(bytes) else {
    return Err(-31)
  }
  // Sealing already required valid UTF-8. The pinned Wasm decoder allocates
  // one UInt16 array and yields a String. Account both even if the backend
  // transfers the array. Each bound is at most one unit per input byte.
  match
    grow({
      record_headers: 2L,
      reference_slots: 0L,
      scalar_words: 2L,
      owned_utf16_units: 2L * bytes.to_int64(),
      owned_wire_bytes: 0L,
    }) {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  // This accessor rejects output slots. The source check above also requires
  // the existing structured seal, so the borrow cannot grant raw JSON input.
  let borrow = match
    @buffers.borrow_filled_payload_input(value.pool, slot, () => {
      physical_reader_stop(physical, child) == 0
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue_code(issue))
  }
  retain(borrow)
  guard @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(wire) else {
    return Err(-31)
  }
  Ok(@utf8.decode(wire)) catch {
    _ => Err(-31)
  }
}

///|
fn prepare_original_project_inputs(
  value : Instance,
  record : StoredOriginalMetadata,
  handle : Int,
  slot : @buffers.BufferSlot,
) -> Int {
  guard @buffers.buffer_length(value.pool, slot) is Some(bytes) &&
    original_mock_project_input_capacity(bytes) is Some(prefix) else {
    return -4
  }
  let capacity = match @resources.reserve_capacity(value.root, prefix, prefix) {
    Ok(value) => value
    Err(_) => return -4
  }
  // Keep the same token across partially acquired inputs and constructor
  // failures. Handle zero is not a published selection.
  let original : StoredProjectInputPreparation = {
    parent: 0,
    capacity,
    charged: prefix,
    documents: Array(capacity=3),
    data_attempted: false,
    data: None,
    data_body: None,
    inputs: None,
    local_inputs: None,
  }
  record.project = Some(ProjectInputsPending(original))
  guard @buffers.buffer_source(value.pool, slot) is Some(source) &&
    @decode.admit(source, {
      max_nodes: 7,
      max_depth: 2,
      max_string_bytes: bytes,
      max_total_string_bytes: bytes,
    })
    is Ok(cursor) &&
    @decode.lookup_original_field(cursor, "project") is Some(parent_value) &&
    @decode.int32(parent_value) is Ok(parent) &&
    original_project_input_selection(value, parent) is Some(selection) &&
    selection.configuration is Some(configuration) &&
    configuration.lock_file() is None else {
    return -31
  }
  original.parent = parent
  match selection.selection.selected_profile() {
    Ok(None) => {
      let result = prepare_original_local_project_inputs(
        value,
        original,
        record.input,
        handle,
        cursor,
        selection,
        configuration,
      )
      if result != 0 {
        return result
      }
      guard original.local_inputs is Some(_) else { return -31 }
      record.project = Some(LocalInputs(original))
      0
    }
    Ok(Some("mock")) if original_mock_project_selection(value, parent)
      is Some(_) => {
      let result = prepare_original_mock_project_inputs(
        value,
        original,
        record.input,
        handle,
        cursor,
      )
      if result == 0 {
        record.project = Some(MockInputs(original))
      }
      result
    }
    _ => -31
  }
}

///|
fn prepare_original_mock_project_inputs(
  value : Instance,
  original : StoredProjectInputPreparation,
  input : Int,
  handle : Int,
  cursor : @decode.Cursor,
) -> Int {
  guard @decode.closed_object(cursor, [
      "project", "connectors", "catalog", "registry",
    ])
    is Ok(object) &&
    required_int32(object, "connectors") is Some(connection_input) &&
    required_int32(object, "catalog") is Some(catalog_input) &&
    @decode.lookup(object, "registry") is Some(registry_input) &&
    original_mock_project_selection(value, original.parent) is Some(selection) &&
    selection.configuration is Some(configuration) &&
    connection_input != input &&
    catalog_input != input &&
    connection_input != catalog_input else {
    return -31
  }
  let grow = units => grow_original_project_input(value, original, units)
  let connections = match
    read_original_project_connections(value, original, handle, connection_input) {
    Ok(connections) => connections
    Err(code) => return code
  }
  let registry = match configuration.model_tasks_file() {
    None => {
      guard @decode.is_null(registry_input) else { return -31 }
      None
    }
    Some(_) => {
      guard @decode.int32(registry_input) is Ok(ticket) &&
        ticket != input &&
        ticket != connection_input &&
        ticket != catalog_input else { return -31 }
      let wire = match
        original_project_input_wire(value, original, handle, ticket) {
        Ok(wire) => wire
        Err(code) => return code
      }
      match
        @host.admit_funded_client_project_model_registry(wire, grow, _ => -31) {
        Ok(value) => Some(value)
        Err(code) => return code
      }
    }
  }
  let catalog_wire = match
    original_project_input_wire(value, original, handle, catalog_input) {
    Ok(wire) => wire
    Err(code) => return code
  }
  guard @host.client_project_catalog_admission_construction_inventory(
      catalog_wire,
    )
    is Some(catalog_units) else {
    return -31
  }
  let catalog = match grow(catalog_units) {
    Ok(_) =>
      match @host.admit_client_project_catalog(catalog_wire) {
        Ok(value) => value
        Err(_) => return -31
      }
    Err(code) => return code
  }
  if catalog.count() != connections.count() {
    return -31
  }
  let count = catalog.count()
  let n = count.to_int64()
  // Exact non-growing array, selected tuple, Source record, overlap-check
  // callbacks and Result/Option for each original catalog entry.
  if grow({
      record_headers: 8L + 12L * n,
      reference_slots: 12L + 20L * n,
      scalar_words: 8L + 8L * n,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Err(code) {
    return code
  }
  let sources : Array[StoredMockProjectSource] = Array(capacity=count)
  for index in 0..<count {
    guard catalog.mock_source_at(connections, index)
      is Some((connection, provider, entry)) else {
      return -31
    }
    let (relation, writes, rows) = match
      @row_host.prepare_funded_project_mock_source_declarations(
        connection,
        entry,
        grow,
        (capacity, construct) => {
          construct_original_mock_project_mapping(
            value, original, capacity, construct,
          )
        },
        _ => -31,
      ) {
      Ok(value) => value
      Err(code) => return code
    }
    if !@row_host.check_project_mock_writable_collections(
        rows,
        writes,
        sources,
        row => row.view.resource,
        row => row.items_path,
        source => source.rows,
        source => source.writes,
      ) {
      return -31
    }
    sources.push({ connection, provider, entry, relation, writes, rows, })
  }
  original.inputs = Some({
    _connections: connections,
    catalog,
    registry,
    sources,
  })
  0
}

///|
/// Attach the selected physical seed only for a fresh Project request. The
/// Project retains the input borrow even if the post-acquisition fence fails.
fn attach_original_mock_project_data(
  value : Instance,
  record : StoredOriginalMetadata,
  borrow : @buffers.BufferBorrow,
) -> Int {
  guard @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(packet) &&
    packet.length() == 12 else {
    return -31
  }
  let project = mock_effect_descriptor_field(packet, 0)
  let configuration = mock_effect_descriptor_field(packet, 4)
  let input = mock_effect_descriptor_field(packet, 8)
  guard value.run_configurations.get(configuration) is Some(current) &&
    current.host_current is Some(_) &&
    current.mock_project == Some(project) &&
    value.original_metadata.get(project) is Some(owner) &&
    owner.kind == 6 &&
    owner.produced &&
    !owner.output_closed &&
    owner.project is Some(MockInputs(original)) &&
    original.inputs is Some(_) &&
    !original.data_attempted else {
    return -32
  }
  match run_configuration_current(value, current) {
    Err(code) => return code
    Ok(_) => ()
  }
  original.data_attempted = true
  guard value.copies.get(input) is Some((slot, physical)) &&
    !physical_equal(borrow.slot, slot) &&
    !original.documents.any(document => physical_equal(document.slot, slot)) &&
    slot.wire_length > 0 &&
    slot.wire_length <= @row_host.project_mock_row_page_limits().max_bytes else {
    return -31
  }
  let data = match
    @buffers.borrow_filled_payload_input(value.pool, slot, () => {
      physical_reader_stop(physical, project) == 0
    }) {
    Ok(data) => data
    Err(issue) => return issue_code(issue)
  }
  original.data = Some(data)
  // The filled input's reservation owns these bytes. The Source Read decodes
  // them later using the same checked Project.
  guard @buffers.filled_payload_input_bytes(value.pool, data) is Some(body) else {
    return -31
  }
  match run_configuration_current(value, current) {
    Err(code) => return code
    Ok(_) => ()
  }
  original.data_body = Some(body)
  record.produced = true
  0
}
