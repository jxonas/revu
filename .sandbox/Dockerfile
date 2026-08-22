FROM aishell:foundation

SHELL ["/bin/bash", "-eo", "pipefail", "-c"]

# >>> knot (managed) >>>
ARG KNOT_VERSION=0.10.0
RUN bbin install https://github.com/UniSoma/knot.git --tag "v${KNOT_VERSION}"
# <<< knot (managed) <<<
