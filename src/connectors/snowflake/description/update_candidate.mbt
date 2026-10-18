///|
pub(all) struct UpdateCandidateLimits {
  max_fields : Int
  max_comparison_work : Int
  max_value_nodes : Int
  max_value_text_bytes : Int
  max_value_depth : Int
  max_statement_bytes : Int
  max_body_bytes : Int
  max_body_nodes : Int
}

///|
pub(all) enum UpdateCandidateIssue {
  InvalidLimits
  Limit
  EmptyUpdate
  UnknownField(String)
  DuplicateField(String)
  IncompleteBeforeImage
  DifferentBeforeImageKey
  UnsupportedWriteType(String, String)
  InvalidValue(String)
} derive(Eq, Debug)

///|
/// Parameterized request DATA from one metadata observation. This is neither
/// an Effect Preview nor an atomicity proof, current permission or send token.
/// The physical Mapping/Effect caller must retain its original approval and
/// prove provider concurrency and affected-item correspondence separately.
pub struct UpdateCandidate {
  priv description : TableDescription
  priv statement : String
  priv bindings : String
}

///|
priv struct UpdateBudget {
  mut comparison : Int
  mut nodes : Int
  mut text : Int
  depth : Int
  body_ceiling : Int
  mut sql_left : Int
  sql : StringBuilder
  bindings : Array[(String, String)]
}

///|
priv suberror UpdateStop {
  UpdateStop(UpdateCandidateIssue)
}

///|
fn update_field(
  description : TableDescription,
  name : String,
  budget : UpdateBudget,
) -> DescriptionColumn raise UpdateStop {
  for column in description.columns {
    for text in [column.name, name] {
      match @scalar.admit_utf8_length(text, budget.comparison) {
        Ok(bytes) => budget.comparison -= bytes
        Err(_) => raise UpdateStop(Limit)
      }
    }
    if column.name == name {
      return column
    }
  }
  raise UpdateStop(UnknownField(name))
}

///|
fn update_values(
  description : TableDescription,
  values : Array[(String, @admitted.CheckedValue)],
  budget : UpdateBudget,
) -> Array[(DescriptionColumn, @admitted.CheckedValue)] raise UpdateStop {
  let checked : Array[(DescriptionColumn, @admitted.CheckedValue)] = []
  for (name, value) in values {
    let field = update_field(description, name, budget)
    for (prior, _) in checked {
      for text in [prior.name, name] {
        match @scalar.admit_utf8_length(text, budget.comparison) {
          Ok(bytes) => budget.comparison -= bytes
          Err(_) => raise UpdateStop(Limit)
        }
      }
      if prior.name == name {
        raise UpdateStop(DuplicateField(name))
      }
    }
    guard field.contract is Some(contract) else {
      raise UpdateStop(UnsupportedWriteType(name, field.native_type))
    }
    // The original metadata Contract is re-admitted by Common, rather than
    // trusting an equal caller schema or copying its CheckedValue wrapper.
    guard
      @admitted.recheck_runtime_value_usage(
        value.value,
        contract,
        {
          max_nodes: budget.nodes,
          max_depth: budget.depth,
          max_text_bytes: budget.text,
        },
      ) is Some((original, nodes, text))
    else {
      raise UpdateStop(InvalidValue(name))
    }
    budget.nodes -= nodes
    budget.text -= text
    if original.value is @admitted.Text(value) &&
      field.max_characters is Some(maximum) &&
      value.to_array().length().to_int64() > maximum {
      raise UpdateStop(InvalidValue(name))
    }
    checked.push((field, original))
  }
  checked
}

///|
fn update_sql(budget : UpdateBudget, text : String) -> Unit raise UpdateStop {
  match @scalar.admit_utf8_length(text, budget.sql_left) {
    Ok(bytes) => budget.sql_left -= bytes
    Err(_) => raise UpdateStop(Limit)
  }
  budget.sql.write_string(text)
}

///|
fn update_identifier(budget : UpdateBudget, name : String) -> Unit raise UpdateStop {
  guard budget.sql_left >= 2 else { raise UpdateStop(Limit) }
  let bytes = match @scalar.admit_utf8_length(name, budget.sql_left - 2) {
    Ok(bytes) => bytes
    Err(_) => raise UpdateStop(Limit)
  }
  let quotes = name.iter().filter(c => c == '"').count()
  if quotes > budget.sql_left - 2 - bytes {
    raise UpdateStop(Limit)
  }
  update_sql(budget, quote_identifier(name))
}

///|
fn update_table(
  budget : UpdateBudget,
  target : TableTarget,
) -> Unit raise UpdateStop {
  update_identifier(budget, target.database)
  update_sql(budget, ".")
  update_identifier(budget, target.schema)
  update_sql(budget, ".")
  update_identifier(budget, target.table)
}

///|
fn update_parameter(
  budget : UpdateBudget,
  field : DescriptionColumn,
  value : @admitted.CheckedValue,
) -> Unit raise UpdateStop {
  // SQL NULL is a literal in the fixed template, not the string "null" and
  // not a provider binding whose null spelling would need to be guessed.
  if value.value is @admitted.Null {
    update_sql(budget, "NULL")
    return
  }
  let (kind, expression) = match (field.native_type, value.value) {
    ("NUMBER" | "DECIMAL" | "NUMERIC", @admitted.Decimal(_)) => {
      guard field.precision is Some(p) && field.scale is Some(s) else {
        raise UpdateStop(InvalidValue(field.name))
      }
      // Explicit precision/scale avoids session-default conversion and a
      // floating intermediate. The same Common decimal Contract checked it.
      ("TEXT", "TO_DECIMAL(?, " + p.to_string() + ", " + s.to_string() + ")")
    }
    ("TEXT" | "VARCHAR" | "STRING", @admitted.Text(_)) => ("TEXT", "?")
    ("BOOLEAN", @admitted.Boolean(_)) => ("BOOLEAN", "?")
    ("FLOAT" | "REAL" | "DOUBLE", @admitted.Number(_)) => ("REAL", "?")
    _ => raise UpdateStop(UnsupportedWriteType(field.name, field.native_type))
  }
  guard @admitted.canonical_scalar_text(value, budget.body_ceiling) is Some(text) else {
    raise UpdateStop(Limit)
  }
  budget.bindings.push((kind, text))
  update_sql(budget, expression)
}

///|
pub fn prepare_update_candidate(
  description : TableDescription,
  key_name : String,
  key : @admitted.CheckedValue,
  before_image : Array[(String, @admitted.CheckedValue)],
  assignments : Array[(String, @admitted.CheckedValue)],
  limits : UpdateCandidateLimits,
) -> Result[UpdateCandidate, UpdateCandidateIssue] {
  if [
      limits.max_fields, limits.max_comparison_work, limits.max_value_nodes,
      limits.max_value_text_bytes, limits.max_value_depth, limits.max_statement_bytes,
      limits.max_body_bytes, limits.max_body_nodes,
    ].any(value => value <= 0) {
    return Err(InvalidLimits)
  }
  if assignments.is_empty() { return Err(EmptyUpdate) }
  if description.columns.length() > limits.max_fields ||
    before_image.length() != description.columns.length() {
    return Err(IncompleteBeforeImage)
  }
  if assignments.length() > limits.max_fields { return Err(Limit) }
  let budget : UpdateBudget = {
    comparison: limits.max_comparison_work,
    nodes: limits.max_value_nodes,
    text: limits.max_value_text_bytes,
    depth: limits.max_value_depth,
    body_ceiling: limits.max_body_bytes,
    sql_left: limits.max_statement_bytes,
    sql: StringBuilder(),
    bindings: [],
  }
  let writer = @encode.writer(limits.max_body_bytes, limits.max_body_nodes, 8) catch {
    _ => return Err(InvalidLimits)
  }
  try {
    let key_value = update_values(description, [(key_name, key)], budget)[0]
    let before = update_values(description, before_image, budget)
    let changes = update_values(description, assignments, budget)
    let mut prior = None
    for (field, value) in before {
      if physical_equal(field, key_value.0) {
        prior = Some(value)
        break
      }
    }
    guard prior is Some(prior) else {
      raise UpdateStop(IncompleteBeforeImage)
    }
    let same_key = if key_value.1.value is @admitted.Null && prior.value is @admitted.Null {
      true
    } else {
      @admitted.compare_key_values(key_value.1, prior) is Ok(0)
    }
    if !same_key { raise UpdateStop(DifferentBeforeImageKey) }
    update_sql(budget, "UPDATE ")
    update_table(budget, description.target)
    update_sql(budget, " AS \"ACTQL_TARGET\" SET ")
    for index, (field, value) in changes {
      if index > 0 { update_sql(budget, ", ") }
      update_identifier(budget, field.name)
      update_sql(budget, " = ")
      update_parameter(budget, field, value)
    }
    update_sql(budget, " WHERE \"ACTQL_TARGET\".")
    update_identifier(budget, key_name)
    update_sql(budget, " IS NOT DISTINCT FROM ")
    update_parameter(budget, key_value.0, key_value.1)
    // Cardinality covers ALL matching target-key rows, not only rows that
    // also match this before-image. This clause alone proves no concurrency
    // guarantee for a later physical request or transaction.
    update_sql(budget, " AND (SELECT COUNT(*) FROM ")
    update_table(budget, description.target)
    update_sql(budget, " AS \"ACTQL_KEYS\" WHERE \"ACTQL_KEYS\".")
    update_identifier(budget, key_name)
    update_sql(budget, " IS NOT DISTINCT FROM ")
    update_parameter(budget, key_value.0, key_value.1)
    update_sql(budget, ") = 1")
    for (field, value) in before {
      update_sql(budget, " AND \"ACTQL_TARGET\".")
      update_identifier(budget, field.name)
      update_sql(budget, " IS NOT DISTINCT FROM ")
      update_parameter(budget, field, value)
    }
    @encode.begin_object(writer)
    for index, (kind, value) in budget.bindings {
      @encode.key(writer, (index + 1).to_string())
      @encode.begin_ordered_object(writer)
      @encode.ordered_key(writer, "type")
      @encode.string_value(writer, kind)
      @encode.ordered_key(writer, "value")
      @encode.string_value(writer, value)
      @encode.end_object(writer)
    }
    @encode.end_object(writer)
    Ok({ description, statement: budget.sql.to_string(), bindings: @encode.finish(writer), })
  } catch {
    UpdateStop(issue) => {
      @encode.cancel_writer(writer)
      Err(issue)
    }
    _ => {
      @encode.cancel_writer(writer)
      Err(Limit)
    }
  }
}

///|
pub fn update_candidate_statement(value : UpdateCandidate) -> String { value.statement }

///|
pub fn update_candidate_bindings(value : UpdateCandidate) -> String { value.bindings }

///|
pub fn update_candidate_matches_description(
  value : UpdateCandidate,
  description : TableDescription,
) -> Bool {
  physical_equal(value.description, description)
}
