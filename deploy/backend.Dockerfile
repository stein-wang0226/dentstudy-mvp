FROM python:3.12-slim

WORKDIR /app
COPY backend ./backend
COPY mobile/assets/all_questions.json ./mobile/assets/all_questions.json

ENV PYTHONUNBUFFERED=1 \
    DENTSTUDY_DB=/var/data/dentstudy.sqlite3 \
    DENTSTUDY_BANK=/app/mobile/assets/all_questions.json

RUN mkdir -p /var/data
EXPOSE 10000
CMD ["sh", "-c", "python backend/server.py --host 0.0.0.0 --port ${PORT:-10000}"]
