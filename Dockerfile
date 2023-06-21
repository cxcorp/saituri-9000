FROM node:18-alpine AS builder-base
# Install deps for building native packages
RUN apk add --no-cache make gcc g++ python3

###################################################################
FROM builder-base AS builder

WORKDIR /builder

# Install dependencies
COPY yarn.lock package.json ./
RUN --mount=type=cache,target=/root/.yarn \
  YARN_CACHE_FOLDER=/root/.yarn \
  JOBS=max \
  yarn --frozen-lockfile --network-timeout 100000

# Copy DB schema and generate client
COPY db db
RUN yarn db:generate-client

# Copy source code and build
COPY tsconfig.json .
COPY src src
RUN PARCEL_WORKER_BACKEND=process yarn build

###################################################################
FROM builder AS production-deps-builder
# Force serial building by reusing builder layer because raspberry appears to
# get stuck pulling deps if they are built in parallel. We reuse the cache so
# it's ok.

WORKDIR /production-deps-builder

COPY yarn.lock package.json ./

RUN --mount=type=cache,target=/root/.yarn \
  YARN_CACHE_FOLDER=/root/.yarn \
  JOBS=max \
  yarn --production --frozen-lockfile --network-timeout 100000

###################################################################
FROM node:18-alpine AS app

WORKDIR /app

COPY --from=builder /builder/build/ ./build/
COPY --from=builder /builder/db/ ./db/
COPY --from=builder /builder/dist/ ./dist/
COPY public ./public/
COPY --from=production-deps-builder /production-deps-builder/node_modules/ ./node_modules/
COPY --from=builder /builder/package.json ./package.json
