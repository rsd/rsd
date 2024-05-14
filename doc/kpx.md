# KeePass Support

KeePass support is provided by the `kpx` command and `kpx` library. The `kpx` command is a command line interface to KeePass databases. The `kpx` library is a Python library that provides a programmatic interface to KeePass databases.

There are several options to interact with KeePass databases, like:
- keepassxc-cli
- keepass
- kpcli

We are defaulting, at least for now, for the use of 'keepassxc-cli'.

## Installation

There are several ways to install it.
For ubuntu it is in the keepassxc package:

### APT

```bash
sudo apt install keepassxc
```
The problem with this is that some x11 dependencies might be installed as well.

So, other forms of installations are:

### Snap

```bash
sudo snap install keepassxc --classic
```

### AppImage

```bash
wget https://github.com/keepassxreboot/keepassxc/releases/download/2.7.4/KeePassXC-2.7.4-x86_64.AppImage

./KeePassXC-2.7.4-x86_64.AppImage --appimage-extract
./squashfs-root/usr/bin/keepassxc-cli --help
```

### Download and compile:
    
```bash
git clone https://github.com/keepassxreboot/keepassxc.git
cd keepassxc
git clone https://github.com/keepassxreboot/keepassxc.git
cd keepassxc
make
sudo make install
```

and so on.