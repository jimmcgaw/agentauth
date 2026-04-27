# test-agent — minimal Python workload that fetches its X.509 SVID from
# the SPIRE Workload API.
#
# The container runs as UID 1000 to match the `unix:uid:1000` selector on
# the registration entry created by scripts/register-test-agent.sh. The
# Workload API socket is mounted in via Docker Compose; this image carries
# no SVID material and writes none.

FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1

# Non-root user with a fixed UID/GID so the unix workload attestor can
# pin identity to it. Keep the GID == UID for symmetry; both are
# referenced from the unix:uid selector.
RUN groupadd --system --gid 1000 testagent \
 && useradd  --system --uid 1000 --gid 1000 --no-create-home --shell /sbin/nologin testagent

WORKDIR /app

COPY requirements.txt /app/requirements.txt
RUN pip install --requirement /app/requirements.txt

COPY main.py /app/main.py

USER 1000:1000

ENTRYPOINT ["python", "/app/main.py"]
