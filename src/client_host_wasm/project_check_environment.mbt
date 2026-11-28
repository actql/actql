///|
// Original child of one admitted Mock Project and the existing installed
// base Checker, usable only for Check under the same current configuration.
priv struct StoredMockProjectCheck {
  mut project : Int
  mut base : Int
  mut configuration : Int
  capacity : @resources.CapacityReservation
  mut charged : Int64
  mut prepared_publication : @source_publication.PreparedPublishedQueryEnvironment?
  mut write_target_bytes : Int64
  write_targets : Array[StoredMockProjectWriteTarget]
  mut runtime_cid : String?
  mut data_path : String?
  mut local_file : @host.ClientProjectLocalFileCheck?
  mut environment : (@checked.CheckEnvironment, String?, String?)?
}

///|
fn grow_mock_project_check(
  value : Instance,
  held : StoredMockProjectCheck,
  units : @execution.PreparationRepresentationUnits,
) -> Bool {
  guard @execution.preparation_representation_cost(units) is Some(cost) &&
    @execution.checked_preparation_add_product(held.charged, 1L, cost)
    is Some(next) &&
    @resources.grow_capacity_reservation(value.root, held.capacity, next, next)
    is Ok(_) else {
    return false
  }
  held.charged = next
  true
}

///|
fn prepare_original_project_check(
  value : Instance,
  record : StoredOriginalMetadata,
  slot : @buffers.BufferSlot,
) -> Int {
  guard @buffers.buffer_length(value.pool, slot) is Some(bytes) &&
    original_mock_project_input_capacity(bytes, check_installation=true)
    is Some(prefix) else {
    return -4
  }
  let capacity = match @resources.reserve_capacity(value.root, prefix, prefix) {
    Ok(value) => value
    Err(_) => return -4
  }
  let held : StoredMockProjectCheck = {
    project: 0,
    base: 0,
    configuration: 0,
    capacity,
    charged: prefix,
    prepared_publication: None,
    write_target_bytes: 0L,
    write_targets: [],
    runtime_cid: None,
    data_path: None,
    local_file: None,
    environment: None,
  }
  record.project = Some(PreparingProjectCheck(held))
  guard @buffers.buffer_source(value.pool, slot) is Some(source) &&
    @decode.admit(source, {
      max_nodes: 7,
      max_depth: 3,
      max_string_bytes: bytes,
      max_total_string_bytes: bytes,
    })
    is Ok(cursor) &&
    @decode.closed_object(cursor, [
      "project", "base", "configuration", "installation",
    ])
    is Ok(fields) &&
    required_int32(fields, "project") is Some(handle) &&
    required_int32(fields, "base") is Some(base_handle) &&
    required_int32(fields, "configuration") is Some(configuration) &&
    value.environments.get(base_handle) is Some(base) &&
    base.publication is None &&
    value.run_configurations.get(configuration) is Some(current) &&
    current.host_current is Some(current_handle) &&
    value.host_currents.get(current_handle) is Some(original_current) &&
    original_current.account is Some(account) else {
    return -31
  }
  if current.sdk is Some({ portable_model: Some(model), .. }) {
    guard @decode.lookup(fields, "installation") is None &&
      @environment.member_count(
        @checked.checking_environment_wire(base.environment),
        ModelTaskContracts,
      ) ==
      0 &&
      installed_portable_model_task(value, model, current_handle)
      is Some({ _configured: Some((configured, _, _)), .. }) else {
      return -31
    }
    let file_inputs = match current.local_project {
      None => {
        guard handle == model else { return -31 }
        None
      }
      Some(local_handle) => {
        guard handle == local_handle &&
          original_local_project_inputs(value, handle) is Some(inputs) &&
          inputs.model_registry is Some(_) else {
          return -31
        }
        Some(inputs)
      }
    }
    held.project = handle
    held.base = base_handle
    held.configuration = configuration
    let result = prepare_portable_model_check_environment(
      value,
      held,
      base,
      current,
      account,
      configured.task,
      file_inputs~,
    )
    if result == 0 {
      record.project = if file_inputs is Some(_) {
        Some(LocalCheck(held))
      } else {
        Some(PortableModelCheck(held))
      }
    }
    return result
  }
  if current.local_project == Some(handle) {
    guard @decode.lookup(fields, "installation") is None &&
      original_local_project_inputs(value, handle) is Some(inputs) else {
      return -31
    }
    held.project = handle
    held.base = base_handle
    held.configuration = configuration
    let result = prepare_original_local_project_check(
      value,
      held,
      base.environment,
      current,
      account,
      inputs,
    )
    if result == 0 {
      record.project = Some(LocalCheck(held))
    }
    return result
  }
  guard current.mock_project == Some(handle) &&
    value.original_metadata.get(handle) is Some(project) &&
    project.kind == 6 &&
    project.produced &&
    !project.output_closed &&
    project.project is Some(MockInputs(original)) &&
    original.inputs is Some(inputs) &&
    original_mock_project_selection(value, original.parent) is Some(_) &&
    inputs.registry.map(registry => registry.task_count()).unwrap_or(0) == 0 else {
    return -31
  }
  let installation = match @decode.lookup(fields, "installation") {
    None => None
    Some(attachment) => {
      guard @decode.closed_object(attachment, [
          "runtime_bundle_cid", "data_path",
        ])
        is Ok(body) &&
        required_text(body, "runtime_bundle_cid") is Some(runtime) &&
        runtime.has_prefix("sha256:") &&
        runtime.length() == 71 &&
        required_text(body, "data_path") is Some(path) &&
        path.has_prefix("/") &&
        path.length() <= 4096 else {
        return -31
      }
      for index in 7..<71 {
        let digit = runtime[index].to_int()
        if !((48 <= digit && digit <= 57) || (97 <= digit && digit <= 102)) {
          return -31
        }
      }
      Some((runtime, path))
    }
  }
  held.project = handle
  held.base = base_handle
  held.configuration = configuration
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  let (checker, publication, scope, prepared, retained) = match
    assemble_original_mock_project_check(
      value, held, base, current, account, inputs, installation,
    ) {
    Ok(original) => original
    Err(code) => return code
  }
  let runtime_bytes = match installation {
    None => 0L
    Some((cid, path)) =>
      @execution.preparation_representation_cost({
        record_headers: 2L,
        reference_slots: 2L,
        scalar_words: 0L,
        owned_utf16_units: cid.length().to_int64() + path.length().to_int64(),
        owned_wire_bytes: 0L,
      }).unwrap()
  }
  guard @execution.checked_preparation_add_product(prefix, 1L, retained)
    is Some(retained) &&
    @execution.checked_preparation_add_product(
      retained,
      1L,
      held.write_target_bytes,
    )
    is Some(retained) &&
    @execution.checked_preparation_add_product(retained, 1L, runtime_bytes)
    is Some(retained) &&
    @resources.shrink_capacity_reservation(
      value.root,
      held.capacity,
      retained,
      retained,
    )
    is Ok(_) else {
    return -4
  }
  held.charged = retained
  held.runtime_cid = installation.map(attachment => attachment.0)
  held.data_path = installation.map(attachment => attachment.1)
  held.prepared_publication = Some(prepared)
  held.environment = Some((checker, Some(publication), Some(scope)))
  record.project = Some(MockCheck(held))
  0
}

///|
fn prepare_original_local_project_check(
  value : Instance,
  held : StoredMockProjectCheck,
  base : @checked.CheckEnvironment,
  current : StoredRunConfiguration,
  account : @authorization.AdmittedAccountConfiguration,
  inputs : StoredLocalProjectInputs,
  initial_prefix? : Int64? = None,
) -> Int {
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  let prefix = initial_prefix.unwrap_or(held.charged)
  let original = match
    @host.prepare_funded_client_project_local_file_check(
      base,
      inputs.catalogs,
      account,
      current.tuple.principal,
      demand => {
        if grow_mock_project_check(value, held, demand) {
          Ok(())
        } else {
          Err(-4)
        }
      },
      _ => -20,
    ) {
    Ok(original) => original
    Err(code) => return code
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  guard @execution.checked_preparation_add_product(
      prefix,
      1L,
      original.retained_bytes,
    )
    is Some(retained) &&
    @resources.shrink_capacity_reservation(
      value.root,
      held.capacity,
      retained,
      retained,
    )
    is Ok(_) else {
    return -4
  }
  held.charged = retained
  held.local_file = Some(original)
  held.prepared_publication = Some(original.prepared)
  held.environment = Some(
    (original.environment, Some(original.publication), Some(original.scope_cid)),
  )
  0
}

///|
fn mock_project_model_construction_units(
  extent : @environment.RegistryConstructionExtent,
) -> @execution.PreparationRepresentationUnits {
  {
    record_headers: extent.record_headers,
    reference_slots: extent.reference_slots,
    scalar_words: extent.scalar_words,
    owned_utf16_units: extent.owned_utf16_units,
    owned_wire_bytes: extent.owned_wire_bytes,
  }
}

///|
// Only the exact admitted Task and connector participate in this static
// audience projection. A denied Task is indistinguishable from its absence.
fn prepare_portable_model_check_environment(
  value : Instance,
  held : StoredMockProjectCheck,
  base : StoredEnvironment,
  current : StoredRunConfiguration,
  account : @authorization.AdmittedAccountConfiguration,
  task : @environment.NormalizedPublicModelTask,
  file_inputs? : StoredLocalProjectInputs? = None,
) -> Int {
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  let prefix = held.charged
  // The same one-Task scope evaluation and selection envelope used by Mock.
  if !grow_mock_project_check(value, held, {
      record_headers: 36L,
      reference_slots: 72L,
      scalar_words: 40L,
      owned_utf16_units: 696L,
      owned_wire_bytes: 136L,
    }) {
    return -4
  }
  let (_, resource, _, _) = @environment.normalized_public_model_task_materials(
    task,
  )
  if !(@authorization.evaluate_account(account, {
      principal: current.tuple.principal,
      connection: @environment.normalized_public_model_task_connector(task),
      resource,
      operation: "infer",
    })
    is Allow(_)) {
    if file_inputs is Some(inputs) {
      return prepare_original_local_project_check(
        value,
        held,
        base.environment,
        current,
        account,
        inputs,
        initial_prefix=Some(prefix),
      )
    }
    match run_configuration_current(value, current) {
      Ok(_) => ()
      Err(code) => return code
    }
    guard @execution.preparation_representation_cost({
        record_headers: 1L,
        reference_slots: 3L,
        scalar_words: 0L,
        owned_utf16_units: 0L,
        owned_wire_bytes: 0L,
      })
      is Some(report) &&
      settle_portable_model_check(value, held, prefix, report) else {
      return -4
    }
    held.environment = Some((base.environment, None, None))
    return 0
  }
  let original = @checked.checking_environment_wire(base.environment)
  let tasks = [task]
  guard @host.mock_project_check_model_projection_inventory(original, tasks)
    is Some((limits, demand)) &&
    grow_mock_project_check(value, held, demand) else {
    return -4
  }
  guard @environment.project_public_model_task_environment(
      original, tasks, limits,
    )
    is Ok((body, cid, _)) else {
    return -20
  }
  guard @host.mock_project_check_wire_read_inventory(body) is Some(read) &&
    grow_mock_project_check(value, held, read) &&
    grow_mock_project_check(
      value,
      held,
      mock_project_model_construction_units(
        @host.client_check_environment_wrapper_construction_extent(false),
      ),
    ) else {
    return -4
  }
  guard @host.admit_client_check_environment_wire(body, cid) is Some(wire) else {
    return -20
  }
  guard @environment.model_tasks_admission_construction_extent(wire)
    is Some(task_inventory) &&
    grow_mock_project_check(
      value,
      held,
      mock_project_model_construction_units(task_inventory),
    ) else {
    return -4
  }
  let profiles = @checked.checking_environment_profile_selection(
    base.environment,
  )
  let projected = match profiles.numeric_profile_cid {
    None =>
      @host.admit_client_check_environment_from_wire(
        wire,
        profiles.expressions,
        profiles.operations,
        graph=profiles.graph,
      )
    Some(numeric) =>
      @host.admit_client_check_environment_from_wire_with_numeric_profile_cid(
        wire,
        profiles.expressions,
        profiles.operations,
        numeric,
        graph=profiles.graph,
      )
  }
  guard projected is Some(environment) else { return -20 }
  if file_inputs is Some(inputs) {
    return prepare_original_local_project_check(
      value,
      held,
      environment,
      current,
      account,
      inputs,
      initial_prefix=Some(prefix),
    )
  }
  // This installation supplies no physical Source aliases. Fund the two-key
  // JSON object, canonical copy, bounded writer and returned short wire before
  // offering its original to the existing published-environment reader.
  if !grow_mock_project_check(value, held, {
      record_headers: 32L,
      reference_slots: 64L,
      scalar_words: 48L,
      owned_utf16_units: 256L,
      owned_wire_bytes: 256L,
    }) {
    return -4
  }
  guard @host.client_project_mock_wire({
      "environmentCid": Json::string(cid),
      "aliases": Json::array([]),
    })
    is Ok(publication) &&
    @host.mock_project_check_admission_inventory(body, publication)
    is Some(demand) else {
    return -20
  }
  if !grow_mock_project_check(value, held, demand) {
    return -4
  }
  let prepared = match
    @source_publication.prepare_published_query_environment(
      environment, publication,
    ) {
    Ok(value) => value
    Err(_) => return -20
  }
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return code
  }
  guard @host.mock_project_check_retained_inventory(
      environment,
      body,
      publication,
      task_inventory=Some(task_inventory),
    )
    is Some(inventory) &&
    @execution.preparation_representation_cost(inventory) is Some(retained) &&
    settle_portable_model_check(value, held, prefix, retained) else {
    return -4
  }
  held.prepared_publication = Some(prepared)
  held.environment = Some((environment, Some(publication), Some(resource)))
  0
}

///|
fn settle_portable_model_check(
  value : Instance,
  held : StoredMockProjectCheck,
  prefix : Int64,
  retained : Int64,
) -> Bool {
  guard @execution.checked_preparation_add_product(prefix, 1L, retained)
    is Some(total) &&
    @resources.shrink_capacity_reservation(
      value.root,
      held.capacity,
      total,
      total,
    )
    is Ok(_) else {
    return false
  }
  held.charged = total
  true
}

///|
// Scratch stays on the same child if the original constructor or current
// callback refuses. Only the typed output returns to the settlement boundary.
fn assemble_original_mock_project_check(
  value : Instance,
  held : StoredMockProjectCheck,
  base : StoredEnvironment,
  current : StoredRunConfiguration,
  account : @authorization.AdmittedAccountConfiguration,
  inputs : StoredMockProjectInputs,
  installation : (String, String)?,
) -> Result[
  (
    @checked.CheckEnvironment,
    String,
    String,
    @source_publication.PreparedPublishedQueryEnvironment,
    Int64,
  ),
  Int,
] {
  guard @host.mock_project_check_assembly_inventory(
      base.environment,
      inputs.sources,
      source => source.relation,
      source => source.entry,
      source => source.writes.iter().map(write => write.mapping.body),
    )
    is Some(demand) &&
    grow_mock_project_check(value, held, demand) else {
    return Err(-4)
  }
  // Mapping declarations support static Check without binding a physical writer.
  let visible_writes : Array[Json] = []
  guard @host.assemble_client_project_mock_environment(
      base.environment,
      inputs.sources,
      () => None,
      source => source.relation,
      (_, _) => Iter::empty(),
      source => {
        source.writes
        .iter()
        .filter(write => {
          mock_project_write_visible(
            account,
            current.tuple.principal,
            source,
            write,
          )
        })
        .map(write => {
          visible_writes.push(Json::string(write.mapping.mapping_cid))
          write.mapping.body
        })
      },
    )
    is Some((body, cid)) else {
    return Err(-20)
  }
  let aliases : Array[Json] = []
  for source in inputs.sources {
    let entry = @json.parse(source.entry) catch { _ => return Err(-31) }
    guard @host.mock_project_check_alias_reference_inventory(
        entry,
        source.relation,
      )
      is Some(demand) else {
      return Err(-20)
    }
    if !grow_mock_project_check(value, held, demand) {
      return Err(-4)
    }
    guard @host.client_project_mock_read_aliases(entry, source.relation, resource => {
        source.rows.any(row => row.view.resource == resource) &&
        @authorization.evaluate_account(account, {
          principal: current.tuple.principal,
          connection: source.connection,
          resource,
          operation: "read",
        })
        is Allow(_)
      })
      is Some(result) else {
      return Err(-20)
    }
    aliases.append(result)
  }
  // Use the same canonical publication and alias/contract admission as the
  // standard Check. Scope identity never leaves the private report envelope.
  let published = {
    "environmentCid": Json::string(cid),
    "aliases": Json::array(aliases),
  }
  if installation is Some(selected) {
    match
      project_mock_update_aliases(
        value, held, current, account, inputs, selected,
      ) {
      Err(code) => return Err(code)
      Ok(targets) =>
        if !targets.is_empty() {
          published["updateTargets"] = Json::array(targets)
        }
    }
  }
  guard @host.client_project_mock_wire(Json::object(published))
    is Ok(publication) &&
    @host.mock_project_check_admission_inventory(body, publication)
    is Some(demand) &&
    @execution.preparation_representation_cost(demand) is Some(quote) else {
    return Err(-20)
  }
  if !grow_mock_project_check(value, held, demand) {
    return Err(-4)
  }
  guard @host.admit_client_check_environment(
      body,
      cid,
      { text_time: false, veca: false, },
      { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    )
    is Some(environment) else {
    return Err(-20)
  }
  let prepared = match
    @source_publication.prepare_published_query_environment(
      environment, publication,
    ) {
    Ok(original) => original
    Err(_) => return Err(-20)
  }
  // Do not include the private Environment CID in the audience context.
  // Only the admitted visible aliases and Mappings enter this preimage.
  let visible = if visible_writes.is_empty() {
    Json::array(aliases)
  } else {
    { "aliases": Json::array(aliases), "mappings": Json::array(visible_writes) }
  }
  guard @host.client_project_mock_wire(visible) is Ok(visible) else {
    return Err(-20)
  }
  let scope = "sha256:" + @sha.hex(@utf8.encode(visible))
  match run_configuration_current(value, current) {
    Ok(_) => ()
    Err(code) => return Err(code)
  }
  guard @host.mock_project_check_retained_inventory(
      environment, body, publication,
    )
    is Some(inventory) &&
    @execution.preparation_representation_cost(inventory) is Some(retained) else {
    return Err(-4)
  }
  // The retained publication refers to the same CheckEnvironment and owns
  // its admitted Catalog and target sections. Until their exact retained
  // inventory is available, keep the existing admission envelope once on
  // this original Check. No Request receives a second publication quote.
  guard @execution.checked_preparation_add_product(retained, 1L, quote)
    is Some(retained) else {
    return Err(-4)
  }
  Ok((environment, publication, scope, prepared, retained))
}
