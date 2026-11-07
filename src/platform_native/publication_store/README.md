# Native publication Store

The Store owns its original filesystem Root, SQLite journal, lock, durable
capacity and active I/O children. Its checked close waits for those original
children; a path, process exit or missing file is not a cleanup acknowledgement.

Captured Content uses that same Store through `CapturedContentCustody`. The
trusted Source caller supplies the original Common candidate and its original
holding CID, retains the returned child before I/O, and funds its constructor,
metadata, writer, verification window and failed-child overlap under the same
parent. Store disk/object quota is separate from that live backing.

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
