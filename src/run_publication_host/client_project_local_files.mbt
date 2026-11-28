///|
/// Exact Local connector entry selected from the admitted Project. A Host
/// still resolves the root and owns currentness, account checks and I/O.
pub struct ClientProjectLocalFiles {
  priv connection : String
  priv csv_tables : Array[@row_host.LocalCsvTable]
  root : String
  content_version : Bool
}

///|
pub(all) enum ClientProjectLocalFilesIssue {
  InvalidLocalFilesConnection
  LocalFilesVersionUnavailable
  CsvTable(@row_host.LocalCsvTableIssue)
} derive(Eq, Debug)

///|
pub fn client_project_local_files_issue_code(
  issue : ClientProjectLocalFilesIssue,
) -> String {
  match issue {
    InvalidLocalFilesConnection => "InvalidLocalFilesConnection"
    LocalFilesVersionUnavailable => "LocalFilesVersionUnavailable"
    CsvTable(table) => @row_host.local_csv_table_issue_code(table)
  }
}

///|
/// Use the exact original span retained in the Project connection index.
/// Validate all selected table declarations before returning any member.
pub fn ClientProjectConnections::local_files(
  self : Self,
  index : Int,
  max_path_bytes : Int,
  max_depth : Int,
) -> Result[ClientProjectLocalFiles, ClientProjectLocalFilesIssue] {
  guard self.at(index) is Some((connection, "local", wire)) else {
    return Err(InvalidLocalFilesConnection)
  }
  project_local_files_from_entry(
    connection,
    wire,
    max_path_bytes,
    max_depth,
    csv_only=false,
    table_funding=_ => Ok(()),
    issue=issue => issue,
  )
}

///|
/// Construct the selected Local member under its original Project allowance.
/// The parse and each exact table projection reserve before construction.
/// This route accepts file views and CSV tables; each table must be supported.
pub fn[E] ClientProjectConnections::funded_local_files(
  self : Self,
  index : Int,
  max_path_bytes : Int,
  max_depth : Int,
  grow : (@execution.PreparationRepresentationUnits) -> Result[Unit, E],
  issue : (ClientProjectLocalFilesIssue) -> E,
) -> Result[ClientProjectLocalFiles, E] {
  guard self.at(index) is Some((connection, "local", wire)) &&
    client_project_connections_admission_construction_inventory(wire)
    is Some(inventory) else {
    return Err(issue(InvalidLocalFilesConnection))
  }
  grow(inventory).bind(_ => {
    project_local_files_from_entry(
      connection,
      wire,
      max_path_bytes,
      max_depth,
      csv_only=true,
      table_funding=table => {
        guard @row_host.local_csv_table_construction_inventory(table)
          is Some(inventory) else {
          return Err(issue(InvalidLocalFilesConnection))
        }
        grow(inventory)
      },
      issue~,
    )
  })
}

///|
fn[E] project_local_files_from_entry(
  connection : String,
  wire : String,
  max_path_bytes : Int,
  max_depth : Int,
  csv_only~ : Bool,
  table_funding~ : (@decode.Cursor) -> Result[Unit, E],
  issue~ : (ClientProjectLocalFilesIssue) -> E,
) -> Result[ClientProjectLocalFiles, E] {
  guard project_metadata_cursor(@utf8.encode(wire)) is Ok(original) &&
    @decode.lookup_original_field(original, "root") is Some(root) &&
    @decode.is_text(root) &&
    project_configuration_text(root) is Some(root) &&
    @scalar.admit_utf8_length(root, 4096) is Ok(_) else {
    return Err(issue(InvalidLocalFilesConnection))
  }
  let content_version = match
    @decode.lookup_original_field(original, "version") {
    None => false
    Some(value) if @decode.is_text(value) &&
      @decode.text(value) == Ok("content") => true
    _ => return Err(issue(LocalFilesVersionUnavailable))
  }
  let csv_tables = []
  if @decode.lookup_original_field(original, "tables") is Some(tables) &&
    @decode.object_length(tables) is Some(count) {
    let mut selected = 0
    for position in 0..<count {
      guard @decode.field_at(tables, position) is Some((_, table)) else {
        return Err(issue(InvalidLocalFilesConnection))
      }
      if @row_host.local_csv_table_is_selected(table) {
        selected += 1
        if selected > @row_host.local_file_max_csv_views() {
          return Err(issue(InvalidLocalFilesConnection))
        }
      } else if csv_only {
        return Err(issue(InvalidLocalFilesConnection))
      }
    }
    for position in 0..<count {
      guard @decode.field_at(tables, position) is Some((resource, table)) else {
        return Err(issue(InvalidLocalFilesConnection))
      }
      if @row_host.local_csv_table_is_selected(table) {
        match table_funding(table) {
          Ok(_) => ()
          Err(cause) => return Err(cause)
        }
        match
          @row_host.prepare_local_csv_table(
            resource, table, max_path_bytes, max_depth,
          ) {
          Ok(Some(table)) => csv_tables.push(table)
          Ok(None) => return Err(issue(InvalidLocalFilesConnection))
          Err(cause) => return Err(issue(CsvTable(cause)))
        }
      }
    }
  } else if csv_only &&
    @decode.lookup_original_field(original, "tables") is Some(_) {
    return Err(issue(InvalidLocalFilesConnection))
  }
  Ok({ connection, root, content_version, csv_tables, })
}

///|
/// Data projection used by the Node binding. The returned JSON holds no
/// installed Root, admission handle or execution authority.
pub fn ClientProjectLocalFiles::json(self : Self) -> String {
  let tables = self.csv_tables.map(table => {
    let view = table.view
    let projected : Json = {
      "resource": Json::string(view.resource),
      "resource_kind": Json::string(view.resource_kind),
      "schema_wire": Json::string(view.schema_wire),
      "schema_cid": Json::string(view.schema_cid),
      "facts_wire": Json::string(view.facts_wire.unwrap()),
    }
    let entry : Json = {
      "path": Json::string(table.path),
      "column_names": Json::array(table.column_names.map(Json::string)),
      "integer_columns": Json::array(table.integer_columns.map(Json::boolean)),
      "key": Json::array(table.keys.map(Json::string)),
      "view": projected,
    }
    entry
  })
  let original : Json = {
    "root": Json::string(self.root),
    "content_version": Json::boolean(self.content_version),
    "csv_tables": Json::array(tables),
  }
  original.stringify()
}
