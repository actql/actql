// A single writer owns its staging file, reservation, and any prepared
// custody until cleanup is confirmed. The Store remains the sole capacity
// authority; the reservation passed here is a one-shot Store capability.
import {constants} from 'node:fs';
import {createHash, randomUUID} from 'node:crypto';
import {resolve} from 'node:path';

class ObjectWriterOwner {
  constructor(maxBytes, trackCustody, reservation, operations) {
    this.maxBytes = maxBytes;
    this.trackCustody = trackCustody;
    this.reservation = reservation;
    this.operations = operations;
    this.temporary = resolve(
      operations.stagingDirectory, `object-${randomUUID()}`,
    );
    this.hash = createHash('sha256');
    this.bytes = 0;
    this.acceptedBytes = 0;
    this.handle = undefined;
    this.finished = false;
    this.cleanupPending = false;
    this.custody = undefined;
    this.busy = Promise.resolve();
    this.ready = this.start();
  }

  async start() {
    try {
      this.handle = await this.operations.open(
        this.temporary,
        constants.O_CREAT | constants.O_EXCL | constants.O_WRONLY,
        0o600,
      );
    } catch (error) {
      this.finished = true;
      this.reservation.release();
      throw error;
    }
  }

  queue(operation) {
    const result = this.busy.then(operation);
    this.busy = result.catch(() => {});
    return result;
  }

  async cleanupTemporary() {
    if (this.handle) {
      await this.handle.close();
      this.handle = undefined;
    }
    try { await this.operations.unlink(this.temporary); }
    catch (error) { if (error?.code !== 'ENOENT') throw error; }
    await this.operations.syncDirectory(this.operations.stagingDirectory);
  }

  async cleanupAndRelease() {
    try {
      await this.cleanupTemporary();
      this.cleanupPending = false;
      this.reservation.release();
    } catch (error) {
      this.cleanupPending = true;
      throw error;
    }
  }

  append(frame) {
    let length;
    if (Buffer.isBuffer(frame) || frame instanceof Uint8Array) {
      length = frame.byteLength;
    } else if (typeof frame === 'string') {
      length = Buffer.byteLength(frame, 'utf8');
    } else {
      return this.queue(async () => this.operations.fail(
        'PublicationObjectLimit',
      ));
    }
    if (this.finished || length > this.maxBytes - this.acceptedBytes) {
      return this.queue(async () => {
        if (this.finished) {
          this.operations.fail('PublicationObjectWriterClosed');
        }
        this.operations.fail('PublicationObjectLimit');
      });
    }
    // Snapshot caller-owned mutable input only after its exact size is
    // known to fit. No rejected frame can force an unbounded copy.
    const buffer = Buffer.isBuffer(frame) ? Buffer.from(frame) :
      frame instanceof Uint8Array ? Buffer.from(frame) :
        Buffer.from(frame, 'utf8');
    this.acceptedBytes += length;
    return this.queue(async () => {
      await this.ready;
      if (this.finished) {
        this.operations.fail('PublicationObjectWriterClosed');
      }
      try {
        let offset = 0;
        while (offset < buffer.byteLength) {
          const result = await this.handle.write(
            buffer, offset, buffer.byteLength - offset, this.bytes + offset,
          );
          if (result.bytesWritten === 0) {
            this.operations.fail('IncompletePublicationWrite');
          }
          offset += result.bytesWritten;
        }
        this.hash.update(buffer);
        this.bytes += buffer.byteLength;
      } catch (error) {
        this.finished = true;
        throw error;
      }
    });
  }

  seal(expectedCid) {
    return this.queue(async () => {
      await this.ready;
      if (this.finished) {
        this.operations.fail('PublicationObjectWriterClosed');
      }
      this.finished = true;
      let installed = false;
      let result;
      let failed = false;
      let primaryFailure;
      try {
        await this.handle.sync();
        const state = await this.handle.stat();
        if (!state.isFile() || state.size !== this.bytes) {
          this.operations.fail('IncompletePublicationWrite');
        }
        await this.handle.close();
        this.handle = undefined;
        const cid = `sha256:${this.hash.digest('hex')}`;
        if (expectedCid !== undefined && expectedCid !== cid) {
          this.operations.fail('PublicationObjectIdentityMismatch');
        }
        if (this.operations.isReclaiming(cid)) {
          this.operations.fail('PublicationObjectReclamationPending');
        }
        if (this.trackCustody) {
          this.custody = await this.operations.registerCustody(
            cid, this.bytes, state,
          );
        }
        const finalPath = this.operations.objectPath(cid);
        try {
          await this.operations.link(this.temporary, finalPath);
          installed = true;
          this.operations.accountInstalled(this.bytes, this.custody);
          await this.operations.syncDirectory(this.operations.objectsDirectory);
        } catch (error) {
          if (error?.code !== 'EEXIST') throw error;
          const existing = await this.operations.verifyObject(cid);
          if (existing.bytes !== this.bytes) {
            this.operations.fail('PublicationObjectIdentityMismatch');
          }
        }
        result = this.custody === undefined
          ? Object.freeze({cid, bytes: this.bytes, created: installed})
          : Object.freeze({
            cid, bytes: this.bytes, created: installed, custody: this.custody,
          });
      } catch (error) {
        failed = true;
        primaryFailure = error;
      }
      if (failed) {
        try { await this.cleanupAndRelease(); }
        catch { this.cleanupPending = true; }
        if (!this.reservation.held && this.custody !== undefined) {
          try {
            if (await this.operations.reclaimCustody(this.custody)) {
              this.custody = undefined;
            } else {
              this.cleanupPending = true;
            }
          } catch { this.cleanupPending = true; }
        }
        throw primaryFailure;
      }
      await this.cleanupAndRelease();
      this.custody = undefined;
      return result;
    });
  }

  cancel() {
    return this.queue(async () => {
      try { await this.ready; }
      catch (error) {
        if (!this.reservation.held) return false;
        throw error;
      }
      if (this.finished && !this.reservation.held &&
          this.custody === undefined) {
        return false;
      }
      this.finished = true;
      if (this.reservation.held) await this.cleanupAndRelease();
      if (this.custody !== undefined) {
        if (await this.operations.reclaimCustody(this.custody)) {
          this.custody = undefined;
          this.cleanupPending = false;
        } else {
          this.cleanupPending = true;
          this.operations.fail('PublicationPreparedCustodyPending');
        }
      }
      return true;
    });
  }

  status() {
    return Object.freeze({
      maxBytes: this.maxBytes,
      bytes: this.bytes,
      finished: this.finished,
      cleanupPending: this.cleanupPending,
      reservationHeld: this.reservation.held,
      custodyPending: this.custody !== undefined,
    });
  }
}

// Only the existing Store writer facade escapes this module. The owner itself
// remains reachable through that facade until cleanup has settled.
export function createObjectWriterOwner(
  maxBytes, trackCustody, reservation, operations,
) {
  const owner = new ObjectWriterOwner(
    maxBytes, trackCustody, reservation, operations,
  );
  return Object.freeze({
    append: frame => owner.append(frame),
    seal: expectedCid => owner.seal(expectedCid),
    cancel: () => owner.cancel(),
    status: () => owner.status(),
  });
}
