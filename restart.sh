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
    error_notify "Usage: bastille plugin vm restart [option(s)] NAME"
    cat << EOF

    Options:

    -b | --boot            Respect the VM boot setting on start.
    -d | --delay VALUE     Time (seconds) to wait after starting the VM.
    -i | --ignore          Do not start the VM if it is already stopped.

EOF
    exit 1
}

# Handle options. Options are forwarded to the sibling stop/start scripts.
start_options=""
IGNORE=0
while [ "$#" -gt 0 ]; do
    case "${1}" in
        -h|--help|help)
            usage
            ;;
        -b|--boot)
            start_options="${start_options} -b"
            shift
            ;;
        -d|--delay)
            start_options="${start_options} -d ${2}"
            shift 2
            ;;
        -i|--ignore)
            IGNORE=1
            shift
            ;;
        -v|--verbose)
            shift
            ;;
        -*)
            for opt in $(echo "${1}" | sed 's/-//g' | fold -w1); do
                case "${opt}" in
                    b) start_options="${start_options} -b" ;;
                    i) IGNORE=1 ;;
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

if [ "${IGNORE}" -eq 1 ] && check_vm_is_stopped "${TARGET}"; then
    info 1 "\n[${TARGET}]:"
    error_exit "VM is stopped."
fi

# Restart via the sibling stop/start entry points (which dispatch to the
# bhyve supervisor). Calling them directly keeps this self-contained,
# independent of how the plugin is named or installed.
"${VM_PLUGIN_DIR}/stop.sh" "${TARGET}"
# shellcheck disable=SC2086
"${VM_PLUGIN_DIR}/start.sh" ${start_options} "${TARGET}"
exit $?
