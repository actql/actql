///|
/// Local metadata is retained with the same Project and its physical input
/// loans. No Root, Source, Check or permission is issued by this stage.
priv struct StoredLocalProjectInputs {
  _connections : @host.ClientProjectConnections
  _registry : @host.ClientProjectModelRegistry?
  model_registry : Int?
  model_configuration : Int?
  catalogs : Array[@host.ClientProjectLocalFileCatalog]
}

///|
fn read_original_project_connections(
  value : Instance,
  original : StoredProjectInputPreparation,
  handle : Int,
  input : Int,
) -> Result[@host.ClientProjectConnections, Int] {
  original_project_input_wire(value, original, handle, input).bind(wire => {
    guard @host.client_project_connections_admission_construction_inventory(
        wire,
      )
      is Some(inventory) else {
      return Err(-31)
    }
    grow_original_project_input(value, original, inventory).bind(_ => {
      @host.admit_client_project_connections(wire).map_err(_ => -31)
    })
  })
}

///|
fn prepare_original_local_project_inputs(
  value : Instance,
  original : StoredProjectInputPreparation,
  input : Int,
  handle : Int,
  cursor : @decode.Cursor,
  selection : StoredProjectConfiguration,
  configuration : @host.ClientProjectConfiguration,
) -> Int {
  guard selection.selection.mock_catalog_file() is Ok(None) &&
    selection.selection.mock_data_file() is Ok(None) &&
    selection.selection.mock_answer_count() == Ok(0) &&
    @decode.closed_object(cursor, [
      "project", "connectors", "registry", "directory", "model_registry", "model_configuration",
    ])
    is Ok(object) &&
    required_int32(object, "connectors") is Some(connection_input) &&
    connection_input != input &&
    @decode.lookup(object, "registry") is Some(registry_input) &&
    @decode.lookup(object, "directory") is Some(directory) &&
    @decode.text(directory) is Ok(directory) &&
    directory.has_prefix("/") &&
    @scalar.admit_utf8_length(directory, 4096) is Ok(_) else {
    return -31
  }
  let connections = match
    read_original_project_connections(value, original, handle, connection_input) {
    Ok(connections) => connections
    Err(code) => return code
  }
  let grow = units => grow_original_project_input(value, original, units)
  let (registry, model_registry) = match (
    configuration.model_tasks_file(),
    @decode.lookup(object, "model_registry"),
  ) {
    (None, None) => {
      guard @decode.is_null(registry_input) else { return -31 }
      (None, None)
    }
    (Some(_), Some(selected)) => {
      guard @decode.is_null(registry_input) &&
        @decode.int32(selected) is Ok(registry_handle) &&
        value.original_metadata.get(registry_handle) is Some(record) &&
        record.kind == 11 && record.produced && !record.output_closed &&
        record.project is Some(ModelRegistry(registered)) &&
        registered.parent == original.parent &&
        registered.registry is Some(registry) &&
        registry.task_count() == 1 else {
        return -31
      }
      (Some(registry), Some(registry_handle))
    }
    (Some(_), None) => {
      guard @decode.int32(registry_input) is Ok(ticket) &&
        ticket != input &&
        ticket != connection_input else {
        return -31
      }
      let wire = match
        original_project_input_wire(value, original, handle, ticket) {
        Ok(wire) => wire
        Err(code) => return code
      }
      match
        @host.admit_funded_client_project_model_registry(wire, grow, _ => -31) {
        Ok(registry) if registry.task_count() == 0 &&
          registry.provider_count() == 0 => (Some(registry), None)
        Ok(_) => return -31
        Err(code) => return code
      }
    }
    (None, Some(_)) => return -31
  }
  let (model_configuration, source_policy) = match @decode.lookup(object, "model_configuration") {
    None => {
      guard model_registry is None else { return -31 }
      (None, None)
    }
    Some(selected) => {
      guard model_registry is Some(registry) &&
        @decode.int32(selected) is Ok(model) &&
        value.original_metadata.get(model) is Some({ project: Some(ModelHttpTask(installed)), .. }) &&
        installed.host_current is Some(current) &&
        installed_portable_model_task(value, model, current) is Some(retained) &&
        physical_equal(retained, installed) &&
        value.original_metadata.get(installed.parent) is Some({ project: Some(ModelTask(task)), .. }) &&
        task.parent == registry else { return -31 }
      let status = validate_host_current(value.nonce, current)
      if status != 0 { return status }
      if installed.source_policy is Some(policy) {
        guard @sha.text_hex(connections.original_wire()) is Ok(digest) &&
          "sha256:" + digest == policy.connectors_sha256 else { return -31 }
      }
      (Some(model), installed.source_policy)
    }
  }
  let count = connections.count()
  guard count > 0 && count <= 128 else { return -31 }
  if grow({
      record_headers: 5L,
      reference_slots: 10L + count.to_int64(),
      scalar_words: 5L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Err(code) {
    return code
  }
  let catalogs : Array[@host.ClientProjectLocalFileCatalog] = Array(
    capacity=count,
  )
  let mut policy_matched = false
  for index in 0..<count {
    let policy = match (source_policy, connections.at(index)) {
      (Some(policy), Some((connection, "local", _))) if connection == policy.connection => {
        if policy_matched { return -31 }
        policy_matched = true
        Some(policy)
      }
      _ => None
    }
    match
      prepare_original_local_file_catalog(
        value, original, connections, index, directory,
        policy~,
      ) {
      Ok(catalog) => catalogs.push(catalog)
      Err(code) => return code
    }
  }
  if source_policy is Some(_) && !policy_matched { return -31 }
  if model_configuration is Some(model) {
    guard value.original_metadata.get(model) is Some({ project: Some(ModelHttpTask(installed)), .. }) &&
      installed.host_current is Some(current) &&
      installed_portable_model_task(value, model, current) is Some(retained) &&
      physical_equal(retained, installed) else { return -31 }
    let status = validate_host_current(value.nonce, current)
    if status != 0 { return status }
  }
  original.local_inputs = Some({
    _connections: connections,
    _registry: registry,
    model_registry,
    model_configuration,
    catalogs,
  })
  0
}

///|
fn prepare_original_local_file_catalog(
  value : Instance,
  original : StoredProjectInputPreparation,
  connections : @host.ClientProjectConnections,
  index : Int,
  directory : String,
  policy? : StoredPortableLocalSourcePolicy? = None,
) -> Result[@host.ClientProjectLocalFileCatalog, Int] {
  let grow = units => grow_original_project_input(value, original, units)
  let local_files = match
    connections.funded_local_files(index, 4096, 32, grow, _ => -31) {
    Ok(local_files) => local_files
    Err(code) => return Err(code)
  }
  // Splitting, joining and checking the lexical path only uses the original
  // directory and root text. The physical Root will be selected separately.
  let path_units = directory.length().to_int64() +
    local_files.root.length().to_int64()
  match
    grow({
      record_headers: 16L + 8L * path_units,
      reference_slots: 16L + 12L * path_units,
      scalar_words: 8L + 4L * path_units,
      owned_utf16_units: 4L * path_units,
      owned_wire_bytes: 0L,
    }) {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  guard @host.resolve_client_project_path(
      directory,
      local_files.root,
      ordinary_file=true,
      ordinary_directory=true,
    )
    is Some(root) &&
    @scalar.admit_utf8_length(root, 4096) is Ok(_) else {
    return Err(-31)
  }
  let classification = match policy {
    None => None
    Some(selected) => {
      if selected.root != root { return Err(-31) }
      Some((selected.resource, selected.classification))
    }
  }
  let limits : @row_host.LocalFileSourceDeclarationLimits = {
    max_files: 1000,
    max_entries: 10000,
    max_pages: 64,
    max_attempts: 64,
    max_listing_bytes: 16777216,
    max_duration_ms: 30000,
    max_path_bytes: 4096,
    max_page_bytes: 1048576,
  }
  guard local_files.catalog_specification_capacity(root, limits) is Ok(first) else {
    return Err(-31)
  }
  grow_original_project_input_bytes(value, original, first).bind(_ => {
    guard local_files.prepare_catalog_specification(root, limits, csv_classification=classification)
      is Ok(prepared) &&
      prepared.construction_capacity() is Ok(issuance) else {
      return Err(-31)
    }
    grow_original_project_input_bytes(value, original, issuance).bind(_ => {
      prepared.issue().map_err(_ => -31)
    })
  })
}

///|
fn original_local_project_inputs(
  value : Instance,
  handle : Int,
) -> StoredLocalProjectInputs? {
  guard value.original_metadata.get(handle) is Some(project) &&
    project.kind == 6 &&
    project.produced &&
    !project.output_closed &&
    project.project is Some(LocalInputs(original)) &&
    original_project_input_selection(value, original.parent) is Some(parent) &&
    parent.selection.selected_profile() == Ok(None) else {
    return None
  }
  original.local_inputs
}
