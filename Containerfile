# A Bazzite-derived bootc image running SwayFX instead of KDE Plasma.
# The `ctx` stage exists so that editing build_files/ does not rebuild the 5 GiB base layer.

FROM scratch AS ctx
COPY build_files   /build_files
COPY system_files  /system_files
# Public half of the signing key; 50-signing.sh installs it and points policy.json at it.
COPY cosign.pub    /cosign.pub

FROM ghcr.io/ublue-os/bazzite-nvidia-open:stable

# Where the image gets published; empty means a local build, which skips the signing setup.
ARG IMAGE_REGISTRY=""

# One image, one tag; it stays an arg because 40-branding.sh writes it into image-info.json.
ARG IMAGE_TAG="sway"

# A hash of the build scripts, used only so podman notices when they change.
# Without it a build says "Using cache" and quietly tags the previous image again.
ARG CTX_DIGEST=""

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    CTX_DIGEST="${CTX_DIGEST}" /ctx/build_files/build.sh

RUN bootc container lint

# The source label is what attaches the package to the repo on GHCR.
LABEL org.opencontainers.image.source="https://github.com/asinglebit/bazzite"
LABEL org.opencontainers.image.description="Bazzite-derived bootc image running SwayFX instead of KDE Plasma"
LABEL org.opencontainers.image.title="bazzite-sway"
