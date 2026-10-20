///|
priv struct LocalInputFileLocation {
  root : String
  name : String
}

///|
// Resolve only operator-selected input metadata. The original Root/Reader
// supplies generation, byte limits and cleanup; this path grants no authority.
fn local_input_file_location(
  root : String,
  selected : String,
) -> LocalInputFileLocation raise ClientStop {
  if selected.is_empty() || selected.has_suffix("/") {
    stop("InvalidLocalInputPath")
  }
  let absolute = try {
    let base = if root.has_prefix("/") {
      "/"
    } else {
      let current = @env.current_dir().unwrap_or_else(() => {
        stop("LocalInputDirectoryUnavailable")
      })
      current
    }
    let directory = local_project_absolute_path(
      base,
      root,
      ordinary_file=true,
      ordinary_directory=true,
    )
    local_project_absolute_path(directory, selected, ordinary_file=true)
  } catch {
    ClientStop(_) => stop("InvalidLocalInputPath")
  }
  if @utf8.encode(absolute).length() > 4096 {
    stop("InvalidLocalInputPath")
  }
  let parts = absolute.split("/").to_array()
  let name = parts[parts.length() - 1].to_owned()
  let parent = absolute[:absolute.length() - name.length() - 1].to_owned()
  { root: if parent.is_empty() { "/" } else { parent }, name, }
}

///|
fn local_input_text_file(
  root : String,
  selected : String,
  maximum : Int64,
) -> String raise ClientStop {
  if command_preparation_invocation.val is Some(original) {
    let location = local_input_file_location(root, selected)
    return command_preparation_result(
      original.text_file(
        location.root,
        location.name,
        maximum,
        ordinary_name=true,
      ),
      stage=Some("input-read"),
    )
  }
  // Unselected legacy callers retain their original managed-name entrance.
  text_file(root, selected, maximum)
}

///|
fn local_input_json_file(
  root : String,
  selected : String,
  maximum : Int64,
) -> Json raise ClientStop {
  json_file_text(
    local_input_text_file(root, selected, maximum),
    selected,
    maximum,
  )
}
