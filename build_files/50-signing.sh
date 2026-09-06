#!/usr/bin/bash
# Bake in the trust needed to verify this image's own updates.
#
# Three files, mirroring exactly how the base image already ships trust for
# ghcr.io/ublue-os:
#
#   /etc/pki/containers/<ns>.pub          the cosign public key
#   /etc/containers/registries.d/<ns>.yaml   "signatures are OCI attachments"
#   /etc/containers/policy.json           require a signature for that namespace
#
# Together these are what make `bootc upgrade` refuse an image that CI did not
# sign. Without the registries.d entry the signature is never looked for and
# verification silently passes on nothing at all.
set -euxo pipefail

CTX="${CTX:-/ctx}"

# A local `just build` publishes nowhere and has no signing key, so there is
# nothing to trust and no policy to install. The image stays unsigned and the
# containers-storage ref from 40-branding.sh matches that reality.
if [[ -z "${IMAGE_REGISTRY:-}" ]]; then
    echo "IMAGE_REGISTRY unset — local build, skipping signing setup"
    exit 0
fi

PUBKEY_SRC="${CTX}/cosign.pub"

# Publishing without baking the key in would produce an image whose updates can
# never be verified, and which would fail its own first `bootc upgrade` once the
# policy did land. Fail the build instead.
if [[ ! -f "${PUBKEY_SRC}" ]]; then
    echo "IMAGE_REGISTRY=${IMAGE_REGISTRY} but ${PUBKEY_SRC} is missing" >&2
    echo "run: COSIGN_PASSWORD=\"\" cosign generate-key-pair" >&2
    exit 1
fi

# ghcr.io/asinglebit -> asinglebit. Names the key and the registries.d file the
# same way the base image names ublue-os.pub / ublue-os.yaml.
NS="${IMAGE_REGISTRY##*/}"
KEY_PATH="/etc/pki/containers/${NS}.pub"
POLICY=/etc/containers/policy.json

grep -q 'BEGIN PUBLIC KEY' "${PUBKEY_SRC}"
install -Dpm0644 "${PUBKEY_SRC}" "${KEY_PATH}"

# use-sigstore-attachments is what tells podman/skopeo/bootc to look for the
# signature as an OCI attachment on the registry (the sha256-<digest>.sig tag
# cosign pushes) rather than at a lookaside signature server.
install -Dpm0644 /dev/stdin "/etc/containers/registries.d/${NS}.yaml" <<EOF
docker:
  ${IMAGE_REGISTRY}:
    use-sigstore-attachments: true
EOF

# matchRepository, not matchExact: cosign signs by digest, and :plasma and
# :plasma-20260906 are two tags on one manifest. matchExact would bind the
# signature to a single tag string and reject the other. It still refuses a
# signature lifted from a different repository under the same key.
#
# keyPaths (array), not keyPath (scalar), mirroring the ublue-os block: to
# rotate the signing key you ship an image trusting both, and drop the old one
# once the machine has moved. With a scalar that is a flag day -- a machine on
# the old image could not verify the new one, and would need another unsigned
# bootstrap switch to recover.
#
# Key order in this object is irrelevant — containers-policy.json(5) matches by
# most specific scope, not document order, so "ghcr.io/asinglebit" beats the ""
# catch-all whatever position it lands in.
jq --arg scope "${IMAGE_REGISTRY}" --arg key "${KEY_PATH}" \
   '.transports.docker[$scope] = [{
        "type": "sigstoreSigned",
        "keyPaths": [ $key ],
        "signedIdentity": { "type": "matchRepository" }
    }]' "${POLICY}" > "${POLICY}.new"
mv "${POLICY}.new" "${POLICY}"

# Guard rails, in the style of the other build scripts: a regression here has to
# fail the *build*, not the next `bootc upgrade` on a booted machine.
test -s "${KEY_PATH}"
jq -e --arg scope "${IMAGE_REGISTRY}" \
   '.transports.docker[$scope][0].type == "sigstoreSigned"' "${POLICY}" >/dev/null
jq -e --arg scope "${IMAGE_REGISTRY}" --arg key "${KEY_PATH}" \
   '.transports.docker[$scope][0].keyPaths == [ $key ]
    and .transports.docker[$scope][0].signedIdentity.type == "matchRepository"
    and (.transports.docker[$scope] | length) == 1' \
   "${POLICY}" >/dev/null

# The "" catch-all must survive. It is what lets the very first switch onto this
# image succeed on a machine that does not yet trust the namespace, and what
# keeps every unrelated registry pullable afterwards.
jq -e '.transports.docker[""][0].type == "insecureAcceptAnything"' "${POLICY}" >/dev/null

# And the trust the base image ships must not have been clobbered.
jq -e '.transports.docker["ghcr.io/ublue-os"][0].type == "sigstoreSigned"' "${POLICY}" >/dev/null

echo "signing trust installed for ${IMAGE_REGISTRY} -> ${KEY_PATH}"
