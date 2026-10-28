///|
let relation_keys_component_key : String = "relation_keys"

///|
let relation_keys_list_key : String = "candidate_keys"

///|
// Only this component is closed. Other carrier-facts extensions retain their
// existing admission and support rules; their data is not key evidence.
priv struct RelationKeyFacts {
  envelope : ContractEnvelope
  tuples : Array[(@decode.Cursor, Array[String])]
}

///|
/// A conditional declaration retained with its original Catalog and schema.
/// This is neither a runtime uniqueness certificate nor an author input key.
struct SourceRelationKeys {
  reference : CatalogReference
  schema : CarrierSchema
  facts : RelationKeyFacts
}

///|
priv struct RelationKeyBudget {
  mut key_work : Int
  meter : CarrierSchemaMeter?
}

///|
fn relation_key_charge(
  budget : RelationKeyBudget,
  source : @decode.Cursor,
  amount : Int,
) -> Unit raise CarrierStop {
  if amount < 0 || amount > budget.key_work {
    carrier_fail(WorkLimit, source)
  }
  budget.key_work -= amount
  if budget.meter is Some(meter) {
    meter.work += amount
  }
}

///|
fn read_relation_key_facts(
  envelope : ContractEnvelope,
  max_work : Int,
  meter? : CarrierSchemaMeter? = None,
) -> (RelationKeyFacts?, Int) raise CarrierStop {
  let root = envelope.body
  let budget : RelationKeyBudget = { key_work: max_work, meter, }
  let object = @decode.open_object(root).unwrap_or_else(() => {
    carrier_fail(InvalidBody, root)
  })
  relation_key_charge(budget, root, @decode.object_length(root).unwrap() + 1)
  guard @decode.lookup(object, relation_keys_component_key) is Some(component) else {
    return (None, max_work - budget.key_work)
  }
  if @decode.object_length(component) != Some(1) ||
    @decode.closed_object(component, [relation_keys_list_key]) is Err(_) {
    carrier_fail(InvalidBody, component)
  }
  relation_key_charge(budget, component, 2)
  let keys = @decode.required(
    @decode.open_object(component).unwrap(),
    relation_keys_list_key,
  ).unwrap_or_else(() => carrier_fail(InvalidBody, component))
  let count = @decode.array_length(keys).unwrap_or_else(() => {
    carrier_fail(InvalidBody, keys)
  })
  if count == 0 {
    carrier_fail(InvalidBody, keys)
  }
  relation_key_charge(budget, keys, count)
  let tuples = []
  let seen : Map[Array[String], Bool] = Map([])
  for index in 0..<count {
    let tuple = @decode.element_at(keys, index).unwrap()
    let arity = @decode.array_length(tuple).unwrap_or_else(() => {
      carrier_fail(InvalidBody, tuple)
    })
    if arity == 0 {
      carrier_fail(InvalidBody, tuple)
    }
    relation_key_charge(budget, tuple, arity)
    let fields = []
    let names : Map[String, Bool] = Map([])
    for field in 0..<arity {
      let at = @decode.element_at(tuple, field).unwrap()
      let name = @decode.text(at).unwrap_or_else(() => {
        carrier_fail(InvalidBody, at)
      })
      relation_key_charge(budget, at, name.length())
      if name == "" || names.contains(name) {
        carrier_fail(InvalidBody, at)
      }
      names[name] = true
      fields.push(name)
    }
    if seen.contains(fields) {
      carrier_fail(InvalidBody, tuple)
    }
    seen[fields] = true
    tuples.push((tuple, fields))
  }
  (Some({ envelope, tuples, }), max_work - budget.key_work)
}

///|
fn bind_source_relation_keys(
  reference : CatalogReference,
  schema : CarrierSchema,
  facts : RelationKeyFacts,
  max_work : Int,
  meter? : CarrierSchemaMeter? = None,
) -> (SourceRelationKeys, Int) raise CarrierStop {
  if !physical_equal(reference.contract, facts.envelope) {
    carrier_fail(InvalidBody, reference.source)
  }
  let rows = @carrier.relation_rows(schema.carrier).unwrap_or_else(() => {
    carrier_fail(CarrierMismatch, reference.source)
  })
  let budget : RelationKeyBudget = { key_work: max_work, meter, }
  relation_key_charge(budget, reference.source, facts.tuples.length())
  for (source, fields) in facts.tuples {
    relation_key_charge(budget, source, fields.length())
    for name in fields {
      relation_key_charge(budget, source, name.length())
      guard @carrier.lookup(rows, @row.Unqualified(name)) is Present(field) &&
        field.presence == @row.Required &&
        field.contract is Some(contract) &&
        !contract.nullable &&
        @value_contract.key_comparable(contract, contract) else {
        carrier_fail(InvalidBody, source)
      }
    }
  }
  ({ reference, schema, facts, }, max_work - budget.key_work)
}

///|
pub fn source_view_relation_keys(
  view : SourceViewCarrier,
) -> SourceRelationKeys? {
  view.relation_keys
}

///|
pub fn source_relation_key_count(keys : SourceRelationKeys) -> Int {
  keys.facts.tuples.length()
}

///|
/// The exact admitted declaration cursor; never a reconstructed local assertion.
pub fn source_relation_key_at(
  keys : SourceRelationKeys,
  index : Int,
) -> @decode.Cursor? {
  keys.facts.tuples.get(index).map(tuple => tuple.0)
}

///|
pub fn source_relation_key_schema(keys : SourceRelationKeys) -> CarrierSchema {
  keys.schema
}

///|
pub fn source_relation_key_reference(
  keys : SourceRelationKeys,
) -> CatalogReference {
  keys.reference
}
