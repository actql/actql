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
fn reference_string_equals(
  value : @identity.CanonicalValue?,
  expected : String,
) -> Bool {
  value is Some(@identity.String(actual)) && actual == expected
}

///|
fn reference_identity(
  contract : @contract.Contract,
  envelope : @identity.CanonicalValue,
) -> Result[(String, ReferenceDomain), ReferenceIssue] {
  guard envelope is @identity.Object(_) else { return Err(InvalidWire) }
  let get = name => @identity.object_field(envelope, name)
  let count = @identity.object_field_count(envelope).unwrap()
  match contract.shape {
    @contract.ResourceRef(resource_kind~) => {
      if count != 8 ||
        !reference_string_equals(get("$actql_ref"), "resource") ||
        !reference_string_equals(get("version"), "actql-resource-ref/0.1") ||
        !reference_string_equals(get("resource_kind"), resource_kind) ||
        !(get("provider_namespace") is Some(@identity.String(provider_space)) &&
        !provider_space.is_empty()) ||
        !(get("provider_identity_cid") is Some(@identity.String(provider)) &&
        valid_reference_cid(provider)) ||
        !(get("authority_scope_cid") is Some(@identity.String(authority)) &&
        valid_reference_cid(authority)) ||
        !(get("boundary_cid") is Some(@identity.String(boundary)) &&
        valid_reference_cid(boundary)) {
        return Err(ContractMismatch)
      }
      guard get("identity_cid") is Some(@identity.String(identity)) &&
        valid_reference_cid(identity) else {
        return Err(InvalidIdentity)
      }
      Ok((identity, Resource(resource_kind)))
    }
    @contract.ArtifactRef(media_type~) => {
      if count != 5 ||
        !reference_string_equals(get("$actql_ref"), "artifact") ||
        !reference_string_equals(get("version"), "actql-artifact-ref/0.1") ||
        !(get("media_type") is Some(@identity.String(media)) &&
        !media.is_empty()) ||
        !(get("metadata") is Some(@identity.Object(_))) {
        return Err(ContractMismatch)
      }
      if media_type is Some(required) &&
        !reference_string_equals(get("media_type"), required) {
        return Err(ContractMismatch)
      }
      guard get("artifact_ref_cid") is Some(@identity.String(identity)) &&
        valid_reference_cid(identity) else {
        return Err(InvalidIdentity)
      }
      guard get("media_type") is Some(@identity.String(media)) else {
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
  admit_reference_envelope(issuer, contract, envelope, canonical)
}

///|
// Canonical conversion and issuer-owned authority checks are separate stages.
// Both synchronous and resumed entry points use this exact authority boundary.
fn admit_reference_envelope(
  issuer : ReferenceIssuer,
  contract : @contract.Contract,
  envelope : @identity.CanonicalValue,
  canonical : String,
) -> Result[CheckedValue, ReferenceIssue] {
  let (identity, domain) = match reference_identity(contract, envelope) {
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
