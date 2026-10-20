///|
// These are registered language signatures, not installed capabilities. Keep
// discovery before project selection and any physical Host acquisition.
fn local_language_operation_rows() -> Array[Json] raise ClientStop {
  let wire = generated_language_operation_catalog()
  guard @utf8.encode(wire).length() <= 1048576 else {
    stop("OperationCatalogOutputLimit")
  }
  let original = @json.parse(wire) catch {
    _ => stop("OperationCatalogUnavailable")
  }
  guard original is Array(rows) && rows.length() <= 4096 else {
    stop("OperationCatalogUnavailable")
  }
  rows
}

///|
fn local_language_operation_parts(
  row : Json,
) -> (String, String, Json, String) raise ClientStop {
  guard row is Object(fields) &&
    fields.get("operation") is Some(String(operation)) &&
    fields.get("family") is Some(String(family)) &&
    fields.get("signature") is Some(signature) &&
    signature is Object(original) &&
    original.get("output") is Some(String(output)) else {
    stop("OperationCatalogUnavailable")
  }
  (operation, family, signature, output)
}

///|
fn local_language_operation_search_text(text : String) -> String {
  let output = StringBuilder()
  for character in text {
    output.write_char(character.to_ascii_lowercase())
  }
  output.to_string()
}

///|
fn local_language_operation_command(
  root : @argparse.Matches,
  parent : @argparse.Matches,
) -> String raise ClientStop {
  guard parent.subcommand is Some((action, child)) else {
    stop("MissingOperationDiscoveryCommand")
  }
  let requested_maximum = positive_int(
    required(root, "max-response-bytes"),
    "max-response-bytes",
  )
  let maximum = if requested_maximum < 1048576 {
    requested_maximum
  } else {
    1048576
  }
  let selected : Array[Json] = []
  let family = if action == "list" { optional(child, "family") } else { None }
  let output = if action == "list" { optional(child, "output") } else { None }
  let operation = if action == "show" {
    Some(required(child, "operation"))
  } else {
    None
  }
  let words = if action == "search" {
    child.values.get("words").unwrap_or([])
  } else {
    []
  }
  if action != "list" && action != "show" && action != "search" {
    stop("UnknownOperationDiscoveryCommand")
  }
  if action == "search" && words.is_empty() {
    stop("MissingOperationSearchWords")
  }
  let words = words.map(local_language_operation_search_text)
  for row in local_language_operation_rows() {
    let (name, original_family, signature, original_output) = local_language_operation_parts(
      row,
    )
    if family is Some(value) && value != original_family {
      continue
    }
    if output is Some(value) && value != original_output {
      continue
    }
    if operation is Some(value) && value != name {
      continue
    }
    if action == "search" {
      let searchable = local_language_operation_search_text(
        name + " " + encode_request_json(signature, 1048576),
      )
      if !words.all(word => searchable.contains(word)) {
        continue
      }
    }
    selected.push(row)
  }
  if action == "show" && selected.length() != 1 {
    stop("UnknownLanguageOperation")
  }
  let body = if child.flags.get("json").unwrap_or(false) {
    if action == "show" {
      encode_request_json(selected[0], maximum)
    } else {
      encode_request_json(Json::array(selected), maximum)
    }
  } else {
    let lines : Array[String] = []
    for row in selected {
      let (name, _, signature, _) = local_language_operation_parts(row)
      lines.push(name + " " + encode_request_json(signature, maximum))
    }
    lines.join("\n")
  }
  if @utf8.encode(body).length() > maximum {
    stop("OperationCatalogOutputLimit")
  }
  body
}
