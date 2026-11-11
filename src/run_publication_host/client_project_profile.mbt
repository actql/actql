///|
/// One original project/profile choice in the existing configuration Owner.
/// This is not a Connector, Model registration, permission or funding issuer.
/// The installed Host still binds physical configuration/currentness and must
/// actually install the selected profile before accepting execution.
struct ClientProjectProfileSelection {
  mut original : ClientProjectProfileSelection?
  mut configuration : ClientProjectConfiguration?
  mut requested : String?
  mut selected : String?
}

///|
pub(all) enum ClientProjectProfileIssue {
  InvalidLimits
  InvalidProfile
  WorkLimit
  ForeignOriginal
  Retired
} derive(Eq, Debug)

///|
/// An explicit choice overrides the same original project's default. No name
/// is normalized, inferred from a path, or translated into execution authority.
/// The work bound applies to inspecting the requested String before retention.
pub fn select_client_project_profile(
  configuration : ClientProjectConfiguration?,
  requested : String?,
  max_work : Int,
) -> Result[ClientProjectProfileSelection, ClientProjectProfileIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if requested is Some(value) {
    if value.length() > max_work {
      return Err(WorkLimit)
    }
    if value.is_empty() || value.contains("\u{0000}") {
      return Err(InvalidProfile)
    }
  }
  let selected = match requested {
    Some(_) => requested
    None =>
      match configuration {
        Some(value) => value.selected_profile()
        None => None
      }
  }
  let result : ClientProjectProfileSelection = {
    original: None,
    configuration,
    requested,
    selected,
  }
  result.original = Some(result)
  Ok(result)
}

///|
fn ClientProjectProfileSelection::require_original(
  self : Self,
) -> Result[Unit, ClientProjectProfileIssue] {
  guard self.original is Some(original) else { return Err(Retired) }
  if physical_equal(original, self) {
    Ok(())
  } else {
    Err(ForeignOriginal)
  }
}

///|
/// Same nominal project and original override, not equal reconstructed DATA.
/// Absence is an explicit original absence, not permission to infer a project.
pub fn client_project_profile_matches(
  selection : ClientProjectProfileSelection,
  configuration : ClientProjectConfiguration?,
  requested : String?,
) -> Bool {
  if selection.require_original() is Err(_) || selection.requested != requested {
    return false
  }
  match (selection.configuration, configuration) {
    (None, None) => true
    (Some(original), Some(candidate)) => physical_equal(original, candidate)
    _ => false
  }
}

///|
pub fn ClientProjectProfileSelection::selected_profile(
  self : Self,
) -> Result[String?, ClientProjectProfileIssue] {
  self.require_original().map(_ => self.selected)
}

///|
/// Mock locators are visible only under this original mock choice. They do
/// not supply records, answers, Contracts, currentness or resource coverage.
pub fn ClientProjectProfileSelection::mock_catalog_file(
  self : Self,
) -> Result[String?, ClientProjectProfileIssue] {
  match self.require_original() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.selected != Some("mock") {
    return Ok(None)
  }
  Ok(
    match self.configuration {
      Some(value) => value.mock_catalog_file()
      None => None
    },
  )
}

///|
pub fn ClientProjectProfileSelection::mock_data_file(
  self : Self,
) -> Result[String?, ClientProjectProfileIssue] {
  match self.require_original() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.selected != Some("mock") {
    return Ok(None)
  }
  Ok(
    match self.configuration {
      Some(value) => value.mock_data_file()
      None => None
    },
  )
}

///|
pub fn ClientProjectProfileSelection::mock_answer_count(
  self : Self,
) -> Result[Int, ClientProjectProfileIssue] {
  match self.require_original() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.selected != Some("mock") {
    return Ok(0)
  }
  Ok(self.configuration.map(value => value.mock_answer_count()).unwrap_or(0))
}

///|
pub fn ClientProjectProfileSelection::mock_answer_at(
  self : Self,
  index : Int,
) -> Result[(String, String)?, ClientProjectProfileIssue] {
  match self.require_original() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if self.selected != Some("mock") {
    return Ok(None)
  }
  Ok(
    match self.configuration {
      Some(value) => value.mock_answer_at(index)
      None => None
    },
  )
}

///|
/// Existing installation retirement only. Drop managed original references;
/// this is not a physical close, GC, Run cleanup or capacity-release ACK.
pub fn retire_client_project_profile(
  selection : ClientProjectProfileSelection,
) -> Result[Unit, ClientProjectProfileIssue] {
  match selection.require_original() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  selection.configuration = None
  selection.requested = None
  selection.selected = None
  selection.original = None
  Ok(())
}
