FROM node:24-bookworm-slim
WORKDIR /app/server
COPY server/package.json ./
COPY server/src ./src
COPY server/migrations ./migrations
ENV HOST=0.0.0.0 PORT=18082 DB_PATH=/data/bustimer.sqlite WEB_ROOT=/app/web BASE_PATH=/bustimer
EXPOSE 18082
CMD ["node", "src/server.js"]
