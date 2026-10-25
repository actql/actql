// Serialize only prepared-object metadata transitions for one material CID.
// Payload writes and external custody remain with their original owners. A
// settled older operation cannot erase the queue of a later queued owner.
export function createPreparedCustodyQueue() {
  const tails = new Map();
  return (cid, transition) => {
    const previous = tails.get(cid) ?? Promise.resolve();
    const operation = previous.then(transition);
    const tail = operation.then(() => {}, () => {});
    tails.set(cid, tail);
    tail.then(() => { if (tails.get(cid) === tail) tails.delete(cid); });
    return operation;
  };
}
