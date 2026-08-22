FROM aishell:base

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# >>> knot (managed) >>>
ARG KNOT_VERSION=0.10.0
RUN bbin install https://github.com/UniSoma/knot.git --tag "v${KNOT_VERSION}"
# <<< knot (managed) <<<

# >>> revu toolchain >>>
# Emacs 30.2 built from source: bookworm ships 28.2, below the project's 30.2 baseline.
# --without-x: batch use only (byte-compile, ert, prototypes run with `emacs -nw`).
# --with-native-compilation=no keeps the build short; nothing here benefits from it.
ARG EMACS_VERSION=30.2
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential make pkg-config texinfo \
      libgnutls28-dev libncurses-dev libjansson-dev libtree-sitter-dev \
      libsqlite3-dev libgccjit-12-dev zlib1g-dev \
  && curl -fsSL "https://ftp.gnu.org/gnu/emacs/emacs-${EMACS_VERSION}.tar.xz" -o /tmp/emacs.tar.xz \
  && mkdir -p /tmp/emacs && tar -xJf /tmp/emacs.tar.xz -C /tmp/emacs --strip-components=1 \
  && cd /tmp/emacs \
  && ./configure --without-x --without-sound --with-native-compilation=no \
       --with-tree-sitter --with-json --with-sqlite3 \
  && make -j"$(nproc)" && make install \
  && rm -rf /tmp/emacs /tmp/emacs.tar.xz \
  && apt-get purge -y build-essential texinfo && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

# Eldev: build/lint/test driver for Emacs packages (byte-compile warnings as errors,
# package-lint, checkdoc, ert). Single script, no other deps.
RUN curl -fsSL https://raw.github.com/emacs-eldev/eldev/master/bin/eldev -o /usr/local/bin/eldev \
  && chmod +x /usr/local/bin/eldev

# revdiff: the reference implementation. Used for byte-compatibility golden tests of the
# markdown Export and for round-trip checks via `revdiff --annotations=<our-export>`.
ARG REVDIFF_VERSION=1.12.0
RUN curl -fsSL "https://github.com/umputun/revdiff/releases/download/v${REVDIFF_VERSION}/revdiff_${REVDIFF_VERSION}_linux_amd64.tar.gz" \
      | tar -xz -C /usr/local/bin revdiff \
  && chmod +x /usr/local/bin/revdiff

# Pre-warm the package archives so `eldev` doesn't hit the network on every container start.
ENV ELDEV_DIR=/opt/eldev
RUN mkdir -p "$ELDEV_DIR" && chmod 777 "$ELDEV_DIR"
# <<< revu toolchain <<<
