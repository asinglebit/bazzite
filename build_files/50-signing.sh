#!/usr/bin/bash
# Bake in the trust needed to verify this image's own updates. Three files,
# mirroring how the base image ships trust for ghcr.io/ublue-os:
#
#   /etc/pki/containers/<ns>.pub              the cosign public key
#   /etc/containers/registries.d/<ns>.yaml    "signatures are OCI attachments"
#   /etc/containers/policy.json               require a signature for that scope
#
# WITHOUT THE registries.d ENTRY the signature is never looked for and
# verification silently passes on nothing at all.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# A local `just build` publishes nowhere and has no signing key, so the image
# stays unsigned and 40-branding.sh's containers-storage ref matches that.
if [[ -z "${IMAGE_REGISTRY:-}" ]]; then
    echo "IMAGE_REGISTRY unset — local build, skipping signing setup"
    exit 0
fi

PUBKEY_SRC="${CTX}/cosign.pub"

# Publishing without the key baked in would produce an image whose updates can
# never be verified, and which would fail its own first `bootc upgrade`.
if [[ ! -f "${PUBKEY_SRC}" ]]; then
    echo "IMAGE_REGISTRY=${IMAGE_REGISTRY} but ${PUBKEY_SRC} is missing" >&2
    echo "run: COSIGN_PASSWORD=\"\" cosign generate-key-pair" >&2
    exit 1
fi

NS="${IMAGE_REGISTRY##*/}"
KEY_PATH="/etc/pki/containers/${NS}.pub"
POLICY=/etc/containers/policy.json

grep -q 'BEGIN PUBLIC KEY' "${PUBKEY_SRC}"
install -Dpm0644 "${PUBKEY_SRC}" "${KEY_PATH}"

# use-sigstore-attachments tells podman/skopeo/bootc to look for the signature
# as an OCI attachment on the registry rather than at a lookaside server.
install -Dpm0644 /dev/stdin "/etc/containers/registries.d/${NS}.yaml" <<EOF
docker:
  ${IMAGE_REGISTRY}:
    use-sigstore-attachments: true
EOF

# matchRepository, NOT matchExact: cosign signs by digest, and two tags on one
# manifest are one signature -- matchExact would bind it to a single tag string
# and reject the other. It still refuses a signature lifted from a different
# repository under the same key.
#
# keyPaths (array), NOT keyPath (scalar): to rotate the key you ship an image
# trusting both and drop the old one once machines have moved. With a scalar
# that is a flag day -- a machine on the old image could not verify the new one.
#
# Key order in this object is irrelevant; containers-policy.json(5) matches by
# most specific scope, not document order.
jq --arg scope "${IMAGE_REGISTRY}" --arg key "${KEY_PATH}" \
   '.transports.docker[$scope] = [{
        "type": "sigstoreSigned",
        "keyPaths": [ $key ],
        "signedIdentity": { "type": "matchRepository" }
    }]' "${POLICY}" > "${POLICY}.new"
mv "${POLICY}.new" "${POLICY}"

# Guard rails: a regression here has to fail the BUILD, not the next
# `bootc upgrade` on a booted machine.
test -s "${KEY_PATH}"
jq -e --arg scope "${IMAGE_REGISTRY}" \
   '.transports.docker[$scope][0].type == "sigstoreSigned"' "${POLICY}" >/dev/null
jq -e --arg scope "${IMAGE_REGISTRY}" --arg key "${KEY_PATH}" \
   '.transports.docker[$scope][0].keyPaths == [ $key ]
    and .transports.docker[$scope][0].signedIdentity.type == "matchRepository"
    and (.transports.docker[$scope] | length) == 1' \
   "${POLICY}" >/dev/null

# The "" catch-all must survive: it is what lets the very first switch onto this
# image succeed on a machine that does not yet trust the namespace, and what
# keeps every unrelated registry pullable afterwards.
jq -e '.transports.docker[""][0].type == "insecureAcceptAnything"' "${POLICY}" >/dev/null

# And the trust the base image ships must not have been clobbered.
jq -e '.transports.docker["ghcr.io/ublue-os"][0].type == "sigstoreSigned"' "${POLICY}" >/dev/null

echo "signing trust installed for ${IMAGE_REGISTRY} -> ${KEY_PATH}"
