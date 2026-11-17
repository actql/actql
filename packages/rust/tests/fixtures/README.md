# Rust Core boundary inputs

`check-environment.json` is the independently authored source-free environment
also used by `scripts/fixtures/python_local_run_inputs.py`. It supplies the
existing source-free profile to the private Wasm preparation entry. The wire
reader requires the exact canonical JSON bytes, without a trailing newline;
the test does not trim or normalize application input to make it admissible.

These bytes are input data, not an expected value generated from Core output.
The Rust tests use the actual Core to prepare the authored AQL and test original
input/reader/cleanup custody. They do not execute Python or claim a public Run.
