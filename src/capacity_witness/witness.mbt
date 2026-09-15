///|
pub(all) struct Limits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum Issue {
  InvalidLimits
  BudgetExceeded
  InvalidWitness
  IdentityMismatch
  NoncanonicalArtifact
} derive(Eq, Debug)

///|
pub(all) enum Source {
  Program(String, String)
  AuthorGuard(String, String)
  Contract(String, String)
  LanguageLaw(String, String)
  HostPolicy(String, String)
} derive(Eq, Debug)

///|
pub(all) enum Derivation {
  SourceValue
  Preserve(String)
  Minimum(Array[String])
  Add(String, String)
  Multiply(String, Int64)
  Clamp(String?, Int64)
  EnforcedCeiling(String)
}

///|
/// Canonical, content-addressed claims only. Source and law applications are
/// not authenticated, and this type is not runnable capacity evidence.
struct WireWitness {
  cursor : @decode.Cursor
  cid : String
  source : Source
  law : @law.RegisteredLaw
  unit : @arithmetic.BoundUnit
  role : @arithmetic.CandidateRole
  value : Int64
  derivation : Derivation
  dependencies : Array[String]
}

///|
priv suberror Stop {
  Stop(Issue)
}

///|
fn[T] get(result : Result[T, @decode.Issue]) -> T raise Stop {
  match result {
    Ok(v) => v
    Err(_) => raise Stop(InvalidWitness)
  }
}

///|
fn text(object : @decode.ObjectView, key : String) -> String raise Stop {
  get(@decode.text(get(@decode.required(object, key))))
}

///|
fn nonempty(object : @decode.ObjectView, key : String) -> String raise Stop {
  let s = text(object, key)
  if s.is_empty() {
    raise Stop(InvalidWitness)
  }
  s
}

///|
fn valid_cid(s : String) -> Bool {
  if s.length() != 71 || !s.has_prefix("sha256:") {
    return false
  }
  for i = 7; i < 71; i = i + 1 {
    let c = s[i].to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      return false
    }
  }
  true
}

///|
fn identity(object : @decode.ObjectView, key : String) -> String raise Stop {
  let s = text(object, key)
  if !valid_cid(s) {
    raise Stop(InvalidWitness)
  }
  s
}

///|
fn number(object : @decode.ObjectView, key : String) -> Int64 raise Stop {
  let n = get(@decode.safe_integer(get(@decode.required(object, key))))
  if n < 0L {
    raise Stop(InvalidWitness)
  }
  n
}

///|
fn identities(
  cursor : @decode.Cursor,
  allow_empty : Bool,
) -> Array[String] raise Stop {
  let result : Array[String] = []
  let elements = get(@decode.elements(cursor))
  if !allow_empty && elements.is_empty() {
    raise Stop(InvalidWitness)
  }
  let mut previous = ""
  for e in elements {
    let id = get(@decode.text(e))
    if !valid_cid(id) || id <= previous {
      raise Stop(InvalidWitness)
    }
    result.push(id)
    previous = id
  }
  result
}

///|
fn read_source(
  cursor : @decode.Cursor,
) -> (Source, @arithmetic.CandidateRole, String) raise Stop {
  let open = get(@decode.open_object(cursor))
  match text(open, "kind") {
    "program" => {
      let o = get(
        @decode.closed_object(cursor, ["kind", "semantic_ref", "proof_cid"]),
      )
      let cid = identity(o, "proof_cid")
      (
        Program(nonempty(o, "semantic_ref"), cid),
        @arithmetic.ProvenUpperBound,
        cid,
      )
    }
    "author_guard" => {
      let o = get(
        @decode.closed_object(cursor, [
          "kind", "source_path", "program_definition_cid",
        ]),
      )
      let path = text(o, "source_path")
      if !path.has_prefix("$") {
        raise Stop(InvalidWitness)
      }
      let cid = identity(o, "program_definition_cid")
      (AuthorGuard(path, cid), @arithmetic.AuthorGuard, cid)
    }
    "contract" => {
      let o = get(
        @decode.closed_object(cursor, ["kind", "field", "contract_cid"]),
      )
      let cid = identity(o, "contract_cid")
      (Contract(nonempty(o, "field"), cid), @arithmetic.ContractCeiling, cid)
    }
    "language_law" => {
      let o = get(@decode.closed_object(cursor, ["kind", "law_id", "law_cid"]))
      let cid = identity(o, "law_cid")
      (
        LanguageLaw(nonempty(o, "law_id"), cid),
        @arithmetic.LanguageCeiling,
        cid,
      )
    }
    "host_policy" => {
      let o = get(
        @decode.closed_object(cursor, ["kind", "field", "policy_cid"]),
      )
      let cid = identity(o, "policy_cid")
      (HostPolicy(nonempty(o, "field"), cid), @arithmetic.HostCeiling, cid)
    }
    _ => raise Stop(InvalidWitness)
  }
}

///|
fn read_derivation(
  cursor : @decode.Cursor,
) -> (Derivation, Array[String]) raise Stop {
  let open = get(@decode.open_object(cursor))
  match text(open, "op") {
    "source" => {
      ignore(get(@decode.closed_object(cursor, ["op"])))
      (SourceValue, [])
    }
    "preserve" => {
      let o = get(@decode.closed_object(cursor, ["op", "input"]))
      let id = identity(o, "input")
      (Preserve(id), [id])
    }
    "min" => {
      let o = get(@decode.closed_object(cursor, ["op", "inputs"]))
      let ids = identities(get(@decode.required(o, "inputs")), false)
      (Minimum(ids), ids)
    }
    "add" => {
      let o = get(@decode.closed_object(cursor, ["op", "left", "right"]))
      let left = identity(o, "left")
      let right = identity(o, "right")
      (Add(left, right), [left, right])
    }
    "multiply" => {
      let o = get(@decode.closed_object(cursor, ["op", "input", "factor"]))
      let id = identity(o, "input")
      (Multiply(id, number(o, "factor")), [id])
    }
    "clamp" => {
      let o = get(@decode.closed_object(cursor, ["op", "input", "maximum"]))
      let maximum = number(o, "maximum")
      match @decode.field(o, "input") {
        Missing => (Clamp(None, maximum), [])
        ExplicitNull => raise Stop(InvalidWitness)
        Present(_) => {
          let id = identity(o, "input")
          (Clamp(Some(id), maximum), [id])
        }
      }
    }
    "enforced_ceiling" => {
      let o = get(@decode.closed_object(cursor, ["op", "resolved_limit_cid"]))
      let id = identity(o, "resolved_limit_cid")
      (EnforcedCeiling(id), [id])
    }
    _ => raise Stop(InvalidWitness)
  }
}

///|
fn role_name(role : @arithmetic.CandidateRole) -> String {
  match role {
    ProvenUpperBound => "proven_upper_bound"
    AuthorGuard => "author_guard"
    ContractCeiling => "contract_ceiling"
    LanguageCeiling => "language_ceiling"
    HostCeiling => "host_ceiling"
  }
}

///|
fn read_unit(s : String) -> @arithmetic.BoundUnit raise Stop {
  match s {
    "rows" => @arithmetic.Rows
    "distinct_keys" => @arithmetic.DistinctKeys
    "effect_items" => @arithmetic.EffectItems
    "bytes" => @arithmetic.Bytes
    "array_items" => @arithmetic.ArrayItems
    "nodes" => @arithmetic.Nodes
    "edges" => @arithmetic.Edges
    "paths" => @arithmetic.Paths
    "matches_per_key" => @arithmetic.MatchesPerKey
    _ => raise Stop(InvalidWitness)
  }
}

///|
/// Called only after the closed shape has been checked. Its nesting is fixed:
/// root, source/derivation object, and string-only reference arrays.
fn emit_cursor(
  cursor : @decode.Cursor,
  w : @encode.Writer,
  omit_identity : Bool,
) -> Unit raise @encode.EncodeFailure {
  match @decode.view(cursor) {
    TextValue(s) => @encode.string_value(w, s)
    NumberValue(n) => @encode.number_value(w, n)
    ArrayValue(items) => {
      @encode.begin_array(w)
      for item in items {
        emit_cursor(item, w, false)
      }
      @encode.end_array(w)
    }
    ObjectValue(object) => {
      let keys = @decode.object_field_names(cursor).unwrap()
      keys.sort_by((a, b) => @unicode.compare_utf16(a, b))
      @encode.begin_object(w)
      for key in keys {
        if omit_identity && key == "witness_cid" {
          continue
        }
        @encode.key(w, key)
        emit_cursor(@decode.lookup(object, key).unwrap(), w, false)
      }
      @encode.end_object(w)
    }
    _ => raise @encode.InvalidStructure
  }
}

///|
/// Validate canonical wire bytes and their preimage CID, not external source
/// integrity, derivation arithmetic, governing-law application or enforcement.
pub fn admit(
  bytes : Bytes,
  expected_cid : String,
  limits : Limits,
) -> Result[WireWitness, Issue] {
  try {
    if limits.max_bytes < 0 || limits.max_nodes < 0 || limits.max_depth < 0 {
      raise Stop(InvalidLimits)
    }
    if bytes.length() > limits.max_bytes {
      raise Stop(BudgetExceeded)
    }
    if !valid_cid(expected_cid) {
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
          _ => raise Stop(InvalidWitness)
        }
    }
    let cursor = match
      @decode.admit(node, {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_string_bytes: limits.max_bytes,
        max_total_string_bytes: limits.max_bytes,
      }) {
      Ok(v) => v
      Err(_) => raise Stop(BudgetExceeded)
    }
    let o = get(
      @decode.closed_object(cursor, [
        "version", "unit", "value", "role", "source", "law_id", "derivation", "dependencies",
        "witness_cid",
      ]),
    )
    if text(o, "version") != "actql-bound-witness/0.1" {
      raise Stop(InvalidWitness)
    }
    let cid = identity(o, "witness_cid")
    if cid != expected_cid {
      raise Stop(IdentityMismatch)
    }
    let unit = read_unit(text(o, "unit"))
    let value = number(o, "value")
    let (source, role, source_cid) = read_source(
      get(@decode.required(o, "source")),
    )
    if text(o, "role") != role_name(role) ||
      (role == @arithmetic.AuthorGuard && value == 0L) {
      raise Stop(InvalidWitness)
    }
    let law = match @law.admit(text(o, "law_id")) {
      Some(v) => v
      None => raise Stop(InvalidWitness)
    }
    let dependencies = identities(
      get(@decode.required(o, "dependencies")),
      true,
    )
    let (derivation, refs) = read_derivation(
      get(@decode.required(o, "derivation")),
    )
    let available : Map[String, Bool] = Map([])
    for id in dependencies {
      available[id] = true
    }
    if !available.contains(source_cid) {
      raise Stop(InvalidWitness)
    }
    for id in refs {
      if !available.contains(id) {
        raise Stop(InvalidWitness)
      }
    }
    let witness : WireWitness = {
      cursor,
      cid,
      source,
      law,
      unit,
      role,
      value,
      derivation,
      dependencies,
    }
    try {
      let preimage = @encode.hashing_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      emit_cursor(cursor, preimage, true)
      let actual = "sha256:" + @encode.finish_hash(preimage)
      if actual != cid {
        raise Stop(IdentityMismatch)
      }
      let full = @encode.hashing_writer(
        limits.max_bytes,
        limits.max_nodes,
        limits.max_depth,
      )
      emit_cursor(cursor, full, false)
      if @encode.finish_hash(full) != @sha.hex(bytes) {
        raise Stop(NoncanonicalArtifact)
      }
    } catch {
      Stop(e) => raise Stop(e)
      _ => raise Stop(BudgetExceeded)
    }
    Ok(witness)
  } catch {
    Stop(e) => Err(e)
  }
}

///|
pub fn cid(w : WireWitness) -> String {
  w.cid
}

///|
pub fn source(w : WireWitness) -> Source {
  w.source
}

///|
pub fn law(w : WireWitness) -> @law.RegisteredLaw {
  w.law
}

///|
pub fn unit(w : WireWitness) -> @arithmetic.BoundUnit {
  w.unit
}

///|
pub fn role(w : WireWitness) -> @arithmetic.CandidateRole {
  w.role
}

///|
pub fn value(w : WireWitness) -> Int64 {
  w.value
}

///|
pub fn dependencies(w : WireWitness) -> Array[String] {
  w.dependencies.copy()
}

///|
pub fn dependency_count(w : WireWitness) -> Int {
  w.dependencies.length()
}

///|
pub fn witness_operand_count(w : WireWitness) -> Int {
  operand_count(w.derivation)
}

///|
pub fn derivation(w : WireWitness) -> Derivation {
  match w.derivation {
    Minimum(ids) => Minimum(ids.copy())
    other => other
  }
}

///|
pub fn emit(
  w : WireWitness,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_cursor(w.cursor, writer, false)
}
