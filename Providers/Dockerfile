FROM node:22-bookworm-slim AS codex
RUN npm install --global @openai/codex@0.172.0
WORKDIR /studio

FROM node:22-bookworm-slim AS claude
RUN npm install --global @anthropic-ai/claude-code@2.1.332
WORKDIR /studio

FROM python:3.12-slim-bookworm AS antigravity
RUN useradd --uid 1000 --create-home studio && pip install --no-cache-dir google-antigravity==0.1.24
COPY antigravity.py /opt/studio/agent.py
WORKDIR /studio
