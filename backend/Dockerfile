FROM utdemir/ghc-musl:v25-ghc944

ARG CABAL_VERSION=3.14.2.0
ARG CABAL_SHA256=f99df35fd67519888188b10689f999267e27beacb9fdd64c8a16073ca9d0a49c
RUN cd /tmp \
 && wget -q https://downloads.haskell.org/~cabal/cabal-install-${CABAL_VERSION}/cabal-install-${CABAL_VERSION}-x86_64-linux-alpine3_17.tar.xz \
 && echo "${CABAL_SHA256}  cabal-install-${CABAL_VERSION}-x86_64-linux-alpine3_17.tar.xz" | sha256sum -c - \
 && tar -xJf cabal-install-${CABAL_VERSION}-x86_64-linux-alpine3_17.tar.xz -C "$(dirname "$(which cabal)")" cabal \
 && rm cabal-install-*.tar.xz \
 && rm -rf ~/.cabal ~/.config/cabal ~/.cache/cabal ~/.local/state/cabal

WORKDIR /build

# Copy dependency files first for better Docker layer caching
COPY tallymark.cabal cabal.project cabal.project.freeze ./
RUN cabal update
RUN cabal build --only-dependencies --ghc-options='-static -optl-static -optl-pthread'

# Copy source and build
COPY . .
RUN cabal build --ghc-options='-static -optl-static -optl-pthread'
RUN cp $(cabal list-bin bootstrap) /build/bootstrap
