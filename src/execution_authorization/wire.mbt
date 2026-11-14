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
/// node count, depth and string sizes are bounded before per-entry work.
/// Entries, `any_of` values and exclusions
/// must already be in canonical ascending order (`NonCanonicalOrder`
/// otherwise); equal neighbours are reported by admission as duplicates. The
/// result is not admitted; pass it to `admit_account_configuration`.
pub fn decode_account_configuration_json(
  body : String,
) -> Result[RawAccountConfiguration, ConfigurationIssue] {
  decode_account_configuration_original(body).map(value => value.0)
}

///|
fn decode_account_configuration_original(
  body : String,
) -> Result[(RawAccountConfiguration, Bytes), ConfigurationIssue] {
  let bytes = @utf8.encode(body)
  let size = bytes.length()
  if size == 0 {
    return Err(MalformedWire({ kind: InvalidJson, path: "$", }))
  }
  let source = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: size,
      max_nodes: size,
      max_depth: 7,
    }) {
    Ok(value) => value
    Err(_) => return Err(MalformedWire({ kind: InvalidJson, path: "$", }))
  }
  decode_account_configuration_source(source, bytes, size)
}

///|
/// Decode and admit a wire configuration.
pub fn admit_account_configuration_json(
  body : String,
) -> Result[AdmittedAccountConfiguration, ConfigurationIssue] {
  match decode_account_configuration_original(body) {
    Ok((raw, bytes)) =>
      admit_account_configuration(raw).map(account => {
        ..account,
        original_wire: Some(bytes),
      })
    Err(issue) => Err(issue)
  }
}

///|
fn decode_account_configuration_source(
  source : @source.Node,
  bytes : Bytes,
  size : Int,
) -> Result[(RawAccountConfiguration, Bytes), ConfigurationIssue] {
  try {
    let cursor = wire_decoded(
      @decode.admit(source, {
        max_nodes: size,
        max_depth: 7,
        max_string_bytes: size,
        max_total_string_bytes: size,
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
    let entries = []
    for item in wire_decoded(@decode.elements(listed)) {
      entries.push(wire_entry(item))
    }
    let bootstrap = match @decode.lookup(object, "bootstrap") {
      None => None
      Some(value) => Some(wire_bootstrap(value))
    }
    let raw : RawAccountConfiguration = { account_id, entries, bootstrap, }
    match first_out_of_order(raw, account_canonical_wire_bounds(size)) {
      Some(path) => Err(NonCanonicalOrder(path))
      None => Ok((raw, bytes))
    }
  } catch {
    WireStop(issue) => Err(MalformedWire(issue))
  }
}

///|
// Private prepared wire half. The existing public entrance above retains its
// original route; no Native caller selects this half before canonical/overlap
// construction and original physical custody are connected as well.
fn decode_account_configuration_prepared(
  body : String,
  prepare : (AccountConfigurationConstruction) -> Bool,
) -> Result[
  (RawAccountConfiguration, Bytes, AccountConstructionContext),
  ConfigurationIssue,
]? {
  if !prepare(account_construction_initial_request) {
    return None
  }
  let context : AccountConstructionContext = {
    prepare,
    wire_live: account_construction_initial,
  }
  if body.is_empty() {
    return Some(Err(MalformedWire({ kind: InvalidJson, path: "$", })))
  }
  let byte_bound = Int64::min(2147483647L, 3L * body.length().to_int64()).to_int()
  let preflight = match
    @source.start_json_source_preflight(body, {
      max_input_bytes: Int::max(1, byte_bound),
      max_nodes: Int::max(1, body.length()),
      max_depth: 7,
    }) {
    Ok(value) => value
    Err(_) => return Some(Err(MalformedWire({ kind: InvalidJson, path: "$", })))
  }
  let mut observed : @source.JsonSourceGeometry? = None
  while observed is None {
    match @source.advance_json_source_preflight(preflight, 4096).unwrap() {
      @source.JsonSourceContinue(..) => ()
      @source.JsonSourceReady(geometry, ..) => observed = Some(geometry)
      @source.JsonSourceFailed(_) => {
        @source.cancel_json_source_preflight(preflight)
        return Some(Err(MalformedWire({ kind: InvalidJson, path: "$", })))
      }
    }
  }
  let geometry = observed.unwrap()
  try {
    // Encode only after the SAME Unicode preflight supplies exact byte size.
    // This remains the original wire, not a normalized/canonical replacement.
    let original_wire = account_construction_units(
      1L,
      0L,
      0L,
      0L,
      wire=geometry.input_bytes.to_int64(),
    )
    account_prepare_construction(Some(context), original_wire, original_wire)
    let bytes = @utf8.encode(body)
    account_prepare_json_tree(context, geometry)
    let parser = @source.take_json_source_parser(preflight).unwrap()
    let mut source : @source.Node? = None
    while source is None {
      match @source.advance_json_parse(parser, 4096).unwrap() {
        @source.JsonParseContinue(..) => ()
        @source.JsonParseComplete(parsed, ..) => source = Some(parsed.node)
        @source.JsonParseFailed(_) =>
          return Some(Err(MalformedWire({ kind: InvalidJson, path: "$", })))
      }
    }
    account_prepare_json_index(context, geometry)
    let typed = account_prepare_wire_decode(context, geometry)
    account_prepare_admission(context, geometry, typed)
    match
      decode_account_configuration_source(
        source.unwrap(),
        bytes,
        bytes.length(),
      ) {
      Err(issue) => Some(Err(issue))
      Ok((raw, original)) => {
        context.wire_live = account_construction_add(
          account_construction_initial, typed,
        )
        account_prepare_overlap(context, raw)
        Some(Ok((raw, original, context)))
      }
    }
  } catch {
    AccountConstructionStop => {
      @source.cancel_json_source_preflight(preflight)
      None
    }
  }
}

///|
/// Prepare each constructor synchronously at the caller's original resource.
/// None means that caller refused construction; it is never Account admission.
/// The continuation is borrowed only for this call and is not retained by the
/// admitted immutable Account or used by later current checks.
pub fn admit_account_configuration_json_prepared(
  body : String,
  prepare : (AccountConfigurationConstruction) -> Bool,
) -> Result[AdmittedAccountConfiguration, ConfigurationIssue]? {
  match decode_account_configuration_prepared(body, prepare) {
    None => None
    Some(Err(issue)) => Some(Err(issue))
    Some(Ok((raw, bytes, _))) =>
      Some(
        admit_account_configuration(raw).map(account => {
          ..account,
          original_wire: Some(bytes),
        }),
      )
  }
}
