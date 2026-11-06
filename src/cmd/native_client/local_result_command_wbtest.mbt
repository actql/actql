///|
fn result_command_child(argv : Array[String]) -> @argparse.Matches raise {
  guard command().parse(argv=argv[:], env=Map([])).subcommand
    is Some(("result", child)) else {
    fail("missing Result command")
  }
  child
}

///|
test "public Result selects the original Run ID without file or attempt substitution" {
  let child = result_command_child([
    "result", "original-run", "--result", "answer",
  ])
  assert_eq(required(child, "run"), "original-run")
  assert_eq(optional(child, "result"), Some("answer"))
  for
    name in [
      "ref-file", "submission-ref-file", "attempt-id", "purpose", "max-output-bytes",
    ] {
    assert_eq(optional(child, name), None)
  }
  assert_eq(local_result_format(child), "jsonl")
  assert_true(local_product_operation("result"))
}

///|
test "public Result refuses Remote before connection or input access" {
  let parsed = command().parse(argv=["result", "original-run"], env=Map([]))
  let reason = execute(parsed) catch { ClientStop(message) => message }
  assert_eq(reason, "operation requires an explicit Local configuration")
}

///|
test "Result defaults use exactly one committed name and preserve explicit names" {
  assert_eq(local_result_name("[\"answer\"]", None), "answer")
  assert_eq(local_result_name("[\"a\",\"b\"]", Some("b")), "b")
  for wire in ["[]", "[\"a\",\"b\"]"] {
    let reason = local_result_name(wire, None) catch {
      ClientStop(message) => message
    }
    assert_eq(reason, "LocalResultNameRequired")
  }
  let missing = local_result_name("[\"answer\"]", Some("other")) catch {
    ClientStop(message) => message
  }
  assert_eq(missing, "LocalResultNotDeclared")
}

///|
test "Result inventory refuses malformed duplicate and overlong names" {
  for
    wire in [
      "{}",
      "[1]",
      "[\"\"]",
      "[\"answer\",\"answer\"]",
      "[\"" + "x".repeat(129) + "\"]",
    ] {
    let reason = local_result_name(wire, None) catch {
      ClientStop(message) => message
    }
    assert_eq(reason, "LocalResultInventoryUnavailable")
  }
  assert_eq(
    local_result_name("[\"" + "x".repeat(128) + "\"]", None),
    "x".repeat(128),
  )
}

///|
test "Result format is presentation only and unsupported delivery adapters are not ignored" {
  for format in ["json", "jsonl", "csv"] {
    let child = result_command_child([
      "result", "original-run", "--format", format,
    ])
    assert_eq(local_result_format(child), format)
    local_result_stdout_only(child)
  }
  let invalid = result_command_child([
    "result", "original-run", "--format", "JSON",
  ])
  let reason = local_result_format(invalid) catch {
    ClientStop(message) => message
  }
  assert_eq(reason, "InvalidLocalReadSelection")
  for name in ["output", "deliver", "receipt"] {
    let child = result_command_child([
      "result",
      "original-run",
      "--" + name,
      "explicit-target",
    ])
    let reason = try {
      local_result_stdout_only(child)
      "unexpected success"
    } catch {
      ClientStop(message) => message
    }
    assert_eq(reason, "LocalResultFileDeliveryUnavailable")
  }
  let child = result_command_child(["result", "original-run", "--json"])
  let reason = try {
    local_result_stdout_only(child)
    "unexpected success"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(reason, "LocalResultJsonEnvelopeUnavailable")
}

///|
test "legacy read retains its explicit original file and delivery selection" {
  guard command().parse(
      argv=[
        "read", "--ref-file", "original.json", "--submission-ref-file", "submission.json",
        "--purpose", "inspection", "--format", "jsonl", "--max-output-bytes", "4096",
        "--result-name", "answer", "--attempt-id", "original-attempt",
      ],
      env=Map([]),
    ).subcommand
    is Some(("read", child)) else {
    fail("legacy read lost")
  }
  for
    (name, value) in [
      ("ref-file", "original.json"),
      ("submission-ref-file", "submission.json"),
      ("purpose", "inspection"),
      ("format", "jsonl"),
      ("max-output-bytes", "4096"),
      ("result-name", "answer"),
      ("attempt-id", "original-attempt"),
    ] {
    assert_eq(required(child, name), value)
  }
}

///|
fn result_command_store(name : String) -> @local_store.Store raise {
  let selected = match @env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT") {
    Some(root) => Some(root)
    None => @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_ROOT")
  }
  let base = request_lookup_some(selected, "result.Store.root")
  let parent = request_lookup_ok(
    @local_filesystem.open_private_root(base),
    "result.Store.parent",
  )
  request_lookup_ok(parent.create_directory(name), "result.Store.directory")
  |> ignore
  request_lookup_ok(parent.close(), "result.Store.parent.close")
  let library = request_lookup_ok(
    @local_sqlite.load_library(
      request_lookup_some(
        @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"),
        "result.Store.library",
      ),
    ),
    "result.Store.load",
  )
  request_lookup_ok(
    @local_store.open_store(
      library,
      base + "/" + name,
      "sha256:" + "c".repeat(64),
      65536L,
      8L,
      131072L,
    ),
    "result.Store.open",
  )
}

///|
test "Result close boundary closes only its original and waits for confirmed cleanup" {
  let store = result_command_store("result-store-success")
  let other = result_command_store("result-store-independent")
  assert_true(store.capacity_usage() is Ok(_))
  local_result_store_close(store, "original-attempt")
  assert_true(store.capacity_usage() is Err(@local_store.Closed))
  assert_true(other.capacity_usage() is Ok(_))
  assert_true(other.close() is Ok(true))
}

///|
test "Result preparation refusal retains the original reason after the same close ACK" {
  let store = result_command_store("result-store-refusal")
  let reason = try {
    errdefer local_result_store_close(store, "original-attempt")
    stop("OriginalPolicyRefused")
  } catch {
    ClientStop(message) => message
  }
  assert_eq(reason, "OriginalPolicyRefused")
  assert_true(store.capacity_usage() is Err(@local_store.Closed))
}

///|
test "Result close boundary cannot turn a pending original Writer into a reply" {
  let store = result_command_store("result-store-pending")
  let request = @test_payload.prepare_publication_payload_request(
    "sha256:" + "c".repeat(64),
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "sha256:" + "d".repeat(64),
    "sha256:" + "e".repeat(64),
    "sha256:" + "f".repeat(64),
    "sha256:" + "1".repeat(64),
    "sha256:" + "2".repeat(64),
    16L,
    1L,
  ).unwrap()
  let writer = request_lookup_ok(store.begin_payload(request), "result.writer")
  let reason = try {
    local_result_store_close(store, "original-attempt")
    "must not escape"
  } catch {
    ClientStop(message) => message
  }
  assert_eq(reason, "LocalReadStoreCleanupPending attempt-id=original-attempt")
  // The same original Writer remains usable/owned, not replaced or discarded.
  writer.append(b"held").unwrap()
  writer.cancel().unwrap()
  assert_true(store.close() is Ok(true))
}

///|
test "main output bypasses buffered replies only for actual Local payload routes" {
  let local_result = command().parse(
    argv=["--mode", "local", "result", "original-run"],
    env=Map([]),
  )
  assert_true(local_payload_already_streamed(local_result))
  let local_read = command().parse(
    argv=[
      "--mode", "local", "read", "--ref-file", "original.json", "--result-name",
      "answer", "--attempt-id", "original-attempt",
    ],
    env=Map([]),
  )
  assert_true(local_payload_already_streamed(local_read))
  let remote_read = command().parse(
    argv=[
      "read", "--ref-file", "original.json", "--result-name", "answer", "--attempt-id",
      "original-attempt",
    ],
    env=Map([]),
  )
  assert_false(local_payload_already_streamed(remote_read))
  let local_status = command().parse(
    argv=["--mode", "local", "status", "original-run"],
    env=Map([]),
  )
  assert_false(local_payload_already_streamed(local_status))
}
