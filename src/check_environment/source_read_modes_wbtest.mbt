///|
fn mode_probe(
  body : String,
  cap? : Int = 10000,
) -> Result[(Array[SourceReadMode], SourceReadMode, Int), SourceReadModeIssue] {
  let budget = { remaining: cap, }
  try {
    let (modes, selected) = check_read_mode_body(sv_cursor(body), budget)
    Ok((modes, selected, cap - budget.remaining))
  } catch {
    ReadModeStop(e) => Err(e)
  }
}

///|
fn mode_fixture(name : String, bounded : Bool, checkpoint : Bool) -> String {
  let suffix = if checkpoint {
    ",\"checkpoint\":{\"kind\":\"opaque\",\"expires\":false,\"value_schema\":{\"id\":\"checkpoint\",\"version\":\"external\",\"cid\":\"sha256:" +
    "a".repeat(64) +
    "\"}}"
  } else {
    ""
  }
  "{\"mode\":\"" + name + "\",\"bounded\":" + bounded.to_string() + suffix + "}"
}

///|
test "advertised read modes distinguish boundedness from profile selection support" {
  for name in ["snapshot", "changes", "watch"] {
    for bounded in [true, false] {
      for checkpoint in [true, false] {
        let wire = "{\"default_mode\":\"" +
          name +
          "\",\"modes\":[" +
          mode_fixture(name, bounded, checkpoint) +
          "]}"
        let accepted = match name {
          "snapshot" => bounded
          "changes" => checkpoint
          _ => !bounded && checkpoint
        }
        let result = mode_probe(wire)
        assert_eq(result is Ok(_), accepted)
        if result is Ok((modes, selected, work)) {
          assert_eq(modes.length(), 1)
          assert_true(physical_equal(modes[0], selected))
          assert_eq(read_mode_bounded(selected), bounded)
          assert_true(mode_probe(wire, cap=work) is Ok(_))
          assert_true(
            mode_probe(wire, cap=work - 1) is Err(e) && e.kind == WorkLimit,
          )
        }
      }
    }
  }
}

///|
test "mode names are unique and default selects exactly one declared object" {
  let snapshot = mode_fixture("snapshot", true, false)
  let watch = mode_fixture("watch", false, true)
  let (modes, selected, _) = mode_probe(
    "{\"default_mode\":\"snapshot\",\"modes\":[" + watch + "," + snapshot + "]}",
  ).unwrap()
  assert_eq(read_mode_kind(modes[0]), WatchMode)
  assert_true(physical_equal(selected, modes[1]))
  for
    body in [
      "{\"default_mode\":\"changes\",\"modes\":[" + snapshot + "]}",
      "{\"default_mode\":\"snapshot\",\"modes\":[]}",
    ] {
    assert_true(mode_probe(body) is Err(e) && e.kind == UndeclaredDefault)
  }
  match
    mode_probe(
      "{\"default_mode\":\"snapshot\",\"modes\":[" +
      snapshot +
      "," +
      snapshot +
      "]}",
    ) {
    Err(e) => {
      assert_eq(e.kind, DuplicateMode(SnapshotMode))
      assert_eq(@decode.cursor_path(e.source.unwrap()), [
        @source.Key("modes"),
        @source.Index(1),
        @source.Key("mode"),
      ])
    }
    Ok(_) => abort("duplicate mode admitted")
  }
}
