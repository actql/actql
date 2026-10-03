///|
pub(all) struct CarrierSchemaLimits {
  max_work : Int
  max_schemas : Int
  bodies : @graph.Limits
}

///|
pub(all) enum CarrierSchemaIssueKind {
  InvalidLimits
  WorkLimit
  SchemaLimit
  BudgetExceeded
  InvalidBody
  InvalidType(@value_contract.AdmissionError)
  InvalidGraph(@graph.ReadIssue)
  InvalidRole(@carrier.Issue)
  CarrierMismatch
} derive(Eq, Debug)

///|
pub(all) struct CarrierSchemaIssue {
  kind : CarrierSchemaIssueKind
  source : @decode.Cursor?
}

///|
struct CarrierSchema {
  envelope : ContractEnvelope
  carrier : @carrier.Carrier
  body_cid : String
}

///|
struct SourceViewCarrier {
  reference : CatalogReference
  schema : CarrierSchema
}

///|
struct CarrierSchemas {
  modes : SourceReadModes
  entries : Array[CarrierSchema]
  by_cid : Map[String, CarrierSchema]
  views : Map[Int, SourceViewCarrier]
  bytes : Int
  nodes : Int
  work : Int
}

///|
priv suberror CarrierStop {
  CarrierStop(CarrierSchemaIssue)
}

///|
fn[T] carrier_fail(
  kind : CarrierSchemaIssueKind,
  c : @decode.Cursor,
) -> T raise CarrierStop {
  raise CarrierStop({ kind, source: Some(c), })
}

///|
fn carrier_required(
  obj : @decode.ObjectView,
  name : String,
  root : @decode.Cursor,
) -> @decode.Cursor raise CarrierStop {
  match @decode.lookup(obj, name) {
    Some(c) => c
    None => carrier_fail(InvalidBody, root)
  }
}

///|
fn carrier_name(
  obj : @decode.ObjectView,
  name : String,
  root : @decode.Cursor,
) -> String raise CarrierStop {
  let c = carrier_required(obj, name, root)
  match @decode.text(c) {
    Ok(s) => s
    Err(_) => carrier_fail(InvalidBody, c)
  }
}

///|
fn carrier_records(
  root : @decode.Cursor,
  limits : @graph.Limits,
) -> @carrier.Knowledge raise CarrierStop {
  let contract = match
    @value_contract.read_checked(root, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_bytes,
    }) {
    Ok(c) => c
    Err(e) => carrier_fail(InvalidType(e), root)
  }
  match @row.from_object(contract) {
    Ok(rows) => @carrier.typed_rows(rows)
    Err(_) => carrier_fail(InvalidBody, root)
  }
}

///|
// The caller first measures the entire canonical body within cumulative bounds.
// These local construction bounds cannot reset the aggregate admission budget.
fn read_carrier_body(
  root : @decode.Cursor,
  limits : @graph.Limits,
  max_contract_work : Int,
) -> (@carrier.Carrier, Int) raise CarrierStop {
  let count = @decode.object_length(root).unwrap_or(0)
  if count != 4 && count != 6 {
    carrier_fail(InvalidBody, root)
  }
  let obj = @decode.open_object(root).unwrap()
  if @decode.lookup(obj, "version") is None {
    return (@carrier.relation(carrier_records(root, limits)), 0)
  }
  let version = carrier_name(obj, "version", root)
  if version == "actql-property-graph-contract/0.1" {
    return match
      @graph.read_property_graph_cursor_usage(root, limits, max_contract_work~) {
      Ok((v, used)) => (@carrier.graph_carrier(@graph.property_graph(v)), used)
      Err(e) => carrier_fail(InvalidGraph(e), root)
    }
  }
  let names = match version {
    "actql-events-contract/0.1" => ["version", "records", "id", "time"]
    "actql-vectors-contract/0.1" => ["version", "records", "ids", "components"]
    _ => carrier_fail(InvalidBody, root)
  }
  if @decode.closed_object(root, names) is Err(_) {
    carrier_fail(InvalidBody, root)
  }
  let records = carrier_records(carrier_required(obj, "records", root), limits)
  let result = if version == "actql-events-contract/0.1" {
    @carrier.events(
      records,
      id=@row.Unqualified(carrier_name(obj, "id", root)),
      time=@row.Unqualified(carrier_name(obj, "time", root)),
    )
  } else {
    let list = carrier_required(obj, "ids", root)
    let n = match @decode.array_length(list) {
      Some(n) => n
      None => carrier_fail(InvalidBody, list)
    }
    let ids = []
    for i in 0..<n {
      let c = @decode.element_at(list, i).unwrap()
      let name = match @decode.text(c) {
        Ok(s) => s
        Err(_) => carrier_fail(InvalidBody, c)
      }
      ids.push(@row.Unqualified(name))
    }
    @carrier.vectors(
      records,
      ids~,
      components=@row.Unqualified(carrier_name(obj, "components", root)),
      max_identity_fields=limits.max_nodes,
    )
  }
  match result {
    Ok(c) => (c, 0)
    Err(e) => carrier_fail(InvalidRole(e), root)
  }
}

///|
fn carrier_spelling(c : @carrier.Carrier) -> String {
  match @carrier.kind(c) {
    RelationKind => "relation"
    GraphKind => "graph"
    EventsKind => "events"
    VectorsKind => "vectors"
  }
}

///|
/// Checks all supplied carrier declarations and SourceView output correspondence.
/// This retains structural types only, not observed identity, order or authority.
pub fn check_carrier_schemas(
  modes : SourceReadModes,
  limits : CarrierSchemaLimits,
) -> Result[CarrierSchemas, CarrierSchemaIssue] {
  if limits.max_work < 0 ||
    limits.max_schemas < 0 ||
    limits.bodies.max_bytes < 0 ||
    limits.bodies.max_nodes < 0 ||
    limits.bodies.max_depth < 0 {
    return Err({ kind: InvalidLimits, source: None, })
  }
  let references = modes.shapes.values.policies.references
  let entries = []
  let by_cid : Map[String, CarrierSchema] = Map([])
  let views : Map[Int, SourceViewCarrier] = Map([])
  let mut bytes = 0
  let mut nodes = 0
  let mut work = 0
  try {
    for envelope in references.contents.registry.entries {
      if work >= limits.max_work {
        carrier_fail(WorkLimit, envelope.body)
      }
      work += 1
      if envelope.kind != "carrier_schema" {
        continue
      }
      if entries.length() >= limits.max_schemas {
        carrier_fail(SchemaLimit, envelope.body)
      }
      let (body_cid, b, n) = hash(
        envelope.body,
        {
          max_bytes: limits.bodies.max_bytes - bytes,
          max_nodes: limits.bodies.max_nodes - nodes,
          max_depth: limits.bodies.max_depth,
          max_members: 0,
        },
        false,
      ) catch {
        _ => carrier_fail(BudgetExceeded, envelope.body)
      }
      bytes += b
      nodes += n
      let (carrier, validation_work) = read_carrier_body(
        envelope.body,
        { max_bytes: b, max_nodes: n, max_depth: limits.bodies.max_depth, },
        limits.max_work - work,
      )
      work += validation_work
      let schema = { envelope, carrier, body_cid, }
      entries.push(schema)
      by_cid[envelope.cid] = schema
    }
    for reference in references.references {
      if work >= limits.max_work {
        carrier_fail(WorkLimit, reference.source)
      }
      work += 1
      if reference.contract.kind != "carrier_schema" {
        continue
      }
      // The generated reference routes admit this role only at SourceView.output.
      let root = member_body(reference.item)
      let cost = @decode.object_length(root).unwrap()
      if cost > limits.max_work - work {
        carrier_fail(WorkLimit, root)
      }
      work += cost
      let obj = @decode.open_object(root).unwrap()
      let output = @decode.open_object(@decode.required(obj, "output").unwrap()).unwrap()
      let name = @decode.required(output, "carrier").unwrap()
      let schema = by_cid[reference.contract.cid]
      if @decode.text(name).unwrap() != carrier_spelling(schema.carrier) {
        carrier_fail(CarrierMismatch, name)
      }
      views[member_index(reference.item)] = { reference, schema, }
    }
    Ok({ modes, entries, by_cid, views, bytes, nodes, work, })
  } catch {
    CarrierStop(e) => Err(e)
  }
}

///|
pub fn carrier_schema_modes(v : CarrierSchemas) -> SourceReadModes {
  v.modes
}

///|
pub fn carrier_schema_usage(v : CarrierSchemas) -> (Int, Int, Int, Int) {
  (v.bytes, v.nodes, v.work, v.entries.length())
}

///|
pub fn carrier_schema_at(v : CarrierSchemas, i : Int) -> CarrierSchema? {
  v.entries.get(i)
}

///|
pub fn carrier_schema_envelope(v : CarrierSchema) -> ContractEnvelope {
  v.envelope
}

///|
pub fn carrier_schema_value(v : CarrierSchema) -> @carrier.Carrier {
  v.carrier
}

///|
pub fn carrier_schema_body_cid(v : CarrierSchema) -> String {
  v.body_cid
}

///|
pub fn carrier_schema_for(
  v : CarrierSchemas,
  envelope : ContractEnvelope,
) -> CarrierSchema? {
  if !physical_equal(
      member_environment(envelope.item),
      v.modes.shapes.values.policies.references.contents.registry.environment,
    ) {
    return None
  }
  v.by_cid.get(envelope.cid)
}

///|
pub fn source_view_carrier(
  v : CarrierSchemas,
  item : Member,
) -> SourceViewCarrier? {
  if member_section(item) != SourceViews ||
    !physical_equal(
      member_environment(item),
      v.modes.shapes.values.policies.references.contents.registry.environment,
    ) {
    return None
  }
  v.views.get(member_index(item))
}

///|
pub fn source_view_carrier_reference(v : SourceViewCarrier) -> CatalogReference {
  v.reference
}

///|
pub fn source_view_carrier_schema(v : SourceViewCarrier) -> CarrierSchema {
  v.schema
}
