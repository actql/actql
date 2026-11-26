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
// The caller already retains this exact input under its finite intake owner.
// Every JSON node and decoded text byte consumes at least one original wire
// byte. Use that observed Int-sized geometry without another parse/count walk
// or arithmetic expansion. These rejection bounds are not physical funding.
fn project_metadata_cursor(bytes : Bytes) -> Result[@decode.Cursor, Unit] {
  let bound = bytes.length()
  if bound <= 0 {
    return Err(())
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: bound,
      max_nodes: bound,
      max_depth: 16,
    }) {
    Ok(value) => value
    Err(_) => return Err(())
  }
  @decode.admit(parsed, {
    max_nodes: bound,
    max_depth: 16,
    max_string_bytes: bound,
    max_total_string_bytes: bound,
  }).map_err(_ => ())
}

///|
fn project_bindings_object(
  wire : String,
  fields : Array[String],
) -> Result[@decode.ObjectView, ClientProjectBindingsIssue] {
  let root = match project_metadata_cursor(@utf8.encode(wire)) {
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
  model_registry? : ClientProjectModelRegistry? = None,
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
  let selected = match (model_tasks, model_registry) {
    (None, original) => original
    (Some(wire), None) =>
      match admit_client_project_model_registry(wire) {
        Ok(original) => Some(original)
        Err(issue) => return Err(issue)
      }
    (Some(_), Some(_)) => return Err(InvalidBindings)
  }
  if selected is Some(registry) &&
    (
      registry.task_count() != 0 ||
      registry.provider_count() != 0 ||
      registry.selected_default_provider() is Some(_)
    ) {
    return Err(BindingsUnavailable)
  }
  Ok({
    connectors_present: connectors is Some(_),
    model_tasks_present: selected is Some(_),
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
