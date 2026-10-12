///|
// Inspect only already admitted descriptor bytes. A component comparison is
// not physical installation evidence, adoption custody or current permission.
fn runtime_component_value(
  runtime : ClientNativeLocalRuntime,
) -> Result[@canonical.CanonicalValue, ClientNativeLocalRuntimeIssue] {
  let source = match
    @source.parse_json_bytes_preserving(@utf8.encode(runtime.wire), {
      max_input_bytes: 65536,
      max_nodes: 8192,
      max_depth: 64,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidManifest)
  }
  Ok(@canonical.from_source(source, 8192, 64, 65536)) catch {
    _ => Err(InvalidManifest)
  }
}

///|
fn runtime_component_json(
  value : @canonical.CanonicalValue,
) -> Result[String, ClientNativeLocalRuntimeIssue] {
  try {
    let writer = @encode.writer(65536, 8192, 64)
    @canonical.emit_value(value, writer)
    Ok(@encode.finish(writer))
  } catch {
    _ => Err(CapacityExceeded)
  }
}

///|
// Every path is unique under the existing runtime reader. Match by original
// member identity rather than array position; no missing entry is inferred.
fn runtime_component_set(
  root : @canonical.CanonicalValue,
  category : String,
) -> Result[Map[String, String], ClientNativeLocalRuntimeIssue] {
  guard @canonical.object_field(root, category) is Some(@canonical.Array(array)) else {
    return Err(InvalidManifest)
  }
  let entries : Map[String, String] = Map([])
  for value in @canonical.array_values(array) {
    guard @canonical.object_field(value, "path")
      is Some(@canonical.String(path)) else {
      return Err(InvalidMember)
    }
    if entries.contains(path) {
      return Err(InvalidMember)
    }
    let body = match runtime_component_json(value) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    entries[path] = body
  }
  Ok(entries)
}

///|
fn validate_runtime_component_sets(
  original : ClientNativeLocalRuntime,
  current : ClientNativeLocalRuntime,
  categories : Array[String],
) -> Result[Unit, ClientNativeLocalRuntimeIssue] {
  if original.platform != current.platform {
    return Err(InvalidIdentity)
  }
  let before = match runtime_component_value(original) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let after = match runtime_component_value(current) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  for category in categories {
    let old_entries = match runtime_component_set(before, category) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let current_entries = match runtime_component_set(after, category) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if old_entries.length() != current_entries.length() {
      return Err(InvalidClosure)
    }
    for path, body in old_entries {
      if current_entries.get(path) != Some(body) {
        return Err(InvalidClosure)
      }
    }
  }
  Ok(())
}

///|
/// Compare the declared physical component closure, including exact paths,
/// bytes, hashes, roles, dependency lists, licenses and ABI descriptors. This
/// does not observe files or permit replacing an original installation path.
/// Source identity remains separate from these bounded descriptor facts.
pub fn validate_client_native_local_runtime_library_components(
  original : ClientNativeLocalRuntime,
  current : ClientNativeLocalRuntime,
) -> Result[Unit, ClientNativeLocalRuntimeIssue] {
  validate_runtime_component_sets(original, current, ["libraries", "licenses"])
}

///|
/// Require exact declared compute assets independently of library agreement.
/// Changed contracts or asset bytes remain a refusal, including an unchanged
/// manifest version or two valid but different dependency closures. This is
/// metadata validation, not compatibility authority for a narrowed profile.
pub fn validate_client_native_local_runtime_compute_components(
  original : ClientNativeLocalRuntime,
  current : ClientNativeLocalRuntime,
) -> Result[Unit, ClientNativeLocalRuntimeIssue] {
  validate_runtime_component_sets(original, current, ["assets"])
}
