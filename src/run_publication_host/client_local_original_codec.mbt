///|
pub(all) enum ClientLocalOriginalCodecIssue {
  Encoding
  InvalidOriginal
  ConfigurationLimit
} derive(Eq, Debug)

///|
/// Pure encoding of the existing ordered Local custody preimages.
/// Raw bodies are metadata, not adopted/current evidence or an Allow decision.
pub fn client_local_original_record_body(
  fields : Array[(String, String)],
) -> Result[Bytes, ClientLocalOriginalCodecIssue] {
  let writer = @encode.writer(8192, 64, 4) catch { _ => return Err(Encoding) }
  try {
    @encode.begin_object(writer)
    for field in fields {
      @encode.key(writer, field.0)
      @encode.string_value(writer, field.1)
    }
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Decode only the original closed, canonically ordered raw string fields.
/// This preserves Native's limits and rejects normalized or repaired copies.
pub fn client_local_original_record_fields(
  body : Bytes,
  keys : Array[String],
) -> Result[Array[String], ClientLocalOriginalCodecIssue] {
  let value = match
    @source.parse_json_bytes_preserving(body, {
      max_input_bytes: 8192,
      max_nodes: 64,
      max_depth: 4,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  let cursor = match
    @decode.admit(value, {
      max_nodes: 64,
      max_depth: 4,
      max_string_bytes: 4096,
      max_total_string_bytes: 8192,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  let object = match @decode.closed_object(cursor, keys) {
    Ok(value) => value
    Err(_) => return Err(InvalidOriginal)
  }
  let fields : Array[String] = []
  for key in keys {
    guard @decode.lookup(object, key) is Some(value) &&
      @decode.text(value) is Ok(text) else {
      return Err(InvalidOriginal)
    }
    fields.push(text)
  }
  let encoded = match
    client_local_original_record_body(keys.mapi((i, key) => (key, fields[i]))) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if encoded != body {
    return Err(InvalidOriginal)
  }
  Ok(fields)
}

///|
/// Original selected-file facts; neither a filename nor a CID grants access.
pub(all) struct ClientLocalOriginalConfigurationFile {
  content_cid : String
  device : UInt64
  inode : UInt64
  name : String
  size : Int64
}

///|
pub(all) struct ClientLocalOriginalManagedRoot {
  device : UInt64
  inode : UInt64
  path : String
}

///|
/// Encode the original Native selection order and domain without doing I/O.
/// The Host's existing selection Owner validates names, pins files and roots,
/// and retains exact bytes. This codec cannot establish those physical facts.
pub fn client_local_configuration_selection_body(
  files : Array[ClientLocalOriginalConfigurationFile],
  managed : ClientLocalOriginalManagedRoot?,
) -> Result[Bytes, ClientLocalOriginalCodecIssue] {
  // The original ten selections plus the distinct initialized Host file.
  // This is one additional physical original, not a resource allowance.
  if files.length() > 11 ||
    (files.length() == 11 && !files.any(file => file.name == "host.json")) {
    return Err(ConfigurationLimit)
  }
  let writer = @encode.writer(8192, 128, 4) catch { _ => return Err(Encoding) }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "files")
    @encode.begin_array(writer)
    for file in files {
      @encode.begin_object(writer)
      @encode.key(writer, "content_cid")
      @encode.string_value(writer, file.content_cid)
      @encode.key(writer, "device")
      @encode.string_value(writer, file.device.to_string())
      @encode.key(writer, "inode")
      @encode.string_value(writer, file.inode.to_string())
      @encode.key(writer, "name")
      @encode.string_value(writer, file.name)
      @encode.key(writer, "size")
      @encode.string_value(writer, file.size.to_string())
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "managed_root")
    match managed {
      None => @encode.null_value(writer)
      Some(root) => {
        @encode.begin_object(writer)
        @encode.key(writer, "device")
        @encode.string_value(writer, root.device.to_string())
        @encode.key(writer, "inode")
        @encode.string_value(writer, root.inode.to_string())
        @encode.key(writer, "path")
        @encode.string_value(writer, root.path)
        @encode.end_object(writer)
      }
    }
    @encode.key(writer, "version")
    @encode.string_value(
      writer, "actql-native-local-configuration-selection/0.1",
    )
    @encode.end_object(writer)
    Ok(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => Err(Encoding)
  }
}
