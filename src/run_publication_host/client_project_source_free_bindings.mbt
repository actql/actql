///|
/// Admitted project declaration facts only. This is not a CheckEnvironment,
/// installed Source/Model, Account decision, physical grant, or Run permission.
struct ClientSourceFreeProjectBindings {
  connectors_present : Bool
  model_tasks_present : Bool
}

///|
pub(all) enum ClientProjectBindingsIssue {
  InvalidBindings
  BindingsUnavailable
} derive(Eq, Debug)

///|
fn project_bindings_object(
  wire : String,
  fields : Array[String],
) -> Result[@decode.ObjectView, ClientProjectBindingsIssue] {
  let parsed = match
    @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 65536,
      max_nodes: 4096,
      max_depth: 16,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidBindings)
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: 4096,
      max_depth: 16,
      max_string_bytes: 65536,
      max_total_string_bytes: 65536,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidBindings)
  }
  @decode.closed_object(root, fields).map_err(_ => InvalidBindings)
}

///|
fn project_bindings_empty_object(
  object : @decode.ObjectView,
  field : String,
) -> Result[Unit, ClientProjectBindingsIssue] {
  guard @decode.lookup(object, field) is Some(value) &&
    @decode.object_length(value) is Some(count) else {
    return Err(InvalidBindings)
  }
  if count != 0 {
    return Err(BindingsUnavailable)
  }
  Ok(())
}

///|
/// Admit the empty public declarations used by an initialized plain project.
/// Nonempty declarations need their actual connector/model assembler; they
/// cannot fall back to the packaged source-free profile. The existing installed
/// Host separately admits and restores its own original environment and policy.
pub fn admit_client_source_free_project_bindings(
  connectors : String?,
  model_tasks : String?,
) -> Result[ClientSourceFreeProjectBindings, ClientProjectBindingsIssue] {
  if connectors is Some(wire) {
    let object = match
      project_bindings_object(wire, ["version", "connections"]) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard @decode.lookup(object, "version") is Some(value) &&
      @decode.text(value) == Ok("actql-connectors/0.1") else {
      return Err(InvalidBindings)
    }
    match project_bindings_empty_object(object, "connections") {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  if model_tasks is Some(wire) {
    let object = match
      project_bindings_object(wire, [
        "version", "tasks", "providers", "default_provider",
      ]) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    guard @decode.lookup(object, "version") is Some(value) &&
      @decode.text(value) == Ok("actql-model-tasks/0.1") else {
      return Err(InvalidBindings)
    }
    if @decode.field(object, "default_provider") is Present(value) {
      guard project_configuration_text(value) is Some(_) else {
        return Err(InvalidBindings)
      }
      return Err(BindingsUnavailable)
    } else if @decode.field(object, "default_provider") is ExplicitNull {
      return Err(InvalidBindings)
    }
    for field in ["tasks", "providers"] {
      match project_bindings_empty_object(object, field) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    }
  }
  Ok({
    connectors_present: connectors is Some(_),
    model_tasks_present: model_tasks is Some(_),
  })
}

///|
pub fn ClientSourceFreeProjectBindings::has_connectors_file(
  self : Self,
) -> Bool {
  self.connectors_present
}

///|
pub fn ClientSourceFreeProjectBindings::has_model_tasks_file(
  self : Self,
) -> Bool {
  self.model_tasks_present
}
