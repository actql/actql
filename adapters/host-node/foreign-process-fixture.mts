// Deliberately invalid peer used only by process-channel boundary tests.
import { Socket } from 'node:net';
import { createProcessFrameReader, encodeProcessFrame } from './process-frames.mjs';
import {encodeProcessUsage, emptyProcessUsage} from './process-accounting.mjs';
import type {ProcessFrameValue, UncheckedProcessEnvelope} from './process-frames.mjs';

type FixtureEnvelope = Pick<UncheckedProcessEnvelope, 'session' | 'run' | 'sequence' | 'kind'> &
  {protocol: ProcessFrameValue; body: {corrupt: string} | null};

const frames = { maxBytes: 4096, maxNodes: 100, maxDepth: 10 };
const socket = new Socket({ fd: 3, readable: true, writable: true });
const reader = createProcessFrameReader(frames, ((message: FixtureEnvelope) => {
  if (message.kind === 'stop') { socket.end(); return; }
  const reply = { ...message, kind: message.kind === 'hello' ? 'ready' : 'reply', body: null };
  if (message.kind === 'execute') {
    if (message.body!.corrupt.startsWith('usage-')) {
      const usage = {...message, kind: 'usage', body: {terminal: false, usage: encodeProcessUsage(emptyProcessUsage())}};
      switch (message.body!.corrupt) {
        case 'usage-run': usage.run = 'another-run'; break;
        case 'usage-session': usage.session = 'another-session'; break;
        case 'usage-sequence': usage.sequence -= 1; break;
        case 'usage-terminal': usage.body.terminal = true; break;
      }
      socket.write(encodeProcessFrame(usage, frames));
      if (message.body!.corrupt === 'usage-duplicate') socket.write(encodeProcessFrame(usage, frames));
    }
    switch (message.body!.corrupt) {
      case 'run': reply.run = 'another-run'; break;
      case 'session': reply.session = 'another-session'; break;
      case 'sequence': reply.sequence -= 1; break;
      case 'extra': (reply as typeof reply & {extra?: boolean}).extra = true; break;
    }
  }
  socket.write(encodeProcessFrame(reply, frames));
}) as Parameters<typeof createProcessFrameReader>[1]);
socket.on('data', (chunk: Buffer) => reader.feed(chunk));
socket.on('error', () => socket.destroy());
