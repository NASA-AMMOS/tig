FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir pika requests

# Copy listener script
COPY listener.py /app/

# Run listener
CMD ["python", "-u", "listener.py"]
