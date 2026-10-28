# Optional user tools

These tools install into the unprivileged home directory used by SimpleSSHD. They do not use root and do not change `/system`, boot settings, or firmware.

Preview the inputs and remote paths without network or filesystem changes:

```sh
bash scripts/install-user-tools.sh --dry-run SSH_HOST
```

Install them explicitly:

```sh
bash scripts/install-user-tools.sh SSH_HOST
```

The script checks for an ARMv7 Android target, fetches pinned files into ignored `sources/`, verifies their sizes and SHA-256 values, and writes only `~/bin`, `~/opt/python3.2`, and `~/env.sh` on the device. It does not install an APK.

Use the tools in an SSH session:

```sh
. "$HOME/env.sh"
python3 --version
curl --fail --location --output download.bin https://example.com/file
```

The provided BusyBox is a static ARMv7 build. QPython3 1.3.5 contains Python 3.2.2, which is obsolete and cannot run most current Python packages. The static curl wrapper uses HTTPS DNS-over-HTTPS for its own name lookups; it does not change Android's DNS settings. Review [external source notes](external-sources.md) before downloading these components.

Android does not provide a Debian package environment. These files do not install `apt`, make arbitrary Debian packages compatible, or turn the legacy Python interpreter into Termux.
