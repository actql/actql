///|
/// Pure original-codec invocation and buffer loans only; never adoption state.
priv struct StoredOriginalMetadata {
  mut input : Int
  kind : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut produced : Bool
  mut output_closed : Bool
  mut project : StoredProjectMetadata?
}

///|
fn original_metadata_uint(object : @decode.ObjectView, key : String) -> UInt64? {
  match required_text(object, key) {
    Some(text) => payload_physical_uint64(text)
    None => None
  }
}

///|
fn original_metadata_size(object : @decode.ObjectView, key : String) -> Int64? {
  match required_text(object, key) {
    Some(text) => payload_physical_size(text)
    None => None
  }
}

///|
fn original_initialization_body(object : @decode.ObjectView) -> Bytes? {
  guard required_text(object, "account") is Some(account_wire) &&
    @authorization.admit_account_configuration_json(account_wire) is Ok(account) &&
    required_text(object, "settings") is Some(settings) &&
    required_text(object, "nonce") is Some(nonce) &&
    original_metadata_uint(object, "parent_device") is Some(parent_device) &&
    original_metadata_uint(object, "parent_inode") is Some(parent_inode) &&
    original_metadata_uint(object, "root_device") is Some(root_device) &&
    original_metadata_uint(object, "root_inode") is Some(root_inode) &&
    original_metadata_uint(object, "source_root_device")
    is Some(source_root_device) &&
    original_metadata_uint(object, "source_root_inode")
    is Some(source_root_inode) &&
    original_metadata_uint(object, "source_device") is Some(source_device) &&
    original_metadata_uint(object, "source_inode") is Some(source_inode) &&
    original_metadata_size(object, "source_size") is Some(source_size) &&
    required_text(object, "source_file") is Some(source_file) &&
    required_text(object, "source_path") is Some(source_path) &&
    required_text(object, "state_name") is Some(state_name) else {
    return None
  }
  @host.client_local_initialization_body(
    account,
    @utf8.encode(account_wire),
    @utf8.encode(settings),
    {
      nonce,
      parent: (parent_device, parent_inode),
      root: (root_device, root_inode),
      source_root: (source_root_device, source_root_inode),
      source_file,
      source_path,
      source_generation: (source_device, source_inode, source_size),
      state_name,
    },
  ).to_option()
}

///|
// The existing observation codec owns these DATA checks; physical custody
// remains with the original Host. The producer retains its one-shot call.
fn original_configuration_selection_body(object : @decode.ObjectView) -> Bytes? {
  guard @decode.required(object, "files") is Ok(files_cursor) &&
    @decode.elements(files_cursor) is Ok(array) &&
    array.length() <= 11 &&
    (array.length() <= 8 || array.length() == 11) else {
    return None
  }
  let files : Array[@host.ClientLocalOriginalConfigurationFile] = []
  for index in 0..<array.length() {
    guard @decode.closed_object(array[index], [
        "body", "name", "device", "inode", "size",
      ])
      is Ok(file) &&
      required_text(file, "body") is Some(body) &&
      required_text(file, "name") is Some(name) &&
      original_metadata_uint(file, "device") is Some(device) &&
      original_metadata_uint(file, "inode") is Some(inode) &&
      original_metadata_size(file, "size") is Some(size) else {
      return None
    }
    let bytes = @utf8.encode(body)
    if bytes.length() > 65536 ||
      bytes.length().to_int64() != size ||
      (index > 0 && files[index - 1].name.lexical_compare(name) >= 0) {
      return None
    }
    files.push({
      content_cid: "sha256:" + @sha.hex(bytes),
      device,
      inode,
      name,
      size,
    })
  }
  if files.length() > 8 &&
    (
      !files.any(file => file.name == "host.json") ||
      !files.any(file => file.name == "effect-host-attestation.json") ||
      !files.any(file => file.name == "effect-reviewer.json")
    ) {
    return None
  }
  guard @decode.lookup(object, "managed_root") is Some(root_cursor) else {
    return None
  }
  let managed : @host.ClientLocalOriginalManagedRoot? = if @decode.is_null(
      root_cursor,
    ) {
    None
  } else {
    guard @decode.closed_object(root_cursor, ["device", "inode", "path"])
      is Ok(root) &&
      original_metadata_uint(root, "device") is Some(device) &&
      original_metadata_uint(root, "inode") is Some(inode) &&
      required_text(root, "path") is Some(path) else {
      return None
    }
    Some({ device, inode, path, })
  }
  match @host.client_local_configuration_selection_body(files, managed) {
    Ok(body) => Some(body)
    Err(_) => None
  }
}

///|
pub fn reserve_original_metadata(
  nonce : Int64,
  input : Int,
  kind : Int,
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
  let selector = kind & 31
  let bound = if kind > 31 &&
    (
      selector == MOCK_EFFECT_REVIEW_READ_KIND ||
      selector == MOCK_EFFECT_WAITING_FIELD_KIND
    ) {
    let count = kind >> 5
    let max = if selector == MOCK_EFFECT_WAITING_FIELD_KIND {
      8192
    } else {
      MOCK_EFFECT_REVIEW_READ_MAX
    }
    if count <= 0 || count > max {
      return -3
    }
    Some(count)
  } else {
    None
  }
  let kind = if bound is Some(_) { selector } else { kind }
  let mock_work = kind == MOCK_EFFECT_SOURCE_CAPTURE_KIND ||
    kind == MOCK_EFFECT_SOURCE_EVIDENCE_KIND ||
    kind == MOCK_EFFECT_COMPUTE_KIND
  let review_extent = kind == MOCK_EFFECT_REVIEW_EXTENT_KIND
  let review_read = kind == MOCK_EFFECT_REVIEW_READ_KIND
  let checkpoint_confirm = kind == MOCK_EFFECT_CHECKPOINT_CONFIRM_KIND
  let effect_waiting = kind == MOCK_EFFECT_WAITING_KIND
  let waiting_field = kind == MOCK_EFFECT_WAITING_FIELD_KIND && bound is Some(_)
  let csv_work = kind == LOCAL_CSV_OFFER_KIND || kind == LOCAL_CSV_RESPONSE_KIND
  let model_declaration = kind == 11 || kind == 12 || kind == 13
  if (
      (kind < 1 || kind > 8) &&
      !mock_work &&
      !csv_work &&
      !review_extent &&
      !review_read &&
      !checkpoint_confirm &&
      !effect_waiting &&
      !waiting_field &&
      !model_declaration
    ) ||
    physical_ticket <= 0 ||
    value.next_handle == 2147483647 ||
    value.copies.values().any(pair => pair.1 == physical_ticket) ||
    value.workspaces.values().any(pair => pair.0 == physical_ticket) ||
    value.native_commands
    .values()
    .any(command => command.physical_ticket == physical_ticket) ||
    value.result_chunks
    .values()
    .any(chunk => chunk.physical_ticket == physical_ticket) {
    return -3
  }
  let wire_limit = if kind == 6 ||
    kind == 7 ||
    kind == 8 ||
    mock_work ||
    checkpoint_confirm ||
    kind == LOCAL_CSV_RESPONSE_KIND ||
    kind == 12 ||
    kind == 13 {
    0
  } else if review_extent {
    4
  } else if effect_waiting {
    155
  } else if review_read || waiting_field {
    bound.unwrap_or(MOCK_EFFECT_REVIEW_READ_MAX)
  } else {
    65536
  }
  let slot = match
    @buffers.reserve_output_buffer(
      value.pool,
      wire_limit,
      physical_copy_bytes,
      () => physical_input_cleanup(physical_ticket) == 0,
    ) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  let stopped = () => physical_reader_stop(physical, handle) == 0
  let borrow = if kind == 8 ||
    mock_work ||
    csv_work ||
    review_extent ||
    review_read ||
    checkpoint_confirm ||
    effect_waiting ||
    waiting_field {
    @buffers.borrow_filled_payload_input(value.pool, input_slot, stopped)
  } else {
    @buffers.borrow_buffer(value.pool, input_slot, stopped)
  }
  value.original_metadata[handle] = {
    input,
    kind,
    borrow,
    slot,
    invoked: false,
    produced: false,
    output_closed: false,
    project: None,
  }
  value.copies[handle] = (slot, physical_ticket)
  value.next_handle += 1
  handle
}

///|
pub fn produce_original_metadata(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.original_metadata.get(handle) is Some(record) else {
    return -2
  }
  if value.closing || value.runtime_closing || record.output_closed {
    return -5
  }
  if record.kind == MOCK_EFFECT_SOURCE_CAPTURE_KIND {
    return advance_original_project_capture(value, handle, record)
  }
  if record.produced {
    return if record.kind == MOCK_EFFECT_WAITING_KIND {
      confirm_original_mock_effect_waiting(value, record)
    } else {
      0
    }
  }
  if record.kind == MOCK_EFFECT_SOURCE_EVIDENCE_KIND ||
    record.kind == MOCK_EFFECT_COMPUTE_KIND {
    return produce_original_mock_effect_work(value, record)
  }
  if record.kind == MOCK_EFFECT_WAITING_KIND &&
    record.project is Some(MockEffectWaiting(waiting)) {
    let code = advance_original_mock_effect_waiting(value, record, waiting)
    if code == 0 {
      record.produced = true
    }
    return code
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(value) => value
    Err(issue) => return issue_code(issue)
  }
  if record.kind == LOCAL_CSV_OFFER_KIND ||
    record.kind == LOCAL_CSV_RESPONSE_KIND {
    guard @buffers.filled_payload_input_bytes(value.pool, borrow) is Some(wire) else {
      return -31
    }
    return if record.kind == LOCAL_CSV_OFFER_KIND {
      produce_sdk_local_csv_offer(value, handle, record, wire)
    } else {
      produce_sdk_local_csv_response(value, record, wire)
    }
  }
  if record.kind == MOCK_EFFECT_WAITING_KIND {
    let code = prepare_original_mock_effect_waiting(value, record, borrow)
    if code == 0 {
      record.produced = true
    }
    return code
  }
  if record.kind == MOCK_EFFECT_WAITING_FIELD_KIND {
    let code = produce_original_mock_effect_waiting_field(value, record, borrow)
    if code == 0 {
      record.produced = true
    }
    return code
  }
  if record.kind == MOCK_EFFECT_CHECKPOINT_CONFIRM_KIND {
    let code = confirm_original_mock_effect_checkpoint(value, record, borrow)
    if code == 0 {
      record.produced = true
    }
    return code
  }
  if record.kind == MOCK_EFFECT_REVIEW_READ_KIND ||
    record.kind == MOCK_EFFECT_REVIEW_EXTENT_KIND {
    let code = produce_original_mock_effect_review_part(value, record, borrow)
    if code == 0 {
      record.produced = true
    }
    return code
  }
  if record.kind == 6 {
    let result = prepare_original_project_inputs(
      value,
      record,
      handle,
      borrow.slot,
    )
    if result == 0 {
      record.produced = true
    }
    return result
  }
  if record.kind == 7 {
    let result = prepare_original_project_check(value, record, borrow.slot)
    if result == 0 {
      record.produced = true
    }
    return result
  }
  if record.kind == 8 {
    return attach_original_mock_project_data(value, record, borrow)
  }
  if record.kind == 11 || record.kind == 12 || record.kind == 13 {
    let code = match record.kind {
      11 =>
        prepare_original_project_model_registry(
          value,
          record,
          handle,
          borrow.slot,
        )
      12 =>
        prepare_original_project_model_task(value, record, handle, borrow.slot)
      _ =>
        prepare_original_project_model_http_task(
          value,
          record,
          handle,
          borrow.slot,
        )
    }
    if code == 0 {
      record.produced = true
    }
    return code
  }
  let keys = match record.kind {
    1 =>
      [
        "account", "settings", "nonce", "parent_device", "parent_inode", "root_device",
        "root_inode", "source_root_device", "source_root_inode", "source_device",
        "source_inode", "source_size", "source_file", "source_path", "state_name",
      ]
    2 => ["initialization", "device", "inode", "size"]
    3 => ["initialization", "configuration_custody", "device", "inode"]
    4 => ["files", "managed_root"]
    5 => ["configuration", "profile"]
    _ => return -3
  }
  guard input_cursor(value, borrow.slot) is Some(cursor) &&
    @decode.closed_object(cursor, keys) is Ok(object) else {
    return -31
  }
  let body = match record.kind {
    1 => original_initialization_body(object).unwrap_or_else(() => b"")
    2 | 3 => {
      guard required_text(object, "initialization") is Some(initialization) &&
        original_metadata_uint(object, "device") is Some(device) &&
        original_metadata_uint(object, "inode") is Some(inode) else {
        return -31
      }
      let result = if record.kind == 2 {
        guard original_metadata_size(object, "size") is Some(size) else {
          return -31
        }
        @host.client_local_configuration_custody_body(
          @utf8.encode(initialization),
          (device, inode, size),
        )
      } else {
        guard required_text(object, "configuration_custody") is Some(custody) else {
          return -31
        }
        @host.client_local_journal_custody_body(
          @utf8.encode(initialization),
          @utf8.encode(custody),
          (device, inode),
        )
      }
      match result {
        Ok(body) => body
        Err(_) => return -31
      }
    }
    4 => original_configuration_selection_body(object).unwrap_or_else(() => b"")
    5 => {
      guard prepare_original_project_configuration(object) is Some(project) else {
        return -31
      }
      // Retain before the fallible encoding/copy, including on failure.
      record.project = Some(Selection(project))
      original_project_configuration_body(project).unwrap_or_else(() => b"")
    }
    _ => return -3
  }
  if body.is_empty() {
    return -31
  }
  let wire = try {
    let writer = @encode.writer(65536, 8, 2)
    @encode.begin_object(writer)
    @encode.key(writer, "body")
    @encode.string_value(writer, @utf8.decode(body))
    @encode.key(writer, "cid")
    @encode.string_value(writer, "sha256:" + @sha.hex(body))
    @encode.end_object(writer)
    @utf8.encode(@encode.finish(writer))
  } catch {
    _ => return -34
  }
  let retains_only_wire = record.kind >= 1 && record.kind <= 4
  let result = status(
    @buffers.supply_buffer_output(
      value.pool,
      record.slot,
      wire,
      // The Profile’s original Selection and input stay live. Its output
      // keeps only the transfer capacity for the immutable bytes just built.
      exact_vm_transfer=retains_only_wire || record.kind == 5,
    ),
  )
  if result != 0 {
    return result
  }
  // These four codecs retain only their independently encoded output. The
  // original input, parser and temporary construction tree have no consumer
  // after the output owns its bytes. Project roles keep their existing loans.
  if retains_only_wire {
    let returned = status(@buffers.return_buffer_borrow(value.pool, borrow))
    if returned != 0 {
      return returned
    }
    record.input = 0
  }
  record.produced = true
  0
}

///|
pub fn original_metadata_length(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.original_metadata.get(handle) is Some(record) &&
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
pub fn close_original_metadata(nonce : Int64, handle : Int) -> Int {
  guard selected(nonce) is Some(value) &&
    value.original_metadata.get(handle) is Some(record) else {
    return -2
  }
  if record.kind == MOCK_EFFECT_WAITING_KIND &&
    value.original_metadata
    .values()
    .any(child => {
      child.project is Some(MockEffectWaitingField(owner)) && owner == handle
    }) {
    return -9
  }
  if record.kind == 7 &&
    (
      value.client_checks.values().any(check => check.environment == handle) ||
      value.preparations.values().any(request => request.environment == handle)
    ) {
    return -9
  }
  if record.kind == 6 &&
    value.original_metadata
    .values()
    .any(child => {
      match child.project {
        Some(PreparingProjectCheck(held))
        | Some(MockCheck(held))
        | Some(LocalCheck(held))
        | Some(PortableModelCheck(held)) => held.project == handle
        _ => false
      }
    }) {
    return -9
  }
  if record.kind == 6 &&
    (
      value.bootstraps
      .values()
      .any(child => {
        match child.project {
          Some(MockBootstrapProject(original, _))
          | Some(FileBootstrapProject(original)) => original == handle
          Some(ProtectedAccountBootstrap(_)) | None => false
        }
      }) ||
      value.run_configurations
      .values()
      .any(config => {
        config.mock_project == Some(handle) ||
        config.local_project == Some(handle)
      })
    ) {
    return -9
  }
  if record.kind == 5 &&
    value.original_metadata
    .values()
    .any(child => {
      match child.project {
        Some(ProjectInputsPending(original))
        | Some(LocalInputs(original))
        | Some(MockInputs(original)) => original.parent == handle
        Some(ModelRegistry(original)) => original.parent == handle
        _ => false
      }
    }) {
    return -9
  }
  if (
      record.kind == MOCK_EFFECT_SOURCE_CAPTURE_KIND ||
      record.kind == LOCAL_CSV_OFFER_KIND
    ) &&
    value.original_metadata
    .values()
    .any(child => {
      match child.project {
        Some(LocalCsvOffer(parent)) | Some(LocalCsvResponse(parent)) =>
          parent == handle
        _ => false
      }
    }) {
    return -9
  }
  if record.kind == 11 &&
    value.original_metadata
    .values()
    .any(child => {
      match child.project {
        Some(ModelTask(held)) => held.parent == handle
        Some(LocalInputs(held)) =>
          held.local_inputs is Some(file_inputs) &&
          file_inputs.model_registry == Some(handle)
        _ => false
      }
    }) {
    return -9
  }
  if record.kind == 13 &&
    (
      value.run_configurations
      .values()
      .any(configuration => {
        configuration.sdk is Some({ portable_model: Some(original), .. }) &&
        original == handle
      }) ||
      value.original_metadata
      .values()
      .any(child => {
        child.project is Some(PortableModelCheck(held)) &&
        held.project == handle
      })
    ) {
    return -9
  }
  if record.kind == 12 &&
    value.original_metadata
    .values()
    .any(child => {
      child.project is Some(ModelHttpTask(held)) && held.parent == handle
    }) {
    return -9
  }
  let closed_model = match record.project {
    Some(ModelRegistry(registry)) =>
      close_original_project_model_registry(value, registry)
    Some(ModelTask(task)) => close_original_project_model_task(value, task)
    Some(ModelHttpTask(task)) =>
      close_original_project_model_http_task(value, task)
    _ => 0
  }
  if closed_model != 0 {
    return closed_model
  }
  if record.project is Some(ModelRegistry(_) | ModelTask(_) | ModelHttpTask(_)) {
    record.project = None
  }
  if record.project is Some(MockEffectCapture(capture)) {
    let code = close_original_mock_effect_capture(value, capture)
    if code != 0 {
      return code
    }
    record.project = None
  }
  if record.project is Some(FileCapture(capture)) {
    if value.physical_starts.get(capture.start)
      is Some({ model_file: Some(work), .. }) {
      if work.source.capture != Some(handle) ||
        value.computes.contains(work.compute_handle) {
        return -9
      }
    } else {
      let retired = retire_sdk_file_capture_work(value, capture.start, handle)
      if retired != 0 {
        return retired
      }
    }
    let csv = retire_sdk_local_csv_read(value, capture.start, handle)
    if csv != 0 {
      return csv
    }
    let code = close_original_mock_effect_capture(value, capture)
    if code != 0 {
      return code
    }
    record.project = None
  }
  if !record.output_closed {
    let result = status(@buffers.close_buffer(value.pool, record.slot))
    if result != 0 {
      return result
    }
    record.output_closed = true
  }
  let result = match record.borrow {
    Ok(borrow) => status(@buffers.return_buffer_borrow(value.pool, borrow))
    Err(_) => 0
  }
  if result == 0 {
    match record.project {
      Some(Selection(project)) =>
        match @host.retire_client_project_profile(project.selection) {
          Ok(_) => record.project = None
          Err(_) => return -31
        }
      Some(ProjectInputsPending(original))
      | Some(LocalInputs(original))
      | Some(MockInputs(original)) => {
        original.inputs = None
        original.local_inputs = None
        while original.documents.last() is Some(document) {
          let closed = status(
            @buffers.return_buffer_borrow(value.pool, document),
          )
          if closed != 0 {
            return closed
          }
          ignore(original.documents.pop())
        }
        // Keep the same parent and token on an unacknowledged settlement.
        original.data_body = None
        if original.data is Some(data) {
          let closed = status(@buffers.return_buffer_borrow(value.pool, data))
          if closed != 0 {
            return closed
          }
          original.data = None
        }
        match @resources.settle_capacity(value.root, original.capacity) {
          Ok(_) => record.project = None
          Err(_) => return -4
        }
      }
      Some(PreparingProjectCheck(held))
      | Some(MockCheck(held))
      | Some(LocalCheck(held))
      | Some(PortableModelCheck(held)) => {
        held.local_file = None
        held.prepared_publication = None
        held.environment = None
        held.write_targets.clear()
        guard @resources.settle_capacity(value.root, held.capacity) is Ok(_) else {
          return -4
        }
        record.project = None
      }
      Some(MockEffectWaiting(waiting)) => {
        if @resources.settle_capacity(waiting.ledger, waiting.capacity)
          is Err(_) {
          return -4
        }
        record.project = None
      }
      Some(MockEffectCapture(_))
      | Some(FileCapture(_))
      | Some(MockEffectReviewRead(_))
      | Some(MockEffectWaitingField(_))
      | Some(LocalCsvOffer(_))
      | Some(LocalCsvResponse(_))
      | Some(ModelRegistry(_))
      | Some(ModelTask(_))
      | Some(ModelHttpTask(_))
      | None => ()
    }
    value.original_metadata.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
