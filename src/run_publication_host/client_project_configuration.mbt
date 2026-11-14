///|
/// Project locators only. These values neither capture installation originals
/// nor admit a Program, resolve a credential, or authorize an operation.
struct ClientProjectConfiguration {
  connectors : String?
  model_tasks : String?
  lock : String?
  state_dir : String
  profile : String?
  mock_catalog : String?
  mock_data : String?
  mock_answers : Array[(String, String)]
}

///|
pub(all) enum ClientProjectConfigurationIssue {
  InvalidConfiguration
} derive(Eq, Debug)

///|
fn project_configuration_text(value : @decode.Cursor) -> String? {
  match @decode.text(value) {
    Ok(text) if !text.is_empty() && !text.contains("\u{0000}") => Some(text)
    _ => None
  }
}

///|
fn project_configuration_optional_text(
  object : @decode.ObjectView,
  key : String,
) -> Result[String?, ClientProjectConfigurationIssue] {
  match @decode.field(object, key) {
    Missing => Ok(None)
    Present(value) =>
      match project_configuration_text(value) {
        Some(text) => Ok(Some(text))
        None => Err(InvalidConfiguration)
      }
    ExplicitNull => Err(InvalidConfiguration)
  }
}

///|
/// Read the public project shape through the existing strict source/decoder
/// Owners. The limits are intake bounds, not physical funding or permission.
/// Locators remain relative to the selected configuration file; this reader
/// performs no path resolution, file access, environment lookup or mutation.
pub fn admit_client_project_configuration(
  wire : String,
) -> Result[ClientProjectConfiguration, ClientProjectConfigurationIssue] {
  let root = match project_metadata_cursor(@utf8.encode(wire)) {
    Ok(value) => value
    Err(_) => return Err(InvalidConfiguration)
  }
  let object = match
    @decode.closed_object(root, [
      "version", "connectors", "model_tasks", "lock", "state_dir", "profile", "mock",
    ]) {
    Ok(value) => value
    Err(_) => return Err(InvalidConfiguration)
  }
  guard @decode.lookup(object, "version") is Some(version) &&
    @decode.text(version) == Ok("actql-config/0.1") else {
    return Err(InvalidConfiguration)
  }
  let connectors = match
    project_configuration_optional_text(object, "connectors") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let model_tasks = match
    project_configuration_optional_text(object, "model_tasks") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let lock = match project_configuration_optional_text(object, "lock") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let state_dir = match
    project_configuration_optional_text(object, "state_dir") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let profile = match project_configuration_optional_text(object, "profile") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let mut mock_catalog = None
  let mut mock_data = None
  let mock_answers : Array[(String, String)] = []
  match @decode.field(object, "mock") {
    Missing => ()
    ExplicitNull => return Err(InvalidConfiguration)
    Present(value) => {
      let mock = match
        @decode.closed_object(value, ["catalog", "data", "answers"]) {
        Ok(value) => value
        Err(_) => return Err(InvalidConfiguration)
      }
      mock_catalog = match
        project_configuration_optional_text(mock, "catalog") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      mock_data = match project_configuration_optional_text(mock, "data") {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match @decode.field(mock, "answers") {
        Missing => ()
        ExplicitNull => return Err(InvalidConfiguration)
        Present(answers) => {
          guard @decode.object_length(answers) is Some(count) else {
            return Err(InvalidConfiguration)
          }
          for index in 0..<count {
            guard @decode.field_at(answers, index) is Some((task, value)) &&
              !task.is_empty() &&
              !task.contains("\u{0000}") &&
              project_configuration_text(value) is Some(path) else {
              return Err(InvalidConfiguration)
            }
            mock_answers.push((task, path))
          }
        }
      }
    }
  }
  Ok({
    connectors,
    model_tasks,
    lock,
    state_dir: state_dir.unwrap_or("./.actql"),
    profile,
    mock_catalog,
    mock_data,
    mock_answers,
  })
}

///|
pub fn ClientProjectConfiguration::connectors_file(self : Self) -> String? {
  self.connectors
}

///|
pub fn ClientProjectConfiguration::model_tasks_file(self : Self) -> String? {
  self.model_tasks
}

///|
pub fn ClientProjectConfiguration::lock_file(self : Self) -> String? {
  self.lock
}

///|
pub fn ClientProjectConfiguration::state_directory(self : Self) -> String {
  self.state_dir
}

///|
pub fn ClientProjectConfiguration::selected_profile(self : Self) -> String? {
  self.profile
}

///|
pub fn ClientProjectConfiguration::mock_catalog_file(self : Self) -> String? {
  self.mock_catalog
}

///|
pub fn ClientProjectConfiguration::mock_data_file(self : Self) -> String? {
  self.mock_data
}

///|
pub fn ClientProjectConfiguration::mock_answer_count(self : Self) -> Int {
  self.mock_answers.length()
}

///|
pub fn ClientProjectConfiguration::mock_answer_at(
  self : Self,
  index : Int,
) -> (String, String)? {
  if index < 0 || index >= self.mock_answers.length() {
    None
  } else {
    Some(self.mock_answers[index])
  }
}
