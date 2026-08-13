# bastille-vm-plugin

First-class bhyve VM management for [Bastille](https://bastillebsd.org),
delivered as a Bastille **plugin** (`bastille -p vm ...`).

A VM is treated as a peer instance type to a jail: each VM runs its bhyve(8)
device model inside a minimal, auto-generated supervision jail (`allow.vmm`), so
it gets a real JID, shows up in `jls(8)`, and is constrained by `rctl(8)` like
any other jail. The jail is the confinement boundary (restricted per-VM devfs,
its own vnet, per-VM rctl); the plugin owns the VM lifecycle.

> Independent, unofficial plugin. Not affiliated with or endorsed by the Bastille
> project; "Bastille" is used here only to describe what this plugs into.

## Requirements

- **Bastille with plugin support** (`bastille -p ...`), see
  [BastilleBSD/bastille#1600](https://github.com/BastilleBSD/bastille/pull/1600).
  Until that ships in a release, apply the plugin patch to your Bastille.
- `vmm(4)`, `nmdm(4)`, `if_bridge(4)`, `if_tap(4)`, and `if_epair(4)` (VNET mode).
- `sysutils/edk2-bhyve` -- UEFI firmware for the guest bootrom.
- `sysutils/qemu-tools` -- only if you boot from a `qcow2` image (`qemu-img`
  converts it to the zvol); raw images need nothing extra.

## Install

The command word after `-p` is the plugin's directory name, so install this into
`plugins/vm` to get `bastille -p vm ...`:

```sh
sharedir=$(bastille config -g bastille_sharedir 2>/dev/null || echo /usr/local/share/bastille)
git clone https://github.com/<you>/bastille-vm-plugin "${sharedir}/plugins/vm"
```

Once #1600's install-by-URL is available you can instead
`bastille -p https://github.com/<you>/bastille-vm-plugin` -- note that installs
under the repo's name, so you would invoke it as `bastille -p bastille-vm-plugin`;
cloning into `plugins/vm` keeps the shorter `bastille -p vm`.

## Usage

```sh
bastille -p vm create [-V|--vnet] NAME TEMPLATE            # from a template
bastille -p vm create [-V|--vnet] --image SRC [flags] NAME # template-less
bastille -p vm start   [-b] [-d SECS] NAME
bastille -p vm stop    [-f] NAME
bastille -p vm restart [-b] [-i] NAME
bastille -p vm console [-a] NAME                           # nmdm serial console
bastille -p vm list    [-u|-d] [NAME]
bastille -p vm clone   [-a|-l] [--reseed [--hostname H]] NAME NEW_NAME [ADDRESS]
bastille -p vm destroy [-f] [-y] NAME
```

`-V|--vnet` gives the VM its own VNET supervision jail; the default is shared
networking (guest tap on the host bridge).

### Template-less create (flags)

Instead of a template, pass `--image` (or `--iso`) plus flags; the plugin builds
the equivalent template on the fly. It generates the `network-config` in the
right form for the guest (see the pitfalls table) and auto-attaches a framebuffer
for RHEL-family images.

```sh
bastille -p vm create -V \
  --image https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.raw \
  --os debian --cpu 2 --memory 2G --disk 20G \
  --nic jailbridge \
  --address 192.168.1.50 --gateway 192.168.1.1 \
  --nameserver 192.168.1.53 --search example.com \
  --hostname web1 --ssh-key "$(cat ~/.ssh/id_ed25519.pub)" \
  web1
```

Run `bastille -p vm create -h` for the full flag list. `--net-iface` overrides
the generated NIC-name form; `--user-data`/`--network-config` supply your own
cloud-init files verbatim; `--dhcp` uses DHCP instead of a static address. The
default NIC bridge is `bastille_vm_bridge` (`bridge0`); set `--nic` (or that
config knob) to your host's bridge.

## Template directives

A VM template is a `Bastillefile` of directives: `VM`, `CPU`, `MEM`, `BOOTROM`,
`DISK name size [source=<image>]`, `NIC [bridge]`, `ISO`, `CLOUDINIT`,
`NETWORK_CONFIG`, `OS`, `ADDRESS`, `RDR`, and:

- `FRAMEBUFFER [bind:port] [WxH] [wait]` (alias `VNC`) -- attach a VGA
  framebuffer served over VNC, plus a USB tablet. Required by guests whose
  bootloader needs a video mode: RHEL/Rocky/Alma GRUB uses `gfxterm` and stalls
  at boot on a headless serial-only VM. Serial-friendly guests (e.g. Alpine)
  don't need it. Defaults to `127.0.0.1:5900` at 1024x768. Example:
  `FRAMEBUFFER 0.0.0.0:5901`.

Known-good starter templates for each major distro are under
[`examples/`](examples/).

## Guest OS pitfalls

Cloud images differ in ways that bite a headless bhyve VM:

| Guest      | Framebuffer  | NIC name | `network-config`      | Gateway     | Cloud user |
| ---------- | ------------ | -------- | --------------------- | ----------- | ---------- |
| Alpine     | not needed   | `eth0`   | `eth0:`               | `gateway4:` | `alpine`   |
| Rocky/RHEL | **required** | `eth0`   | `eth0:` (no `match:`) | `gateway4:` | `rocky`    |
| Debian     | not needed   | `enp0s4` | `match: name: "en*"`  | `gateway4:` | `debian`   |
| Ubuntu     | not needed   | `enp0s4` | `match: name: "en*"`  | `gateway4:` | `ubuntu`   |

- **Framebuffer (RHEL family):** Rocky/Alma/CentOS/RHEL/Fedora GRUB uses
  `gfxterm` and stalls before the kernel on a serial-only VM. Add `FRAMEBUFFER`,
  or rely on the plugin auto-attaching one when it detects a RHEL-family guest
  (from the `OS` label or image name).
- **NIC naming:** images that keep `net.ifnames=1` (Debian, Ubuntu) name the NIC
  `enp0s4` (its PCI slot), not `eth0`. Match by glob (`en*`) so the name does not
  matter. RHEL/Alpine images use `eth0`.
- **`match:` support:** the NetworkManager backend (RHEL) ignores `match:` -- name
  the interface explicitly there. eni/networkd/netplan (Alpine/Debian/Ubuntu)
  honor it.
- **Gateway:** `gateway4:` works on every backend tested. Do **not** use the v2
  `routes: [{to: default}]` form on Alpine -- its busybox `ifup` aborts the
  interface on the resulting `post-up route` command.

## Configuration

The plugin reads `bastille_vm*` knobs from `bastille.conf` and self-defaults any
that are unset:

| Variable                       | Default                                          |
| ------------------------------ | ------------------------------------------------ |
| `bastille_vmdir`               | `${bastille_prefix}/vms`                         |
| `bastille_vm_bootrom`          | `/usr/local/share/uefi-firmware/BHYVE_UEFI.fd`   |
| `bastille_vm_bridge`           | `bridge0`                                         |
| `bastille_vm_shutdown_timeout` | `30`                                             |
| `bastille_vm_disk_type`        | `virtio-blk`                                      |
| `bastille_vm_nic_type`         | `virtio-net`                                      |
| `bastille_vm_devfs_ruleset`    | `100`                                            |
| `bastille_vm_isolated_devfs`   | `YES` (own jail root + restricted per-VM devfs)  |

## Layout

```
create.sh start.sh stop.sh restart.sh console.sh destroy.sh list.sh clone.sh
vm.subr        glue: config defaults + check_vm* helpers, sources bhyve.sh
bhyve.sh       the vm_* library
examples/      known-good per-distro starter templates
```

Each command sources core `common.sh`, then `vm.subr`; the library path is
resolved from the script's own location, so the plugin works wherever it is
installed.

## Notes

- Boot-time VM ordering (starting VMs alongside jails at system boot) is host
  integration, not something a plugin can provide. Manage it with the host
  `rc.d/bastille` hook or a dedicated rc script if you need boot ordering.

## License

BSD-3-Clause. Copyright (c) 2026, Sasha Karcz. See [LICENSE](LICENSE).
