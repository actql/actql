///|
// The same real malformed fixture distinguishes an observer refusal from an
// actual database-open attempt. No replacement Library or I/O mock is used.
test "Source current entry refusal precedes real database open and retains original cleanup" {
  guard resident_compute_prerequisites() is Some((library_path, root_path)) else {
    fail("actual Native DuckDB fixture required")
  }
  let library = @duckdb.load_library(library_path).unwrap()
  let path = root_path + "/source-entry-invalid.duckdb"
  let mut denied_entries = 0
  let denied = @resident.open_resident_source_compute(
    resident_compute_prepared(),
    resident_compute_configuration(library, path),
    "source-entry-denied",
    observe=event => {
      if event is @resident.AcquisitionEntered {
        denied_entries += 1
      }
      false
    },
  )
  guard denied
    is Err(
      (
        @resident.ObservationUnrecorded(@resident.AcquisitionEntered),
        denied_cleanup,
      )
    ) else {
    fail("current refusal must happen before the malformed database is opened")
  }
  assert_eq(denied_entries, 1)
  assert_true(
    @output.retry_native_remote_standard_input_failure_cleanup(denied_cleanup),
  )
  let mut entered = 0
  let failed_open = @resident.open_resident_source_compute(
    resident_compute_prepared(),
    resident_compute_configuration(library, path),
    "source-entry-allowed-invalid",
    observe=event => {
      if event is @resident.AcquisitionEntered {
        entered += 1
      }
      true
    },
  )
  guard failed_open is Err((@resident.Acquisition(Database(_)), open_cleanup)) else {
    fail("the same actual malformed database must refuse physical open")
  }
  assert_eq(entered, 1)
  assert_true(
    @output.retry_native_remote_standard_input_failure_cleanup(open_cleanup),
  )
}
