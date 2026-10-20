FROM node:24-bookworm-slim
WORKDIR /app/server
COPY server/package.json server/package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts
COPY server/src ./src
COPY server/migrations ./migrations
ENV HOST=0.0.0.0 PORT=18082 WEB_ROOT=/app/web BASE_PATH=/bustimer
EXPOSE 18082
CMD ["node", "src/server.js"]
