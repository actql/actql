///|
/// Wire geometry observed during the SAME original Unicode/byte preflight.
/// This is not grammar validation, decoded/normalized text size, a resource
/// grant or a checked Program. Escaped spelling stays raw in these counts.
pub(all) struct JsonSourceGeometry {
  input_bytes : Int
  input_utf16_units : Int
  objects : Int
  arrays : Int
  fields : Int
  quoted_tokens : Int
  quoted_raw_utf16_units : Int
  longest_quoted_raw_utf16 : Int
  atoms : Int
  longest_atom_utf16 : Int
  depth_upper : Int
  node_upper : Int
} derive(Eq, Debug)

///|
priv struct JsonGeometryState {
  mut in_string : Bool
  mut escaped : Bool
  mut atom_open : Bool
  mut current_quoted : Int
  mut current_atom : Int
  mut depth : Int
  mut deepest : Int
  mut node_prefix : Int
  mut node_upper : Int
  mut objects : Int
  mut arrays : Int
  mut fields : Int
  mut quotes : Int
  mut quoted_units : Int
  mut longest_quote : Int
  mut atoms : Int
  mut longest_atom : Int
}

///|
/// A staging reference to the existing parser, not another parser, Ledger or
/// cleanup engine. Taking transfers that SAME cursor once. The caller funds
/// initial controls before creation and the tree phase before taking/advancing.
struct JsonSourcePreflight {
  mut cursor : JsonParse?
  geometry : JsonGeometryState
  mut completed_geometry : JsonSourceGeometry?
}

///|
pub(all) enum JsonSourcePreflightIssue {
  InvalidQuantum
  Consumed
  NotReady
} derive(Eq, Debug)

///|
pub enum JsonSourcePreflightPoll {
  JsonSourceContinue(work~ : Int)
  JsonSourceReady(JsonSourceGeometry, work~ : Int)
  JsonSourceFailed(ParseError, work~ : Int)
}

///|
fn make_json_source_preflight(cursor : JsonParse) -> JsonSourcePreflight {
  {
    cursor: Some(cursor),
    completed_geometry: None,
    geometry: {
      in_string: false,
      escaped: false,
      atom_open: false,
      current_quoted: 0,
      current_atom: 0,
      depth: 0,
      deepest: 0,
      node_prefix: 0,
      node_upper: 0,
      objects: 0,
      arrays: 0,
      fields: 0,
      quotes: 0,
      quoted_units: 0,
      longest_quote: 0,
      atoms: 0,
      longest_atom: 0,
    },
  }
}

///|
pub fn start_json_source_preflight(
  source : String,
  limits : ParseLimits,
  source_path? : String = "<memory>",
  data_keys? : Bool = false,
) -> Result[JsonSourcePreflight, ParseError] {
  start_json_parse(source, limits, source_path~, data_keys~).map(
    make_json_source_preflight,
  )
}

///|
/// Retain the existing Program key mode, including its root-anchored Effect
/// literal-key exceptions. A data-key cursor must not stand in for this mode.
pub fn start_program_json_source_preflight(
  source : String,
  limits : ParseLimits,
  source_path? : String = "<memory>",
) -> Result[JsonSourcePreflight, ParseError] {
  if !valid_limits(limits) {
    return Err(input_error(InvalidLimits, source_path, Unavailable))
  }
  Ok(
    make_json_source_preflight(
      make_json_parse(
        source,
        source_path,
        limits,
        normalize_text=true,
        effect_literal_keys=true,
      ),
    ),
  )
}

///|
fn geometry_node(state : JsonGeometryState) -> Unit {
  state.node_prefix += 1
  state.node_upper = Int::max(state.node_upper, state.node_prefix)
}

///|
/// Delimiters inside quoted spelling never affect envelope counts. Counting a
/// quoted key initially as a node and removing it at its colon bounds every
/// valid prefix; retaining the maximum also covers the prefix before an error.
/// No stack, StringBuilder, decoded String, Node or key Map is constructed.
fn observe_json_wire_scalar(
  state : JsonGeometryState,
  unit : Int,
  units : Int,
  offset : Int,
) -> Unit {
  if offset == 0 && unit == 0xfeff {
    return
  }
  if state.in_string {
    if !state.escaped && unit == 0x22 {
      state.in_string = false
      return
    }
    state.current_quoted += units
    state.quoted_units += units
    state.longest_quote = Int::max(state.longest_quote, state.current_quoted)
    if state.escaped {
      state.escaped = false
    } else if unit == 0x5c {
      state.escaped = true
    }
    return
  }
  if unit == 0x22 {
    state.atom_open = false
    state.current_atom = 0
    state.in_string = true
    state.current_quoted = 0
    state.quotes += 1
    geometry_node(state)
  } else if unit == 0x7b || unit == 0x5b {
    state.atom_open = false
    state.current_atom = 0
    if unit == 0x7b {
      state.objects += 1
    } else {
      state.arrays += 1
    }
    state.depth += 1
    state.deepest = Int::max(state.deepest, state.depth)
    geometry_node(state)
  } else if unit == 0x7d || unit == 0x5d {
    state.atom_open = false
    state.current_atom = 0
    state.depth = Int::max(0, state.depth - 1)
  } else if unit == 0x3a {
    state.atom_open = false
    state.current_atom = 0
    state.fields += 1
    state.node_prefix -= 1
  } else if unit == 0x2c ||
    unit == 0x20 ||
    unit == 0x09 ||
    unit == 0x0a ||
    unit == 0x0d {
    state.atom_open = false
    state.current_atom = 0
  } else {
    if !state.atom_open {
      state.atom_open = true
      state.atoms += 1
      geometry_node(state)
    }
    state.current_atom += units
    state.longest_atom = Int::max(state.longest_atom, state.current_atom)
  }
}

///|
fn json_source_geometry(
  value : JsonSourcePreflight,
  cursor : JsonParse,
) -> JsonSourceGeometry {
  let state = value.geometry
  {
    input_bytes: cursor.preflight_bytes,
    input_utf16_units: cursor.document.parser.source.length(),
    objects: state.objects,
    arrays: state.arrays,
    fields: state.fields,
    quoted_tokens: state.quotes,
    quoted_raw_utf16_units: state.quoted_units,
    longest_quoted_raw_utf16: state.longest_quote,
    atoms: state.atoms,
    longest_atom_utf16: state.longest_atom,
    depth_upper: state.deepest,
    node_upper: state.node_upper,
  }
}

///|
/// Stop exactly before the first grammar transition. Unicode/byte failure is
/// produced by the same original preflight step, including its original error
/// precedence/coordinates. No successful preflight is repeated after transfer.
pub fn advance_json_source_preflight(
  value : JsonSourcePreflight,
  quantum : Int,
) -> Result[JsonSourcePreflightPoll, JsonSourcePreflightIssue] {
  if quantum < 1 {
    return Err(InvalidQuantum)
  }
  guard value.cursor is Some(cursor) else { return Err(Consumed) }
  let mut work = 0
  while !cursor.preflight_done && work < quantum {
    work += 1
    let offset = cursor.preflight_offset
    if json_preflight_step(cursor) is Some(error) {
      cancel_json_source_preflight(value)
      return Ok(JsonSourceFailed(error, work~))
    }
    if cursor.preflight_offset > offset {
      observe_json_wire_scalar(
        value.geometry,
        cursor.document.parser.source[offset].to_int(),
        cursor.preflight_offset - offset,
        offset,
      )
    }
  }
  if cursor.preflight_done {
    let geometry = match value.completed_geometry {
      Some(original) => original
      None => {
        let original = json_source_geometry(value, cursor)
        value.completed_geometry = Some(original)
        original
      }
    }
    Ok(JsonSourceReady(geometry, work~))
  } else {
    Ok(JsonSourceContinue(work~))
  }
}

///|
/// The original cursor transfers only after preflight, once. A numerical copy
/// of the geometry cannot issue this transfer. The next phase's existing
/// reservation must be admitted BEFORE taking/advancing that parser.
pub fn take_json_source_parser(
  value : JsonSourcePreflight,
) -> Result[JsonParse, JsonSourcePreflightIssue] {
  guard value.cursor is Some(cursor) else { return Err(Consumed) }
  if !cursor.preflight_done {
    return Err(NotReady)
  }
  value.cursor = None
  value.completed_geometry = None
  Ok(cursor)
}

///|
/// Logical data retirement delegates to the original parser. After transfer,
/// this view no longer owns it and cannot cancel the successor's cursor.
/// This is not physical stop, output completion or a Host cleanup ACK.
pub fn cancel_json_source_preflight(value : JsonSourcePreflight) -> Unit {
  if value.cursor is Some(cursor) {
    cancel_json_parse(cursor)
    value.cursor = None
  }
  value.completed_geometry = None
}

///|
pub(all) struct JsonSourcePreflightControlExtent {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
} derive(Eq, Debug)

///|
/// Fixed initial controls BEFORE any preflight: Parser/Document/JsonParse
/// 3H7R16W; two empty arrays4H18R4W; staging reference+Some2H3R1W;
/// geometry1H17W; report/failure alternatives5H5R16W; scalar tuple1H2W.
/// The cached ready DATA adds one optional slot (ref/tag) and Some1H1R1W;
/// its geometry record was already in the original report inventory.
/// Original source/limits/path Strings and backend outer roles remain borrowed
/// separately. This excludes grammar tree/key/normalization construction.
pub fn json_source_preflight_control_extent() -> JsonSourcePreflightControlExtent {
  json_source_preflight_controls
}

///|
// Installed immutable DATA: reading initial demand must not allocate a new
// request-owned recipe before its original initial scope has been funded.
let json_source_preflight_controls : JsonSourcePreflightControlExtent = {
  record_headers: 17L,
  reference_slots: 35L,
  scalar_words: 58L,
}
