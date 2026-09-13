///|
fn query_record_fixture(broad : Bool) -> QueryRecordPayload {
  {
    requirement_cid: "sha256:2721dd2b75b22dba5d59b1f81f9594d8d2493308e7ba890bdd49e7e4b980b835",
    snapshot: None,
    scan_scope_cid: "sha256:3ce846b6366a1485c90cd8583a0f5693771ae24a55f63c5b0a1feee33f69f573",
    access: {
      scope_cid: if broad {
        "sha256:c405adf54d82c6781da6c60986f6ddda8b387965838feb07a3cbf5f59ba9ada6"
      } else {
        "sha256:a0444b106a6e402c65f2c8d337b107d5356824b164b218dfb713c84b67efb21d"
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
        "sha256:0ac6f30b70c81f5da98168698421429dda1d7c51bcba7a057f0a02257d969329",
      ),
      (
        false,
        Filter,
        "sha256:18a73f47882072bd1cb700a53d47c76795941b3416a47dc99c0788b8125b2750",
      ),
      (
        false,
        Select,
        "sha256:c3dfea4ea0d592715f04d50d106f8de7fc70d6b7e4672b7f8ef9959aee4ad7fe",
      ),
      (
        true,
        SourceValidation,
        "sha256:721863b9df04589f55af9fdda6d7c6e9d0bb8201c36d0da2db760e729a81986d",
      ),
      (
        true,
        Filter,
        "sha256:0d80f0ca2b281a630554eab6cb8d13a8b9012bb59d1690e542395e5db51d95b0",
      ),
      (
        true,
        Select,
        "sha256:541fc183ae91a020a9e6d6f222cde24c46ad309755203023e28aa20b92bd4134",
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
