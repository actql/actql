///|
/// Preserve the existing Owner's classification. A missing original journal or
/// credential record is unavailable responsibility, never an unsent proof.
priv enum HolderCatalogUseObservationIssue {
  Original(@journal.NativeRemoteJournalIssue)
  Resource(@effect_resource.NativeCredentialResourceIssue)
  Changed
}

///|
/// Query callbacks only, not a physical Journal, successful GET or cleanup ACK.
test "Catalog cleanup reobserves the original use after a transient query failure" {
  let queries = Ref(0)
  let original = "sha256:" + "a".repeat(64)
  let query : () -> Result[@effect_resource.NativeCredentialUseStatus?, Unit] = () => {
    queries.val += 1
    if queries.val == 1 {
      Err(())
    } else {
      Ok(Some({ use_cid: original, outcome: "unknown", status: None, }))
    }
  }
  assert_false(
    holder_catalog_cleanup_original_use_observed(
      false, true, false, false, false, query,
    ),
  )
  assert_true(
    holder_catalog_cleanup_original_use_observed(
      false, true, false, false, false, query,
    ),
  )
  assert_eq(queries.val, 2)
  assert_false(
    holder_catalog_use_succeeded({
      use_cid: original,
      outcome: "unknown",
      status: None,
    }),
  )
}

///|
test "Catalog cleanup query failure or absence stays pending on each pass" {
  let queries = Ref(0)
  for pass in 0..<3 {
    assert_false(
      holder_catalog_cleanup_original_use_observed(
        false,
        true,
        false,
        false,
        false,
        () => {
          queries.val += 1
          if pass == 1 {
            Ok(None)
          } else {
            Err(())
          }
        },
      ),
    )
  }
  assert_eq(queries.val, 3)
}

///|
test "Catalog cleanup does not query before a read or replace existing evidence" {
  let queries = Ref(0)
  for
    (started, original, custody, observation) in [
      (false, false, false, false),
      (true, true, false, false),
      (true, false, true, false),
      (true, false, false, true),
    ] {
    assert_true(
      holder_catalog_cleanup_original_use_observed(
        false,
        started,
        original,
        custody,
        observation,
        () => {
          queries.val += 1
          Err(())
        },
      ),
    )
  }
  assert_eq(queries.val, 0)
}

///|
/// The flag models an already accepted Store cleanup ACK only. This does not
/// manufacture that ACK, close the pending client or release its reservation.
test "Catalog cleanup confirmed Store retirement does not requery a closed credential DB" {
  let queries = Ref(0)
  let query_closed_database = () => {
    queries.val += 1
    Err(())
  }
  // A failed client close can leave the original database already closed.
  // Every later close pass must reach that same client rather than query it.
  for _ in 0..<2 {
    assert_true(
      holder_catalog_cleanup_original_use_observed(
        true, true, false, false, false, query_closed_database,
      ),
    )
  }
  assert_eq(queries.val, 0)
  // Without the original Store ACK, the same missing-use boundary stays pending.
  assert_false(
    holder_catalog_cleanup_original_use_observed(
      false, true, false, false, false, query_closed_database,
    ),
  )
  assert_eq(queries.val, 1)
}

///|
/// Compile-only projection boundaries; the query Owner must supply the actual
/// authenticated use. These values are not service or persistence evidence.
test "restored Catalog adoption requires confirmed successful original use" {
  let use_cid = "sha256:" + "a".repeat(64)
  for
    (outcome, status) in [
      ("claimed", None),
      ("unknown", Some(200)),
      ("failed", Some(500)),
      ("succeeded", None),
      ("succeeded", Some(500)),
    ] {
    assert_false(holder_catalog_use_succeeded({ use_cid, outcome, status, }))
  }
  assert_true(
    holder_catalog_use_succeeded({
      use_cid,
      outcome: "succeeded",
      status: Some(200),
    }),
  )
}

///|
/// Compile-only caller counterexample: absence in the original Journal never
/// reaches even the read-only Resource query, let alone a Provider GET.
test "Catalog restoration missing original use does not query a replacement resource DB" {
  let resource_queries = Ref(0)
  let result = holder_catalog_original_use_query(
    () => Err(@journal.Physical(@sqlite.NotFound)),
    () => {
      resource_queries.val += 1
      Err(@effect_resource.Journal(@sqlite.NotFound))
    },
  )
  assert_true(result is Err(Original(@journal.Physical(@sqlite.NotFound))))
  assert_eq(resource_queries.val, 0)
}

///|
/// Preserve original Owner reasons, including a foreign request or generation;
/// missing Checkpoint is deliberately not an input to this restoration seam.
test "Catalog restoration unavailable original custody preserves its reason without a fresh query" {
  for
    issue in [
      @journal.Closed,
      @journal.MissingDispatch,
      @journal.StaleSiteBinding,
      @journal.StateCollision,
      @journal.Physical(@sqlite.Collision),
    ] {
    let resource_queries = Ref(0)
    let result = holder_catalog_original_use_query(() => Err(issue), () => {
      resource_queries.val += 1
      Err(@effect_resource.Journal(@sqlite.NotFound))
    })
    match result {
      Err(Original(actual)) =>
        assert_true(
          match (issue, actual) {
            (@journal.Closed, @journal.Closed)
            | (@journal.MissingDispatch, @journal.MissingDispatch)
            | (@journal.StaleSiteBinding, @journal.StaleSiteBinding)
            | (@journal.StateCollision, @journal.StateCollision)
            | (
              @journal.Physical(@sqlite.Collision),
              @journal.Physical(@sqlite.Collision),
            ) => true
            _ => false
          },
        )
      _ => abort("Original Catalog responsibility was not retained")
    }
    assert_eq(resource_queries.val, 0)
  }
}

///|
/// Common-issued nominal uses for caller projection cases only. These do not
/// establish signature admission, a physical journal or Resource response.
fn holder_catalog_original_use_fixture(
  id : String,
) -> @effect_credential.RemoteCredentialUse {
  let cid = (unit : String) => "sha256:" + unit.repeat(64)
  let grant = @effect_credential.prepare_grant(
    "credential-authority",
    "provider-principal",
    "original-workspace",
    "preview",
    "selected-site",
    4,
    cid("a"),
    "salesforce",
    "salesforce/0.1",
    "https://provider.example",
    "salesforce:catalog:describe",
    cid("b"),
    3,
    cid("c"),
    2000000000000L,
    2,
  ).unwrap()
  @effect_credential.prepare_credential_use(
    grant,
    id,
    1999999999999L,
    0,
    false,
    "provider-principal",
    "original-workspace",
    "preview",
    "selected-site",
    4,
    cid("a"),
    "salesforce",
    "salesforce/0.1",
    "https://provider.example",
    "salesforce:catalog:describe",
    cid("b"),
    3,
    cid("c"),
  ).unwrap()
}

///|
test "Catalog restoration cannot adopt another resource use or a changed original witness" {
  let original = holder_catalog_original_use_fixture("original-use")
  let foreign = holder_catalog_original_use_fixture("foreign-use")
  let original_cid = @effect_credential.credential_use_cid(original)
  let foreign_cid = @effect_credential.credential_use_cid(foreign)
  let wrong_resource = holder_catalog_original_use_query(() => Ok(original), () => {
    Ok({ use_cid: foreign_cid, outcome: "succeeded", status: Some(200), })
  })
  assert_true(wrong_resource is Err(Changed))
  let reads = Ref(0)
  let changed = holder_catalog_original_use_query(
    () => {
      reads.val += 1
      Ok(if reads.val == 1 { original } else { foreign })
    },
    () => {
      Ok({ use_cid: original_cid, outcome: "succeeded", status: Some(200), })
    },
  )
  assert_true(changed is Err(Changed))
  assert_eq(reads.val, 2)
}

///|
test "Catalog restoration keeps resource DB absence and unknown separate from successful original response" {
  let original = holder_catalog_original_use_fixture("original-use")
  assert_true(
    holder_catalog_original_use_query(() => Ok(original), () => {
      Err(@effect_resource.Journal(@sqlite.NotFound))
    })
    is Err(Resource(@effect_resource.Journal(@sqlite.NotFound))),
  )
  for outcome in ["claimed", "unknown", "failed", "succeeded"] {
    let reads = Ref(0)
    let queried = holder_catalog_original_use_query(
      () => {
        reads.val += 1
        Ok(original)
      },
      () => {
        Ok({
          use_cid: @effect_credential.credential_use_cid(original),
          outcome,
          status: Some(200),
        })
      },
    ).unwrap()
    assert_eq(reads.val, 2)
    assert_eq(queried.outcome, outcome)
    assert_eq(holder_catalog_use_succeeded(queried), outcome == "succeeded")
  }
}

///|
test "Catalog restoration rechecks original responsibility after the resource read" {
  let original = holder_catalog_original_use_fixture("original-use")
  let reads = Ref(0)
  let queried = holder_catalog_original_use_query(
    () => {
      reads.val += 1
      if reads.val == 1 {
        Ok(original)
      } else {
        Err(@journal.StaleSiteBinding)
      }
    },
    () => {
      Ok({
        use_cid: @effect_credential.credential_use_cid(original),
        outcome: "succeeded",
        status: Some(200),
      })
    },
  )
  assert_true(queried is Err(Original(@journal.StaleSiteBinding)))
  assert_eq(reads.val, 2)
}

///|
/// A previous query error is not permanent retirement evidence. Each cleanup
/// pass can inspect only the same original Journal/Resource use. This result
/// acknowledges observation only: claimed/unknown is neither successful GET
/// nor Store/physical cleanup, and no absence permits another read or claim.
/// The existing Store cleanup ACK retires this query prerequisite only; failed
/// service handles still require their original close retry. The credential DB
/// may already be closed when another service handle remains pending.
fn holder_catalog_cleanup_original_use_observed(
  catalog_cleanup_confirmed : Bool,
  read_started : Bool,
  has_original_use : Bool,
  has_custody : Bool,
  has_observation : Bool,
  query : () -> Result[@effect_resource.NativeCredentialUseStatus?, Unit],
) -> Bool {
  if !catalog_cleanup_confirmed &&
    read_started &&
    !has_original_use &&
    !has_custody &&
    !has_observation {
    query() is Ok(Some(_))
  } else {
    true
  }
}

///|
/// The original Journal Owner selects a nominal use before and after the
/// Resource query. This function issues no claim or Provider call and accepts
/// no use identity from a candidate response or replacement credential DB.
fn holder_catalog_original_use_query(
  read_original : () -> Result[
    @effect_credential.RemoteCredentialUse,
    @journal.NativeRemoteJournalIssue,
  ],
  query_resource : () -> Result[
    @effect_resource.NativeCredentialUseStatus,
    @effect_resource.NativeCredentialResourceIssue,
  ],
) -> Result[
  @effect_resource.NativeCredentialUseStatus,
  HolderCatalogUseObservationIssue,
] {
  let original = match read_original() {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  let status = match query_resource() {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  let current = match read_original() {
    Ok(value) => value
    Err(issue) => return Err(Original(issue))
  }
  let original_cid = @effect_credential.credential_use_cid(original)
  if @effect_credential.credential_use_cid(current) != original_cid ||
    status.use_cid != original_cid {
    return Err(Changed)
  }
  Ok(status)
}

///|
fn holder_catalog_use_succeeded(
  original : @effect_resource.NativeCredentialUseStatus,
) -> Bool {
  original.outcome == "succeeded" && original.status == Some(200)
}
