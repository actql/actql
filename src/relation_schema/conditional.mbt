///|
/// Field presence is independent of the admitted value contract's nullability.
pub(all) enum FieldPresence {
  Required
  Conditional
} derive(Eq, Debug)

///|
struct ConditionalField {
  field : Field
  presence : FieldPresence
}

///|
/// A finite typed layout whose rows may omit only conditional fields. This
/// cannot be passed to the dense Relation APIs as an ordinary Schema.
struct ConditionalSchema {
  fields : Array[ConditionalField]
  relation : Schema
  required : Schema
  required_indices : Array[Int]
}

///|
pub(all) enum DefinitionPresenceIssue {
  InvalidDefinitionLimits
  EmptyDefinitions
  DefinitionLimit
  DefinitionSchema(Issue)
  ConflictingReference(FieldName)
  IncompatibleDeclaration(FieldName)
} derive(Eq, Debug)

///|
priv struct DefinitionField {
  name : FieldName
  contract : @contract.Contract
  declarations : Int
}

///|
/// Derive one finite row layout from the statically possible definitions.
/// A missing declaration is not a nullable value. Callers must include all
/// bridge roles, authored aliases and properties of each definition; this
/// function does not infer them from observed rows or predicate outcomes.
pub fn from_definition_fields(
  definitions : Array[Array[(FieldName, @contract.Contract)]],
  max_definitions~ : Int,
  max_fields~ : Int,
  max_name_bytes~ : Int,
  max_contract_work~ : Int,
) -> Result[(ConditionalSchema, Int), DefinitionPresenceIssue] {
  if max_definitions < 0 ||
    max_fields < 0 ||
    max_name_bytes < 0 ||
    max_contract_work < 0 {
    return Err(InvalidDefinitionLimits)
  }
  if definitions.is_empty() {
    return Err(EmptyDefinitions)
  }
  if definitions.length() > max_definitions {
    return Err(DefinitionLimit)
  }
  let accumulated : Array[DefinitionField] = []
  let positions : Map[String, Int] = Map([])
  let mut remaining = max_contract_work
  for definition in definitions {
    if remaining == 0 || definition.length() > remaining - 1 {
      return Err(DefinitionLimit)
    }
    remaining -= 1
    let admitted = match from_fields(definition, max_fields~, max_name_bytes~) {
      Ok(value) => value
      Err(issue) => return Err(DefinitionSchema(issue))
    }
    for index in 0..<field_count(admitted) {
      remaining -= 1
      let field = field_at(admitted, index).unwrap()
      let spelling = reference_name(field.name)
      match positions.get(spelling) {
        None => {
          if accumulated.length() >= max_fields {
            return Err(DefinitionLimit)
          }
          positions[spelling] = accumulated.length()
          accumulated.push({
            name: field.name,
            contract: field.contract,
            declarations: 1,
          })
        }
        Some(position) => {
          let previous = accumulated[position]
          if previous.name != field.name {
            return Err(ConflictingReference(field.name))
          }
          let (joined, used) = @contract.join_nullability_usage(
            previous.contract,
            field.contract,
            remaining,
          ) catch {
            _ => return Err(DefinitionLimit)
          }
          remaining -= used
          guard joined is Some(contract) else {
            return Err(IncompatibleDeclaration(field.name))
          }
          accumulated[position] = {
            name: field.name,
            contract,
            declarations: previous.declarations + 1,
          }
        }
      }
    }
  }
  let entries = accumulated.map(field => {
    (
      field.name,
      field.contract,
      if field.declarations == definitions.length() {
        FieldPresence::Required
      } else {
        FieldPresence::Conditional
      },
    )
  })
  match from_conditional_fields(entries, max_fields~, max_name_bytes~) {
    Ok(schema) => Ok((schema, max_contract_work - remaining))
    Err(issue) => Err(DefinitionSchema(issue))
  }
}

///|
pub enum PresenceLookup {
  AlwaysPresent(Field)
  ConditionallyPresent(Field)
  AbsentField
}

///|
/// Validate all names and contracts through the existing schema owner, then
/// retain the presence declaration separately from the nullable value type.
pub fn from_conditional_fields(
  entries : Array[(FieldName, @contract.Contract, FieldPresence)],
  max_fields~ : Int,
  max_name_bytes~ : Int,
) -> Result[ConditionalSchema, Issue] {
  if max_fields < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  if entries.length() > max_fields {
    return Err(LimitExceeded)
  }
  let all = match
    from_presence_fields(
      entries.map(entry => {
        (
          entry.0,
          entry.1,
          if entry.2 == FieldPresence::Required {
            Presence::Required
          } else {
            Presence::Conditional
          },
        )
      }),
      max_fields~,
      max_name_bytes~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let presence : Map[String, FieldPresence] = Map([])
  for (name, _, declared) in entries {
    presence[reference_name(name)] = declared
  }
  let result_fields = []
  let required_entries = []
  for field in fields(all) {
    let declared = presence[reference_name(field.name)]
    result_fields.push({ field, presence: declared, })
    if declared == Required {
      required_entries.push((field.name, field.contract))
    }
  }
  let required = from_fields(required_entries, max_fields~, max_name_bytes~).unwrap()
  let required_indices = []
  for index in 0..<result_fields.length() {
    if result_fields[index].presence == Required {
      required_indices.push(index)
    }
  }
  Ok({ fields: result_fields, relation: all, required, required_indices, })
}

///|
/// The same checked finite field set in the shared Relation owner. This is
/// schema evidence only; it does not turn a provisional row into retained
/// Relation storage or a publishable Result.
pub fn conditional_relation_schema(schema : ConditionalSchema) -> Schema {
  schema.relation
}

///|
pub fn presence_field_count(schema : ConditionalSchema) -> Int {
  schema.fields.length()
}

///|
pub fn presence_field_at(
  schema : ConditionalSchema,
  index : Int,
) -> ConditionalField? {
  schema.fields.get(index)
}

///|
pub fn presence_field_name(field : ConditionalField) -> FieldName {
  field.field.name
}

///|
pub fn presence_field_contract(field : ConditionalField) -> @contract.Contract {
  field.field.contract
}

///|
pub fn conditional_field_presence(field : ConditionalField) -> FieldPresence {
  field.presence
}

///|
pub fn presence_lookup(
  schema : ConditionalSchema,
  name : FieldName,
) -> PresenceLookup {
  let spelling = reference_name(name)
  let mut lo = 0
  let mut hi = schema.fields.length()
  while lo < hi {
    let mid = lo + (hi - lo) / 2
    let candidate = reference_name(schema.fields[mid].field.name)
    if @canonical.compare_utf16(candidate, spelling) < 0 {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  match schema.fields.get(lo) {
    Some(entry) if entry.field.name == name =>
      if entry.presence == Required {
        AlwaysPresent(entry.field)
      } else {
        ConditionallyPresent(entry.field)
      }
    _ => AbsentField
  }
}

///|
/// Only these columns may enter an existing dense Relation consumer without
/// a separate proof that conditionally present fields exist in every row.
pub fn required_projection_schema(schema : ConditionalSchema) -> Schema {
  schema.required
}

///|
pub fn required_source_index(schema : ConditionalSchema, index : Int) -> Int? {
  schema.required_indices.get(index)
}
