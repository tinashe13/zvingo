FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
# gcc and python3-dev might be needed for some python packages like hiredis if no wheels are available
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    python3-dev \
    && rm -rf /var/lib/apt/lists/*

# Build-time memory guards. Poetry defaults to min(cpu_count + 4, 10) parallel
# installer workers, each unpacking a wheel in memory at once; on a small
# droplet that is enough to get the build OOM-killed ("signal: killed") during
# `poetry install`. One worker is slower but has a much lower peak.
ENV POETRY_INSTALLER_MAX_WORKERS=1 \r
    POETRY_NO_INTERACTION=1 \r
    PIP_NO_CACHE_DIR=1 \r
    PIP_DISABLE_PIP_VERSION_CHECK=1 \r
    PYTHONDONTWRITEBYTECODE=1

# Install poetry
RUN pip install --no-cache-dir poetry

# Copy dependency files
COPY pyproject.toml poetry.lock* ./

# Configure poetry to not create a virtualenv (since we are in docker)
RUN poetry config virtualenvs.create false

# Install runtime dependencies only (no dev group, no project package)
RUN poetry install --no-interaction --no-ansi --no-root --only main

# Copy application code
COPY . .

# Run as a non-root user. The app writes uploaded images to static/uploads,
# so pre-create it with the right ownership.
RUN useradd --create-home --uid 1000 appuser \
    && mkdir -p /app/static/uploads \
    && chown -R appuser:appuser /app
USER appuser

# Expose ports
# 8000: FastAPI
# 9090: UDP BinProto
# 9091: TCP BinProto
EXPOSE 8000 9090 9091

# Run the application (dev docker-compose overrides this command).
# NOTE: intentionally a single worker — the app's lifespan starts BinProto
# UDP/TCP servers on fixed ports and a dispatch retry loop; multiple workers
# would try to bind the same ports. Scale horizontally with more containers
# behind nginx instead. --proxy-headers trusts X-Forwarded-* from the proxy.
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers"]
