///|
pub enum SchemaIssue {
  InvalidLimits
  NonFlatSchema
  BudgetExceeded
  MissingExpectedColumn(String)
  TypeMismatch
  PrimaryKey(@evidence.Issue)
  InvalidOrderField(String)
}

///|
struct SchemaAgreement {
  declaration : Checked
  schema : @schema.Schema
  carrier : @carrier.Carrier
  key : @evidence.KeyedRelation?
  usage : Usage
}

///|
priv struct TypeBudget {
  mut nodes : Int
  mut text : Int
  depth : Int
}

///|
priv suberror SchemaStop {
  SchemaStop(SchemaIssue)
}

///|
fn type_text(b : TypeBudget, text : String) -> Unit raise SchemaStop {
  match @scalar.admit_utf8_length(text, b.text) {
    Ok(n) => b.text -= n
    Err(_) => raise SchemaStop(BudgetExceeded)
  }
}

///|
fn type_scan(
  b : TypeBudget,
  root : @contract.Contract,
) -> Unit raise SchemaStop {
  let pending = [(root, 0)]
  while pending.pop() is Some((c, depth)) {
    if b.nodes == 0 || depth > b.depth {
      raise SchemaStop(BudgetExceeded)
    }
    b.nodes -= 1
    match c.shape {
      @contract.Array(item, ..) => pending.push((item, depth + 1))
      @contract.Object(fields) => {
        let count = @contract.field_count(fields)
        if count > b.nodes {
          raise SchemaStop(BudgetExceeded)
        }
        for i in 0..<count {
          let field = @contract.field_at(fields, i).unwrap()
          type_text(b, field.name)
          pending.push((field.contract, depth + 1))
        }
      }
      @contract.ResourceRef(resource_kind~) => type_text(b, resource_kind)
      @contract.ArtifactRef(media_type=Some(media)) => type_text(b, media)
      _ => ()
    }
  }
}

///|
/// Prove type-assertion agreement only, not snapshot identity/source/authority.
/// Keep the supplied stronger schema without modifying authored source.
pub fn check_schema(
  declaration : Checked,
  schema : @schema.Schema,
  limits : Limits,
) -> Result[SchemaAgreement, SchemaIssue] {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  try {
    let actual = match @schema.as_object(schema) {
      Some(c) => c
      None => raise SchemaStop(NonFlatSchema)
    }
    let b = {
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
      depth: limits.max_depth,
    }
    type_scan(b, actual)
    let authored = @carrier.complete_schema(
      @carrier.relation_rows(declaration.carrier).unwrap(),
    )
    if authored is Some(authored) {
      let expected = @schema.as_object(authored).unwrap()
      type_scan(b, expected)
      let valid = @contract.assignable(actual, expected, limits.max_nodes) catch {
        _ => raise SchemaStop(BudgetExceeded)
      }
      if !valid {
        raise SchemaStop(TypeMismatch)
      }
    }
    for name in declaration.expected {
      if b.nodes == 0 {
        raise SchemaStop(BudgetExceeded)
      }
      b.nodes -= 1
      type_text(b, name)
      if @schema.lookup(schema, @schema.Unqualified(name)) is None {
        raise SchemaStop(MissingExpectedColumn(name))
      }
    }
    let carrier = @carrier.relation(@carrier.typed_rows(schema))
    let key = match declaration.key {
      None => None
      Some(key) => {
        // Recheck formerly unknown field types. Retain conditional admission,
        // never interpret complete schema evidence as proof of row uniqueness.
        let count = @evidence.key_field_count(key)
        if count > b.nodes {
          raise SchemaStop(BudgetExceeded)
        }
        b.nodes -= count
        let checked = match
          @evidence.declare_primary_key(@evidence.key_source(key), carrier, {
            max_fields: count,
            max_name_bytes: b.text,
          }) {
          Ok(v) => v
          Err(e) => {
            if e.kind == @evidence.LimitExceeded {
              raise SchemaStop(BudgetExceeded)
            }
            raise SchemaStop(PrimaryKey(e))
          }
        }
        for i in 0..<count {
          type_text(
            b,
            @schema.reference_name(
              @evidence.key_field_at(checked, i).unwrap().name,
            ),
          )
        }
        Some(checked)
      }
    }
    if declaration.order is Some(terms) {
      for term in terms {
        if b.nodes == 0 {
          raise SchemaStop(BudgetExceeded)
        }
        b.nodes -= 1
        type_text(b, term.field)
        let c = match @schema.lookup(schema, @schema.Unqualified(term.field)) {
          Some(c) => c
          None => raise SchemaStop(InvalidOrderField(term.field))
        }
        if !@order.author_orderable(c) {
          raise SchemaStop(InvalidOrderField(term.field))
        }
      }
    }
    Ok({
      declaration,
      schema,
      carrier,
      key,
      usage: {
        nodes: limits.max_nodes - b.nodes,
        text_bytes: limits.max_text_bytes - b.text,
      },
    })
  } catch {
    SchemaStop(e) => Err(e)
  }
}

///|
pub fn schema_declaration(v : SchemaAgreement) -> Checked {
  v.declaration
}

///|
pub fn supplied_schema(v : SchemaAgreement) -> @schema.Schema {
  v.schema
}

///|
pub fn schema_carrier(v : SchemaAgreement) -> @carrier.Carrier {
  v.carrier
}

///|
pub fn schema_primary_key(v : SchemaAgreement) -> @evidence.KeyedRelation? {
  v.key
}

///|
pub fn schema_usage(v : SchemaAgreement) -> Usage {
  v.usage
}
