# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/), and the project adheres to
[Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `plugin.conf` -- a sysrc-style plugin manifest (name, min_version,
  depends_kmods, depends_pkgs) following the format under discussion in
  BastilleBSD/bastille#1600. Advisory today; consumed by Bastille once supported.

## [1.0.0] - 2026-08-14

First stable release. Manage bhyve VMs as first-class peers of Bastille jails
via the plugin mechanism (`bastille -p vm ...`). Each VM runs inside an
`allow.vmm` supervision jail with a restricted per-VM devfs and its own vnet.

### Added

- **VM lifecycle**: `create`, `start`, `stop`, `restart`, `console`, `list`,
  `clone`, `destroy`.
- **Templates**: `Bastillefile` directives (`VM`, `CPU`, `MEM`, `BOOTROM`,
  `DISK ... [source=<image>]`, `NIC`, `ISO`, `CLOUDINIT`, `NETWORK_CONFIG`,
  `OS`, `ADDRESS`, `RDR`, `FRAMEBUFFER`, `PASSTHRU`).
- **Template-less create from flags**: `create --image SRC [flags] NAME`
  synthesizes an equivalent template on the fly (`--cpu/--memory/--disk/--nic/
  --os/--address/--gateway/--nameserver/--search/--hostname/--ssh-key/--dhcp/
  --net-iface/--user-data/--network-config`).
- **Cloud images + cloud-init**: remote/local raw or qcow2 disk import
  (qcow2 via `qemu-img`), NoCloud seed (user-data + network-config) presented as
  virtio-blk so `ds-identify` finds it.
- **Networking**: shared (guest tap on a host bridge) or VNET (`-V`, own network
  stack); create-time duplicate-address guard.
- **Framebuffer/VNC** (`FRAMEBUFFER`): auto-attached for RHEL-family guests whose
  GRUB needs a video mode.
- **PCI passthrough** (`PASSTHRU b/s/f` / `--passthru`): emits the bhyve passthru
  device, wires guest RAM (`-S`), exposes the `ppt` node in the private devfs,
  and preflights the IOMMU and `ppt` binding.
- **Cold migration** (`migrate NAME [user@]host`): ZFS `send -R | ssh | recv` of
  the whole VM; receives into the destination's own pool/prefix; `--nic` retargets
  the guest bridge, `-s` starts on arrival, `-d` removes the source.
- **Hardening** (default, `bastille_vm_isolated_devfs=YES`): own jail root,
  read-only nullfs userland, restricted per-VM devfs, per-VM vnet.
- Per-distro example templates (Alpine, Rocky, Debian, Ubuntu) under `examples/`.

### Notes

- `vm_start` loads `vmm`/`nmdm` and retries a fast bhyve exit, so a fresh host
  works and the hardened-jail nmdm console clone race self-heals.
- Requires Bastille with plugin support (BastilleBSD/bastille#1600),
  `sysutils/edk2-bhyve`, and (for qcow2) `sysutils/qemu-tools`.
- Live migration is out of scope: FreeBSD's GENERIC kernel lacks
  `BHYVE_SNAPSHOT`.

[1.0.0]: https://github.com/usenix17/bastille-vm-plugin/releases/tag/v1.0.0
