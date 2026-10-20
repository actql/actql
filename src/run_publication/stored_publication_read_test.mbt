///|
fn stored_publication_test_rows(
  fixture : CommitReadFixture,
) -> Map[String, String] {
  let rows : Map[String, String] = Map([])
  for original in fixture.originals {
    rows[publication_contract_identity(original)] = publication_contract_json(
      original,
    )
  }
  rows
}

///|
fn stored_publication_test_load(
  fixture : CommitReadFixture,
  read : (String) -> Result[String?, Int],
  current : () -> Result[Unit, Int],
  max_contracts? : Int = 14,
  max_total_bytes? : Int = 1048576,
) -> Result[PublicationCommitPreparation, StoredPublicationReadIssue[Int]] {
  let index = fixture.originals[7]
  let projected = project_public_index_read(index).unwrap()
  let key = publication_index_storage_key(index, 65536, 4096, 32).unwrap()
  let index_cid = publication_contract_identity(index)
  read_stored_effect_free_publication(
    projected.namespace_id,
    projected.authority_scope_cid,
    projected.run_definition_cid,
    (table, selected) => {
      if table == "public_index" && selected == key {
        Ok(Some(@utf8.encode(index_cid)))
      } else if table == "publication_contract" {
        read(selected).map(value => value.map(text => @utf8.encode(text)))
      } else {
        Err(74)
      }
    },
    current,
    max_contracts,
    max_total_bytes,
    65536,
    4096,
    32,
    32768,
  ).bind(value => {
    match value {
      Some(owner) => Ok(owner)
      None => Err(Missing(index_cid))
    }
  })
}

///|
test "stored publication reads and validates every original body before Result selection" {
  let fixture = commit_read_fixture()
  let rows = stored_publication_test_rows(fixture)
  let calls : Array[String] = []
  let mut checks = 0
  let owner = stored_publication_test_load(
    fixture,
    cid => {
      calls.push(cid)
      Ok(rows.get(cid))
    },
    () => {
      checks += 1
      Ok(())
    },
  ).unwrap()
  assert_eq(calls.length(), 14)
  assert_true(checks >= calls.length() * 2 + 2)
  for original in fixture.originals {
    assert_eq(
      calls
      .filter(cid => cid == publication_contract_identity(original))
      .length(),
      1,
    )
  }
  // A restarted process gets validated durable bodies, never a reconstructed
  // compiler/physical invocation or a pointer-equality substitute for them.
  commit_read_complete(owner, 64) |> ignore
  let view = owner.finish_view().unwrap()
  assert_eq(owner.view_count(view).unwrap(), 14)
  for index in 0..<14 {
    assert_eq(
      publication_contract_json(owner.view_contract(view, index).unwrap()),
      publication_contract_json(fixture.originals[index]),
    )
  }
  let stored_index = owner.view_contract(view, 7).unwrap()
  let request = owner.view_contract(view, 5).unwrap()
  let attempt = owner.view_contract(view, 6).unwrap()
  owner.begin_observed_commit(view, request, attempt, stored_index).unwrap()
  observed_commit_test_complete(owner, view, 64) |> ignore
  let selected = owner
    .observed_result_read_materials(view, "answer", 16)
    .unwrap()
  assert_eq(
    publication_contract_json(selected.manifest),
    publication_contract_json(fixture.originals[2]),
  )
  assert_eq(selected.read.result_name, "answer")
  owner.release_observed_commit(view).unwrap()
  owner.release_view(view).unwrap()
  fixture.preparation.cancel()
}

///|
test "stored publication refuses missing corrupt changed and foreign bodies without replacement" {
  let fixture = commit_read_fixture()
  let rows = stored_publication_test_rows(fixture)
  for original in fixture.originals {
    let missing = publication_contract_identity(original)
    assert_true(
      stored_publication_test_load(
        fixture,
        cid => Ok(if cid == missing { None } else { rows.get(cid) }),
        () => Ok(()),
      )
      is Err(Missing(cid)) &&
      cid == missing,
    )
  }
  let index_cid = publication_contract_identity(fixture.originals[7])
  assert_true(
    stored_publication_test_load(
      fixture,
      cid => Ok(if cid == index_cid { Some("{}") } else { rows.get(cid) }),
      () => Ok(()),
    )
    is Err(Contract(_)),
  )
  let (foreign_attempt, _) = observed_commit_test_pair(fixture)
  let attempt_cid = publication_contract_identity(fixture.originals[6])
  assert_true(
    stored_publication_test_load(
      fixture,
      cid => {
        Ok(
          if cid == attempt_cid {
            Some(publication_contract_json(foreign_attempt))
          } else {
            rows.get(cid)
          },
        )
      },
      () => Ok(()),
    )
    is Err(References),
  )
  let index = fixture.originals[7]
  let projected = project_public_index_read(index).unwrap()
  let mut reads = 0
  let refused : Result[
    PublicationCommitPreparation?,
    StoredPublicationReadIssue[Int],
  ] = read_stored_effect_free_publication(
    projected.namespace_id,
    "invalid-scope",
    projected.run_definition_cid,
    (_, _) => {
      reads += 1
      Ok(None)
    },
    () => Ok(()),
    14,
    1048576,
    65536,
    4096,
    32,
    32768,
  )
  assert_true(refused is Err(References))
  assert_eq(reads, 0)
  fixture.preparation.cancel()
}

///|
test "stored publication preserves read and current errors and finite copy bounds" {
  let fixture = commit_read_fixture()
  let rows = stored_publication_test_rows(fixture)
  assert_true(
    stored_publication_test_load(fixture, _ => Err(71), () => Ok(()))
    is Err(Read(71)),
  )
  let mut reads = 0
  assert_true(
    stored_publication_test_load(
      fixture,
      cid => {
        reads += 1
        Ok(rows.get(cid))
      },
      () => Err(72),
    )
    is Err(Read(72)),
  )
  assert_eq(reads, 0)
  let mut active = true
  assert_true(
    stored_publication_test_load(
      fixture,
      cid => {
        active = false
        Ok(rows.get(cid))
      },
      () => if active { Ok(()) } else { Err(73) },
    )
    is Err(Read(73)),
  )
  assert_true(
    stored_publication_test_load(
      fixture,
      cid => Ok(rows.get(cid)),
      () => Ok(()),
      max_contracts=13,
    )
    is Err(Bounds),
  )
  assert_true(
    stored_publication_test_load(
      fixture,
      cid => Ok(rows.get(cid)),
      () => Ok(()),
      max_total_bytes=1,
    )
    is Err(Bounds),
  )
  fixture.preparation.cancel()
}

///|
test "stored publication distinguishes absent index from malformed or missing original body" {
  let fixture = commit_read_fixture()
  let index = fixture.originals[7]
  let projected = project_public_index_read(index).unwrap()
  let mut calls = 0
  fn inspect(
    read : (String, String) -> Result[Bytes?, Int],
  ) -> Result[PublicationCommitPreparation?, StoredPublicationReadIssue[Int]] {
    read_stored_effect_free_publication(
      projected.namespace_id,
      projected.authority_scope_cid,
      projected.run_definition_cid,
      read,
      () => Ok(()),
      14,
      1048576,
      65536,
      4096,
      32,
      32768,
    )
  }
  assert_true(
    inspect((table, key) => {
      calls += 1
      if table != "public_index" ||
        key != publication_index_storage_key(index, 65536, 4096, 32).unwrap() {
        return Err(75)
      }
      Ok(None)
    })
    is Ok(None),
  )
  assert_eq(calls, 1)
  assert_true(
    inspect((_, _) => Ok(Some(b"not-an-index-identity"))) is Err(References),
  )
  let cid = publication_contract_identity(index)
  assert_true(
    inspect((table, _) => {
      Ok(if table == "public_index" { Some(@utf8.encode(cid)) } else { None })
    })
    is Err(Missing(missing)) &&
    missing == cid,
  )
  assert_true(
    inspect((table, _) => {
      Ok(
        Some(if table == "public_index" { @utf8.encode(cid) } else { b"\xff" }),
      )
    })
    is Err(References),
  )
  fixture.preparation.cancel()
}
