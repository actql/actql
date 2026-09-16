// Deliberately invalid peer used only by process-channel boundary tests.
import { Socket } from 'node:net';
import { createProcessFrameReader, encodeProcessFrame } from './process-frames.mjs';
import {encodeProcessUsage, emptyProcessUsage} from './process-accounting.mjs';

const frames = { maxBytes: 4096, maxNodes: 100, maxDepth: 10 };
const socket = new Socket({ fd: 3, readable: true, writable: true });
const reader = createProcessFrameReader(frames, message => {
  if (message.kind === 'stop') { socket.end(); return; }
  const reply = { ...message, kind: message.kind === 'hello' ? 'ready' : 'reply', body: null };
  if (message.kind === 'execute') {
    if (message.body.corrupt.startsWith('usage-')) {
      const usage = {...message, kind: 'usage', body: {terminal: false, usage: encodeProcessUsage(emptyProcessUsage())}};
      switch (message.body.corrupt) {
        case 'usage-run': usage.run = 'another-run'; break;
        case 'usage-session': usage.session = 'another-session'; break;
        case 'usage-sequence': usage.sequence -= 1; break;
        case 'usage-terminal': usage.body.terminal = true; break;
      }
      socket.write(encodeProcessFrame(usage, frames));
      if (message.body.corrupt === 'usage-duplicate') socket.write(encodeProcessFrame(usage, frames));
    }
    switch (message.body.corrupt) {
      case 'run': reply.run = 'another-run'; break;
      case 'session': reply.session = 'another-session'; break;
      case 'sequence': reply.sequence -= 1; break;
      case 'extra': reply.extra = true; break;
    }
  }
  socket.write(encodeProcessFrame(reply, frames));
});
socket.on('data', chunk => reader.feed(chunk));
socket.on('error', () => socket.destroy());
