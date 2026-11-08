# Native publication Store

The Store owns its original filesystem Root, SQLite journal, lock, durable
capacity and active I/O children. Its checked close waits for those original
children; a path, process exit or missing file is not a cleanup acknowledgement.

Captured Content uses that same Store through `CapturedContentCustody`. The
trusted Source caller supplies the original Common candidate and its original
holding CID, retains the returned child before I/O, and funds its constructor,
metadata, writer, verification window and failed-child overlap under the same
parent. Store disk/object quota is separate from that live backing.

The construction inventory may borrow that same candidate to bound its closed
canonical record. Its tag, holding CID, state, generation and escaped original
wire determine the writer/parser geometry. Raw database readback retains the
full configured Store bound, including malformed or failed-state bytes. A body
too long to be the canonical original refuses before parser/index construction;
the remaining records still pass the original exact canonical equality check.
This changes neither the stored format nor the Store policy ceiling. Omitting
the candidate retains the original full-bound inventory.

`persist` checks the exact byte count and digest before acquisition, reserves one
object even for empty content, and retains the actual writer and sealed file
generation. A successful journal CAS establishes the immutable terminal once;
ambiguous failure cleanup and saved restoration read the exact stored terminal.
Neither path rewrites the Source, creates another holding or retries a request.
`confirm` verifies the original retained bytes through an accounted read window.
The original Source/Run current check and Common ReferenceIssuer remain required
before the candidate becomes an admitted ContentRef.

Retirement closes original I/O first. It cancels only an uncommitted writer it
actually acquired, retains committed bytes and quota, and never infers physical
cleanup from absence. Store recovery retains sealed Content and refuses unresolved
pending Content whose original cleanup owner is unavailable. Closing Content I/O
preserves confirmed immutable DATA while the Store remains available; it grants
no new Source, Run or reference authority.

After confirmed I/O cleanup, `CapturedContentCustody.retained_inventory` counts
the same child, generation, private names, original record Bytes and the Store
Map's actual retained bucket/entry backing. Removing an entry does not release
its bucket allocation. This callback-free DATA permits the same Source owner to
retain the confirmed reference while returning finished construction workspace;
it is neither a physical acknowledgement nor a replacement current check.
