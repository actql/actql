///|
/// Pure original-codec invocation and buffer loans only; never adoption state.
priv struct StoredOriginalMetadata {
  input : Int
  kind : Int
  borrow : Result[@buffers.BufferBorrow, @buffers.BufferIssue]
  slot : @buffers.BufferSlot
  mut invoked : Bool
  mut produced : Bool
  mut output_closed : Bool
  mut project : StoredProjectConfiguration?
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
    array.length() <= 8 else {
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
  if kind < 1 ||
    kind > 5 ||
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
  let slot = match
    @buffers.reserve_output_buffer(value.pool, 65536, physical_copy_bytes, () => {
      physical_input_cleanup(physical_ticket) == 0
    }) {
    Ok(slot) => slot
    Err(issue) => return issue_code(issue)
  }
  let handle = value.next_handle
  let borrow = @buffers.borrow_buffer(value.pool, input_slot, () => {
    physical_reader_stop(physical, handle) == 0
  })
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
  if record.produced {
    return 0
  }
  if record.invoked {
    return -33
  }
  record.invoked = true
  let borrow = match record.borrow {
    Ok(value) => value
    Err(issue) => return issue_code(issue)
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
      record.project = Some(project)
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
  let result = status(
    @buffers.supply_buffer_output(value.pool, record.slot, wire),
  )
  if result == 0 {
    record.produced = true
  }
  result
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
    if record.project is Some(project) {
      match @host.retire_client_project_profile(project.selection) {
        Ok(_) => record.project = None
        Err(_) => return -31
      }
    }
    value.original_metadata.remove(handle) |> ignore
    value.copies.remove(handle) |> ignore
  }
  result
}
