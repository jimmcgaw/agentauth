"""Reference SPIFFE workload — fetches and rotates an X.509 SVID.

This service is the canonical example of how every Python workload in this
platform integrates with SPIRE:

    * Identity is obtained exclusively via the Workload API (Unix Domain
      Socket exposed by the local SPIRE Agent). No SVID material is read
      from disk, env, or any ambient credential.
    * The ``spiffe`` SDK auto-rotates SVIDs in the background via a streaming
      gRPC connection. We never cache an SVID ourselves or check expiry by
      hand — both are anti-patterns called out in CLAUDE.md.
    * All output is structured JSON via ``structlog`` so the audit pipeline
      can ingest it directly. No ``print``.

The service does not (yet) perform any outbound calls. Once Phase 3 lands
the Envoy PEP, this same identity will front mTLS connections to other
services. For now its job is simply to prove that the identity layer works
end-to-end from inside a Docker workload.
"""

from __future__ import annotations

import logging
import signal
import sys
import threading
from datetime import datetime, timezone
from types import FrameType
from typing import Final, Optional

import structlog
from cryptography.x509 import Certificate
from spiffe import WorkloadApiClient, X509Svid
from spiffe.workloadapi.x509_context import X509Context

LOGGER_NAME: Final[str] = "test-agent"

# Shutdown coordination: the main thread blocks on this Event while the
# WorkloadApiClient streams SVID updates on a background thread.
_shutdown = threading.Event()


def _configure_logging() -> structlog.stdlib.BoundLogger:
    """Configure stdlib + structlog for JSON output to stdout.

    Per CLAUDE.md, all services emit structured JSON logs and never use
    ``print``. We log SPIFFE IDs (URI strings) but never SVID cert/key bytes.
    """
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=logging.INFO,
    )
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            structlog.processors.dict_tracebacks,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )
    return structlog.get_logger(LOGGER_NAME)


log = _configure_logging()


def _leaf_not_after(leaf: Certificate) -> datetime:
    """Return the leaf's expiration as a tz-aware UTC datetime.

    cryptography>=42 introduced ``not_valid_after_utc``; older builds only
    have the deprecated naive ``not_valid_after``. The ``spiffe`` package
    pins cryptography>=46 so the modern attribute is the expected path —
    the fallback exists purely as belt-and-suspenders defensive code.
    """
    try:
        return leaf.not_valid_after_utc
    except AttributeError:
        return leaf.not_valid_after.replace(tzinfo=timezone.utc)


def _seconds_until(when: datetime) -> int:
    return int((when - datetime.now(timezone.utc)).total_seconds())


def _log_svid(event: str, svid: X509Svid) -> None:
    """Emit a structured record describing an SVID.

    We log the SPIFFE ID, chain depth, and expiry — never the certificate
    bytes or the private key. Per CLAUDE.md: "No secret material in logs."
    """
    leaf = svid.leaf
    not_after = _leaf_not_after(leaf)
    log.info(
        event,
        spiffe_id=str(svid.spiffe_id),
        chain_length=len(svid.cert_chain),
        not_after=not_after.isoformat(),
        ttl_seconds=_seconds_until(not_after),
    )


def _on_x509_context_update(ctx: X509Context) -> None:
    _log_svid("svid_rotated", ctx.default_svid)


def _on_x509_context_error(error: Exception) -> None:
    # Stream errors are not necessarily fatal — the SDK retries internally
    # under the default RetryPolicy. We surface them at WARN so operators
    # see transient Workload API outages without paging.
    log.warning(
        "svid_watch_error",
        error=str(error),
        error_type=type(error).__name__,
    )


def _install_signal_handlers() -> None:
    def _handle(signum: int, _frame: Optional[FrameType]) -> None:
        log.info("signal_received", signum=signum)
        _shutdown.set()

    signal.signal(signal.SIGINT, _handle)
    signal.signal(signal.SIGTERM, _handle)


def main() -> int:
    """Entry point. Runs until SIGINT/SIGTERM."""
    _install_signal_handlers()

    # `WorkloadApiClient()` reads SPIFFE_ENDPOINT_SOCKET from the env. We
    # rely on the Compose service definition to set it; if it's missing the
    # SDK raises ArgumentError which we let propagate as a hard fail (this
    # is correct fail-closed behavior — a workload with no path to the
    # Workload API has no identity and must not start).
    with WorkloadApiClient() as client:
        endpoint = client.get_spiffe_endpoint_socket()
        log.info("starting", workload_api_socket=endpoint)

        # Synchronous fetch first. This surfaces config / attestation errors
        # immediately at startup rather than waiting for the streaming
        # connection to fail later. Per CLAUDE.md, we do not store this
        # SVID anywhere — the streaming watcher below is the source of
        # truth from here on out.
        initial = client.fetch_x509_svid()
        _log_svid("svid_initial", initial)

        cancel = client.stream_x509_contexts(
            on_success=_on_x509_context_update,
            on_error=_on_x509_context_error,
        )
        try:
            while not _shutdown.is_set():
                _shutdown.wait(timeout=60.0)
        finally:
            log.info("shutting_down")
            cancel.cancel()

    return 0


if __name__ == "__main__":
    sys.exit(main())
