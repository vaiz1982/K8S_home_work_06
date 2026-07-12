FROM python:3.12-slim AS base

WORKDIR /app

# Install deps first for better layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# App code
COPY app.py .

# Run as non-root
RUN useradd --create-home --shell /usr/sbin/nologin appuser
USER appuser

ENV PORT=8080
EXPOSE 8080

# gunicorn is already in requirements.txt
CMD ["gunicorn", "--bind", "0.0.0.0:8080", "--workers", "2", "app:app"]
