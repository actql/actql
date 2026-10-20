///|
priv suberror MockRowsStop {
  MockRowsStop(RowSourceIssue)
}

///|
fn mock_rows_work(work : Ref[Int], amount : Int) -> Unit raise MockRowsStop {
  if amount < 0 || work.val < amount {
    raise MockRowsStop(InvalidPage)
  }
  work.val -= amount
}

///|
fn mock_rows_field(
  object : @decode.ObjectView,
  name : String,
) -> @decode.Cursor raise MockRowsStop {
  @decode.lookup(object, name).unwrap_or_else(() => {
    raise MockRowsStop(MissingField(name))
  })
}

///|
// The physical JSON number is interpreted only under the original int64
// contract. Its rounded parser Double is never read or converted to Int64.
fn mock_rows_int64(
  cell : @decode.Cursor,
  bytes : Bytes,
  limits : @admitted.Limits,
) -> @decode.Cursor raise MockRowsStop {
  guard @decode.view(cell) is @decode.NumberValue(_) else {
    raise MockRowsStop(InvalidPage)
  }
  let span = @decode.cursor_span(cell)
  if span.start_byte < 0 ||
    span.end_byte <= span.start_byte ||
    span.end_byte > bytes.length() {
    raise MockRowsStop(InvalidPage)
  }
  let text = @utf8.decode(bytes[span.start_byte:span.end_byte]) catch {
    _ => raise MockRowsStop(InvalidPage)
  }
  let start = if text.has_prefix("-") { 1 } else { 0 }
  if text.length() <= start {
    raise MockRowsStop(InvalidPage)
  }
  for index in start..<text.length() {
    if text[index] < '0' || text[index] > '9' {
      raise MockRowsStop(InvalidPage)
    }
  }
  let cursor = @decode.admit_raw_json(text.to_json(), span, {
    max_nodes: limits.max_nodes,
    max_depth: limits.max_depth,
    max_string_bytes: limits.max_text_bytes,
    max_total_string_bytes: limits.max_text_bytes,
  }).unwrap_or_else(() => raise MockRowsStop(InvalidPage))
  guard @decode.decimal_int64(cursor) is Ok(_) else {
    raise MockRowsStop(InvalidPage)
  }
  cursor
}

///|
fn mock_rows_schema(
  declaration : RowDeclaration,
  warehouse : Bool,
  limits : RowDeclarationLimits,
  work : Ref[Int],
) -> @schema.Schema raise MockRowsStop {
  let connector = if warehouse { "snowflake" } else { "salesforce" }
  let registration = "mock_" + connector
  let resource = if warehouse { "usage_30d" } else { "Account" }
  let identity = if warehouse { "account_id" } else { "id" }
  if declaration.connector_id != connector ||
    declaration.connector_registration != registration ||
    declaration.connector_version != registration + "/0.1" ||
    declaration.views.length() != 1 ||
    declaration.view_bodies.length() != 1 ||
    declaration.views[0].resource != resource {
    raise MockRowsStop(ForeignSource)
  }
  mock_rows_work(work, limits.max_nodes)
  let (kind, contract) = mapping_original_relation(
    declaration, resource, identity, limits,
  ).unwrap_or_else(() => raise MockRowsStop(InvalidInputSchema))
  let schema = @schema.from_object(contract).unwrap_or_else(() => {
    raise MockRowsStop(InvalidInputSchema)
  })
  let names = if warehouse {
    ["account_id", "active_users", "trend"]
  } else {
    ["id", "name", "description", "Churn_Risk__c", "Risk_Reason__c"]
  }
  if kind != (if warehouse { "table" } else { "record" }) ||
    @schema.field_count(schema) != names.length() {
    raise MockRowsStop(InvalidInputSchema)
  }
  for name in names {
    mock_rows_work(work, limits.max_nodes)
    let field = @schema.lookup_reference(schema, name).unwrap_or_else(() => {
      raise MockRowsStop(InvalidInputSchema)
    })
    let expected = @contract.primitive(
      if name == "active_users" {
        @contract.Signed64Type
      } else {
        @contract.StringType
      },
      nullable=name == "Risk_Reason__c",
    )
    let same = @contract.type_equal(field.contract, expected, limits.max_nodes) catch {
      _ => false
    }
    if !same {
      raise MockRowsStop(InvalidInputSchema)
    }
  }
  mock_rows_work(work, limits.max_nodes)
  guard mock_churn_risk_original_key(declaration, limits, identity) is Ok(_) else {
    raise MockRowsStop(InvalidInputSchema)
  }
  schema
}

///|
// Full document admission precedes appending any selected row. Both original
// declarations and every physical field remain checked even when the query
// consumes only one relation or a strict subset of its columns.
fn mock_churn_risk_document_rows(
  read : RowSourceRead,
  selected : RowDeclaration,
  salesforce : RowDeclaration,
  snowflake : RowDeclaration,
  bytes : Bytes,
  max_work : Int,
) -> Result[Array[Array[@admitted.CheckedValue]], RowSourceIssue] {
  mock_churn_risk_selected_document(
    read.schema,
    read.columns,
    read.page_limits,
    read.values,
    selected,
    salesforce,
    snowflake,
    bytes,
    max_work,
  ).map(value => value.0)
}

///|
// Shared bounded DATA admission for the original reader and conditional file
// writer. This does not construct a read attempt or consume a byte ticket.
// Each physical caller retains its own authorization, backing and cleanup.
fn mock_churn_risk_selected_document(
  selected_schema : @schema.Schema,
  columns : Array[String],
  bounds : RowPageLimits,
  values : @admitted.Limits,
  selected : RowDeclaration,
  salesforce : RowDeclaration,
  snowflake : RowDeclaration,
  bytes : Bytes,
  max_work : Int,
) -> Result[
  (Array[Array[@admitted.CheckedValue]], @decode.Cursor),
  RowSourceIssue,
] {
  try {
    let work = Ref(max_work)
    mock_rows_work(work, bytes.length())
    if bytes.length() > bounds.max_bytes {
      raise MockRowsStop(InvalidPage)
    }
    let node = @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: bounds.max_bytes,
      max_nodes: bounds.max_nodes,
      max_depth: bounds.max_depth,
    }).unwrap_or_else(() => raise MockRowsStop(InvalidPage))
    let root = @decode.admit(node, {
      max_nodes: bounds.max_nodes,
      max_depth: bounds.max_depth,
      max_string_bytes: bounds.max_bytes,
      max_total_string_bytes: bounds.max_bytes,
    }).unwrap_or_else(() => raise MockRowsStop(InvalidPage))
    mock_rows_work(work, @decode.admission_usage(root).nodes)
    let object = @decode.closed_object(root, ["salesforce", "snowflake"]).unwrap_or_else(() => {
        raise MockRowsStop(InvalidPage)
      },
    )
    let declaration_limits : RowDeclarationLimits = {
      max_bytes: bounds.max_bytes,
      max_nodes: bounds.max_nodes,
      max_depth: bounds.max_depth,
      max_views: 1,
      max_fields: 5,
    }
    let selected_rows : Array[Array[@admitted.CheckedValue]] = []
    for declaration in [salesforce, snowflake] {
      let warehouse = physical_equal(declaration, snowflake)
      let schema = mock_rows_schema(
        declaration, warehouse, declaration_limits, work,
      )
      let identity = if warehouse { "account_id" } else { "id" }
      let resource = if warehouse { "usage_30d" } else { "Account" }
      let connection = mock_rows_field(object, declaration.connector_id)
      let connection = @decode.closed_object(connection, [resource]).unwrap_or_else(() => {
          raise MockRowsStop(InvalidPage)
        },
      )
      let table = @decode.closed_object(mock_rows_field(connection, resource), [
        "key", "rows",
      ]).unwrap_or_else(() => raise MockRowsStop(InvalidPage))
      let keys = @decode.elements(mock_rows_field(table, "key")).unwrap_or_else(() => {
          raise MockRowsStop(InvalidPage)
        },
      )
      if keys.length() != 1 || @decode.text(keys[0]) != Ok(identity) {
        raise MockRowsStop(InvalidPage)
      }
      let rows = @decode.elements(mock_rows_field(table, "rows")).unwrap_or_else(() => {
          raise MockRowsStop(InvalidPage)
        },
      )
      if rows.length() > bounds.max_rows {
        raise MockRowsStop(InvalidPage)
      }
      let observed_keys : Array[String] = []
      let names = declaration.views[0].fields
      for row in rows {
        let fields = @decode.closed_object(row, names).unwrap_or_else(() => {
          raise MockRowsStop(InvalidPage)
        })
        let key = @decode.text(mock_rows_field(fields, identity)).unwrap_or_else(() => {
            raise MockRowsStop(InvalidPage)
          },
        )
        for previous in observed_keys {
          mock_rows_work(work, previous.length())
          mock_rows_work(work, key.length())
          if previous == key {
            raise MockRowsStop(InvalidPage)
          }
        }
        observed_keys.push(key)
        let checked : Map[String, @admitted.CheckedValue] = Map([])
        for name in names {
          let cell = mock_rows_field(fields, name)
          let full = @schema.lookup_reference(schema, name).unwrap().contract
          let target = if physical_equal(declaration, selected) {
            @schema.lookup_reference(selected_schema, name)
            .map(field => field.contract)
            .unwrap_or(full)
          } else {
            full
          }
          mock_rows_work(work, bounds.max_nodes)
          let same = @contract.type_equal(full, target, bounds.max_nodes) catch {
            _ => false
          }
          if !same {
            raise MockRowsStop(InvalidInputSchema)
          }
          let span = @decode.cursor_span(cell)
          mock_rows_work(work, span.end_byte - span.start_byte + 1)
          let cell = if target.shape is @contract.Signed64 {
            mock_rows_int64(cell, bytes, values)
          } else {
            cell
          }
          let value = @admitted.admit(target, cell, values).unwrap_or_else(() => {
            raise MockRowsStop(Value(name))
          })
          checked[name] = value
        }
        if physical_equal(declaration, selected) {
          let values = []
          for name in columns {
            values.push(
              checked
              .get(name)
              .unwrap_or_else(() => raise MockRowsStop(MissingField(name))),
            )
          }
          selected_rows.push(values)
        }
      }
    }
    Ok((selected_rows, root))
  } catch {
    MockRowsStop(issue) => Err(issue)
  }
}

///|
/// The original full Mock document is charged before decoding. The ticket
/// accounts for bytes only; Host file/current/operation and shared phase
/// custody remain separate. Refusal aborts this same attempt without capture.
pub fn accept_charged_mock_churn_risk_document(
  run : RowRun,
  charge : RowPageCharge,
  acquisition : RowAcquisition,
  salesforce : RowDeclaration,
  snowflake : RowDeclaration,
  bytes : Bytes,
  max_work : Int,
) -> Result[Int, RowHostIssue] {
  guard !run.closed && run.attempt.state is Reading(read) else {
    return Err(InvalidState)
  }
  match consume_row_page_charge(run, charge) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = try {
    guard run.attempt.preparation is DirectPreparation(preparation) &&
      physical_equal(preparation, acquisition.preparation) &&
      physical_equal(read.schema, preparation.schema) &&
      charge.received_bytes == bytes.length().to_int64() &&
      read.pages == 0L &&
      read.listing is None &&
      read.keyed is None else {
      raise MockRowsStop(ForeignSource)
    }
    let selected = if salesforce.views.length() == 1 &&
      physical_equal(preparation.view, salesforce.views[0]) {
      salesforce
    } else if snowflake.views.length() == 1 &&
      physical_equal(preparation.view, snowflake.views[0]) {
      snowflake
    } else {
      raise MockRowsStop(ForeignSource)
    }
    mock_churn_risk_document_rows(
      read, selected, salesforce, snowflake, bytes, max_work,
    ).bind(rows => accept_row_source_values(read, read.columns, rows))
  } catch {
    MockRowsStop(issue) => Err(issue)
  }
  match result {
    Ok(count) => Ok(count)
    Err(issue) => {
      abort_row_run(run)
      Err(Source(issue))
    }
  }
}
