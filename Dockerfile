FROM node:18 AS builder-base
# Install deps for building native packages
RUN apt-get update && apt-get install -y make g++ gcc python3

###################################################################
FROM builder-base AS builder

WORKDIR /builder

# Install dependencies
COPY yarn.lock package.json ./
RUN --mount=type=cache,target=/root/.yarn \
  YARN_CACHE_FOLDER=/root/.yarn \
  JOBS=max \
  yarn --network-timeout 100000

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
  yarn --production --network-timeout 100000

###################################################################
FROM node:18 AS app

WORKDIR /app

RUN apt-get update && apt-get install -y openssl && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=builder /builder/build/ ./build/
COPY --from=builder /builder/db/ ./db/
COPY --from=builder /builder/dist/ ./dist/
COPY public ./public/
COPY --from=production-deps-builder /production-deps-builder/node_modules/ ./node_modules/
COPY --from=builder /builder/package.json ./package.json
