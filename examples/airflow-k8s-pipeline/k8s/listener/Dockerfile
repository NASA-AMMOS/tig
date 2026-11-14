FROM python:3.11-slim

WORKDIR /app

# Install locked, hash-pinned dependencies from wheels only (regenerate with
# `pip-compile --generate-hashes --strip-extras requirements.in` on Python 3.11)
COPY requirements.txt /app/
RUN pip install --no-cache-dir --only-binary :all: --require-hashes -r requirements.txt

# Copy listener script
COPY listener.py /app/

# Run listener as an unprivileged user
RUN useradd --uid 1000 --user-group --no-create-home listener
USER 1000:1000

CMD ["python", "-u", "listener.py"]
