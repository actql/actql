///|
priv suberror WireStop {
  WireStop(WireIssue)
}

///|
fn wire_path(path : Array[@source.PathSegment]) -> String {
  let builder = StringBuilder()
  builder.write_string("$")
  for segment in path {
    match segment {
      Key(name) => {
        builder.write_string(".")
        builder.write_string(name)
      }
      Index(index) => {
        builder.write_string("[")
        builder.write_string(index.to_string())
        builder.write_string("]")
      }
    }
  }
  builder.to_string()
}

///|
fn[T] wire_decoded(value : Result[T, @decode.Issue]) -> T raise WireStop {
  match value {
    Ok(result) => result
    Err(issue) =>
      raise WireStop({ kind: InvalidShape, path: wire_path(issue.path), })
  }
}

///|
fn wire_shape(cursor : @decode.Cursor) -> WireStop {
  WireStop({ kind: InvalidShape, path: wire_path(@decode.cursor_path(cursor)), })
}

///|
// These account configuration positions contain identifiers, never data strings.
fn wire_identifier(cursor : @decode.Cursor) -> String raise WireStop {
  let raw = wire_decoded(@decode.text(cursor))
  match @canonical.normalize_nfc_lf(raw) {
    Ok(value) => value
    Err(_) => raise wire_shape(cursor)
  }
}

///|
fn wire_text(
  object : @decode.ObjectView,
  name : String,
) -> String raise WireStop {
  wire_identifier(wire_decoded(@decode.required(object, name)))
}

///|
fn wire_selector(cursor : @decode.Cursor) -> Selector raise WireStop {
  let object = wire_decoded(@decode.closed_object(cursor, ["all", "any_of"]))
  match (@decode.lookup(object, "all"), @decode.lookup(object, "any_of")) {
    (Some(all), None) =>
      if wire_decoded(@decode.boolean(all)) {
        All
      } else {
        raise wire_shape(all)
      }
    (None, Some(values)) => {
      let result = []
      for value in wire_decoded(@decode.elements(values)) {
        result.push(wire_identifier(value))
      }
      AnyOf(result)
    }
    _ => raise wire_shape(cursor)
  }
}

///|
fn wire_box(object : @decode.ObjectView) -> SelectorBox raise WireStop {
  {
    principal: wire_selector(
      wire_decoded(@decode.required(object, "principal")),
    ),
    connection: wire_selector(
      wire_decoded(@decode.required(object, "connection")),
    ),
    resource: wire_selector(wire_decoded(@decode.required(object, "resource"))),
    operation: wire_selector(
      wire_decoded(@decode.required(object, "operation")),
    ),
  }
}

///|
fn wire_outcome(cursor : @decode.Cursor) -> ConfiguredOutcome raise WireStop {
  match wire_decoded(@decode.text(cursor)) {
    "allow" => Allow
    "deny" => Deny
    "delegate" => Delegate
    _ => raise wire_shape(cursor)
  }
}

///|
fn wire_entry(cursor : @decode.Cursor) -> RawAccountEntry raise WireStop {
  let object = wire_decoded(
    @decode.closed_object(cursor, [
      "connection", "entry_id", "exclusions", "operation", "outcome", "principal",
      "resource",
    ]),
  )
  let exclusions = []
  let listed = wire_decoded(@decode.required(object, "exclusions"))
  match @decode.array_length(listed) {
    Some(length) if length > MAX_EXCLUSIONS_PER_ENTRY =>
      raise WireStop({
        kind: InvalidShape,
        path: wire_path(@decode.cursor_path(listed)),
      })
    _ => ()
  }
  for item in wire_decoded(@decode.elements(listed)) {
    exclusions.push(
      wire_box(
        wire_decoded(
          @decode.closed_object(item, [
            "connection", "operation", "principal", "resource",
          ]),
        ),
      ),
    )
  }
  {
    entry_id: wire_text(object, "entry_id"),
    outcome: wire_outcome(wire_decoded(@decode.required(object, "outcome"))),
    scope: wire_box(object),
    exclusions,
  }
}

///|
fn wire_bootstrap(cursor : @decode.Cursor) -> BootstrapProfile raise WireStop {
  let object = wire_decoded(
    @decode.closed_object(cursor, [
      "profile_cid", "profile_id", "profile_version",
    ]),
  )
  {
    profile_id: wire_text(object, "profile_id"),
    profile_version: wire_text(object, "profile_version"),
    profile_cid: wire_text(object, "profile_cid"),
  }
}

///|
/// Decode the `actql-execution-account-config/0.1` wire shape. Input size,
/// node count, depth, string sizes, entry count and exclusion count are
/// bounded before any per-entry work. Entries, `any_of` values and exclusions
/// must already be in canonical ascending order (`NonCanonicalOrder`
/// otherwise); equal neighbours are reported by admission as duplicates. The
/// result is not admitted; pass it to `admit_account_configuration`.
pub fn decode_account_configuration_json(
  body : String,
) -> Result[RawAccountConfiguration, ConfigurationIssue] {
  let bytes = @utf8.encode(body)
  if bytes.length() > MAX_CONFIG_INPUT_BYTES {
    return Err(MalformedWire({ kind: InputTooLarge, path: "$", }))
  }
  let source = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: MAX_CONFIG_INPUT_BYTES,
      max_nodes: 262144,
      max_depth: 7,
    }) {
    Ok(value) => value
    Err(_) => return Err(MalformedWire({ kind: InvalidJson, path: "$", }))
  }
  try {
    let cursor = wire_decoded(
      @decode.admit(source, {
        max_nodes: 262144,
        max_depth: 7,
        max_string_bytes: MAX_NAME_LENGTH * 4,
        max_total_string_bytes: MAX_CONFIG_INPUT_BYTES,
      }),
    )
    let object = wire_decoded(
      @decode.closed_object(cursor, [
        "account_id", "bootstrap", "entries", "version",
      ]),
    )
    if wire_text(object, "version") != ACCOUNT_CONFIG_VERSION {
      raise WireStop({ kind: UnsupportedVersion, path: "$.version", })
    }
    let account_id = wire_text(object, "account_id")
    let listed = wire_decoded(@decode.required(object, "entries"))
    match @decode.array_length(listed) {
      Some(length) if length > MAX_ENTRIES =>
        raise WireStop({ kind: InvalidShape, path: "$.entries", })
      _ => ()
    }
    let entries = []
    for item in wire_decoded(@decode.elements(listed)) {
      entries.push(wire_entry(item))
    }
    let bootstrap = match @decode.lookup(object, "bootstrap") {
      None => None
      Some(value) => Some(wire_bootstrap(value))
    }
    let raw : RawAccountConfiguration = { account_id, entries, bootstrap, }
    match first_out_of_order(raw) {
      Some(path) => Err(NonCanonicalOrder(path))
      None => Ok(raw)
    }
  } catch {
    WireStop(issue) => Err(MalformedWire(issue))
  }
}

///|
/// Decode and admit a wire configuration.
pub fn admit_account_configuration_json(
  body : String,
) -> Result[AdmittedAccountConfiguration, ConfigurationIssue] {
  match decode_account_configuration_json(body) {
    Ok(raw) => admit_account_configuration(raw)
    Err(issue) => Err(issue)
  }
}
