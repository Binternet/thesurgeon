# Build stage not needed for minimal Node app
FROM node:20-alpine AS runtime

WORKDIR /app

COPY app/package.json app/server.js ./

EXPOSE 8080

ENV NODE_ENV=production
ENV PORT=8080

USER node

CMD ["node", "server.js"]
