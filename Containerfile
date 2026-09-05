# Bazzite + Sway — a Bazzite-derived bootc image running Sway instead of KDE Plasma.
#
# Built on the ublue-os/image-template shape: the `ctx` scratch stage keeps the
# build scripts out of the base layer's cache key, so editing build_files/ does
# not invalidate the 5+ GiB base image layer.

FROM scratch AS ctx
COPY build_files   /build_files
COPY system_files  /system_files

FROM ghcr.io/ublue-os/bazzite-nvidia-open:stable

# 0 = install Sway alongside Plasma (boot 1, keeps a fallback session)
# 1 = also strip the Plasma session and KDE apps (boot 2)
ARG REMOVE_KDE=0

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build_files/build.sh

RUN bootc container lint
