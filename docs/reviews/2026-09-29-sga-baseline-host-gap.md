# SGA baseline preparation findings

The accepted SGA surface has not been implemented. Its independent
reach/subgraph Program baseline passes source admission and structural OP
comparison, but does not yet pass the installed Local Host preparation path.
Do not count the expected result rows as executed evidence.

## Reproduction

Use an existing clean packed installation and a fresh workspace-local state
directory with Node 22:

```sh
ACTQL_LOCAL_STATE_DIR="$PWD/_build/sga-state" \
  node scripts/reproduce-sga-baseline.mjs /path/to/packed-installation
```

The script submits the committed JSON Program through installed @actql/node.
It does not parse new syntax or inject a provider. Expected schema and rows
are separately authored fixture data. The script exits nonzero on the observed
preparation failure; this is a diagnostic reproduction, not a passing gate.

## Observations

1. Explicit edge Result ordering by src/dst was rejected. Extending the
   authored order to src/dst/rel still yields `ClientProgramRejected`.
   A diagnostic call to the existing source build's preparation API identifies
   `LocalConstructionFailure.Source -> SourceFailure.SourceView ->
   Program -> Program -> LocalProgramIssue.Order -> ResultOrder ->
   UnresolvedOrder` at `stages[0].results.edges`.
2. The control variant `--inherited-order` removes only that Result's authored
   order. Installed preparation then returns `ClientProgramPreparationFailure`,
   surfaced as `SubmissionUnknown` by the existing Client rules. It does not
   reach Named Result reads. Do not retry with a new ID or claim a failed Run.
3. A source-build diagnostic using the stock check-environment fixture reaches
   a capacity-context refusal after the order issue is removed. That fixture
   is not the installed Host's composed environment; it does not establish the
   exact cause of the installed preparation failure.

Keep the explicit baseline and independent expectations. Do not remove an
edge Result, weaken semantics, add an implicit sort, or create a Frontend
execution fallback to obtain a passing test. The Compute/checker owner should
triage order evidence; the Host owner should triage the composed environment
and preparation failure. Recheck against their adopted changes before fixing
any shared file. These are existing Program-path observations, not regressions
introduced by a new SGA parser.

## Artifact scope

The installed artifacts are the previously verified projection package set
from source `fc5d0e469e167b919f0adce9d7b3a3e0e6f5aec2`. Their digests were
rechecked for this reproduction:

| Package | Tarball SHA-256 |
| --- | --- |
| client-wire | 8e09005f4aac5063c1f6f8e4680dbb778a00e5c098126a85283e1f07685a76e5 |
| sdk | 1e4e83612b9c965388795f066be8cf24b0358feb46bd2335c8d98c36e83ed515 |
| local-node | 3085a41b3803d62246c28cc0231d30eff009ddd1fb2fca85ab17f9748f173200 |
| node | c72364973dd1ed42faea32425632b314de037c9b92035c9f5ec35b875914f225 |

This is not a test of latest main, new provider code, HTTP execution, or public
raw SGA text routing. Structural baseline source started at `4b589c4d9`, with
the explicit edge order subsequently extended to include rel. All runtime
findings above precede Compute. Public SDK/CLI routing remains the prerequisite
for implementing the new surface.
