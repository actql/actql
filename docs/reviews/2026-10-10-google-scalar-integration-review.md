# Google scalar integration review

The integration retains main's DATA, HAVING, PIVOT and UNPIVOT changes and
the submitted STARTS_WITH, ENDS_WITH and finite Number SIGN implementations.
Text affixes use the existing retained-root bounded comparison cursor;
they do not normalize Unicode or fall back to a one-shot host search.
Both arguments retain the existing eager expression-error semantics.
SIGN canonicalizes both zero signs to positive zero.

Current grammar and Values Run identity inputs were recomputed through their
independent normative preimage helpers. Past fixtures retain their frozen
complete dependency closures rather than borrowing installed current laws.
The two failed historical vectors in the first integration diagnostic were
fixed by restoring their old dependencies, not by changing expected CIDs.

The current grammar manifest CID is
`sha256:e70b946c81182b086c5ede1fb047eebe512699e7d71313986906d8d29acf8ab5`.
The current independently derived Values Run CID is
`sha256:8c894c1e9c88f1c67e3f4d4a8d922c9692307dd541d916dd0c375d5a39d600ce`.

## Executed scope

On the integration tree committed as
`0354d5050`:

- `run-mMSx1H`: 13/13 targeted JS affix/SIGN/lowering tests.
- `run-Z20HF1`: 95/95 Node contract, independent identity, registration and
  public-profile checks, plus five read-only generated/normative validators.
- `run-6rRVfh`: 3/3 actual Local Host scalar tests, 1/1 consuming Values Run
  reconstruction test, and affected relation execution Wasm/Native
  denied-warning compilation checks. The real Host cases include exact
  Unicode, declared nullable inputs and errors before dispatch.

The subsequent normal author merge `88b6b5719` changes only the two
historical-vector Node test files. It does not change the product or runtime
build inputs used above. `run-Dqu9il` then executes those two merged test
files: 14/14, no skipped cases, including the independent current SGA
grammar body and the frozen scalar-parent Run closure.

These results establish the selected implementation and integrated contract
boundaries. They are not a new clean-HEAD five-package distribution campaign,
authenticated HTTPS acceptance, full Core, Native runtime execution or live
Google service comparison. Hosted CI remains stopped by instruction.
