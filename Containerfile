# Bazzite + Sway — a Bazzite-derived bootc image running Sway instead of KDE Plasma.
#
# Built on the ublue-os/image-template shape: the `ctx` scratch stage keeps the
# build scripts out of the base layer's cache key, so editing build_files/ does
# not invalidate the 5+ GiB base image layer.

FROM scratch AS ctx
COPY build_files   /build_files
COPY system_files  /system_files
# Public half of the CI signing key. 50-signing.sh installs it as
# /etc/pki/containers/asinglebit.pub and points policy.json at it.
COPY cosign.pub    /cosign.pub

FROM ghcr.io/ublue-os/bazzite-nvidia-open:stable

# 0 = install Sway alongside Plasma (boot 1, keeps a fallback session)
# 1 = also strip the Plasma session and KDE apps (boot 2)
ARG REMOVE_KDE=0

# Where this image will be published. Empty means a local build: 40-branding.sh
# then keeps the containers-storage ref and 50-signing.sh skips the trust setup,
# so `just build` still produces a working unsigned image with no GHCR involved.
ARG IMAGE_REGISTRY=""
ARG IMAGE_TAG="test"

# org.opencontainers.image.source is what makes GHCR attach the package to the
# repo and inherit its visibility settings; without it the package floats free.
LABEL org.opencontainers.image.source="https://github.com/asinglebit/bazzite"
LABEL org.opencontainers.image.description="Bazzite-derived bootc image running Sway instead of KDE Plasma"
LABEL org.opencontainers.image.title="bazzite-sway"

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/build.sh

RUN bootc container lint
