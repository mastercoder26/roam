# Pinned base image rather than the buildpack that produced the first
# revision. The buildpack chose its own Node version at build time, so two
# deploys of identical source could land on different runtimes.
FROM node:22-slim

ENV NODE_ENV=production

WORKDIR /app

# Dependencies install from the lockfile in their own layer so a source change
# does not reinstall them. `tsx` is a runtime dependency here, not a dev one:
# the server runs TypeScript directly, so `--omit=dev` is safe.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev

COPY server.ts tsconfig.json ./
COPY src ./src

# Cloud Run assigns the port and expects the container to honour it. The
# default matches the local dev port so the image behaves the same when run
# by hand.
ENV PORT=8080
EXPOSE 8080

# Run as the image's unprivileged user rather than root.
USER node

CMD ["npm", "start"]
