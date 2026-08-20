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
    error_notify "Usage: bastille plugin vm create [option(s)] NAME TEMPLATE"
    error_notify "       bastille plugin vm create [option(s)] --image SRC NAME"
    cat << EOF

    Create a VM from a template, or template-less from flags (--image or --iso).

    Networking:
    -V | --vnet              Own VNET stack (default: shared host bridge).

    Template-less build (NAME only, no TEMPLATE):
    --image SRC              Boot disk image (cloud image URL or path).
    --iso SRC                Install ISO (URL or path), instead of --image.
    --cpu N                  vCPUs (default 2).
    --memory SIZE            RAM, e.g. 2G (default 2G).
    --disk SIZE              Boot disk size, e.g. 20G (default 20G).
    --bootrom SPEC           Firmware (default uefi).
    --nic BRIDGE             Host bridge for the NIC (default bastille_vm_bridge).
    --os LABEL               Guest OS label; also guides the framebuffer and the
                             generated NIC-name form (e.g. rocky, debian, ubuntu).
    --hostname NAME          cloud-init hostname (default: VM name).
    --ssh-key "KEY"          Authorized SSH key for the default cloud user.
    --ssh-key-file PATH      Read authorized key(s) from a file (one per line).
    --address IP[/PREFIX]    Static IPv4 (prefix defaults to /24).
    --gateway IP             Default gateway.
    --nameserver LIST        DNS servers, comma-separated.
    --search DOMAIN          DNS search domain(s), comma-separated.
    --net-iface NAME         Guest NIC name or glob (default per --os: eth0 for
                             Alpine/RHEL, "en*" otherwise).
    --dhcp                   Use DHCP instead of a static address.
    --framebuffer            Attach a VNC framebuffer (needed by RHEL-family
                             guests; auto-added for those anyway).
    --passthru B/S/F         Pass a physical PCI device (bus/slot/func, from
                             pciconf) through to the guest. Repeatable. Needs an
                             IOMMU and the device reserved by ppt(4).
    --user-data FILE         Use this cloud-init user-data verbatim.
    --network-config FILE    Use this cloud-init network-config verbatim.

EOF
    exit 1
}

validate_vm_name() {

    local NAME_VERIFY="${NAME}"
    local NAME_SANITY="$(echo "${NAME_VERIFY}" | tr -c -d 'a-zA-Z0-9-_')"

    if check_vm_exists "${NAME}"; then
        error_exit "[ERROR]: VM already exists: ${NAME}"
    elif check_target_exists "${NAME}"; then
        error_exit "[ERROR]: A jail already exists with that name: ${NAME}"
    elif [ -n "$(echo "${NAME_SANITY}" | awk "/^[-_].*$/")" ]; then
        error_exit "[ERROR]: VM names may not begin with (-|_) characters!"
    elif [ "${NAME_VERIFY}" != "${NAME_SANITY}" ]; then
        error_exit "[ERROR]: VM names may not contain special characters!"
    elif echo "${NAME_VERIFY}" | grep -qE '^[0-9]+$'; then
        error_exit "[ERROR]: VM names may not contain only digits."
    fi
}

# Build a throwaway template directory from the collected flags and echo its
# path. vm_create renders it exactly like a real template, so the flag path
# reuses all of the image-import, cloud-init, and per-distro handling.
build_flag_template() {
    local td
    td="$(mktemp -d "${TMPDIR:-/tmp}/bastille-vmflags.XXXXXX")" || \
        error_exit "[ERROR]: Failed to create a temporary template directory."

    # Assemble the SSH keys (from --ssh-key and/or --ssh-key-file).
    local ssh_keys=""
    if [ -n "${FB_SSHKEYFILE}" ]; then
        [ -r "${FB_SSHKEYFILE}" ] || { rm -rf "${td}"; error_exit "[ERROR]: SSH key file not readable: ${FB_SSHKEYFILE}"; }
        ssh_keys="$(cat "${FB_SSHKEYFILE}")"
    fi
    if [ -n "${FB_SSHKEY}" ]; then
        ssh_keys="${ssh_keys}${ssh_keys:+
}${FB_SSHKEY}"
    fi

    # Resolve the NIC-name form for a generated static/DHCP config.
    local iface="${FB_IFACE}"
    if [ -z "${iface}" ]; then
        case "$(echo "${FB_OS}" | tr 'A-Z' 'a-z')" in
            *alpine*|*rocky*|*rhel*|*alma*|*centos*|*fedora*|*oracle*) iface="eth0" ;;
            *) iface='en*' ;;
        esac
    fi

    # Bastillefile.
    {
        printf 'VM\n'
        printf 'CPU %s\n' "${FB_CPU}"
        printf 'MEM %s\n' "${FB_MEM}"
        printf 'BOOTROM %s\n' "${FB_BOOTROM}"
        if [ -n "${FB_IMAGE}" ]; then
            printf 'DISK disk0 %s source=%s\n' "${FB_DISK}" "${FB_IMAGE}"
        else
            printf 'DISK disk0 %s\n' "${FB_DISK}"
        fi
        printf 'NIC %s\n' "${FB_NIC}"
        [ -n "${FB_ISO}" ] && printf 'ISO %s\n' "${FB_ISO}"
    } > "${td}/Bastillefile"

    # cloud-init user-data.
    local have_ud=0
    if [ -n "${FB_USERDATA}" ]; then
        [ -r "${FB_USERDATA}" ] || { rm -rf "${td}"; error_exit "[ERROR]: user-data not readable: ${FB_USERDATA}"; }
        cp "${FB_USERDATA}" "${td}/user-data"
        have_ud=1
    elif [ -n "${FB_HOSTNAME}" ] || [ -n "${ssh_keys}" ]; then
        {
            printf '#cloud-config\n'
            [ -n "${FB_HOSTNAME}" ] && printf 'hostname: %s\n' "${FB_HOSTNAME}"
            if [ -n "${ssh_keys}" ]; then
                printf 'ssh_authorized_keys:\n'
                printf '%s\n' "${ssh_keys}" | while IFS= read -r _k; do
                    [ -n "${_k}" ] && printf '  - %s\n' "${_k}"
                done
            fi
        } > "${td}/user-data"
        have_ud=1
    fi
    [ "${have_ud}" -eq 1 ] && printf 'CLOUDINIT user-data\n' >> "${td}/Bastillefile"

    # cloud-init network-config.
    local have_nc=0
    if [ -n "${FB_NETCONF}" ]; then
        [ -r "${FB_NETCONF}" ] || { rm -rf "${td}"; error_exit "[ERROR]: network-config not readable: ${FB_NETCONF}"; }
        cp "${FB_NETCONF}" "${td}/network-config"
        have_nc=1
    elif [ "${FB_DHCP}" -eq 1 ] || [ -n "${FB_ADDR}" ]; then
        {
            printf 'version: 2\n'
            printf 'ethernets:\n'
            case "${iface}" in
                *'*'*) printf '  primary:\n    match:\n      name: "%s"\n' "${iface}" ;;
                *)     printf '  %s:\n' "${iface}" ;;
            esac
            if [ "${FB_DHCP}" -eq 1 ]; then
                printf '    dhcp4: true\n'
            else
                local addr="${FB_ADDR}"
                case "${addr}" in */*) : ;; *) addr="${addr}/24" ;; esac
                printf '    dhcp4: false\n'
                printf '    addresses: [%s]\n' "${addr}"
                [ -n "${FB_GW}" ] && printf '    gateway4: %s\n' "${FB_GW}"
                if [ -n "${FB_DNS}" ] || [ -n "${FB_SEARCH}" ]; then
                    printf '    nameservers:\n'
                    [ -n "${FB_DNS}" ] && printf '      addresses: [%s]\n' "${FB_DNS}"
                    [ -n "${FB_SEARCH}" ] && printf '      search: [%s]\n' "${FB_SEARCH}"
                fi
            fi
        } > "${td}/network-config"
        have_nc=1
    fi
    [ "${have_nc}" -eq 1 ] && printf 'NETWORK_CONFIG network-config\n' >> "${td}/Bastillefile"

    # Framebuffer + OS + ADDRESS metadata.
    [ "${FB_FB}" -eq 1 ] && printf 'FRAMEBUFFER\n' >> "${td}/Bastillefile"
    for _pt in ${FB_PASSTHRU}; do printf 'PASSTHRU %s\n' "${_pt}" >> "${td}/Bastillefile"; done
    [ -n "${FB_OS}" ] && printf 'OS %s\n' "${FB_OS}" >> "${td}/Bastillefile"
    [ -n "${FB_ADDR}" ] && printf 'ADDRESS %s\n' "${FB_ADDR%%/*}" >> "${td}/Bastillefile"

    echo "${td}"
}

# Handle options
VNET=0
FB_IMAGE=""; FB_ISO=""; FB_CPU="2"; FB_MEM="2G"; FB_DISK="20G"; FB_BOOTROM="uefi"
FB_NIC=""; FB_OS=""; FB_HOSTNAME=""; FB_SSHKEY=""; FB_SSHKEYFILE=""
FB_ADDR=""; FB_GW=""; FB_DNS=""; FB_SEARCH=""; FB_IFACE=""; FB_DHCP=0
FB_FB=0; FB_USERDATA=""; FB_NETCONF=""; FB_PASSTHRU=""; HAVE_BUILD_FLAGS=0
while [ "$#" -gt 0 ]; do
    case "${1}" in
        -h|--help|help)           usage ;;
        -V|--vnet)                VNET=1; shift ;;
        --image)                  FB_IMAGE="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --iso)                    FB_ISO="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --cpu)                    FB_CPU="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --memory|--mem)           FB_MEM="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --disk)                   FB_DISK="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --bootrom)                FB_BOOTROM="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --nic)                    FB_NIC="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --os)                     FB_OS="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --hostname)               FB_HOSTNAME="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --ssh-key)                FB_SSHKEY="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --ssh-key-file)           FB_SSHKEYFILE="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --address|--ip)           FB_ADDR="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --gateway|--gw)           FB_GW="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --nameserver|--dns)       FB_DNS="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --search)                 FB_SEARCH="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --net-iface)              FB_IFACE="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --dhcp)                   FB_DHCP=1; HAVE_BUILD_FLAGS=1; shift ;;
        --framebuffer|--vnc)      FB_FB=1; HAVE_BUILD_FLAGS=1; shift ;;
        --passthru|--ppt)         FB_PASSTHRU="${FB_PASSTHRU}${FB_PASSTHRU:+ }${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --user-data)              FB_USERDATA="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        --network-config)         FB_NETCONF="${2}"; HAVE_BUILD_FLAGS=1; shift 2 ;;
        -*)                       error_exit "[ERROR]: Unknown Option: \"${1}\"" ;;
        *)                        break ;;
    esac
done

bastille_root_check

if [ "${VNET}" -eq 1 ]; then
    VM_NETWORK_TYPE="vnet"
else
    VM_NETWORK_TYPE="shared"
fi

# Flag (template-less) mode is selected by a disk source (--image or --iso).
if [ -n "${FB_IMAGE}" ] || [ -n "${FB_ISO}" ]; then
    if [ "$#" -ne 1 ]; then
        error_notify "[ERROR]: Template-less create takes exactly one NAME (no TEMPLATE)."
        usage
    fi
    NAME="${1}"
    info 1 "\nCreating VM: ${NAME}..."
    validate_vm_name
    TD="$(build_flag_template)"
    trap 'rm -rf "${TD}"' EXIT INT TERM
    vm_create "${NAME}" "${TD}" "${VM_NETWORK_TYPE}"
    rc=$?
    rm -rf "${TD}"
    trap - EXIT INT TERM
    exit "${rc}"
fi

# Template mode.
if [ "${HAVE_BUILD_FLAGS}" -eq 1 ]; then
    error_exit "[ERROR]: Build flags require --image or --iso (template-less mode)."
fi
if [ "$#" -ne 2 ]; then
    usage
fi
NAME="${1}"
TEMPLATE="${2}"
info 1 "\nCreating VM: ${NAME}..."
validate_vm_name
vm_create "${NAME}" "${TEMPLATE}" "${VM_NETWORK_TYPE}"
exit $?
