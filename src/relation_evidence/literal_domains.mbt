///|
pub(all) enum LiteralValue {
  Text(String)
  Number(Double)
  Boolean(Bool)
} derive(Eq, Debug)

///|
pub enum LiteralOrigin {
  Binding(@relation.CheckedOperation, Int)
  Union(@append.CheckedAppend, LiteralDomain, LiteralDomain)
}

///|
struct LiteralDomain {
  values : Array[LiteralValue]
  origin : LiteralOrigin
}

///|
struct LiteralDomains {
  schema : @row.Schema
  fields : Map[String, LiteralDomain]
}

///|
pub struct LiteralTransfer {
  domains : LiteralDomains
  work : Int
  text_bytes : Int
}

///|
pub fn literal_origin(value : LiteralDomain) -> LiteralOrigin {
  value.origin
}

///|
pub fn literal_value_count(value : LiteralDomain) -> Int {
  value.values.length()
}

///|
pub fn literal_value_at(value : LiteralDomain, index : Int) -> LiteralValue? {
  value.values.get(index)
}

///|
pub fn literal_domain(
  value : LiteralDomains,
  field : @row.FieldName,
) -> LiteralDomain? {
  value.fields.get(field_key(field))
}

///|
pub fn admit_literal_domains(
  source : @decode.Cursor,
  domains : LiteralDomains,
  limits : TransferLimits,
) -> Result[LiteralTransfer, Issue] {
  try {
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    for (name, domain) in domains.fields {
      spend(b, source, 1)
      let bytes = @scalar.admit_utf8_length(name, b.text).unwrap_or(-1)
      if bytes < 0 {
        fail(source, LimitExceeded)
      }
      b.text -= bytes
      for value in domain.values {
        literal_charge(b, source, value)
      }
    }
    Ok({
      domains,
      work: limits.max_work - b.work,
      text_bytes: limits.max_name_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
fn literal_charge(
  b : TransferBudget,
  source : @decode.Cursor,
  value : LiteralValue,
) -> Unit raise Stop {
  spend(b, source, 1)
  let bytes = match value {
    Text(text) => @scalar.admit_utf8_length(text, b.text).unwrap_or(-1)
    Number(_) => 8
    Boolean(_) => 1
  }
  if bytes < 0 || bytes > b.text {
    fail(source, LimitExceeded)
  }
  b.text -= bytes
}

///|
fn binding_literal(
  b : TransferBudget,
  op : @relation.CheckedOperation,
  i : Int,
) -> LiteralDomain? raise Stop {
  let source = @relation.source(op)
  let expression = @relation.binding_expression_at(op, i).unwrap()
  guard @typing.node_form(expression, 0) is Some(Expression("literal", body)) else {
    return None
  }
  let value = match @decode.view(body) {
    TextValue(value) => Text(value)
    NumberValue(value) => Number(value)
    BoolValue(value) => Boolean(value)
    _ => return None
  }
  literal_charge(b, source, value)
  Some({ values: [value], origin: Binding(op, i), })
}

///|
/// Only direct scalar literals establish domains. General expressions and
/// Parameter references are not evaluated to manufacture static value facts.
pub fn transfer_literal_domains(
  previous : LiteralDomains?,
  op : @relation.CheckedOperation,
  limits : TransferLimits,
) -> Result[LiteralTransfer, Issue] {
  try {
    let source = @relation.source(op)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    if previous is Some(previous) &&
      !physical_equal(previous.schema, @relation.input_schema(op)) {
      fail(source, InputContractMismatch)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    let fields : Map[String, LiteralDomain] = Map([])
    let schema = @relation.output_schema(op)
    let put = fn(field : @row.FieldName, domain : LiteralDomain?) raise Stop {
      charge(b, source, field)
      if domain is Some(domain) {
        fields[field_key(field)] = domain
      }
    }
    match @relation.operation(op) {
      Derive => {
        spend(b, source, @relation.binding_count(op))
        let slots : Array[LiteralDomain?] = []
        let outputs : Map[String, LiteralDomain?] = Map([])
        for i in 0..<@relation.binding_count(op) {
          let copy = @relation.binding_copy_at(op, i).unwrap()
          let domain = match copy.input {
            Some(InputField(field)) =>
              previous.bind(v => literal_domain(v, field))
            Some(PriorSlot(slot)) => slots[slot]
            None => binding_literal(b, op, i)
          }
          slots.push(domain)
          if copy.output is Some(name) {
            charge(b, source, Unqualified(name))
            outputs[field_key(Unqualified(name))] = domain
          }
        }
        spend(b, source, @row.field_count(schema))
        for i in 0..<@row.field_count(schema) {
          let field = @row.field_at(schema, i).unwrap().name
          put(
            field,
            match outputs.get(field_key(field)) {
              Some(v) => v
              None => previous.bind(v => literal_domain(v, field))
            },
          )
        }
      }
      Select | Rename | Drop | Distinct =>
        if @relation.row_operation(op) is Some(DistinctRows) {
          spend(b, source, @row.field_count(schema))
          for i in 0..<@row.field_count(schema) {
            let field = @row.field_at(schema, i).unwrap().name
            put(field, previous.bind(v => literal_domain(v, field)))
          }
        } else {
          let projection = @relation.projection(op)
          spend(b, source, projection.length())
          for p in projection {
            put(p.output, previous.bind(v => literal_domain(v, p.input)))
          }
        }
      Unpivot => {
        spend(b, source, @relation.unpivot_keep_count(op))
        for i in 0..<@relation.unpivot_keep_count(op) {
          let field = @relation.unpivot_keep_at(op, i).unwrap().field
          put(field, previous.bind(v => literal_domain(v, field)))
        }
      }
      Filter
      | Sort
      | Take
      | AssertRows
      | DedupeRows
      | TopK
      | TopKBy
      | Lag
      | Analytic
      | JsonPick
      | WatermarkRows
      | Unnest => {
        spend(b, source, @row.field_count(schema))
        for i in 0..<@row.field_count(schema) {
          let field = @row.field_at(schema, i).unwrap().name
          put(field, previous.bind(v => literal_domain(v, field)))
        }
      }
      Group | Pivot => ()
    }
    Ok({
      domains: { schema, fields, },
      work: limits.max_work - b.work,
      text_bytes: limits.max_name_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}

///|
fn union_domain(
  b : TransferBudget,
  source : @decode.Cursor,
  op : @append.CheckedAppend,
  left : LiteralDomain,
  right : LiteralDomain,
) -> LiteralDomain raise Stop {
  spend(b, source, left.values.length() + right.values.length())
  let values = left.values.copy()
  for value in right.values {
    literal_charge(b, source, value)
    let mut found = false
    for old in values {
      literal_charge(b, source, old)
      if value == old {
        found = true
        break
      }
    }
    if !found {
      values.push(value)
    }
  }
  { values, origin: Union(op, left, right), }
}

///|
pub fn append_literal_domains(
  left : LiteralDomains?,
  right : LiteralDomains?,
  op : @append.CheckedAppend,
  limits : TransferLimits,
) -> Result[LiteralTransfer, Issue] {
  try {
    let source = @append.source(op)
    if limits.max_work < 0 || limits.max_name_bytes < 0 {
      fail(source, InvalidLimits)
    }
    if left is Some(v) &&
      !physical_equal(v.schema, @append.input_schema(op, Left)) {
      fail(source, InputContractMismatch)
    }
    if right is Some(v) &&
      !physical_equal(v.schema, @append.input_schema(op, Right)) {
      fail(source, InputContractMismatch)
    }
    let b : TransferBudget = {
      work: limits.max_work,
      text: limits.max_name_bytes,
    }
    let schema = @append.output_schema(op)
    let fields : Map[String, LiteralDomain] = Map([])
    spend(b, source, @row.field_count(schema))
    for i in 0..<@row.field_count(schema) {
      let field = @row.field_at(schema, i).unwrap().name
      charge(b, source, field)
      if left.bind(v => literal_domain(v, field)) is Some(l) &&
        right.bind(v => literal_domain(v, field)) is Some(r) {
        fields[field_key(field)] = union_domain(b, source, op, l, r)
      }
    }
    Ok({
      domains: { schema, fields, },
      work: limits.max_work - b.work,
      text_bytes: limits.max_name_bytes - b.text,
    })
  } catch {
    Stop(e) => Err(e)
  }
}
