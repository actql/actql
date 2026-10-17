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
  let tasks : Array[(String, String)] = []
  for index in 0..<task_count {
    guard @decode.field_at(task_map, index) is Some((name, path)) &&
      !name.is_empty() &&
      !name.contains("\u{0000}") &&
      project_configuration_text(path) is Some(path) else {
      return Err(InvalidBindings)
    }
    tasks.push((name, path))
  }
  let providers : Array[(String, String, String?)] = []
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
