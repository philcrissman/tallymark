FROM utdemir/ghc-musl:v25-ghc944

WORKDIR /build

# Copy dependency files first for better Docker layer caching
COPY tallymark.cabal cabal.project cabal.project.freeze ./
RUN cabal update
RUN cabal build --only-dependencies --ghc-options='-static -optl-static -optl-pthread'

# Copy source and build
COPY . .
RUN cabal build --ghc-options='-static -optl-static -optl-pthread'
RUN cp $(cabal list-bin bootstrap) /build/bootstrap
