#!/bin/sh
#
# SPDX-License-Identifier: BSD-3-Clause
#
# Copyright (c) 2026, Sasha Karcz <sasha@starnix.net>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# * Redistributions of source code must retain the above copyright notice, this
#   list of conditions and the following disclaimer.
#
# * Redistributions in binary form must reproduce the above copyright notice,
#   this list of conditions and the following disclaimer in the documentation
#   and/or other materials provided with the distribution.
#
# * Neither the name of the copyright holder nor the names of its
#   contributors may be used to endorse or promote products derived from
#   this software without specific prior written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

. /usr/local/share/bastille/common.sh
VM_PLUGIN_DIR="$(dirname "$(realpath "$0")")"
# shellcheck source=/dev/null
. "${VM_PLUGIN_DIR}/vm.subr"

usage() {
    error_notify "Usage: bastille plugin vm clone [option(s)] NAME NEW_NAME [ADDRESS]"
    cat << EOF

    Options:

    -a | --auto      Auto mode. Start/stop the VM if required. Cannot be used
                     with [-l|--live].
    -l | --live      Clone a running VM (ZFS only). Cannot be used with
                     [-a|--auto].
    --reseed         Rebuild the cloud-init seed with a fresh instance-id so the
                     clone re-provisions at first boot (its own IP/hostname/keys)
                     instead of being an identical twin. Pass ADDRESS to give it
                     a new address.
    --hostname NAME  (With --reseed) Hostname for the reseeded clone
                     (default: NEW_NAME).

EOF
    exit 1
}

# Handle options
AUTO=0
LIVE=0
RESEED=0
RESEED_HOSTNAME=""
while [ "$#" -gt 0 ]; do
    case "${1}" in
        -h|--help|help)
            usage
            ;;
        -a|--auto)
            AUTO=1
            shift
            ;;
        -l|--live)
            if ! checkyesno bastille_zfs_enable; then
                error_exit "[-l|--live] can only be used with ZFS."
            fi
            LIVE=1
            shift
            ;;
        --reseed)
            RESEED=1
            shift
            ;;
        --hostname)
            if [ -z "${2}" ]; then
                error_exit "[ERROR]: [--hostname] requires a name."
            fi
            RESEED_HOSTNAME="${2}"
            shift 2
            ;;
        -*)
            for opt in $(echo "${1}" | sed 's/-//g' | fold -w1); do
                case "${opt}" in
                    a) AUTO=1 ;;
                    l) LIVE=1 ;;
                    *) error_exit "[ERROR]: Unknown Option: \"${1}\"" ;;
                esac
            done
            shift
            ;;
        *)
            break
            ;;
    esac
done

# Verify options
if [ "${AUTO}" -eq 1 ] && [ "${LIVE}" -eq 1 ]; then
    error_exit "[-a|--auto] cannot be used with [-l|--live]"
fi

# Verify parameter count. ADDRESS is optional (it is RDR metadata; the guest's
# real network config lives inside the guest and is cloned as-is).
if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
    usage
fi

TARGET="${1}"
NEW_NAME="${2}"
NEW_ADDRESS="${3}"

bastille_root_check

if ! check_vm_exists "${TARGET}"; then
    error_exit "[ERROR]: VM not found: ${TARGET}"
fi

vm_clone "${TARGET}" "${NEW_NAME}" "${NEW_ADDRESS}" "${AUTO}" "${LIVE}" "${RESEED}" "${RESEED_HOSTNAME}"
exit $?
