///|
test "durable dispatch record round-trips through independent admission" {
  let source = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(source, request("durable-a", 31, 1, bundle))
  provision(record)
  execute(record)
  let body = dispatch_record_durable_json(record).unwrap()
  let admitted = admit_durable_dispatch_record(@utf8.encode(body)).unwrap()
  assert_eq(durable_dispatch_record_revision(admitted), 2)
  assert_eq(durable_dispatch_record_journal_key(admitted), [
    "coordinator-a",
    "site-a",
    "1",
    "durable-a",
    cid("0000000000000000000000000000000000000000000000000000000000000000"),
    "task-a",
    "31",
  ])
  let restored_journal = journal()
  let restored = restore_durable_dispatch_record(restored_journal, admitted).unwrap()
  assert_eq(dispatch_record_durable_json(restored).unwrap(), body)
  let repeated = restore_durable_dispatch_record(restored_journal, admitted).unwrap()
  assert_eq(dispatch_record_durable_json(repeated).unwrap(), body)
}

///|
test "durable dispatch record rejects noncanonical and impossible state" {
  let state = journal()
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let (_, record) = accept(state, request("durable-b", 32, 1, bundle))
  let body = dispatch_record_durable_json(record).unwrap()
  assert_true(
    admit_durable_dispatch_record(@utf8.encode(" " + body))
    is Err(InvalidJournal),
  )
  let changed_version = body.replace(
    old="actql-remote-dispatch-record/0.1",
    new="actql-remote-dispatch-record/0.2",
  )
  assert_true(
    admit_durable_dispatch_record(@utf8.encode(changed_version))
    is Err(InvalidJournal),
  )
  let impossible = body.replace(
    old="\"material_available\":false",
    new="\"material_available\":true",
  )
  assert_true(
    admit_durable_dispatch_record(@utf8.encode(impossible))
    is Err(InvalidJournal),
  )
  let request_changed = body.replace(
    old=cid("0000000000000000000000000000000000000000000000000000000000000000"),
    new=cid("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"),
  )
  assert_true(
    admit_durable_dispatch_record(@utf8.encode(request_changed))
    is Err(InvalidJournal),
  )
}

///|
test "durable attempt identity prevents dispatch ID from authorizing reexecution" {
  let bundle = cid(
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
  )
  let first = request("attempt-key-a", 33, 1, bundle)
  let second = request("attempt-key-b", 33, 1, bundle)
  assert_true(
    dispatch_request_identity(first) != dispatch_request_identity(second),
  )
  assert_eq(
    dispatch_request_attempt_identity(first).unwrap(),
    dispatch_request_attempt_identity(second).unwrap(),
  )
}
