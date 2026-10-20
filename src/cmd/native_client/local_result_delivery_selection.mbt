///|
// A requested presentation destination, never a read grant or a Writer ACK.
priv struct LocalResultFileSelection {
  result_name : String?
  format : String
  path : String
}

///|
priv struct LocalResultDeliverySelection {
  files : Array[LocalResultFileSelection]
  receipt : String?
  json : Bool
}

///|
fn normalize_native_result_arguments(
  matches : @argparse.Matches,
) -> Unit raise ClientStop {
  guard matches.subcommand is Some(("result", child)) else { return }
  let directory = @env.current_dir().unwrap_or_else(() => {
    stop("ProjectConfigurationDirectoryUnavailable")
  })
  ignore(local_result_delivery_selection(child, directory))
}

///|
// Ordinary file presentation metadata, separate from the installation's
// managed-object basename restriction. OS lookup/seal supplies actual name
// limits and errors; this split never opens a path or grants output access.
fn local_result_file_location(
  path : String,
) -> LocalProductLocation raise ClientStop {
  if !local_product_path(path) || path.contains("\\") {
    stop("InvalidLocalResultDestination")
  }
  let parts = path.split("/").to_array()
  let name = parts[parts.length() - 1].to_owned()
  let prefix = path[:path.length() - name.length() - 1].to_owned()
  {
    parent_path: if prefix.is_empty() {
      "/"
    } else {
      prefix
    },
    directory_name: name,
  }
}

///|
fn local_result_output_path(
  directory : String,
  value : String,
) -> String raise ClientStop {
  if value.is_empty() || value.has_suffix("/") {
    stop("InvalidLocalResultDestination")
  }
  let absolute = local_project_absolute_path(directory, value) catch {
    ClientStop(_) => stop("InvalidLocalResultDestination")
  }
  ignore(local_result_file_location(absolute))
  absolute
}

///|
fn local_result_delivery_item(
  value : String,
  directory : String,
) -> LocalResultFileSelection raise ClientStop {
  if value.length() > 4352 || value.contains("\u{0000}") {
    stop("InvalidLocalResultDelivery")
  }
  let mut equal = -1
  let mut colon = -1
  for index in 0..<value.length() {
    if equal < 0 && value[index] == '=' {
      equal = index
    } else if equal >= 0 && value[index] == ':' {
      colon = index
      break
    }
  }
  if equal < 1 || equal > 128 || colon <= equal + 1 {
    stop("InvalidLocalResultDelivery")
  }
  let result_name = value[:equal].to_owned()
  let format = value[equal + 1:colon].to_owned()
  if !["json", "jsonl", "csv"].contains(format) {
    stop("InvalidLocalReadSelection")
  }
  {
    result_name: Some(result_name),
    format,
    path: local_result_output_path(directory, value[colon + 1:].to_owned()),
  }
}

///|
// Validate the complete request before any destination, read attempt or file
// is acquired. In particular, repeating --deliver never means ignoring all
// but its last value, and lexical aliases cannot target the same pathname.
fn local_result_delivery_selection(
  child : @argparse.Matches,
  directory : String,
) -> LocalResultDeliverySelection raise ClientStop {
  let files : Array[LocalResultFileSelection] = []
  match child.values.get("deliver") {
    Some(values) => {
      if values.is_empty() || values.length() > 16 {
        stop("InvalidLocalResultDelivery")
      }
      for name in ["output", "result", "format"] {
        if child.values.contains(name) {
          stop("ConflictingLocalResultDelivery")
        }
      }
      for value in values {
        files.push(local_result_delivery_item(value, directory))
      }
    }
    None => {
      let format = local_result_format(child)
      if optional(child, "output") is Some(path) {
        let result_name = optional(child, "result")
        if result_name is Some(name) &&
          (name.is_empty() || name.length() > 128 || name.contains("\u{0000}")) {
          stop("InvalidLocalResultDelivery")
        }
        files.push({
          result_name,
          format,
          path: local_result_output_path(directory, path),
        })
      }
    }
  }
  let receipt = match optional(child, "receipt") {
    None => None
    Some(path) => {
      if files.is_empty() {
        stop("LocalResultReceiptRequiresFile")
      }
      Some(local_result_output_path(directory, path))
    }
  }
  let paths : Map[String, Bool] = Map([])
  for selected in files {
    if paths.contains(selected.path) {
      stop("ConflictingLocalResultDestination")
    }
    paths[selected.path] = true
  }
  if receipt is Some(path) && paths.contains(path) {
    stop("ConflictingLocalResultDestination")
  }
  let json = child.flags.get("json").unwrap_or(false)
  if json && files.is_empty() {
    stop("LocalResultJsonEnvelopeUnavailable")
  }
  { files, receipt, json, }
}
