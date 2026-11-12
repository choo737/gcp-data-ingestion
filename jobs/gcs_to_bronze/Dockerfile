FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY pyproject.toml loader.py ./

RUN pip install --no-cache-dir --upgrade pip==25.0.1 && \
    pip install --no-cache-dir .

USER 65532:65532

ENTRYPOINT ["python", "-m", "loader"]
