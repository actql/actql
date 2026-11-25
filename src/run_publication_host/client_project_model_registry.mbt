///|
/// Original project locators only. This snapshot is not a ModelTask, checked
/// Environment, provider registration, Account decision or execution grant.
struct ClientProjectModelRegistry {
  wire : String
  tasks : Array[(String, String)]
  providers : Array[(String, String, String?)]
  default_provider : String?
}

///|
// The original wire is already owned by the caller. Quoting borrows it and
// uses the caller's existing preparation control workspace.
fn client_project_model_registry_admission_inventory(
  wire : String,
) -> (@execution.PreparationRepresentationUnits, Int64)? {
  // The registry parser rejects according to its original input geometry. It
  // does not use the smaller Catalog and Connections projection profile.
  guard client_project_admission_geometry(wire, 2147483647, 2147483647)
    is Some((bytes, nodes, depth)) &&
    bytes > 0 else {
    return None
  }
  let nodes = Int::min(nodes, bytes)
  let n = nodes.to_int64()
  guard @decode.preserving_json_admission_construction_inventory(
      bytes, nodes, depth,
    )
    is Some(parser) &&
    @decode.closed_object_field_construction_extent(Some(nodes), 4, 0L)
    is Some(root) &&
    @decode.closed_object_field_construction_extent(Some(2), 2, 2L)
    is Some(provider) &&
    @decode.closed_object_field_construction_extent(Some(nodes), 2, 2L)
    is Some(provider_refusal) &&
    @decode.cursor_path_construction_extent(4L) is Some(field_refusal) &&
    @shape.reference_array_retained_extent(2L, n) is Some(registries) &&
    @shape.reference_array_retained_extent(n + 1L, 2L * n + 4L) is Some(allowed) else {
    return None
  }
  // Closed-object views and their allowed-key and lookup carriers cannot
  // escape through the Registry's typed String/tuple fields. Keep the full
  // parser text/byte inventory and the Registry arrays and tuple envelope.
  let scratch : @execution.PreparationRepresentationUnits = {
    record_headers: root.record_headers +
    provider_refusal.record_headers +
    field_refusal.record_headers +
    allowed.record_headers +
    provider.record_headers * n,
    reference_slots: root.reference_slots +
    provider_refusal.reference_slots +
    field_refusal.reference_slots +
    allowed.reference_slots +
    provider.reference_slots * n,
    scalar_words: root.scalar_words +
    provider_refusal.scalar_words +
    field_refusal.scalar_words +
    allowed.scalar_words +
    provider.scalar_words * n,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }
  guard @execution.preparation_representation_cost(scratch) is Some(returned) else {
    return None
  }
  // The arrays are allocated once from observed counts. Typed strings may
  // keep parser backing. Per-entry controls also cover field and lookup
  // cursors, optional text/presence results and the original tuples.
  Some(
    (
      {
        record_headers: parser.record_headers +
        registries.record_headers +
        scratch.record_headers +
        24L * n +
        24L,
        reference_slots: parser.reference_slots +
        registries.reference_slots +
        scratch.reference_slots +
        36L * n +
        32L,
        scalar_words: parser.scalar_words +
        registries.scalar_words +
        scratch.scalar_words +
        28L * n +
        24L,
        owned_utf16_units: parser.owned_utf16_units,
        owned_wire_bytes: bytes.to_int64(),
      },
      returned,
    ),
  )
}

///|
/// Admit the original registry after its current owner funds the constructor.
/// The caller funds the fixed quote and optional settlement controls before
/// entry. After successful return from the typed parser, it may return only
/// the identified closed-object workspace on that same reservation.
/// This uses the existing Common parser and preserves the funding refusal.
pub fn[E] admit_funded_client_project_model_registry(
  wire : String,
  prepare : (@execution.PreparationRepresentationUnits) -> Result[Unit, E],
  binding_issue : (ClientProjectBindingsIssue) -> E,
  settle? : ((Int64) -> Result[Unit, E])? = None,
) -> Result[ClientProjectModelRegistry, E] {
  guard client_project_model_registry_admission_inventory(wire)
    is Some((units, scratch)) else {
    return Err(binding_issue(InvalidBindings))
  }
  match prepare(units) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let admitted = admit_client_project_model_registry(wire).map_err(
    binding_issue,
  )
  if admitted is Ok(_) &&
    settle is Some(settle_original) &&
    settle_original(scratch) is Err(issue) {
    return Err(issue)
  }
  admitted
}

///|
/// Read every declaration, including unused tasks/providers, under the existing
/// project intake bounds. Paths remain relative to the original registry file;
/// no file, credential, environment variable or provider is accessed here.
pub fn admit_client_project_model_registry(
  wire : String,
) -> Result[ClientProjectModelRegistry, ClientProjectBindingsIssue] {
  let root = match
    project_bindings_object(wire, [
      "version", "tasks", "providers", "default_provider",
    ]) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.lookup(root, "version") is Some(version) &&
    @decode.text(version) == Ok("actql-model-tasks/0.1") else {
    return Err(InvalidBindings)
  }
  guard @decode.lookup(root, "tasks") is Some(task_map) &&
    @decode.object_length(task_map) is Some(task_count) &&
    @decode.lookup(root, "providers") is Some(provider_map) &&
    @decode.object_length(provider_map) is Some(provider_count) else {
    return Err(InvalidBindings)
  }
  // These are the exact entry counts of the already admitted objects.
  // Reserve each final array once before collecting its original fields.
  let tasks : Array[(String, String)] = Array(capacity=task_count)
  for index in 0..<task_count {
    guard @decode.field_at(task_map, index) is Some((name, path)) &&
      !name.is_empty() &&
      !name.contains("\u{0000}") &&
      project_configuration_text(path) is Some(path) else {
      return Err(InvalidBindings)
    }
    tasks.push((name, path))
  }
  let providers : Array[(String, String, String?)] = Array(
    capacity=provider_count,
  )
  for index in 0..<provider_count {
    guard @decode.field_at(provider_map, index) is Some((name, body)) &&
      !name.is_empty() &&
      !name.contains("\u{0000}") else {
      return Err(InvalidBindings)
    }
    let object = match @decode.closed_object(body, ["type", "api_key_env"]) {
      Ok(value) => value
      Err(_) => return Err(InvalidBindings)
    }
    guard @decode.lookup(object, "type") is Some(kind) &&
      project_configuration_text(kind) is Some(kind) else {
      return Err(InvalidBindings)
    }
    let key_env = match
      project_configuration_optional_text(object, "api_key_env") {
      Ok(value) => value
      Err(_) => return Err(InvalidBindings)
    }
    // A provider type is a locator, not an implementation allowlist. Only the
    // actual installed provider Owner can admit or refuse that implementation.
    providers.push((name, kind, key_env))
  }
  let default_provider = match
    project_configuration_optional_text(root, "default_provider") {
    Ok(value) => value
    Err(_) => return Err(InvalidBindings)
  }
  if default_provider is Some(selected) &&
    !providers.any(provider => provider.0 == selected) {
    return Err(InvalidBindings)
  }
  Ok({ wire, tasks, providers, default_provider, })
}

///|
/// Retain the original bytes for the existing Host configuration/material
/// binding. Reconstructed/equal DATA is never an installed original or grant.
pub fn ClientProjectModelRegistry::original_wire(self : Self) -> String {
  self.wire
}

///|
pub fn ClientProjectModelRegistry::task_count(self : Self) -> Int {
  self.tasks.length()
}

///|
pub fn ClientProjectModelRegistry::task_at(
  self : Self,
  index : Int,
) -> (String, String)? {
  self.tasks.get(index)
}

///|
pub fn ClientProjectModelRegistry::provider_count(self : Self) -> Int {
  self.providers.length()
}

///|
pub fn ClientProjectModelRegistry::provider_at(
  self : Self,
  index : Int,
) -> (String, String, String?)? {
  self.providers.get(index)
}

///|
pub fn ClientProjectModelRegistry::selected_default_provider(
  self : Self,
) -> String? {
  self.default_provider
}
