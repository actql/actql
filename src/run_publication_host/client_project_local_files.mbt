///|
/// Exact Local connector entry selected from the admitted Project. A Host
/// still resolves the root and owns currentness, account checks and I/O.
pub(all) struct ClientProjectLocalFiles {
  root : String
  content_version : Bool
  csv_tables : Array[@row_host.LocalCsvTable]
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
  guard self.at(index) is Some((_, "local", wire)) &&
    project_metadata_cursor(@utf8.encode(wire)) is Ok(original) &&
    @decode.open_object(original) is Ok(entry) &&
    @decode.lookup(entry, "root") is Some(root) &&
    project_configuration_text(root) is Some(root) &&
    @scalar.admit_utf8_length(root, 4096) is Ok(_) else {
    return Err(InvalidLocalFilesConnection)
  }
  let content_version = match @decode.field(entry, "version") {
    Missing => false
    Present(value) if @decode.text(value) == Ok("content") => true
    _ => return Err(LocalFilesVersionUnavailable)
  }
  let csv_tables = []
  if @decode.lookup(entry, "tables") is Some(tables) &&
    @decode.object_length(tables) is Some(count) {
    for position in 0..<count {
      guard @decode.field_at(tables, position) is Some((resource, table)) else {
        return Err(InvalidLocalFilesConnection)
      }
      match
        @row_host.prepare_local_csv_table(
          resource, table, max_path_bytes, max_depth,
        ) {
        Ok(Some(table)) => csv_tables.push(table)
        Ok(None) => ()
        Err(issue) => return Err(CsvTable(issue))
      }
    }
  }
  Ok({ root, content_version, csv_tables, })
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
