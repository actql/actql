class ClientError(Exception):
    """A public transport or Client-contract failure, never a retry permission."""

    def __init__(self, code: str, **facts):
        super().__init__(code)
        self.code = code
        self.cleanup_client = None
        self.submission_ref = None
        self.request_id = None
        self.attempt_ref = None
        self.cancel_ref = None
        self.outcome = None
        self.signed = None
        self.attempt_id = None
        self.rows_yielded = None
        self.original_error = None
        self.cleanup_error = None
        self.validation_error = None
        self.execution = None
        self.observation = None
        for key, value in facts.items():
            setattr(self, key, value)


class RequestConflict(ClientError):
    """The same scoped request name already binds different original intent."""

    def __init__(self, **facts):
        super().__init__('RequestConflict', **facts)


def _retain_context_cleanup(failure, cleanup, client):
    """Keep actual exception objects and cleanup-only handles, never outcomes."""
    for error in (cleanup, failure):
        if isinstance(error, ClientError) and error.cleanup_client is None:
            error.cleanup_client = client
    if cleanup is failure:
        return
    previous = getattr(failure, 'cleanup_error', None)
    if previous is not None:
        # Preserve both existing chains. An overlapping suffix is already
        # retained through the earlier head; no error is cloned or formatted.
        old, cursor = set(), previous
        while isinstance(cursor, BaseException) and id(cursor) not in old:
            if cursor is cleanup:
                return
            old.add(id(cursor))
            cursor = getattr(cursor, 'cleanup_error', None)
        seen, cursor = {id(failure)}, cleanup
        while True:
            seen.add(id(cursor))
            following = getattr(cursor, 'cleanup_error', None)
            if (not isinstance(following, BaseException)
                    or id(following) in seen or id(following) in old):
                cursor.cleanup_error = previous
                break
            cursor = following
    failure.cleanup_error = cleanup
