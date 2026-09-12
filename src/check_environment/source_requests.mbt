///|
pub(all) struct SourceRequestLimits {
  max_work : Int
  max_roles : Int
}

///|
pub(all) enum SourceRequestIssueKind {
  InvalidLimits
  WorkLimit
  RoleLimit
  InvalidRequestContract
  InvalidAcquisition
  UnsupportedResponseCarrier
  MismatchedArity
  UnknownRequestField(String)
  UnknownResponseField(String)
  IncomparableKeys
  InvalidIdentity(String)
} derive(Eq, Debug)

///|
pub(all) struct SourceRequestIssue {
  kind : SourceRequestIssueKind
  source : @decode.Cursor?
}

///|
pub(all) enum SourceCardinality {
  ZeroOrOne
  ZeroOrMany
  One
  OneOrMany
} derive(Eq, Debug)

///|
pub struct CorrelationRole {
  name : String
  contract : @value_contract.Contract
  source : @decode.Cursor
}

///|
pub struct CorrelationPair {
  request : CorrelationRole
  response : CorrelationRole
}

///|
struct SourceCorrelation {
  source : @decode.Cursor
  pairs : Array[CorrelationPair]
  identity : Array[CorrelationRole]
  cardinality : SourceCardinality
}

///|
struct SourceViewRequestContract {
  item : Member
  reference : CatalogReference
  schema : @row.Schema
  correlation : SourceCorrelation?
}

///|
struct SourceRequestContracts {
  carriers : CarrierSchemas
  views : Array[SourceViewRequestContract]
  by_view : Map[Int, SourceViewRequestContract]
  work : Int
  roles : Int
}

///|
priv struct SourceRequestBudget {
  mut work : Int
  mut roles : Int
}

///|
priv suberror SourceRequestStop {
  SourceRequestStop(SourceRequestIssue)
}

///|
fn[T] request_fail(
  kind : SourceRequestIssueKind,
  c : @decode.Cursor,
) -> T raise SourceRequestStop {
  raise SourceRequestStop({ kind, source: Some(c), })
}

///|
fn request_charge(
  b : SourceRequestBudget,
  n : Int,
  c : @decode.Cursor,
) -> Unit raise SourceRequestStop {
  if n > b.work {
    request_fail(WorkLimit, c)
  }
  b.work -= n
}

///|
fn request_object(
  c : @decode.Cursor,
  b : SourceRequestBudget,
) -> @decode.ObjectView raise SourceRequestStop {
  request_charge(b, @decode.object_length(c).unwrap() + 1, c)
  @decode.open_object(c).unwrap()
}

///|
fn response_records(c : @carrier.Carrier) -> @carrier.Knowledge? {
  match c {
    @carrier.Relation(rows) => Some(rows)
    @carrier.EventValue(events) => Some(events.records)
    @carrier.VectorValue(vectors) => Some(@carrier.vector_records(vectors))
    _ => None
  }
}

///|
// Preceding shape admission guarantees canonical, distinct, nonempty text lists.
// Charge all declared positions before allocating typed role arrays.
fn request_role_name(
  c : @decode.Cursor,
  b : SourceRequestBudget,
) -> String raise SourceRequestStop {
  let name = @decode.text(c).unwrap()
  request_charge(b, name.length() + 1, c)
  name
}

///|
fn response_role(
  c : @decode.Cursor,
  records : @carrier.Knowledge,
  b : SourceRequestBudget,
) -> CorrelationRole raise SourceRequestStop {
  let name = request_role_name(c, b)
  match @carrier.lookup(records, @row.Unqualified(name)) {
    @carrier.Present(field) =>
      { name, contract: field.contract.unwrap(), source: c, }
    _ => request_fail(UnknownResponseField(name), c)
  }
}

///|
fn read_source_correlation(
  root : @decode.Cursor,
  request : @row.Schema,
  records : @carrier.Knowledge,
  b : SourceRequestBudget,
) -> SourceCorrelation raise SourceRequestStop {
  let obj = request_object(root, b)
  let req = @decode.required(obj, "request_fields").unwrap()
  let res = @decode.required(obj, "response_fields").unwrap()
  let ids = @decode.required(obj, "identity").unwrap()
  let count = @decode.array_length(req).unwrap()
  if count != @decode.array_length(res).unwrap() {
    request_fail(MismatchedArity, res)
  }
  let id_count = @decode.array_length(ids).unwrap()
  for n in [count, count, id_count] {
    if n > b.roles {
      request_fail(RoleLimit, root)
    }
    b.roles -= n
  }
  let pairs = []
  for i in 0..<count {
    let c = @decode.element_at(req, i).unwrap()
    let name = request_role_name(c, b)
    let contract = match @row.lookup(request, @row.Unqualified(name)) {
      Some(t) => t
      None => request_fail(UnknownRequestField(name), c)
    }
    let response = response_role(
      @decode.element_at(res, i).unwrap(),
      records,
      b,
    )
    if !@value_contract.key_comparable(contract, response.contract) {
      request_fail(IncomparableKeys, response.source)
    }
    pairs.push({ request: { name, contract, source: c, }, response, })
  }
  let identity = []
  for i in 0..<id_count {
    let role = response_role(@decode.element_at(ids, i).unwrap(), records, b)
    if role.contract.nullable ||
      !@value_contract.key_comparable(role.contract, role.contract) {
      request_fail(InvalidIdentity(role.name), role.source)
    }
    identity.push(role)
  }
  let cardinality = match
    @decode.text(@decode.required(obj, "cardinality").unwrap()).unwrap() {
    "zero_or_one" => ZeroOrOne
    "zero_or_many" => ZeroOrMany
    "one" => One
    _ => OneOrMany
  }
  { source: root, pairs, identity, cardinality, }
}

///|
/// Resolve declared request and correlation roles, not request values or actual
/// response completeness, cardinality and identity uniqueness.
pub fn check_source_request_contracts(
  carriers : CarrierSchemas,
  limits : SourceRequestLimits,
) -> Result[SourceRequestContracts, SourceRequestIssue] {
  if limits.max_work < 0 || limits.max_roles < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let values = carriers.modes.shapes.values
  let b = { work: limits.max_work, roles: limits.max_roles, }
  let requests : Map[Int, CatalogReference] = Map([])
  let views = []
  let by_view : Map[Int, SourceViewRequestContract] = Map([])
  try {
    for reference in values.policies.references.references {
      request_charge(b, 1, reference.source)
      // The generated table contains one request_schema route per SourceView.
      if reference.contract.kind == "request_schema" {
        requests[member_index(reference.item)] = reference
      }
    }
    for view in carriers.modes.views {
      let root = member_body(view.item)
      let obj = request_object(root, b)
      let reference = requests[member_index(view.item)]
      let typed = values.by_cid[reference.contract.cid]
      let schema = match @row.from_object(typed.contract) {
        Ok(s) => s
        Err(_) => request_fail(InvalidRequestContract, reference.contract.body)
      }
      let acquisition = request_object(
        @decode.required(obj, "acquisition").unwrap(),
        b,
      )
      let correlation = match @decode.lookup(acquisition, "correlation") {
        None => None
        Some(source) => {
          let kind = @decode.required(acquisition, "kind").unwrap()
          if @decode.text(kind).unwrap() == "scan" {
            request_fail(InvalidAcquisition, kind)
          }
          let carrier = carriers.views[member_index(view.item)].schema.carrier
          let records = match response_records(carrier) {
            Some(r) => r
            None => request_fail(UnsupportedResponseCarrier, source)
          }
          Some(read_source_correlation(source, schema, records, b))
        }
      }
      let checked = { item: view.item, reference, schema, correlation, }
      views.push(checked)
      by_view[member_index(view.item)] = checked
    }
    Ok({
      carriers,
      views,
      by_view,
      work: limits.max_work - b.work,
      roles: limits.max_roles - b.roles,
    })
  } catch {
    SourceRequestStop(e) => Err(e)
  }
}

///|
pub fn source_request_carriers(v : SourceRequestContracts) -> CarrierSchemas {
  v.carriers
}

///|
pub fn source_request_usage(v : SourceRequestContracts) -> (Int, Int, Int) {
  (v.work, v.roles, v.views.length())
}

///|
pub fn source_request_at(
  v : SourceRequestContracts,
  i : Int,
) -> SourceViewRequestContract? {
  v.views.get(i)
}

///|
pub fn source_request_for(
  v : SourceRequestContracts,
  item : Member,
) -> SourceViewRequestContract? {
  if member_section(item) != SourceViews ||
    !physical_equal(
      member_environment(item),
      v.carriers.modes.shapes.values.policies.references.contents.registry.environment,
    ) {
    return None
  }
  v.by_view.get(member_index(item))
}

///|
pub fn source_request_member(v : SourceViewRequestContract) -> Member {
  v.item
}

///|
pub fn source_request_reference(
  v : SourceViewRequestContract,
) -> CatalogReference {
  v.reference
}

///|
pub fn source_request_schema(v : SourceViewRequestContract) -> @row.Schema {
  v.schema
}

///|
pub fn source_request_correlation(
  v : SourceViewRequestContract,
) -> SourceCorrelation? {
  v.correlation
}

///|
pub fn source_correlation_source(v : SourceCorrelation) -> @decode.Cursor {
  v.source
}

///|
pub fn source_correlation_cardinality(
  v : SourceCorrelation,
) -> SourceCardinality {
  v.cardinality
}

///|
pub fn source_correlation_pair_count(v : SourceCorrelation) -> Int {
  v.pairs.length()
}

///|
pub fn source_correlation_pair_at(
  v : SourceCorrelation,
  i : Int,
) -> CorrelationPair? {
  v.pairs.get(i)
}

///|
pub fn source_correlation_identity_count(v : SourceCorrelation) -> Int {
  v.identity.length()
}

///|
pub fn source_correlation_identity_at(
  v : SourceCorrelation,
  i : Int,
) -> CorrelationRole? {
  v.identity.get(i)
}
