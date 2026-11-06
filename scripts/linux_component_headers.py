"""Original Linux system headers only; no compile, load or runtime admission."""
import hashlib
import os
from pathlib import Path
import stat

SYSTEM_INCLUDE = Path('/usr/include')
# This separate kernel UAPI layout must be selected by the caller. It never
# becomes a fallback after the default /usr/include boundary refuses an alias.
ADDITIONAL_ROOTS = frozenset((Path('/usr/lib/linux/uapi'),))
MAXIMUM_HEADER_BYTES = 16 * 1024 * 1024


def _stamp(value):
    return {key: str(getattr(value, key)) for key in
            ('st_dev', 'st_ino', 'st_mode', 'st_size', 'st_mtime_ns', 'st_ctime_ns')}


def _root(path):
    if (not path.is_absolute() or '..' in path.parts or path.resolve(strict=True) != path
            or not stat.S_ISDIR(path.lstat().st_mode)):
        raise ValueError('Linux system-header root must be an original canonical directory')
    return _stamp(path.lstat())


class LinuxSystemHeaders:
    def __init__(self, additional_roots=()):
        selected = tuple(Path(path) for path in additional_roots)
        if len(set(selected)) != len(selected) or any(path not in ADDITIONAL_ROOTS for path in selected):
            raise ValueError('Unknown or duplicate explicit Linux system-header root')
        self.roots = {str(path): _root(path) for path in (SYSTEM_INCLUDE, *selected)}
        self.aliases = {}
        self._originals = {}

    def contains(self, path):
        # Additional roots qualify destinations only, not arbitrary source
        # aliases or a replacement compiler include search path.
        return path.is_absolute() and path.is_relative_to(SYSTEM_INCLUDE)

    def _resolve(self, path):
        links, current, pending = {}, Path('/'), list(path.parts[1:])
        roots = tuple(Path(root) for root in self.roots)
        while pending:
            part = pending.pop(0)
            candidate = current.parent if part == '..' else current / part
            # Canonical ancestors are needed by the original ../ prefixes.
            # Resolve each reached link BEFORE processing a later '..'; lexical
            # normalization can otherwise hide a link into an unselected root.
            if not any(candidate.is_relative_to(root) or root.is_relative_to(candidate) for root in roots):
                raise ValueError('Linux system-header alias escapes selected roots')
            observed = candidate.lstat()
            if stat.S_ISLNK(observed.st_mode):
                if len(links) >= 40 or str(candidate) in links:
                    raise ValueError('Cyclic or excessive Linux system-header alias chain')
                target = os.readlink(candidate)
                links[str(candidate)] = {'target': target, **_stamp(observed)}
                # Keep empty and '.' components: a trailing slash or '/.'
                # requires a directory in kernel traversal, even at the end.
                if target.startswith('/'):
                    current = Path('/')
                    pending = target.split('/')[1:] + pending
                else:
                    pending = target.split('/') + pending
            else:
                if (pending or part in ('', '.')) and not stat.S_ISDIR(observed.st_mode):
                    raise ValueError('Linux system-header traversal crosses a non-directory')
                current = candidate
        if not any(current.is_relative_to(root) for root in roots):
            raise ValueError('Linux system-header alias escapes selected roots')
        return current, links

    def _observe(self, path):
        if not self.contains(path) or '..' in path.parts:
            raise ValueError('Unselected Linux system-header spelling')
        resolved, links = self._resolve(path)
        with os.fdopen(os.open(resolved, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as source:
            before = os.fstat(source.fileno())
            if not stat.S_ISREG(before.st_mode) or not 0 < before.st_size <= MAXIMUM_HEADER_BYTES:
                raise ValueError('Invalid original Linux system header')
            checksum = hashlib.sha256()
            remaining = before.st_size
            while remaining:
                block = source.read(min(65536, remaining))
                if not block:
                    raise ValueError('Incomplete original Linux system header')
                checksum.update(block)
                remaining -= len(block)
            if source.read(1) or _stamp(os.fstat(source.fileno())) != _stamp(before):
                raise ValueError('Original Linux system header changed')
        if self._resolve(path) != (resolved, links) or _stamp(resolved.lstat()) != _stamp(before):
            raise ValueError('Original Linux system-header alias changed')
        return {'resolved_path': str(resolved), 'bytes': before.st_size, 'sha256': checksum.hexdigest(),
                'target_identity': _stamp(before), 'links': links}

    def capture(self, path):
        observed = self._observe(path)
        self._originals[str(path)] = observed
        if observed['resolved_path'] != str(path):
            self.aliases[str(path)] = observed
        return {key: observed[key] for key in ('resolved_path', 'bytes', 'sha256')}

    def verify(self):
        if any(_root(Path(path)) != expected for path, expected in self.roots.items()):
            raise ValueError('Selected Linux system-header root changed')
        for name, expected in self._originals.items():
            if self._observe(Path(name)) != expected:
                raise ValueError('Original Linux system header or alias changed')

    def receipt(self):
        self.verify()
        return {'roots': self.roots, 'aliases': self.aliases}
