///|
/// A physical snapshot under the original dispatch responsibility. It grants
/// no current Site authority, start permission, borrow or capacity reservation.
struct NativeOutputFileCustody {
  request_cid : String
  occurrence : String
  generation : @filesystem.NativeFileGeneration
  content_cid : String
  material_generation : String
  manifest : @manifest.PhysicalManifest
}

///|
fn custody_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<71 {
    let unit = value[index]
    if !((unit >= '0' && unit <= '9') || (unit >= 'a' && unit <= 'f')) {
      return false
    }
  }
  true
}

///|
/// Called with the sealed writer's saved generation, never a fresh stat of
/// the current pathname. The common manifest is independently readmitted.
pub fn prepare_native_output_file_custody(
  request : @remote.DispatchRequest,
  occurrence : String,
  generation : @filesystem.NativeFileGeneration,
  content_cid : String,
  material_generation : String,
  manifest : @manifest.PhysicalManifest,
) -> Result[NativeOutputFileCustody, NativeRemoteJournalIssue] {
  if occurrence.is_empty() ||
    occurrence.length() > 121 ||
    !custody_cid(content_cid) ||
    generation.size < 0L ||
    generation.size != manifest.referenced_bytes {
    return Err(StateCollision)
  }
  for unit in occurrence.iter() {
    if !((unit >= 'a' && unit <= 'z') ||
      (unit >= 'A' && unit <= 'Z') ||
      (unit >= '0' && unit <= '9') ||
      unit == '-' ||
      unit == '_' ||
      unit == '.') {
      return Err(StateCollision)
    }
  }
  if @remote.remote_output_holding_evidence_cid(
      request,
      material_generation,
      generation.size,
    )
    is Err(_) {
    return Err(StateCollision)
  }
  let body = match @manifest.manifest_json(manifest) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let admitted = match
    @manifest.admit_json(
      body,
      @manifest.manifest_cid(manifest),
      manifest.chunks.length(),
      manifest.metadata_bytes,
      generation.size,
    ) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  Ok({
    request_cid: @remote.dispatch_request_identity(request),
    occurrence,
    generation,
    content_cid,
    material_generation,
    manifest: admitted,
  })
}

///|
pub fn native_output_file_custody_occurrence(
  custody : NativeOutputFileCustody,
) -> String {
  custody.occurrence
}

///|
pub fn native_output_file_custody_generation(
  custody : NativeOutputFileCustody,
) -> @filesystem.NativeFileGeneration {
  custody.generation
}

///|
pub fn native_output_file_custody_content_cid(
  custody : NativeOutputFileCustody,
) -> String {
  custody.content_cid
}

///|
pub fn native_output_file_custody_material_generation(
  custody : NativeOutputFileCustody,
) -> String {
  custody.material_generation
}

///|
pub fn native_output_file_custody_manifest(
  custody : NativeOutputFileCustody,
) -> @manifest.PhysicalManifest {
  custody.manifest
}

///|
pub fn native_output_file_custody_matches_request(
  custody : NativeOutputFileCustody,
  request : @remote.DispatchRequest,
) -> Bool {
  custody.request_cid == @remote.dispatch_request_identity(request)
}

///|
#warnings("-unused_value")
// Storage calls this only on Native; keep the value codec portable.
fn output_file_matches_subject(
  custody : NativeOutputFileCustody,
  subject : @remote.RemoteManagedOutputSubject,
) -> Bool {
  let values = @remote.remote_managed_output_subject_projection(subject)
  let manifest = custody.manifest
  values[0] == custody.request_cid &&
  values[1] == custody.material_generation &&
  values[4] == manifest.schema_contract_cid &&
  values[5] == manifest.view_contract_cid &&
  values[6] == manifest.codec_contract_cid &&
  values[7] == @manifest.manifest_cid(manifest) &&
  values[9] == manifest.row_count.to_string() &&
  values[10] == custody.generation.size.to_string()
}

///|
fn output_file_custody_json(
  custody : NativeOutputFileCustody,
) -> Result[String, NativeRemoteJournalIssue] {
  let manifest = match @manifest.manifest_json(custody.manifest) {
    Ok(value) => value
    Err(_) => return Err(StateCollision)
  }
  let fields = [
    ("content_cid", custody.content_cid),
    ("device", custody.generation.device.to_string()),
    ("inode", custody.generation.inode.to_string()),
    ("manifest_cid", @manifest.manifest_cid(custody.manifest)),
    ("manifest_json", manifest),
    ("material_generation", custody.material_generation),
    ("occurrence", custody.occurrence),
    ("request_cid", custody.request_cid),
    ("size", custody.generation.size.to_string()),
  ]
  // Every UTF-8 byte needs at most six JSON bytes when escaped. Include all
  // values, not just the manifest, and reject overflow before writer creation.
  let mut max_bytes = 256
  for field in fields {
    let bytes = @utf8.encode(field.1).length()
    if bytes > (2147483647 - max_bytes) / 6 {
      return Err(StateCollision)
    }
    max_bytes += bytes * 6
  }
  try {
    let writer = @encode.writer(max_bytes, 19, 1)
    @encode.begin_object(writer)
    for field in fields {
      @encode.key(writer, field.0)
      @encode.string_value(writer, field.1)
    }
    @encode.end_object(writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(StateCollision)
  }
}

///|
priv suberror OutputFileDecodeStop {
  Stop
}

///|
fn[T] output_file_decoded(
  value : Result[T, @decode.Issue],
) -> T raise OutputFileDecodeStop {
  match value {
    Ok(value) => value
    Err(_) => raise Stop
  }
}

///|
#warnings("-unused_value")
// Storage calls this only on Native; non-Native storage remains unsupported.
fn admit_output_file_custody(
  request : @remote.DispatchRequest,
  body : String,
) -> Result[NativeOutputFileCustody, NativeRemoteJournalIssue] {
  let bytes = @utf8.encode(body)
  try {
    let node = match
      @source.parse_json_bytes_preserving(bytes, {
        max_input_bytes: bytes.length(),
        max_nodes: 19,
        max_depth: 1,
      }) {
      Ok(value) => value
      Err(_) => raise Stop
    }
    let cursor = output_file_decoded(
      @decode.admit(node, {
        max_nodes: 19,
        max_depth: 1,
        max_string_bytes: bytes.length(),
        max_total_string_bytes: bytes.length(),
      }),
    )
    let names = [
      "content_cid", "device", "inode", "manifest_cid", "manifest_json", "material_generation",
      "occurrence", "request_cid", "size",
    ]
    let object = output_file_decoded(@decode.closed_object(cursor, names))
    let text = fn(name : String) -> String raise OutputFileDecodeStop {
      output_file_decoded(
        @decode.text(output_file_decoded(@decode.required(object, name))),
      )
    }
    if text("request_cid") != @remote.dispatch_request_identity(request) {
      raise Stop
    }
    let device = @string.parse_uint64(text("device"))
    let inode = @string.parse_uint64(text("inode"))
    let size = @string.parse_int64(text("size"))
    if device.to_string() != text("device") ||
      inode.to_string() != text("inode") ||
      size.to_string() != text("size") {
      raise Stop
    }
    let manifest_json = text("manifest_json")
    let manifest = match
      @manifest.admit_json(
        manifest_json,
        text("manifest_cid"),
        manifest_json.length() / 4,
        manifest_json.length(),
        size,
      ) {
      Ok(value) => value
      Err(_) => raise Stop
    }
    let custody = match
      prepare_native_output_file_custody(
        request,
        text("occurrence"),
        { device, inode, size, },
        text("content_cid"),
        text("material_generation"),
        manifest,
      ) {
      Ok(value) => value
      Err(_) => raise Stop
    }
    // Reject changed raw values and alternative decimal/canonical forms.
    match output_file_custody_json(custody) {
      Ok(encoded) if encoded == body => ()
      _ => raise Stop
    }
    Ok(custody)
  } catch {
    _ => Err(StateCollision)
  }
}
