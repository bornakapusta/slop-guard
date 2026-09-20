FROM ruby:3.4.10-slim AS build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential pkg-config libyaml-dev \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV BUNDLE_WITHOUT=test BUNDLE_DEPLOYMENT=true BUNDLE_PATH=/usr/local/bundle
COPY Gemfile Gemfile.lock ./
RUN gem install bundler -v 2.7.2 --no-document && bundle install

FROM ruby:3.4.10-slim
WORKDIR /app
ENV BUNDLE_WITHOUT=test BUNDLE_DEPLOYMENT=true BUNDLE_PATH=/usr/local/bundle \
    SLOP_GUARD_DATA_DIR=/data RACK_ENV=production PORT=3000
RUN groupadd --gid 10001 slopguard && useradd --uid 10001 --gid slopguard --create-home slopguard \
    && mkdir /data && chown slopguard:slopguard /data
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY Gemfile Gemfile.lock config.ru ./
COPY lib/ lib/
COPY config/ config/
COPY bin/app-server bin/app-worker bin/
USER slopguard
VOLUME /data
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s \
    CMD ruby -rnet/http -e 'exit(Net::HTTP.get_response(URI("http://127.0.0.1:3000/healthz")).code == "200" ? 0 : 1)'
CMD ["bundle", "exec", "ruby", "bin/app-server"]
