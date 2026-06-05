# VM Quick Start Guide

Create and manage virtual machines with `rsd vm`.

## Prerequisites

The libvirt driver requires these binaries in `$PATH`:

| Binary | Arch package | Purpose |
| :--- | :--- | :--- |
| `virsh` | `libvirt` | VM lifecycle |
| `virt-install` | `virt-install` | VM creation |
| `qemu-system-x86_64` | `qemu-full` | Virtualization engine |
| `qemu-img` | `qemu-full` | Disk image management |
| `genisoimage` | `cdrtools` | Cloud-init ISO generation |
| `curl` | `curl` | Cloud image download |

RSD checks these automatically and reports any missing binaries.

You also need an SSH key pair. If you don't have one:

```bash
ssh-keygen -t ed25519
```

> **Note:** The `libvirtd` service must be running. If it's not, `rsd vm` will
> detect this and tell you the exact command to start it.

---

## Step 0: Check Environment

Before creating your first VM, run the preflight check:

```bash
# Session mode (default)
rsd vm check

# System mode (bridge networking)
rsd vm check --system
```

This probes all prerequisites — binaries, KVM, libvirt service, default
network, SSH keys, group membership — and reports exactly what's ready
and what needs fixing.

---

## Step 1: Create a VM

```bash
rsd vm create test-vm --os ubuntu-26.04 --system
```

This will:
1. Download the Ubuntu 26.04 (Resolute Raccoon) cloud image (~860 MB)
2. Cache it locally for reuse
3. Create a 20 GB qcow2 disk backed by the image
4. Generate a cloud-init ISO (hostname, user `rsd`, SSH key injection)
5. Boot the VM and wait for SSH readiness
6. Report the guest IP address

### Create Options

| Option | Default | Description |
| :--- | :--- | :--- |
| `--os <distro-ver>` | `ubuntu-26.04` | Cloud image (see `rsd vm images`) |
| `--ram <size>` | `2G` | Memory |
| `--vcpus <n>` | `2` | Virtual CPUs |
| `--disk <size>` | `20G` | Disk size |
| `--user <name>` | `rsd` | Guest username |
| `--key <path>` | `~/.ssh/id_ed25519.pub` | SSH public key |
| `--session` | *(default)* | Rootless mode (QEMU user-mode NAT) |
| `--system` | *(flag)* | System mode (bridge networking, `libvirt` group required) |
| `--bridge <iface>` | *(auto)* | Bridge interface (implies `--system`) |
| `--driver <name>` | `libvirt` | Backend driver |
| `--no-bootstrap` | *(flag)* | Skip RSD install in guest |

### Connection Modes

| Mode | Networking | Permissions | When to use |
| :--- | :--- | :--- | :--- |
| `--session` | User-mode NAT (SLIRP) | No sudo | Quick testing, no bridge setup |
| `--system` | Bridge (`virbr0`) | `libvirt` group | Production-like, reliable IP discovery |

For `--system` mode, ensure the default virtual network is active.

### What is the default network?

When using `--system` mode, libvirt manages a **virtual bridge** (`virbr0`) that
creates an isolated subnet (typically `192.168.122.0/24`) with its own DHCP
server and NAT. This is what gives your VMs a reachable IP address.

On Arch Linux, this network exists but is **not active** by default after
installing libvirt. You need to start it once:

```bash
# Check current state
virsh net-list --all

# Expected output if inactive:
#  Name      State      Autostart   Persistent
# -----------------------------------------------
#  default   inactive   no          yes

# Start the network
sudo virsh net-start default

# Optional: auto-start on boot so you don't have to do this again
sudo virsh net-autostart default
```

With `--session` mode, this is not needed — QEMU handles networking itself
via user-mode NAT (SLIRP), which doesn't require any virtual bridge.

---

## Step 2: Connect

```bash
# SSH into the VM
rsd vm ssh test-vm

# Or use the reported IP directly
ssh rsd@192.168.122.x
```

### Verify inside the guest

```bash
lsb_release -a        # Ubuntu 26.04 (Resolute Raccoon)
hostname               # test-vm
whoami                 # rsd
sudo whoami            # root (passwordless)
```

### Serial console (if SSH is not yet available)

```bash
rsd vm console test-vm
# Detach with Ctrl+]
```

---

## Step 3: Snapshot

```bash
# Take a snapshot before testing
rsd vm snapshot test-vm --name clean-base

# ... test something risky ...

# Rollback to the clean state
rsd vm rollback test-vm --to clean-base

# List snapshots
rsd vm snapshots test-vm

# Merge a snapshot into the base image
rsd vm commit test-vm --snap clean-base

# Delete a snapshot
rsd vm delete-snap test-vm clean-base
```

---

## Step 4: Power Operations

```bash
rsd vm stop test-vm          # Graceful ACPI shutdown
rsd vm start test-vm         # Power on
rsd vm pause test-vm         # Freeze VM state
rsd vm resume test-vm        # Resume frozen VM
rsd vm kill test-vm          # Force power off (last resort)
```

---

## Step 5: Info & Cleanup

```bash
rsd vm list                  # All RSD-managed VMs
rsd vm status test-vm        # Detailed VM info (state, IP, vCPUs, snapshots)
rsd vm images                # Available cloud images

# Remove VM and all associated storage
rsd vm destroy test-vm
```

---

## Using a VM as an RSD Target

*(Phase 2 — virsh:// protocol bridge)*

Once the `virsh://` protocol is implemented, any VM can be used as a remote
target for RSD commands:

```bash
rsd @virsh://test-vm recipe run nginx/install
rsd @virsh://test-vm systemd status nginx.service
```

For now, SSH in and run RSD inside the guest:

```bash
rsd vm ssh test-vm
# Inside guest:
rsd recipe run nginx/install
```

---

## Configuration

Defaults are in `config/vm.ini`. Override per-user in `~/.config/rsd/vm.ini`:

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

---

## Storage Paths

| Mode | VM disks | Managed by |
| :--- | :--- | :--- |
| `--session` | `~/.local/share/libvirt/images/` | libvirt (user) |
| `--system` | `/var/lib/libvirt/images/` | libvirt (system) |

Cloud image cache: `~/.local/share/rsd/vm/cache/` (configurable).

---

## Troubleshooting

| Symptom | Cause | Fix |
| :--- | :--- | :--- |
| "Cannot connect to libvirt" | Service not running | `sudo systemctl start libvirtd` (rsd will tell you) |
| "Could not resolve guest IP" | VM still booting | Wait 30s, retry. Or use `rsd vm console` |
| "network not found" (system mode) | Default network inactive | `sudo virsh net-start default` |
| Download fails | Bad URL or no network | `rsd vm images` to verify, `curl -I <url>` to test |
| Permission denied on disk (system) | Not in `libvirt` group | `sudo usermod -aG libvirt $USER` then re-login |

---

## Available Images

View registered cloud images:

```bash
rsd vm images
```

Add new images by editing `data/vm/images.ini`:

```ini
[ubuntu]
26.04=https://cloud-images.ubuntu.com/resolute/current/resolute-server-cloudimg-amd64.img

[debian]
12=https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2
```
