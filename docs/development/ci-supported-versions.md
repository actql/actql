# Lightweight supported-version acceptance

The Client compatibility job consumes the same run's canonical Client artifact
ID. It never rebuilds packages. Each matrix member installs into a new external
directory, compares installed files with the original tar inventory, and resolves
public imports from that directory. SDK acceptance uses an independent loopback
Host protocol fixture for connect/attach/read/close; it is not Core or ordinary
Host acceptance. Local acceptance uses the installed public Node package for
open/query/close with an independent one-row result.

| Normal consumer | Declared lower bound | Selected interpreters |
| --- | --- | --- |
| `@actql/sdk` and its `client-wire` dependency | Node `>=22` | `22.0.0`, `26.13.0` |
| `@actql/node`, Local and their canonical dependencies | Node `^22.16.0 || >=24.0.0` | `22.16.0`, `26.13.0` |
| `actql-sdk`, `actql`, `actql-local-runtime` | Python `>=3.11` | `3.11.0`, `3.15.2` |

The existing Python job builds its normal darwin-arm64 cohort once. The two
compatibility consumers each create a private venv, install the original three
wheel URLs under exact constraints, use the existing wheel/installed-payload
verifiers, and run the existing typed-refusal/healthy-query/close fixture. No
consumer build, source resolution, ABI override or platform substitution is
allowed. One version's failure does not suppress the other version. Node matrix
fail-fast is disabled; the existing Client aggregate rejects failure,
cancellation, missing results and unexpected skips.

Versions were checked on 2026-11-07 against the official
[Node release index](https://nodejs.org/dist/index.json) and
[Python release index](https://www.python.org/downloads/). Prerelease Node 27 and
Python 3.16 are excluded. Exact lower releases follow the package declarations,
not the CI toolchain's later patch. The official
[setup-python manifest](https://github.com/actions/python-versions/blob/main/versions-manifest.json)
has ordinary darwin-arm64 distributions for both selected Python versions.

This bounded matrix does not multiply Native, proof or mutation campaigns.
Existing formal tar fresh installs and cold source builds remain required.
No timing reduction or compatibility success is established by these workflow
or fixture controls alone; exact-candidate hosted consumers supply that evidence.

## Declaration audit outside this canonical cohort

The HTTP/AI SDK providers, Node OpenTelemetry package and Explorer declare Node
`>=22`, but their optional package artifacts are not produced by the canonical
five-tar Client producer. Their min/latest acceptance is not established by this
matrix. The Native CLI wrapper declares `>=22.22.0` and requires its separate
matching Native artifacts; the existing Native acceptance is unchanged. Packages
without an explicit engines declaration receive no invented lower bound.

Explorer currently declares Node `>=22` while depending on `@actql/node`, whose
range starts at `22.16.0`. That declaration/dependency discrepancy needs a
compatibility disposition. This change does not silently raise Explorer's floor,
skip a declared version or claim its acceptance from the SDK test.
