FROM ubuntu:rolling AS builder
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update -y && \
    apt-get install automake build-essential pkg-config libffi-dev libgmp-dev libssl-dev libtinfo-dev libsystemd-dev zlib1g-dev make g++ tmux git jq wget libncursesw5 libtool autoconf liblmdb-dev curl -y

# Create src folder for installations
RUN mkdir src

# Install libsodium
RUN cd src && \
    git clone https://github.com/input-output-hk/libsodium && \
    cd libsodium && \
    git checkout 66f017f1 && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install

#Install libsecp256k1
RUN cd src && \
    git clone https://github.com/bitcoin-core/secp256k1 && \
    cd secp256k1 && \
    git checkout ac83be33 && \
    ./autogen.sh && \
    ./configure --enable-module-schnorrsig --enable-experimental && \
    make && \
    make install

# Install GHC version 8.10.4 and Cabal
RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 BOOTSTRAP_HASKELL_MINIMAL=1 sh
ENV PATH="/root/.ghcup/bin:${PATH}"
RUN ghcup upgrade && \
    ghcup install cabal 3.6.2.0 && \
    ghcup set cabal 3.6.2.0 && \
    ghcup install ghc 8.10.7 && \
    ghcup set ghc 8.10.7

# Update PATH
ENV LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"
ENV PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

# Update Cabal
RUN cabal update

# Clone Cardano Node and checkout to latest version
RUN TAG=$(curl -s https://api.github.com/repos/input-output-hk/cardano-node/releases/latest | jq -r .tag_name) && \
    echo $TAG && \
    cd src && \
    git clone https://github.com/input-output-hk/cardano-node.git && \
    cd cardano-node && \
    git fetch --all --recurse-submodules --tags && \
    git tag && \
    git checkout tags/${TAG}

# Set config for cabal project
RUN echo "package cardano-crypto-praos" >>  /src/cardano-node/cabal.project.local && \
    echo "flags: -external-libsodium-vrf" >>  /src/cardano-node/cabal.project.local

# Build cardano-node & cardano-cli
RUN cd src/cardano-node && \
    cabal build all

# Find and copy binaries to ~/.local/bin
RUN cp $(find /src/cardano-node/dist-newstyle/build -type f -name "cardano-cli") /usr/local/bin/cardano-cli
RUN cp $(find /src/cardano-node/dist-newstyle/build -type f -name "cardano-node") /usr/local/bin/cardano-node

FROM ubuntu:rolling

COPY --from=builder /usr/local/bin/cardano-cli /usr/local/bin
COPY --from=builder /usr/local/bin/cardano-node /usr/local/bin

# Install dependencies
RUN apt-get update -y && \
    apt-get install automake build-essential pkg-config libffi-dev libgmp-dev libssl-dev libtinfo-dev libsystemd-dev zlib1g-dev make g++ tmux git jq wget libncursesw5 libtool autoconf liblmdb-dev curl vim -y

#Install libsodium
RUN mkdir src && \
    cd src && \
    git clone https://github.com/input-output-hk/libsodium && \
    cd libsodium && \
    git checkout 66f017f1 && \
    ./autogen.sh && \
    ./configure && \
    make && \
    make install

#Install libsecp256k1
RUN cd src && \
    git clone https://github.com/bitcoin-core/secp256k1 && \
    cd secp256k1 && \
    git checkout ac83be33 && \
    ./autogen.sh && \
    ./configure --enable-module-schnorrsig --enable-experimental && \
    make && \
    make install

# Delete src folder
RUN rm -r /src

# Dockerfile
# add this and below command will run without cache
ARG CACHEBUST=1

# Get latest config files from https://book.world.dev.cardano.org/environments.html
RUN wget -P /node/configuration \
    https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/config.json \
    https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/topology.json \
    https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/byron-genesis.json \
    https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/shelley-genesis.json \
    https://raw.githubusercontent.com/input-output-hk/cardano-world/master/docs/environments/preview/alonzo-genesis.json

# Change config to save them in /root/node/log/node.log file instead of stdout
RUN sed -i 's/StdoutSK/FileSK/' /node/configuration/config.json && \
    sed -i 's/stdout/\/node\/logs\/node.log/' /node/configuration/config.json

# Update libsodium PATH
ENV LD_LIBRARY_PATH="/usr/local/lib:$LD_LIBRARY_PATH"
ENV PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH"

# Set node socket evironment for cardano-cli
ENV CARDANO_NODE_SOCKET_PATH="/node/ipc/node.socket"

# Set testnet magic number for Pre-View Testnet
ENV TESTNET_MAGIC=2

# Create keys, ipc, data, scripts, logs folders
RUN mkdir -p /node/logs /node/ipc /node/keys /node/addresses /node/transactions /node/plutus-scripts /node/native-scripts /node/data

# Copy developer scripts
RUN git clone https://github.com/solidsnakedev/cardano-dev-scripts.git
# Create symbolic links
RUN ln -s /cardano-dev-scripts/*.sh /usr/local/bin

# Set executable permits
RUN /bin/bash -c "chmod +x /usr/local/bin/*.sh"

# Run cardano-node at the startup
CMD [ "/usr/local/bin/run-cardano-node.sh" ]