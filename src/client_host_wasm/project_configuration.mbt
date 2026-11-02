///|
/// Original project/profile metadata under the existing input loan. Locators
/// are DATA; they do not supply an installed Source, permission or capacity.
priv struct StoredProjectConfiguration {
  configuration : @host.ClientProjectConfiguration?
  requested : String?
  selection : @host.ClientProjectProfileSelection
}

///|
fn prepare_original_project_configuration(
  object : @decode.ObjectView,
) -> StoredProjectConfiguration? {
  let configuration = match @decode.lookup(object, "configuration") {
    Some(value) if @decode.is_null(value) => None
    Some(value) => {
      guard @decode.text(value) is Ok(wire) &&
        @host.admit_client_project_configuration(wire) is Ok(configuration) else {
        return None
      }
      Some(configuration)
    }
    None => return None
  }
  let requested = match @decode.lookup(object, "profile") {
    Some(value) if @decode.is_null(value) => None
    Some(value) => {
      guard @decode.text(value) is Ok(profile) else { return None }
      Some(profile)
    }
    None => return None
  }
  guard @host.select_client_project_profile(configuration, requested, 65536)
    is Ok(selection) else {
    return None
  }
  Some({ configuration, requested, selection, })
}

///|
fn project_optional_text(
  writer : @encode.Writer,
  key : String,
  value : String?,
) -> Unit raise @encode.EncodeFailure {
  @encode.key(writer, key)
  match value {
    Some(text) => @encode.string_value(writer, text)
    None => @encode.null_value(writer)
  }
}

///|
/// Project only the same nominal choice. A serialized copy of these locators
/// cannot replace the retained selection when the Host installs a profile.
fn original_project_configuration_body(
  original : StoredProjectConfiguration,
) -> Bytes? {
  if !@host.client_project_profile_matches(
      original.selection,
      original.configuration,
      original.requested,
    ) {
    return None
  }
  guard original.selection.selected_profile() is Ok(profile) &&
    original.selection.mock_data_file() is Ok(mock_data) &&
    original.selection.mock_answer_count() is Ok(answer_count) else {
    return None
  }
  let configuration = original.configuration
  try {
    let writer = @encode.writer(65536, 8192, 8)
    @encode.begin_object(writer)
    project_optional_text(
      writer,
      "connectors",
      configuration.map(value => value.connectors_file()).unwrap_or(None),
    )
    project_optional_text(
      writer,
      "lock",
      configuration.map(value => value.lock_file()).unwrap_or(None),
    )
    @encode.key(writer, "mock_answers")
    @encode.begin_array(writer)
    for index in 0..<answer_count {
      guard original.selection.mock_answer_at(index) is Ok(Some((task, path))) else {
        return None
      }
      @encode.begin_array(writer)
      @encode.string_value(writer, task)
      @encode.string_value(writer, path)
      @encode.end_array(writer)
    }
    @encode.end_array(writer)
    project_optional_text(writer, "mock_data", mock_data)
    project_optional_text(
      writer,
      "model_tasks",
      configuration.map(value => value.model_tasks_file()).unwrap_or(None),
    )
    project_optional_text(writer, "profile", profile)
    @encode.key(writer, "state_dir")
    @encode.string_value(
      writer,
      configuration.map(value => value.state_directory()).unwrap_or("./.actql"),
    )
    @encode.end_object(writer)
    Some(@utf8.encode(@encode.finish(writer)))
  } catch {
    _ => None
  }
}
