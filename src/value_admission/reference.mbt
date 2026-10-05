///|
/// Trusted reference issuance boundary. Program text cannot construct this
/// capability; a Host binds its evidence validator and current authorization
/// check before admitting any opaque reference value.
pub struct ReferenceIssuer {
  identity : ReferenceIssuerIdentity
  mode : ReferenceIssuerMode
}

///|
/// Package-owned identity token. The public issuer and value stay opaque
/// without exposing the runtime reference representation in their API.
struct ReferenceIssuerIdentity {
  token : Ref[Unit]
}

///|
enum ReferenceIssuerMode {
  Issue((@contract.Contract, String) -> Bool, (String) -> Bool)
  Reissue((@contract.Contract, String) -> ReferenceValue?)
}

///|
enum ReferenceDomain {
  Resource(String)
  Artifact(String)
}

///|
/// Immutable admitted reference. Its tagged canonical envelope is retained for
/// wire emission while equality and canonical key ordering use only the
/// specification-selected identity CID.
pub struct ReferenceValue {
  issuer : ReferenceIssuerIdentity
  identity_cid : String
  domain : ReferenceDomain
  envelope : @identity.CanonicalValue
  wire : String
  authorize : () -> Bool
}

///|
pub(all) struct ReferenceLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_text_units : Int
} derive(Eq, Debug)

///|
pub(all) enum ReferenceIssue {
  InvalidLimits
  InvalidWire
  NonCanonicalWire
  ContractMismatch
  InvalidIdentity
  IssuerRejected
  Unauthorized
} derive(Eq, Debug)

///|
priv struct ReferenceCursorUsage {
  mut nodes : Int
  mut text_bytes : Int
}

///|
pub fn bind_reference_issuer(
  validate : (@contract.Contract, String) -> Bool,
  authorize : (String) -> Bool,
) -> ReferenceIssuer {
  { identity: { token: Ref(()), }, mode: Issue(validate, authorize), }
}

///|
/// Re-admit an exact previously issued occurrence without manufacturing a new
/// authority. The resolver must return the original opaque value for this
/// contract and canonical envelope.
pub fn bind_reference_reissuer(
  resolve : (@contract.Contract, String) -> ReferenceValue?,
) -> ReferenceIssuer {
  { identity: { token: Ref(()), }, mode: Reissue(resolve), }
}

///|
fn valid_reference_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index = 7; index < 71; index = index + 1 {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn json_string_equals(value : Json?, expected : String) -> Bool {
  value is Some(String(actual)) && actual == expected
}

///|
fn charge_reference_cursor_text(
  text : String,
  limits : ReferenceLimits,
  usage : ReferenceCursorUsage,
) -> Bool {
  if usage.text_bytes > limits.max_bytes {
    return false
  }
  match @scalar.admit_utf8_length(text, limits.max_bytes - usage.text_bytes) {
    Ok(bytes) => {
      usage.text_bytes += bytes
      true
    }
    Err(_) => false
  }
}

///|
fn reference_cursor_json(
  cursor : @decode.Cursor,
  limits : ReferenceLimits,
  usage : ReferenceCursorUsage,
  parent_depth : Int,
) -> Result[Json, ReferenceIssue] {
  if usage.nodes >= limits.max_nodes {
    return Err(InvalidWire)
  }
  usage.nodes += 1
  match @decode.view(cursor) {
    @decode.NullValue => Ok(Json::null())
    @decode.BoolValue(value) => Ok(Json::boolean(value))
    @decode.NumberValue(value) => Ok(Json::number(value))
    @decode.TextValue(value) =>
      if charge_reference_cursor_text(value, limits, usage) {
        Ok(Json::string(value))
      } else {
        Err(InvalidWire)
      }
    @decode.ArrayValue(items) => {
      if parent_depth >= limits.max_depth {
        return Err(InvalidWire)
      }
      let values = []
      for item in items {
        match reference_cursor_json(item, limits, usage, parent_depth + 1) {
          Ok(value) => values.push(value)
          Err(issue) => return Err(issue)
        }
      }
      Ok(Json::array(values))
    }
    @decode.ObjectValue(view) => {
      if parent_depth >= limits.max_depth {
        return Err(InvalidWire)
      }
      let names = match @decode.object_field_names(cursor) {
        Ok(value) => value
        Err(_) => return Err(InvalidWire)
      }
      let fields : Map[String, Json] = Map([])
      for name in names {
        if !charge_reference_cursor_text(name, limits, usage) {
          return Err(InvalidWire)
        }
        guard @decode.lookup(view, name) is Some(child) else {
          return Err(InvalidWire)
        }
        match reference_cursor_json(child, limits, usage, parent_depth + 1) {
          Ok(value) => fields[name] = value
          Err(issue) => return Err(issue)
        }
      }
      Ok(Json::object(fields))
    }
  }
}

///|
fn reference_identity(
  contract : @contract.Contract,
  parsed : Json,
) -> Result[(String, ReferenceDomain), ReferenceIssue] {
  guard parsed is Object(fields) else { return Err(InvalidWire) }
  match contract.shape {
    @contract.ResourceRef(resource_kind~) => {
      if fields.length() != 8 ||
        !json_string_equals(fields.get("$actql_ref"), "resource") ||
        !json_string_equals(fields.get("version"), "actql-resource-ref/0.1") ||
        !json_string_equals(fields.get("resource_kind"), resource_kind) ||
        !(fields.get("provider_namespace") is Some(String(provider_space)) &&
        !provider_space.is_empty()) ||
        !(fields.get("provider_identity_cid") is Some(String(provider)) &&
        valid_reference_cid(provider)) ||
        !(fields.get("authority_scope_cid") is Some(String(authority)) &&
        valid_reference_cid(authority)) ||
        !(fields.get("boundary_cid") is Some(String(boundary)) &&
        valid_reference_cid(boundary)) {
        return Err(ContractMismatch)
      }
      guard fields.get("identity_cid") is Some(String(identity)) &&
        valid_reference_cid(identity) else {
        return Err(InvalidIdentity)
      }
      Ok((identity, Resource(resource_kind)))
    }
    @contract.ArtifactRef(media_type~) => {
      if fields.length() != 5 ||
        !json_string_equals(fields.get("$actql_ref"), "artifact") ||
        !json_string_equals(fields.get("version"), "actql-artifact-ref/0.1") ||
        !(fields.get("media_type") is Some(String(media)) && !media.is_empty()) ||
        !(fields.get("metadata") is Some(Object(_))) {
        return Err(ContractMismatch)
      }
      if media_type is Some(required) &&
        !json_string_equals(fields.get("media_type"), required) {
        return Err(ContractMismatch)
      }
      guard fields.get("artifact_ref_cid") is Some(String(identity)) &&
        valid_reference_cid(identity) else {
        return Err(InvalidIdentity)
      }
      guard fields.get("media_type") is Some(String(media)) else {
        return Err(ContractMismatch)
      }
      Ok((identity, Artifact(media)))
    }
    _ => Err(ContractMismatch)
  }
}

///|
fn issue_parsed_reference(
  issuer : ReferenceIssuer,
  contract : @contract.Contract,
  parsed : Json,
  limits : ReferenceLimits,
) -> Result[CheckedValue, ReferenceIssue] {
  let envelope = @identity.from_json(
    parsed,
    limits.max_nodes,
    limits.max_depth,
    limits.max_text_units,
  ) catch {
    _ => return Err(InvalidWire)
  }
  let canonical = @identity.stringify_value(
    envelope,
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(InvalidWire)
  }
  let (identity, domain) = match reference_identity(contract, parsed) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match issuer.mode {
    Reissue(resolve) => {
      guard resolve(contract, canonical) is Some(source) &&
        source.wire == canonical &&
        source.identity_cid == identity &&
        reference_compatible(source, contract) else {
        return Err(IssuerRejected)
      }
      if !reference_available(source) {
        return Err(Unauthorized)
      }
      return Ok({ contract, value: Reference(source), })
    }
    Issue(validate, authorize) => {
      if !validate(contract, canonical) {
        return Err(IssuerRejected)
      }
      if !authorize(canonical) {
        return Err(Unauthorized)
      }
      Ok({
        contract,
        value: Reference({
          issuer: issuer.identity,
          identity_cid: identity,
          domain,
          envelope,
          wire: canonical,
          authorize: () => authorize(canonical),
        }),
      })
    }
  }
}

///|
fn issue_reference_cursor_usage(
  issuer : ReferenceIssuer,
  contract : @contract.Contract,
  cursor : @decode.Cursor,
  limits : ReferenceLimits,
) -> Result[(CheckedValue, Int, Int), ReferenceIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 0 ||
    limits.max_text_units < 0 {
    return Err(InvalidLimits)
  }
  let usage = { nodes: 0, text_bytes: 0, }
  let parsed = match reference_cursor_json(cursor, limits, usage, 0) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  match issue_parsed_reference(issuer, contract, parsed, limits) {
    Ok(value) => Ok((value, usage.nodes, usage.text_bytes))
    Err(issue) => Err(issue)
  }
}

///|
/// Admit a Host-issued reference after independent canonical-envelope checks
/// and issuer-owned evidence validation. This is intentionally separate from
/// authored JSON value admission.
pub fn issue_reference(
  issuer : ReferenceIssuer,
  contract : @contract.Contract,
  wire : String,
  limits : ReferenceLimits,
) -> Result[CheckedValue, ReferenceIssue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 0 ||
    limits.max_text_units < 0 {
    return Err(InvalidLimits)
  }
  if @scalar.admit_utf8_length(wire, limits.max_bytes) is Err(_) {
    return Err(InvalidWire)
  }
  let parsed = @json.parse(wire) catch { _ => return Err(InvalidWire) }
  let envelope = @identity.from_json(
    parsed,
    limits.max_nodes,
    limits.max_depth,
    limits.max_text_units,
  ) catch {
    _ => return Err(InvalidWire)
  }
  let canonical = @identity.stringify_value(
    envelope,
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(InvalidWire)
  }
  if canonical != wire {
    return Err(NonCanonicalWire)
  }
  issue_parsed_reference(issuer, contract, parsed, limits)
}

///|
pub fn reference_identity_cid(value : ReferenceValue) -> String {
  value.identity_cid
}

///|
pub fn reference_available(value : ReferenceValue) -> Bool {
  (value.authorize)()
}

///|
/// Reference equality has one Artifact domain regardless of media restriction;
/// Resource domains remain separated by ResourceKind.
pub fn reference_same_domain(
  left : ReferenceValue,
  right : ReferenceValue,
) -> Bool {
  match (left.domain, right.domain) {
    (Resource(a), Resource(b)) => a == b
    (Artifact(_), Artifact(_)) => true
    _ => false
  }
}

///|
/// Check whether a non-null issued value can inhabit the target reference
/// contract. Nullability does not alter a present value's domain.
pub fn reference_compatible(
  value : ReferenceValue,
  contract : @contract.Contract,
) -> Bool {
  match (value.domain, contract.shape) {
    (Resource(actual), @contract.ResourceRef(resource_kind=required)) =>
      actual == required
    (Artifact(_), @contract.ArtifactRef(media_type=None)) => true
    (Artifact(actual), @contract.ArtifactRef(media_type=Some(required))) =>
      actual == required
    _ => false
  }
}

///|
pub fn reference_wire(value : ReferenceValue) -> String {
  value.wire
}

///|
pub fn reference_same_issuer(
  left : ReferenceValue,
  right : ReferenceValue,
) -> Bool {
  physical_equal(left.issuer.token, right.issuer.token)
}
