///|
fn installed_child_stop_and_finish(
  fixture : InstalledProcessFixture,
  process : InstalledArenaProcess,
) -> Unit raise {
  fixture.host.restrict_process_transport(fixture.domain, process).unwrap()
  fixture.host.return_process_transport(fixture.domain, process).unwrap()
  for index = 0; index < 200 && process.stop is None; index = index + 1 {
    fixture.host.poll_process_stop(fixture.domain, process).unwrap() |> ignore
    if process.stop is None {
      assert_eq(process_test_sleep(1000), 0)
    }
  }
  assert_true(process.stop is Some(_))
  process.stop.unwrap().require_current(process.holder.unwrap()).unwrap()
  fixture.host.retire_stopped_process(fixture.domain, process).unwrap()
  assert_true(process.closed && fixture.domain.loan is Some(_))
  installed_process_finish(fixture)
}

///|
test "installed child uses the original captured backing on FD4 and the original argv and selected environment" {
  let fixture = installed_process_fixture("installed-child-fd4")
  let process = installed_process_prepare(
      fixture,
      fixture.descriptor,
      32L * page_bytes_ffi(),
    )
    .original_process()
    .unwrap()
  let frame = process.frame.unwrap()
  let arguments = [
    "-c", "test -f /dev/fd/4 && test -r /dev/fd/4 && test -w /dev/fd/4 && test \"$LANG\" = C",
  ]
  let environment = [("LANG", "C")]
  fixture.host
  .prepare_process_child(
    fixture.domain,
    process,
    "/bin/sh",
    arguments,
    environment,
  )
  .unwrap()
  arguments[1] = "exit 9"
  environment[0] = ("LANG", "changed")
  fixture.host.spawn_prepared_process_child(fixture.domain, process).unwrap()
  assert_true(physical_equal(frame, process.frame.unwrap()))
  assert_eq(
    process.holder.unwrap().child().unwrap().wait(true).unwrap(),
    Some(@executor.Exited(0)),
  )
  assert_true(
    fixture.host.spawn_prepared_process_child(fixture.domain, process) is Err(_),
  )
  installed_child_stop_and_finish(fixture, process)
}

///|
test "installed child known failed spawn keeps its original descriptor snapshot for no-child cleanup and no relaunch" {
  let fixture = installed_process_fixture("installed-child-known-failure")
  let process = installed_process_prepare(
      fixture,
      fixture.descriptor,
      32L * page_bytes_ffi(),
    )
    .original_process()
    .unwrap()
  fixture.host
  .prepare_process_child(
    fixture.domain,
    process,
    fixture.path + "/absent",
    [],
    [],
  )
  .unwrap()
  assert_true(
    fixture.host.spawn_prepared_process_child(fixture.domain, process)
    is Err(@bootstrap.Process(@executor.SpawnFailed)),
  )
  assert_true(
    process.holder.unwrap().child() is Err(@executor.InvalidConfiguration),
  )
  assert_true(process.stop is None && fixture.domain.loan is Some(_))
  fixture.host.restrict_process_transport(fixture.domain, process).unwrap()
  fixture.host.return_process_transport(fixture.domain, process).unwrap()
  fixture.host.close_prepared_process(fixture.domain, process).unwrap()
  assert_true(process.closed && process.stop is None)
  assert_true(
    fixture.host.spawn_prepared_process_child(fixture.domain, process) is Err(_),
  )
  installed_process_finish(fixture)
}

///|
test "installed child foreign and duplicate environment refusals preserve the same original prepared owner" {
  let fixture = installed_process_fixture("installed-child-preflight")
  let process = installed_process_prepare(
      fixture,
      fixture.descriptor,
      32L * page_bytes_ffi(),
    )
    .original_process()
    .unwrap()
  let descriptor = fixture.host
    .process_backing_descriptor(fixture.domain, process)
    .unwrap()
  let other = prepared_host(64L * page_bytes_ffi())
  assert_true(
    other.prepare_process_child(fixture.domain, process, "/bin/sh", [], [])
    is Err(@bootstrap.Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal))),
  )
  assert_true(
    fixture.host.prepare_process_child(fixture.domain, process, "/bin/sh", [], [
      ("LANG", "C"),
      ("LANG", "other"),
    ])
    is Err(@bootstrap.Process(@executor.InvalidConfiguration)),
  )
  assert_false(process.closing || process.closed)
  assert_eq(
    fixture.host.process_backing_descriptor(fixture.domain, process),
    Ok(descriptor),
  )
  process.holder.unwrap().require_prepared().unwrap()
  fixture.host.restrict_process_transport(fixture.domain, process).unwrap()
  fixture.host.return_process_transport(fixture.domain, process).unwrap()
  fixture.host.close_prepared_process(fixture.domain, process).unwrap()
  installed_process_finish(fixture)
  other.try_close().unwrap()
}
