#!/usr/bin/bash
# Installs the three files needed to verify this image's own updates: the public key,
# a note that signatures live on the registry, and a policy requiring one.
# Miss the middle file and verification passes without ever looking for a signature.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# A local build publishes nowhere and has no key, so it stays unsigned.
if [[ -z "${IMAGE_REGISTRY:-}" ]]; then
    echo "IMAGE_REGISTRY unset — local build, skipping signing setup"
    exit 0
fi

PUBKEY_SRC="${CTX}/cosign.pub"

# Publishing without the key would make an image that fails its own first upgrade.
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

# Tells the tools to look for the signature on the registry itself.
install -Dpm0644 /dev/stdin "/etc/containers/registries.d/${NS}.yaml" <<EOF
docker:
  ${IMAGE_REGISTRY}:
    use-sigstore-attachments: true
EOF

# matchRepository rather than matchExact, because one signature covers every tag on a manifest.
# keyPaths is a list so a key can be rotated by trusting both for a while.
jq --arg scope "${IMAGE_REGISTRY}" --arg key "${KEY_PATH}" \
   '.transports.docker[$scope] = [{
        "type": "sigstoreSigned",
        "keyPaths": [ $key ],
        "signedIdentity": { "type": "matchRepository" }
    }]' "${POLICY}" > "${POLICY}.new"
mv "${POLICY}.new" "${POLICY}"

# These have to fail the build, not someone's next upgrade.
test -s "${KEY_PATH}"
jq -e --arg scope "${IMAGE_REGISTRY}" \
   '.transports.docker[$scope][0].type == "sigstoreSigned"' "${POLICY}" >/dev/null
jq -e --arg scope "${IMAGE_REGISTRY}" --arg key "${KEY_PATH}" \
   '.transports.docker[$scope][0].keyPaths == [ $key ]
    and .transports.docker[$scope][0].signedIdentity.type == "matchRepository"
    and (.transports.docker[$scope] | length) == 1' \
   "${POLICY}" >/dev/null

# The catch-all must survive, or the first switch onto this image cannot happen at all.
jq -e '.transports.docker[""][0].type == "insecureAcceptAnything"' "${POLICY}" >/dev/null

# And the base image's own trust must still be there.
jq -e '.transports.docker["ghcr.io/ublue-os"][0].type == "sigstoreSigned"' "${POLICY}" >/dev/null

echo "signing trust installed for ${IMAGE_REGISTRY} -> ${KEY_PATH}"
