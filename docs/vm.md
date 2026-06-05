# VM Management

RSD's `vm` command provides full lifecycle management for virtual machines using pluggable backend drivers.

## Quick Start

```bash
# Create a VM from Ubuntu 26.04 cloud image
rsd vm create test-vm --os ubuntu-26.04

# SSH into the VM
rsd vm ssh test-vm

# Run recipes inside the VM (VM as RSD target)
rsd @virsh://test-vm recipe run nginx/install

# Snapshot the current state
rsd vm snapshot test-vm --name post-nginx

# Rollback if needed
rsd vm rollback test-vm --to post-nginx

# Clean up
rsd vm destroy test-vm
```

## Architecture

The `vm` command uses a **driver-based** architecture:

```
command/vm          → Unified CLI (driver-agnostic)
lib/vm.lib          → Driver dispatcher + common utilities
lib/vm/libvirt.lib  → KVM/QEMU backend via virsh/virt-install
lib/vm/docker.lib   → Future: Docker/Podman backend
lib/vm/lxd.lib      → Future: LXD container backend
```

The active driver is resolved by:
1. CLI flag: `--driver libvirt`
2. Config: `vm.ini → [defaults] driver=libvirt`
3. Auto-detect: probes for `virsh` in `$PATH`

## Dependencies (Libvirt Driver)

The libvirt driver requires:

| Binary | Package (Arch) | Purpose |
| :--- | :--- | :--- |
| `virsh` | `libvirt` | VM lifecycle management |
| `virt-install` | `virt-install` | VM creation |
| `qemu-system-x86_64` | `qemu-full` | Virtualization |
| `qemu-img` | `qemu-full` | Disk image management |
| `genisoimage` | `cdrtools` | Cloud-init ISO generation |
| `curl` | `curl` | Cloud image download |

RSD validates these at every entry point and reports missing binaries.

## Connection Modes

| Flag | Description |
| :--- | :--- |
| `--session` (default) | Rootless QEMU. User-mode NAT networking. No sudo required. |
| `--system` | System libvirt. Bridge networking. Requires `libvirt` group membership. |

## Configuration

Edit `config/vm.ini` (or `~/.config/rsd/vm.ini` for user overrides):

```ini
[defaults]
driver=libvirt
mode=session
user=rsd
ram=2G
vcpus=2
disk=20G
key=~/.ssh/id_ed25519.pub
bootstrap=true

[cache]
dir=~/.local/share/rsd/vm/cache/
enabled=true
```

## Commands

### Lifecycle

```bash
rsd vm create <name> [options]    # Create from cloud image
rsd vm destroy <name>             # Remove VM + storage
rsd vm start <name>               # Power on
rsd vm stop <name>                # Graceful ACPI shutdown
rsd vm kill <name>                # Force off
rsd vm pause <name>               # Freeze state
rsd vm resume <name>              # Unfreeze
```

### Connectivity

```bash
rsd vm ssh <name>                 # SSH into guest
rsd vm console <name>             # Serial console (Ctrl+] to detach)
```

### Snapshots

```bash
rsd vm snapshot <name> [--name t] # Take named snapshot
rsd vm rollback <name> --to <t>   # Revert to snapshot
rsd vm commit <name> --snap <t>   # Merge snapshot into base
rsd vm snapshots <name>           # List all snapshots
rsd vm delete-snap <name> <snap>  # Delete a snapshot
```

### Information

```bash
rsd vm list                       # List all RSD-managed VMs
rsd vm status <name>              # Detailed VM info
rsd vm images                     # Available cloud images
rsd vm help                       # Command reference
```

### Create Options

| Option | Default | Description |
| :--- | :--- | :--- |
| `--os` | `ubuntu-26.04` | Cloud image (see `rsd vm images`) |
| `--ram` | `2G` | Memory allocation |
| `--vcpus` | `2` | Virtual CPUs |
| `--disk` | `20G` | Disk size |
| `--user` | `rsd` | Guest username |
| `--key` | `~/.ssh/id_ed25519.pub` | SSH public key |
| `--session` | *(default)* | Rootless mode |
| `--system` | *(flag)* | System mode |
| `--bridge` | *(none)* | Bridge interface |
| `--driver` | `libvirt` | Backend driver |
| `--no-bootstrap` | *(flag)* | Skip RSD install in guest |

## VM as RSD Target

Created VMs can be used as targets for any RSD command via the `virsh://` protocol:

```bash
# Direct protocol addressing
rsd @virsh://test-vm recipe run nginx/install
rsd @virsh://test-vm systemd status nginx.service

# Register as a named alias for convenience
rsd remote alias test-vm virsh://test-vm
rsd @test-vm recipe run php/fpm
```

## Storage

| Mode | Path | Managed by |
| :--- | :--- | :--- |
| Session | `~/.local/share/libvirt/images/` | libvirt (user) |
| System | `/var/lib/libvirt/images/` | libvirt (system) |

Cloud image cache: `~/.local/share/rsd/vm/cache/` (configurable).

## Cloud Images

The image registry at `data/vm/images.ini` maps OS specs to download URLs:

```ini
[ubuntu]
26.04=https://cloud-images.ubuntu.com/plucky/current/plucky-server-cloudimg-amd64.img

[debian]
12=https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
```

Each VM is provisioned via **cloud-init** (NoCloud datasource), which:
- Sets the hostname
- Creates the user with sudo access
- Injects the SSH public key
- Installs basic packages (bash, curl, tar, git)
