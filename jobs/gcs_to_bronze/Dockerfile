FROM python:3.13-slim@sha256:e48f59cdba69a3cbd9ed2cf0f348d90d45a8d350d98134cf1070bc106ee9ed90

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

COPY requirements.lock ./
RUN printf 'pip==26.3 --hash=sha256:f3b60b20ffaadd4415ed7957212a38ac63fa4c5fa375bd0f4a797777940fad13 --hash=sha256:6c36ae7da8695be67e3cd9f7d87919667ced53f57ce2ede75d89b5912ed2bc4c\n' > /tmp/pip.lock && \
    pip install --no-cache-dir --require-hashes --no-deps -r /tmp/pip.lock && \
    rm -f /tmp/pip.lock && \
    pip install --no-cache-dir --require-hashes --no-deps -r requirements.lock

COPY pyproject.toml loader.py ./

USER 65532:65532

ENTRYPOINT ["python", "-m", "loader"]
