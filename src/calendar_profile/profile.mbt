///|
pub(all) struct Limits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_zones : Int
  max_transitions : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  IdentityMismatch
  InvalidJson
  InvalidBody
  UnsupportedVersion
  UnsupportedLaw
  InvalidCoverage
  InvalidZone
  InvalidTable(String, @transition.Issue)
  NoncanonicalArtifact
} derive(Eq, Debug)

///|
struct Profile {
  cid : String
  tzdb_version : String
  zones : Map[String, @transition.Table]
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] decoded(v : Result[T, @decode.Issue]) -> T raise Stop {
  match v {
    Ok(x) => x
    Err(_) => raise Stop(InvalidBody)
  }
}

///|
fn required_field(
  o : @decode.ObjectView,
  key : String,
) -> @decode.Cursor raise Stop {
  decoded(@decode.required(o, key))
}

///|
/// expected_cid and expected_tzdb_version belong to the trusted Check Environment.
/// Integrity and structural validity do not independently certify IANA provenance.
pub fn admit(
  bytes : Bytes,
  expected_cid : String,
  expected_tzdb_version : String,
  limits : Limits,
) -> Result[Profile, Issue] {
  try {
    if limits.max_bytes < 0 ||
      limits.max_nodes < 0 ||
      limits.max_depth < 0 ||
      limits.max_zones < 0 ||
      limits.max_transitions < 0 {
      raise Stop(InvalidLimits)
    }
    if bytes.length() > limits.max_bytes {
      raise Stop(BudgetExceeded)
    }
    let cid = "sha256:" + @sha.hex(bytes)
    if cid != expected_cid {
      raise Stop(IdentityMismatch)
    }
    let node = match
      @source.parse_json_bytes(bytes, {
        max_input_bytes: limits.max_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
      }) {
      Ok(v) => v
      Err(e) =>
        match e.issue {
          InputLimit | NodeLimit | DepthLimit => raise Stop(BudgetExceeded)
          _ => raise Stop(InvalidJson)
        }
    }
    let c = match
      @decode.admit(node, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_bytes,
        max_total_string_bytes: limits.max_bytes,
      }) {
      Ok(v) => v
      Err(_) => raise Stop(BudgetExceeded)
    }
    let o = decoded(
      @decode.closed_object(c, [
        "version", "tzdb_version", "conversion_law", "coverage_start_ms", "coverage_end_ms",
        "zones",
      ]),
    )
    if decoded(@decode.text(required_field(o, "version"))) !=
      "actql-tzdb-table/0.1" {
      raise Stop(UnsupportedVersion)
    }
    let version = decoded(@decode.text(required_field(o, "tzdb_version")))
    if version.is_empty() || version != expected_tzdb_version {
      raise Stop(UnsupportedVersion)
    }
    if decoded(@decode.text(required_field(o, "conversion_law"))) !=
      "actql-calendar-boundaries/0.1" {
      raise Stop(UnsupportedLaw)
    }
    let start = decoded(
      @decode.safe_integer(required_field(o, "coverage_start_ms")),
    )
    let end = decoded(
      @decode.safe_integer(required_field(o, "coverage_end_ms")),
    )
    if start != -62135596800000L || end != 253402300800000L {
      raise Stop(InvalidCoverage)
    }
    let zc = required_field(o, "zones")
    let names = decoded(@decode.object_field_names(zc))
    if names.length() > limits.max_zones {
      raise Stop(BudgetExceeded)
    }
    let zo = decoded(@decode.open_object(zc))
    let zones : Map[String, @transition.Table] = Map([])
    let mut remaining = limits.max_transitions
    for name in names {
      if name.is_empty() {
        raise Stop(InvalidZone)
      }
      let z = decoded(
        @decode.closed_object(required_field(zo, name), [
          "initial_offset_seconds", "transitions",
        ]),
      )
      let initial = decoded(
        @decode.int32(required_field(z, "initial_offset_seconds")),
      )
      let xs = decoded(@decode.elements(required_field(z, "transitions")))
      if xs.length() > remaining {
        raise Stop(BudgetExceeded)
      }
      remaining -= xs.length()
      let transitions : Array[@transition.Transition] = []
      for x in xs {
        let t = decoded(@decode.closed_object(x, ["at_ms", "offset_seconds"]))
        transitions.push({
          at_ms: decoded(@decode.safe_integer(required_field(t, "at_ms"))),
          offset_seconds: decoded(
            @decode.int32(required_field(t, "offset_seconds")),
          ),
        })
      }
      let table = match
        @transition.admit(
          start,
          end,
          initial,
          transitions,
          max_transitions=xs.length(),
        ) {
        Ok(t) => t
        Err(e) => raise Stop(InvalidTable(name, e))
      }
      zones[name] = table
    }
    match zones.get("UTC") {
      Some(t) =>
        if @transition.initial_offset(t) != 0 ||
          @transition.transition_count(t) != 0 {
          raise Stop(InvalidZone)
        }
      None => raise Stop(InvalidZone)
    }
    let profile : Profile = { cid, tzdb_version: version, zones, }
    // The source parser normalizes strings. Re-emission must match the original
    // byte identity, so repairs, alternate number spellings and whitespace fail.
    let canonical = canonical_hash(profile, names, limits) catch {
      _ => raise Stop(NoncanonicalArtifact)
    }
    if "sha256:" + canonical != cid {
      raise Stop(NoncanonicalArtifact)
    }
    Ok(profile)
  } catch {
    Stop(e) => Err(e)
  }
}

///|
fn canonical_hash(
  p : Profile,
  names : Array[String],
  limits : Limits,
) -> String raise @encode.EncodeFailure {
  names.sort_by(@canonical.compare_utf16)
  let w = @encode.hashing_writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  )
  @encode.begin_object(w)
  @encode.key(w, "conversion_law")
  @encode.string_value(w, "actql-calendar-boundaries/0.1")
  @encode.key(w, "coverage_end_ms")
  @encode.number_value(w, 253402300800000.0)
  @encode.key(w, "coverage_start_ms")
  @encode.number_value(w, -62135596800000.0)
  @encode.key(w, "tzdb_version")
  @encode.string_value(w, p.tzdb_version)
  @encode.key(w, "version")
  @encode.string_value(w, "actql-tzdb-table/0.1")
  @encode.key(w, "zones")
  @encode.begin_object(w)
  for name in names {
    let t = p.zones.get(name).unwrap()
    @encode.key(w, name)
    @encode.begin_object(w)
    @encode.key(w, "initial_offset_seconds")
    @encode.number_value(w, @transition.initial_offset(t).to_double())
    @encode.key(w, "transitions")
    @encode.begin_array(w)
    for i in 0..<@transition.transition_count(t) {
      let x = @transition.transition_at(t, i).unwrap()
      @encode.begin_object(w)
      @encode.key(w, "at_ms")
      @encode.number_value(w, x.at_ms.to_double())
      @encode.key(w, "offset_seconds")
      @encode.number_value(w, x.offset_seconds.to_double())
      @encode.end_object(w)
    }
    @encode.end_array(w)
    @encode.end_object(w)
  }
  @encode.end_object(w)
  @encode.end_object(w)
  @encode.finish_hash(w)
}

///|
pub fn cid(p : Profile) -> String {
  p.cid
}

///|
pub fn tzdb_version(p : Profile) -> String {
  p.tzdb_version
}

///|
pub fn zone(p : Profile, name : String) -> @transition.Table? {
  p.zones.get(name)
}
