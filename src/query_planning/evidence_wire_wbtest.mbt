///|
/// Isolated codec experiment against the independent shared fixture. This is
/// not a product issuer or a substitute for the pending owned requirement.
priv enum QueryRecordRole {
  SourceValidation
  Filter
  Select
}

///|
priv struct QueryActualAccess {
  scope_cid : String
  provider_scope_cid : String?
  received_rows : Int
  received_fields : Array[String]
  received_bytes : Int
}

///|
priv struct QueryOutputIdentity {
  contract_cid : String
  rows_cid : String
  row_count : Int
}

///|
priv struct QueryRecordPayload {
  requirement_cid : String
  snapshot : (String, String)?
  scan_scope_cid : String
  access : QueryActualAccess
  output : QueryOutputIdentity
}

///|
fn emit_query_optional_cid(
  value : String?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match value {
    None => @encode.null_value(writer)
    Some(cid) => @encode.string_value(writer, cid)
  }
}

///|
fn emit_query_access(
  access : QueryActualAccess,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "provider_scope_cid")
  emit_query_optional_cid(access.provider_scope_cid, writer)
  @encode.key(writer, "received_bytes")
  @encode.number_value(writer, access.received_bytes.to_double())
  @encode.key(writer, "received_fields")
  @encode.begin_array(writer)
  for field in access.received_fields {
    @encode.string_value(writer, field)
  }
  @encode.end_array(writer)
  @encode.key(writer, "received_rows")
  @encode.number_value(writer, access.received_rows.to_double())
  @encode.key(writer, "scope_cid")
  @encode.string_value(writer, access.scope_cid)
  @encode.end_object(writer)
}

///|
fn emit_query_output(
  output : QueryOutputIdentity,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "contract_cid")
  @encode.string_value(writer, output.contract_cid)
  @encode.key(writer, "row_count")
  @encode.number_value(writer, output.row_count.to_double())
  @encode.key(writer, "rows_cid")
  @encode.string_value(writer, output.rows_cid)
  @encode.end_object(writer)
}

///|
fn emit_query_snapshot(
  snapshot : (String, String)?,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match snapshot {
    None => @encode.null_value(writer)
    Some((contract, token)) => {
      @encode.begin_object(writer)
      @encode.key(writer, "contract_cid")
      @encode.string_value(writer, contract)
      @encode.key(writer, "token_cid")
      @encode.string_value(writer, token)
      @encode.end_object(writer)
    }
  }
}

///|
fn emit_query_record(
  payload : QueryRecordPayload,
  issuer : String,
  attempt : String,
  role : QueryRecordRole,
  writer : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "actual_access")
  emit_query_access(payload.access, writer)
  @encode.key(writer, "attempt")
  @encode.string_value(writer, attempt)
  @encode.key(writer, "issuer")
  @encode.string_value(writer, issuer)
  @encode.key(writer, "output")
  emit_query_output(payload.output, writer)
  @encode.key(writer, "requirement_cid")
  @encode.string_value(writer, payload.requirement_cid)
  @encode.key(writer, "role")
  @encode.string_value(
    writer,
    match role {
      SourceValidation => "source_validation"
      Filter => "filter"
      Select => "select"
    },
  )
  @encode.key(writer, "scan_scope_cid")
  @encode.string_value(writer, payload.scan_scope_cid)
  @encode.key(writer, "snapshot")
  emit_query_snapshot(payload.snapshot, writer)
  @encode.key(writer, "version")
  @encode.string_value(writer, "actql-query-process-evidence/0.1")
  @encode.end_object(writer)
}

///|
fn query_record_fixture(broad : Bool) -> QueryRecordPayload {
  {
    requirement_cid: "sha256:f01ed40e4f8980416994928d4aefd7bf9a941b2f3eacb30eb531e32f35da6cb2",
    snapshot: None,
    scan_scope_cid: "sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573",
    access: {
      scope_cid: if broad {
        "sha256:45a0c6172b1fac98210d96990a3b69af5a0e2e13cef99b27d025756890f26255"
      } else {
        "sha256:64e78755f5bea203049d8c076008831629e1bbccae7d5983fcf2142af5009a06"
      },
      provider_scope_cid: None,
      received_rows: if broad {
        3
      } else {
        2
      },
      received_fields: if broad {
        ["amount", "id", "status"]
      } else {
        ["id"]
      },
      received_bytes: if broad {
        120
      } else {
        23
      },
    },
    output: {
      contract_cid: "sha256:b2022f831ddc08fb0cf0def00bf30679fd2f50e55b6928a42bc8555f016cb84b",
      rows_cid: "sha256:30cbdf39c841b57751c60906376659a274455e096bdfcc059fb333db6e91578a",
      row_count: 2,
    },
  }
}

///|
test "isolated record codec matches six independent shared process evidence vectors" {
  for
    (broad, role, expected) in [
      (
        false,
        SourceValidation,
        "sha256:ed46499a8c5a02f3535a5ad1aef63bf0340628bd266e1a24945873c04fef9910",
      ),
      (
        false,
        Filter,
        "sha256:30073c7d232bb6804117dbc849ef06952af6c6ef64a18cd7a4c82e767e752020",
      ),
      (
        false,
        Select,
        "sha256:8981b90f63b88d25c751e0e1fcd8302b37e39ad2094e7822e793f32983a0eddb",
      ),
      (
        true,
        SourceValidation,
        "sha256:c9f8cf08fc225037e39adf4a0065d33ad8ffda2f6cad810454f4a06492f225f8",
      ),
      (
        true,
        Filter,
        "sha256:600e728b3dbe8affac697e971d9e2ed599285bc571297684b9266eeb5421149b",
      ),
      (
        true,
        Select,
        "sha256:8ee2fd57f27d8201faf30fdf4cfe6799ec5721f810be4a19d824ae8a0b2fd1b1",
      ),
    ] {
    let payload = query_record_fixture(broad)
    let attempt = if broad { "2" } else { "1" }
    let writer = @encode.hashing_writer(10000, 1000, 10)
    emit_query_record(payload, "fixture-process", attempt, role, writer)
    let (hash, bytes, nodes) = @encode.finish_hash_usage(writer)
    assert_eq("sha256:" + hash, expected)
    let exact = @encode.hashing_writer(bytes, nodes, 10)
    emit_query_record(payload, "fixture-process", attempt, role, exact)
    assert_eq("sha256:" + @encode.finish_hash(exact), expected)
    let short = @encode.hashing_writer(bytes - 1, nodes, 10)
    let rejected = try {
      emit_query_record(payload, "fixture-process", attempt, role, short)
      @encode.finish_hash(short) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
    let closed = try {
      @encode.finish_hash(short) |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(closed)
    let other = @encode.hashing_writer(10000, 1000, 10)
    emit_query_record(
      payload, "fixture-process", "different-attempt", role, other,
    )
    assert_true("sha256:" + @encode.finish_hash(other) != expected)
  }
}
