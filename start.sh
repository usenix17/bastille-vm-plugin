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
    error_notify "Usage: bastille -p vm start [option(s)] NAME"
    cat << EOF

    Options:

    -b | --boot            Respect the VM boot setting (skip if boot=off).
    -d | --delay VALUE     Time (seconds) to wait after starting the VM.

EOF
    exit 1
}

# Handle options
BOOT=0
DELAY_TIME=0
while [ "$#" -gt 0 ]; do
    case "${1}" in
        -h|--help|help)
            usage
            ;;
        -b|--boot)
            BOOT=1
            shift
            ;;
        -d|--delay)
            if [ -z "${2}" ] || ! echo "${2}" | grep -Eq '^[0-9]+$'; then
                error_exit "[-d|--delay] requires a value."
            fi
            DELAY_TIME="${2}"
            shift 2
            ;;
        -v|--verbose)
            shift
            ;;
        -*)
            for opt in $(echo "${1}" | sed 's/-//g' | fold -w1); do
                case "${opt}" in
                    b) BOOT=1 ;;
                    v) ;;
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

# Verify parameter count
if [ "$#" -ne 1 ]; then
    usage
fi

TARGET="${1}"

bastille_root_check

if ! check_vm_exists "${TARGET}"; then
    error_exit "[ERROR]: VM not found: ${TARGET}"
fi

# Respect '-b|--boot' + settings.conf boot value, like jails.
if [ "${BOOT}" -eq 1 ]; then
    BOOT_ENABLED="$(sysrc -f "${bastille_vmdir}/${TARGET}/settings.conf" -n boot 2>/dev/null)"
    if [ "${BOOT_ENABLED}" = "off" ]; then
        exit 0
    fi
fi

info 1 "\n[${TARGET}]:"
if vm_start "${TARGET}"; then
    sleep "${DELAY_TIME}"
    exit 0
else
    exit 1
fi
