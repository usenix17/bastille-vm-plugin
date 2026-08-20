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
    error_notify "Usage: bastille plugin vm list [option(s)] [NAME]"
    cat << EOF

    Options:

    -d | --down      Show only stopped VMs.
    -u | --up        Show only running VMs.

EOF
    exit 1
}

# Handle options
OPT_STATE="all"
while [ "$#" -gt 0 ]; do
    case "${1}" in
        -h|--help|help)
            usage
            ;;
        -d|--down)
            OPT_STATE="Down"
            shift
            ;;
        -u|--up)
            OPT_STATE="Up"
            shift
            ;;
        -*)
            for opt in $(echo "${1}" | sed 's/-//g' | fold -w1); do
                case "${opt}" in
                    d) OPT_STATE="Down" ;;
                    u) OPT_STATE="Up" ;;
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

TARGET="${1}"

# Resolve the VM name of a vm.conf directory.
vm_row_os() {
    local vm="${1}" os
    os="$(vm_get "${vm}" os)"
    if [ -z "${os}" ]; then
        case "$(vm_get "${vm}" bootrom)" in
            *CSM*|*csm*) os="uefi-csm" ;;
            *) os="uefi-guest" ;;
        esac
    fi
    printf '%s' "${os}"
}

# Firmware/loader type from the bootrom.
vm_row_loader() {
    case "$(vm_get "${1}" bootrom)" in
        *CSM*|*csm*) printf 'uefi-csm' ;;
        *) printf 'uefi' ;;
    esac
}

# VNC endpoint from the framebuffer spec (tcp=<bind:port>,w=..,h=..), or "-".
vm_row_vnc() {
    local fb="$(vm_get "${1}" framebuffer)"
    [ -z "${fb}" ] && { printf '%s' '-'; return; }
    fb="${fb#tcp=}"
    printf '%s' "${fb%%,*}"
}

# Build the VM list.
if [ -n "${TARGET}" ]; then
    if ! check_vm_exists "${TARGET}"; then
        error_exit "[ERROR]: VM not found: ${TARGET}"
    fi
    VM_LIST="${TARGET}"
else
    VM_LIST="$(ls -v --color=never "${bastille_vmdir}" 2>/dev/null)"
fi

if [ -z "${VM_LIST}" ]; then
    error_exit "[ERROR]: No VMs found."
fi

# Column widths: start at the header labels, widen to the data. Datastore is the
# ZFS pool (one per host), so its width is fixed across rows.
DS="${bastille_zfs_zpool:--}"
W_JID=3; W_NAME=4; W_DS=9; W_LOAD=6; W_CPU=3; W_MEM=6; W_VNC=3
W_BOOT=4; W_PRIO=8; W_STATE=5; W_IP=10; W_OS=7
[ "${#DS}" -gt "${W_DS}" ] && W_DS="${#DS}"
for vm in ${VM_LIST}; do
    [ -f "${bastille_vmdir}/${vm}/vm.conf" ] || continue
    [ "${#vm}" -gt "${W_NAME}" ] && W_NAME="${#vm}"
    _l="$(vm_row_loader "${vm}")"; [ "${#_l}" -gt "${W_LOAD}" ] && W_LOAD="${#_l}"
    _c="$(vm_get "${vm}" cpu)"; _c="${_c:-1}"; [ "${#_c}" -gt "${W_CPU}" ] && W_CPU="${#_c}"
    _m="$(vm_get "${vm}" memory)"; _m="${_m:-512M}"; [ "${#_m}" -gt "${W_MEM}" ] && W_MEM="${#_m}"
    _vnc="$(vm_row_vnc "${vm}")"; [ "${#_vnc}" -gt "${W_VNC}" ] && W_VNC="${#_vnc}"
    _ip="$(vm_get "${vm}" address)"; _ip="${_ip:--}"
    [ "${#_ip}" -gt "${W_IP}" ] && W_IP="${#_ip}"
    _os="$(vm_row_os "${vm}")"
    [ "${#_os}" -gt "${W_OS}" ] && W_OS="${#_os}"
done

# Header.
printf " %-*s %-*s %-*s %-*s %-*s %-*s %-*s %-*s %-*s %-*s %-*s %-*s\n" \
    "${W_JID}" "JID" "${W_NAME}" "NAME" "${W_DS}" "DATASTORE" "${W_LOAD}" "LOADER" \
    "${W_CPU}" "CPU" "${W_MEM}" "MEMORY" "${W_VNC}" "VNC" "${W_BOOT}" "BOOT" \
    "${W_PRIO}" "PRIORITY" "${W_STATE}" "STATE" "${W_IP}" "IP" "${W_OS}" "OS"

# Rows.
for vm in ${VM_LIST}; do
    [ -f "${bastille_vmdir}/${vm}/vm.conf" ] || continue

    if check_vm_is_running "${vm}"; then
        STATE="Up"
    else
        STATE="Down"
    fi
    if [ "${OPT_STATE}" != "all" ] && [ "${STATE}" != "${OPT_STATE}" ]; then
        continue
    fi

    JID="$(jls -j "${vm}" jid 2>/dev/null)"; JID="${JID:--}"
    LOAD="$(vm_row_loader "${vm}")"
    CPU="$(vm_get "${vm}" cpu)"; CPU="${CPU:-1}"
    MEM="$(vm_get "${vm}" memory)"; MEM="${MEM:-512M}"
    VNC="$(vm_row_vnc "${vm}")"
    BOOT="$(sysrc -f "${bastille_vmdir}/${vm}/settings.conf" -n boot 2>/dev/null)"; BOOT="${BOOT:--}"
    PRIO="$(sysrc -f "${bastille_vmdir}/${vm}/settings.conf" -n priority 2>/dev/null)"; PRIO="${PRIO:--}"
    IP="$(vm_get "${vm}" address)"; IP="${IP:--}"
    OS="$(vm_row_os "${vm}")"

    printf " %-*s %-*s %-*s %-*s %-*s %-*s %-*s %-*s %-*s %-*s %-*s %-*s\n" \
        "${W_JID}" "${JID}" "${W_NAME}" "${vm}" "${W_DS}" "${DS}" "${W_LOAD}" "${LOAD}" \
        "${W_CPU}" "${CPU}" "${W_MEM}" "${MEM}" "${W_VNC}" "${VNC}" "${W_BOOT}" "${BOOT}" \
        "${W_PRIO}" "${PRIO}" "${W_STATE}" "${STATE}" "${W_IP}" "${IP}" "${W_OS}" "${OS}"
done
