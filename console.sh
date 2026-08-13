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
    error_notify "Usage: bastille -p vm console [option(s)] NAME"
    cat << EOF

    Options:

    -a | --auto      Auto mode. Start the VM first if it is not running.

EOF
    exit 1
}

# Handle options
AUTO=0
while [ "$#" -gt 0 ]; do
    case "${1}" in
        -h|--help|help)
            usage
            ;;
        -a|--auto)
            AUTO=1
            shift
            ;;
        -*)
            error_exit "[ERROR]: Unknown Option: \"${1}\""
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

# A VM console is the nmdm serial line, not a jexec login.
if ! check_vm_is_running "${TARGET}"; then
    if [ "${AUTO}" -eq 1 ]; then
        "${VM_PLUGIN_DIR}/start.sh" "${TARGET}" || error_exit "[ERROR]: Failed to start VM: ${TARGET}"
        # bhyve is daemon-backgrounded, so wait briefly for the supervision jail.
        waited=0
        while [ "${waited}" -lt 10 ]; do
            check_vm_is_running "${TARGET}" && break
            sleep 1
            waited=$((waited + 1))
        done
    else
        info 1 "\n[${TARGET}]:"
        error_notify "VM is not running."
        error_exit "Use [-a|--auto] to auto-start the VM."
    fi
fi

info 1 "\n[${TARGET}]:"
vm_console "${TARGET}"
exit $?
