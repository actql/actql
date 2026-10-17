///|
/// Structural declaration bounds, not installation authority or a reservation.
pub(all) struct NotionReadContractLimits {
  metadata : NotionDatabaseLimits
  contracts : @contract.Limits
  max_columns : Int
  max_work : Int
}

///|
pub(all) enum NotionReadContractIssue {
  InvalidLimits
  BudgetExceeded
  Metadata(NotionDatabaseIssue)
  InvalidDeclaration
  Contract(@contract.AdmissionError)
  InvalidProperty(String)
  MissingContract(String)
  UnsupportedProperty(String)
  InvalidColumn(String)
  ForeignDatabase
  InvalidSelection
  ForeignOriginal
} derive(Eq, Debug)

///|
pub enum NotionPropertyProjection {
  Value
  Start
  End
} derive(Eq, Debug)

///|
priv struct DeclaredNotionReadColumn {
  property_id : String
  name : String
  projection : NotionPropertyProjection
  contract : @contract.Contract
}

///|
/// Original bounded DATA from a database alias declaration, not an installed
/// Site, configuration revision, current read capability or writable Mapping.
pub struct NotionDatabaseReadDeclaration {
  database_id : String
  priv source_id : String?
  priv original : @decode.Cursor
  priv columns : Array[DeclaredNotionReadColumn]
  priv property_ids : Array[String]
}

///|
pub struct NotionPropertyReadColumn {
  name : String
  projection : NotionPropertyProjection
  contract : @contract.Contract
  priv property : NotionPropertyMetadata
}

///|
/// Retains both originals. Reparsed equal configuration/schema cannot replace
/// them in a retained binding. The actual installation must independently bind
/// this DATA pair to its own original configuration/revision and current Site.
pub struct NotionDataSourceReadContracts {
  priv declaration : NotionDatabaseReadDeclaration
  priv source : NotionDataSourceCatalog
  priv columns : Array[NotionPropertyReadColumn]
  priv schema : @contract.Contract
}

///|
priv struct NotionReadContractBudget {
  mut work : Int
  mut nodes : Int
  mut text : Int
}

///|
fn read_contract_limits_valid(limits : NotionReadContractLimits) -> Bool {
  database_limits_valid(limits.metadata) &&
  limits.contracts.max_nodes > 0 &&
  limits.contracts.max_depth > 0 &&
  limits.contracts.max_text_bytes >= 0 &&
  limits.max_columns > 0 &&
  limits.max_work > 0
}

///|
fn read_contract_spend(budget : NotionReadContractBudget, work : Int) -> Bool {
  if work < 0 || work > budget.work {
    return false
  }
  budget.work -= work
  true
}

///|
fn read_contract_text(
  cursor : @decode.Cursor,
  bound : Int,
) -> Result[String, NotionReadContractIssue] {
  match metadata_text(cursor, bound, true) {
    Ok(value) => Ok(value)
    Err(BudgetExceeded) => Err(BudgetExceeded)
    Err(_) => Err(InvalidDeclaration)
  }
}

///|
/// Compatibility: an original String database id still declares the singleton
/// shorthand. New explicit read contracts use the existing checked Contract
/// grammar, not display metadata, samples or a parallel logical type reader.
pub fn read_notion_database_read_declaration(
  bytes : Bytes,
  limits : NotionReadContractLimits,
) -> Result[NotionDatabaseReadDeclaration, NotionReadContractIssue] {
  if !read_contract_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  let original = match database_cursor(bytes, limits.metadata) {
    Ok(value) => value
    Err(issue) => return Err(Metadata(issue))
  }
  if @decode.text(original) is Ok(_) {
    let database_id = match
      read_contract_text(original, limits.metadata.max_identity_bytes) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    return Ok({
      database_id,
      source_id: None,
      original,
      columns: [],
      property_ids: [],
    })
  }
  guard @decode.closed_object(original, [
      "id", "unique", "marker", "data_source_id", "read_contracts",
    ])
    is Ok(root) &&
    @decode.lookup(root, "id") is Some(id) else {
    return Err(InvalidDeclaration)
  }
  let database_id = match
    read_contract_text(id, limits.metadata.max_identity_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Existing write selectors remain original declaration DATA. They are
  // validated, never interpreted here as a unique-key proof or marker grant.
  for name in ["unique", "marker"] {
    match @decode.field(root, name) {
      Missing => ()
      Present(value) =>
        match read_contract_text(value, limits.metadata.max_name_bytes) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      _ => return Err(InvalidDeclaration)
    }
  }
  let source_id = match @decode.field(root, "data_source_id") {
    Missing => None
    Present(value) =>
      match read_contract_text(value, limits.metadata.max_identity_bytes) {
        Ok(value) => Some(value)
        Err(issue) => return Err(issue)
      }
    _ => return Err(InvalidDeclaration)
  }
  let columns = []
  let property_ids = []
  let budget = {
    work: limits.max_work,
    nodes: limits.contracts.max_nodes,
    text: limits.contracts.max_text_bytes,
  }
  match @decode.field(root, "read_contracts") {
    Missing => ()
    Present(contracts) => {
      guard @decode.open_object(contracts) is Ok(contracts_view) &&
        @decode.object_field_names(contracts) is Ok(ids) else {
        return Err(InvalidDeclaration)
      }
      if ids.length() > limits.metadata.max_properties {
        return Err(BudgetExceeded)
      }
      for property_id in ids {
        if property_id.is_empty() ||
          @admitted.text_value(property_id, limits.metadata.max_identity_bytes)
          is None {
          return Err(InvalidProperty(property_id))
        }
        if !read_contract_spend(budget, 1) ||
          !read_contract_spend(budget, property_id.length()) {
          return Err(BudgetExceeded)
        }
        let entries = @decode.lookup(contracts_view, property_id).unwrap()
        guard @decode.array_length(entries) is Some(count) &&
          count >= 1 &&
          count <= 2 else {
          return Err(InvalidProperty(property_id))
        }
        property_ids.push(property_id)
        for index in 0..<count {
          if columns.length() >= limits.max_columns ||
            !read_contract_spend(budget, 1) {
            return Err(BudgetExceeded)
          }
          let entry = @decode.element_at(entries, index).unwrap()
          guard @decode.closed_object(entry, [
              "column", "projection", "contract",
            ])
            is Ok(entry) &&
            @decode.lookup(entry, "column") is Some(name) &&
            @decode.lookup(entry, "projection") is Some(projection) &&
            @decode.lookup(entry, "contract") is Some(contract) else {
            return Err(InvalidProperty(property_id))
          }
          let name = match
            read_contract_text(name, limits.metadata.max_name_bytes) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          let projection = match @decode.text(projection) {
            Ok("value") => Value
            Ok("start") => Start
            Ok("end") => End
            _ => return Err(InvalidProperty(property_id))
          }
          let (contract, nodes, text) = match
            @contract.read_checked_usage(contract, {
              ..limits.contracts,
              max_nodes: budget.nodes,
              max_text_bytes: budget.text,
            }) {
            Ok(value) => value
            Err(issue) => return Err(Contract(issue))
          }
          if !read_contract_spend(budget, nodes) ||
            !read_contract_spend(budget, text) {
            return Err(BudgetExceeded)
          }
          budget.nodes -= nodes
          budget.text -= text
          columns.push({ property_id, name, projection, contract, })
        }
      }
    }
    _ => return Err(InvalidDeclaration)
  }
  Ok({ database_id, source_id, original, columns, property_ids, })
}

///|
/// A scalar id selects only an original singleton. Explicit ids select their
/// occurrence in this same database inventory; names/array order never infer it.
pub fn notion_database_read_source_index(
  declaration : NotionDatabaseReadDeclaration,
  database : NotionDatabaseCatalog,
) -> Result[Int, NotionReadContractIssue] {
  if declaration.database_id != database.id {
    return Err(ForeignDatabase)
  }
  match declaration.source_id {
    None =>
      if database.sources.length() == 1 {
        Ok(0)
      } else {
        Err(InvalidSelection)
      }
    Some(id) => {
      for index in 0..<database.sources.length() {
        if database.sources[index].0 == id {
          return Ok(index)
        }
      }
      Err(InvalidSelection)
    }
  }
}

///|
fn notion_implicit_read_contract(
  property : NotionPropertyMetadata,
) -> @contract.Contract? {
  let primitive = match property.kind {
    "title" | "rich_text" | "unique_id" | "created_by" | "last_edited_by" =>
      return Some(@contract.primitive(@contract.StringType, nullable=false))
    "url" | "email" | "phone_number" | "select" | "status" =>
      @contract.StringType
    "checkbox" =>
      return Some(@contract.primitive(@contract.BooleanType, nullable=false))
    "created_time" | "last_edited_time" =>
      return Some(@contract.primitive(@contract.TimestampType, nullable=false))
    "multi_select" | "people" | "relation" =>
      return @contract.array_contract(
        @contract.primitive(@contract.StringType, nullable=false),
        nullable=false,
      )
    _ => return None
  }
  Some(@contract.primitive(primitive, nullable=true))
}

///|
fn notion_read_column_type(
  property : NotionPropertyMetadata,
  projection : NotionPropertyProjection,
  contract : @contract.Contract,
) -> Bool {
  match (property.kind, projection, contract.shape) {
    ("number", Value, Decimal(..)) => true
    ("date", Start | End, Date | Timestamp) => true
    ("formula" | "rollup", Value, Text(_) | Boolean | Decimal(..)) => true
    ("formula" | "rollup", Start | End, Date | Timestamp) => true
    (
      "title"
      | "rich_text"
      | "select"
      | "status"
      | "url"
      | "email"
      | "phone_number"
      | "unique_id"
      | "created_by"
      | "last_edited_by",
      Value,
      Text(_),
    ) => true
    ("checkbox", Value, Boolean) => true
    ("created_time" | "last_edited_time", Value, Timestamp) => true
    ("multi_select" | "people" | "relation", Value, Array(item, ..)) =>
      item.shape is Text(_) && !item.nullable
    _ => false
  }
}

///|
pub fn bind_notion_data_source_read_contracts(
  declaration : NotionDatabaseReadDeclaration,
  source : NotionDataSourceCatalog,
  limits : NotionReadContractLimits,
) -> Result[NotionDataSourceReadContracts, NotionReadContractIssue] {
  if !read_contract_limits_valid(limits) {
    return Err(InvalidLimits)
  }
  let index = match
    notion_database_read_source_index(declaration, source.database) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if source.source_index != index {
    return Err(InvalidSelection)
  }
  if source.properties.length() > limits.metadata.max_properties {
    return Err(BudgetExceeded)
  }
  let budget = { work: limits.max_work, nodes: 0, text: 0, }
  let columns = []
  let selected : Map[String, Bool] = Map([])
  for property in source.properties {
    if !read_contract_spend(budget, 1) {
      return Err(BudgetExceeded)
    }
    let property_columns = []
    for column in declaration.columns {
      if !read_contract_spend(
          budget,
          1 + property.id.length() + column.property_id.length(),
        ) {
        return Err(BudgetExceeded)
      }
      if column.property_id == property.id {
        if !notion_read_column_type(
            property,
            column.projection,
            column.contract,
          ) {
          return Err(InvalidProperty(property.id))
        }
        property_columns.push({
          name: column.name,
          projection: column.projection,
          contract: column.contract,
          property,
        })
      }
    }
    if property_columns.is_empty() {
      guard notion_implicit_read_contract(property) is Some(contract) else {
        return Err(MissingContract(property.id))
      }
      property_columns.push({
        name: property.name,
        projection: Value,
        contract,
        property,
      })
    } else {
      selected[property.id] = true
      if property_columns.length() == 2 {
        let a = property_columns[0]
        let b = property_columns[1]
        if !((a.projection == Start && b.projection == End) ||
          (a.projection == End && b.projection == Start)) ||
          !((a.contract.shape is Date && b.contract.shape is Date) ||
          (a.contract.shape is Timestamp && b.contract.shape is Timestamp)) {
          return Err(InvalidProperty(property.id))
        }
      } else if property_columns[0].projection == End {
        return Err(InvalidProperty(property.id))
      }
    }
    for column in property_columns {
      if columns.length() >= limits.max_columns {
        return Err(BudgetExceeded)
      }
      columns.push(column)
    }
  }
  for id in declaration.property_ids {
    if !read_contract_spend(budget, 1) {
      return Err(BudgetExceeded)
    }
    if !selected.contains(id) {
      return Err(InvalidProperty(id))
    }
  }
  let schema = match
    @contract.object_contract(
      columns.map(c => (c.name, c.contract)),
      nullable=false,
      max_fields=limits.max_columns,
      max_name_bytes=limits.metadata.max_bytes,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidColumn("names"))
  }
  Ok({ declaration, source, columns, schema, })
}

///|
pub fn notion_data_source_read_matches(
  binding : NotionDataSourceReadContracts,
  declaration : NotionDatabaseReadDeclaration,
  source : NotionDataSourceCatalog,
) -> Bool {
  physical_equal(binding.declaration, declaration) &&
  physical_equal(binding.source, source)
}

///|
pub fn notion_data_source_read_column_count(
  binding : NotionDataSourceReadContracts,
) -> Int {
  binding.columns.length()
}

///|
pub fn notion_data_source_read_column_at(
  binding : NotionDataSourceReadContracts,
  index : Int,
) -> NotionPropertyReadColumn? {
  if index < 0 || index >= binding.columns.length() {
    None
  } else {
    Some(binding.columns[index])
  }
}

///|
pub fn notion_data_source_read_schema(
  binding : NotionDataSourceReadContracts,
) -> @contract.Contract {
  binding.schema
}

///|
pub fn notion_database_read_declaration_original(
  declaration : NotionDatabaseReadDeclaration,
) -> @decode.Cursor {
  declaration.original
}

///|
pub fn notion_property_read_original(
  column : NotionPropertyReadColumn,
) -> NotionPropertyMetadata {
  column.property
}

///|
/// Canonical checked schema from the same retained declaration/schema pair.
/// This wire is DATA, not installation membership or a current capability.
pub fn notion_data_source_read_schema_wire(
  binding : NotionDataSourceReadContracts,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, NotionReadContractIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  Ok(
    @contract.stringify_checked(binding.schema, max_bytes, max_nodes, max_depth),
  ) catch {
    _ => Err(BudgetExceeded)
  }
}
