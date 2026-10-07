# Graph abbreviated edges: source-to-Program connection

## Contract and missing entry

The selected [GoogleSQL element-pattern clause](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/graph-patterns#element_pattern),
consulted on 2026-10-07, defines abbreviated outgoing, incoming and
any-direction edges without fillers. They correspond to full empty edges.
Its quantified-path clause admits edge quantification. This change connects
those spellings to the existing finite, homogeneous traversal profile; it
does not claim support for every quantified pattern or full GQL conformance.

At `3e50336de40c0fa5987987c7d6914c654343ddea` (parent #835 plus main
`e1f08d3d33da52d9e026daf03c0259cd0077c163`), `graph_edge` always required
`[` after the first dash. The lowerer and common checker already supported
all three directions with no edge label selection. No new executor, Graph
identity, compatibility route, resource allowance or owner is needed.

The parser now distinguishes a full filler from an abbreviated empty edge
before their shared direction and finite-bound processing. Full edge variables,
labels, predicates, node scopes and existing unsupported shapes retain their
current behavior. `--` remains a SQL line comment. Malformed dual arrows do
not become a successful edge.

## Independent controls and counterexamples

The complete machine control in `graph_abbreviated_edge_test.mbt` derives
only the authored direction and absence of `edge_types` from the independent
fixed-hop Program. It preserves both node predicates, ordinary nullable object
property access, Values, constructor, projection and Result declarations. Both
full and abbreviated spellings must equal this complete control and pass the
ordinary checker. Bounded comparisons preserve the same existing arguments.

The public fixture uses two parallel R edges 1→2, an incoming R edge 3→1,
an R self-loop 1→1, and an S edge 1→3. Starting at node 1 gives four outgoing,
two incoming, or five any-direction one-hop paths. Excluding S accidentally
or synthesizing two directional self-loop instances changes those counts.
The independent machine controls carry no implicit `edge_types` filter.

The reached-node nullable predicate yields two paths to node 3, and the
score predicate yields two paths to node 2. Empty selection retains the
declared number column. A mixed full/abbreviated two-hop WALK has four edge
sequences. Two differently keyed self-loops in distinct R/S definitions have
seven WALK, five TRAIL and one ACYCLIC paths at bounds 0..2. Expected rows,
columns, types and multiplicities are authored without product output.

The new corpus is registered in normal packed acceptance as well as the
focused `--graph-abbreviated-only` selection. Refusals cover malformed arrows,
fillers without brackets, open bounds, quantified terminal predicates,
foreign receivers and missing members. The existing public consumer checks
pre-admission refusal, no provider I/O, Result description, rows, column
order, hidden-column absence and same-request Run identity.

## Local evidence before distribution acceptance

The initial compiling regression run (`run-sEe6Kj`, `focused-test-MOhi5L`)
recorded six positive/lowering tests failing at the mandatory-bracket parser.
The seventh failure was an incorrect new test expectation that a SQL line
comment should be rejected; it was corrected to assert that the comment
introduces no edge. It is not a product defect. An earlier test authoring
compile failure (`run-fL37ct`) is also not execution evidence.

After the parser fix, the selected JS tests passed 15/15 (`run-Huk30w`,
`focused-test-9SbvCP`), including existing full direction forms and the
affected Values Run fixture. Targeted Node checks passed 11/11 (`run-a6Lq2o`,
`focused-test-KhuXwx`). Read-only compilation-manifest freshness and
`git diff --check` passed. These are worktree checks of the staged source,
not CI or a fresh packed runtime claim.

## Canonical identity impact

The grammar bytes and normative query rules change. Existing generation
updates the grammar manifest and MoonBit pins. The new grammar manifest is
`sha256:e855c6be158d29cc88c3e1e7fd01eb1940cbc6a1301c49414fbe024c20a4bea3`.
An independently assembled canonical Values Run preimage gives
`sha256:21982c4ae013552cb120f9e32e35c672b6c23092e8fa47323d4fabbe5ca00033`.
The ordinary Values Unit, proof, ResultPlan and Program bodies remain unchanged.
Historical full-edge grammar and Run vectors remain frozen with their original
pins; saved Runs are not relabeled.

Distribution acceptance must use normal prepack of five packages at a clean
fixed HEAD and record their SHA-256 manifest. Public Local and HTTPS results,
exact revision, receipt and CI status are recorded separately in the PR.
Full Core, Wasm/native execution, proof campaigns and the full packed corpus
have not been run for this unit. Parent #835 remains an explicit dependency
until its implementation reaches main.
