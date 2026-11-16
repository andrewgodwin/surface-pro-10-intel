#!/usr/bin/env python3
"""
Import Bluetooth pairing keys from a Windows install into BlueZ, so a device
paired in Windows (e.g. the Surface Pro Flex Keyboard) also works under Linux
without re-pairing.

Handles both BLE devices (LTK/IRK/CSRK...) and classic BR/EDR link keys.
No dependencies: includes a minimal read-only Windows registry hive parser.

Usage:
    sudo ./win-bt-import.py --dry-run     # show what would be written
    sudo ./win-bt-import.py               # write keys, restart bluetooth

Options:
    --hive PATH     use this SYSTEM hive instead of auto-mounting Windows
    --device DEV    Windows partition (default: autodetect NTFS with Windows)
    --filter TEXT   only import devices whose MAC or name contains TEXT
    --yes           don't ask for confirmation
"""
import argparse
import glob
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import time

# ---------------------------------------------------------------- regf parser


class Hive:
    def __init__(self, path):
        with open(path, "rb") as f:
            self.d = f.read()
        if self.d[:4] != b"regf":
            raise ValueError(f"{path} is not a registry hive")
        seq1, seq2 = struct.unpack_from("<II", self.d, 4)
        self.dirty = seq1 != seq2
        self.root = struct.unpack_from("<I", self.d, 0x24)[0]

    def cell(self, off):
        """Return the data of the cell at hbin-relative offset `off`."""
        pos = 4096 + off
        size = struct.unpack_from("<i", self.d, pos)[0]
        return memoryview(self.d)[pos + 4 : pos + abs(size)]

    def _subkey_offsets(self, list_off):
        c = self.cell(list_off)
        sig = bytes(c[:2])
        n = struct.unpack_from("<H", c, 2)[0]
        if sig in (b"lf", b"lh"):
            return [struct.unpack_from("<I", c, 4 + i * 8)[0] for i in range(n)]
        if sig == b"li":
            return [struct.unpack_from("<I", c, 4 + i * 4)[0] for i in range(n)]
        if sig == b"ri":
            out = []
            for i in range(n):
                out += self._subkey_offsets(struct.unpack_from("<I", c, 4 + i * 4)[0])
            return out
        raise ValueError(f"unknown subkey list {sig!r}")

    def key(self, off):
        return Key(self, off)

    def open(self, path):
        k = self.key(self.root)
        for part in path.split("\\"):
            k = k.subkey(part)
            if k is None:
                return None
        return k


class Key:
    def __init__(self, hive, off):
        self.h = hive
        c = hive.cell(off)
        if bytes(c[:2]) != b"nk":
            raise ValueError("not an nk cell")
        flags = struct.unpack_from("<H", c, 2)[0]
        self.n_sub = struct.unpack_from("<I", c, 20)[0]
        self.sub_off = struct.unpack_from("<I", c, 28)[0]
        self.n_val = struct.unpack_from("<I", c, 36)[0]
        self.val_off = struct.unpack_from("<I", c, 40)[0]
        nlen = struct.unpack_from("<H", c, 72)[0]
        raw = bytes(c[76 : 76 + nlen])
        self.name = raw.decode("latin-1") if flags & 0x20 else raw.decode("utf-16-le")

    def subkeys(self):
        if not self.n_sub:
            return []
        return [Key(self.h, o) for o in self.h._subkey_offsets(self.sub_off)]

    def subkey(self, name):
        for k in self.subkeys():
            if k.name.lower() == name.lower():
                return k
        return None

    def values(self):
        """Return {name: (type, bytes)}."""
        out = {}
        if not self.n_val:
            return out
        lst = self.h.cell(self.val_off)
        for i in range(self.n_val):
            c = self.h.cell(struct.unpack_from("<I", lst, i * 4)[0])
            if bytes(c[:2]) != b"vk":
                continue
            nlen, dsize, doff, vtype, flags = struct.unpack_from("<HIIIH", c, 2)
            raw = bytes(c[20 : 20 + nlen])
            name = raw.decode("latin-1") if flags & 1 else raw.decode("utf-16-le")
            if dsize & 0x80000000:  # data stored inline in the offset field
                data = struct.pack("<I", doff)[: dsize & 0x7FFFFFFF]
            else:
                data = bytes(self.h.cell(doff)[:dsize])
            out[name] = (vtype, data)
        return out


# ---------------------------------------------------------------- helpers


def mac_fmt(s):
    s = s.replace(":", "").upper()
    return ":".join(s[i : i + 2] for i in range(0, 12, 2))


def as_int(data):
    return int.from_bytes(data, "little")


def find_windows_partition():
    out = subprocess.run(
        ["lsblk", "-rno", "PATH,FSTYPE,SIZE"], capture_output=True, text=True
    ).stdout
    parts = [l.split()[0] for l in out.splitlines() if l.split()[1:2] == ["ntfs"]]
    # Prefer the largest NTFS partition (skip recovery partitions)
    def size(p):
        try:
            return int(open(f"/sys/class/block/{os.path.basename(p)}/size").read())
        except OSError:
            return 0
    return sorted(parts, key=size, reverse=True)


def find_ci(base, *parts):
    """Case-insensitive path lookup."""
    cur = base
    for p in parts:
        try:
            match = [e for e in os.listdir(cur) if e.lower() == p.lower()]
        except OSError:
            return None
        if not match:
            return None
        cur = os.path.join(cur, match[0])
    return cur


def mount_ro(dev, mnt):
    for cmd in (
        ["mount", "-t", "ntfs3", "-o", "ro", dev, mnt],
        ["ntfs-3g", "-o", "ro", dev, mnt],
    ):
        if subprocess.run(cmd, capture_output=True).returncode == 0:
            return True
    return False


# ---------------------------------------------------------------- extraction


def read_devices(hive):
    sel = hive.open("Select")
    cur = as_int(sel.values()["Current"][1]) if sel else 1
    base = f"ControlSet{cur:03d}\\Services\\BTHPORT\\Parameters"
    keys = hive.open(base + "\\Keys")
    if keys is None:
        sys.exit(f"No {base}\\Keys in hive - nothing paired in Windows?")
    devs_key = hive.open(base + "\\Devices")

    def name_for(mac):
        if devs_key is None:
            return None
        k = devs_key.subkey(mac.replace(":", "").lower())
        if k:
            v = k.values().get("Name")
            if v:
                return v[1].split(b"\0")[0].decode("utf-8", "replace")
        return None

    result = {}  # adapter_mac -> list of device dicts
    for adapter in keys.subkeys():
        amac = mac_fmt(adapter.name)
        devs = []
        # Classic: values named by device MAC containing a 16-byte link key
        for vname, (vtype, data) in adapter.values().items():
            if len(vname) == 12 and len(data) == 16:
                m = mac_fmt(vname)
                devs.append(dict(kind="classic", mac=m, name=name_for(m), linkkey=data))
        # LE: subkeys named by device MAC
        for sk in adapter.subkeys():
            v = sk.values()
            if "LTK" not in v:
                continue
            m = mac_fmt(sk.name)
            if "Address" in v:  # identity address
                m = mac_fmt(f"{as_int(v['Address'][1]):012x}")
            devs.append(
                dict(
                    kind="le",
                    mac=m,
                    name=name_for(m) or name_for(sk.name),
                    ltk=v["LTK"][1],
                    enc=as_int(v["KeyLength"][1]) if "KeyLength" in v else 16,
                    ediv=as_int(v["EDIV"][1]) if "EDIV" in v else 0,
                    rand=as_int(v["ERand"][1]) if "ERand" in v else 0,
                    irk=v.get("IRK", (0, None))[1],
                    csrk=v.get("CSRK", (0, None))[1],
                    addrtype=as_int(v["AddressType"][1]) if "AddressType" in v else 1,
                )
            )
        result[amac] = devs
    return result


# ---------------------------------------------------------------- bluez output


def parse_ini(text):
    sections, cur = {}, None
    for line in text.splitlines():
        line = line.strip()
        if line.startswith("[") and line.endswith("]"):
            cur = sections.setdefault(line[1:-1], {})
        elif "=" in line and cur is not None:
            k, v = line.split("=", 1)
            cur[k] = v
    return sections


def dump_ini(sections):
    return "\n".join(
        f"[{s}]\n" + "".join(f"{k}={v}\n" for k, v in kv.items())
        for s, kv in sections.items()
    )


def build_info(dev, existing):
    s = existing
    g = s.setdefault("General", {})
    if dev["name"] and "Name" not in g:
        g["Name"] = dev["name"]
    g["Trusted"] = "true"
    g["Blocked"] = "false"
    if dev["kind"] == "classic":
        g.setdefault("SupportedTechnologies", "BR/EDR;")
        s["LinkKey"] = {"Key": dev["linkkey"].hex().upper(), "Type": "4", "PINLength": "0"}
    else:
        g["AddressType"] = "public" if dev["addrtype"] == 0 else "static"
        g.setdefault("SupportedTechnologies", "LE;")
        s["LongTermKey"] = {
            "Key": dev["ltk"].hex().upper(),
            "Authenticated": "0",
            "EncSize": str(dev["enc"]),
            "EDiv": str(dev["ediv"]),
            "Rand": str(dev["rand"]),
        }
        if dev["irk"]:
            s["IdentityResolvingKey"] = {"Key": dev["irk"].hex().upper()}
        if dev["csrk"]:
            s["LocalSignatureKey"] = {
                "Key": dev["csrk"].hex().upper(),
                "Counter": "0",
                "Authenticated": "false",
            }
    return s


# ---------------------------------------------------------------- main


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--hive")
    ap.add_argument("--device")
    ap.add_argument("--filter")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--yes", action="store_true")
    a = ap.parse_args()

    if os.geteuid() != 0:
        sys.exit("Run with sudo (needs to mount Windows and write /var/lib/bluetooth).")

    mnt = None
    try:
        hive_path = a.hive
        if not hive_path:
            for dev in [a.device] if a.device else find_windows_partition():
                mnt = tempfile.mkdtemp(prefix="winbt-")
                if mount_ro(dev, mnt):
                    hive_path = find_ci(mnt, "Windows", "System32", "config", "SYSTEM")
                    if hive_path:
                        print(f"Using {dev} -> {hive_path}")
                        break
                    subprocess.run(["umount", mnt])
                os.rmdir(mnt)
                mnt = None
            if not hive_path:
                sys.exit("Could not find/mount a Windows partition. Use --device or --hive.")

        # Copy so we never touch the Windows file and can unmount immediately
        tmp = tempfile.NamedTemporaryFile(delete=False)
        shutil.copyfile(hive_path, tmp.name)
        hive = Hive(tmp.name)
        os.unlink(tmp.name)
    finally:
        if mnt:
            subprocess.run(["umount", mnt])
            os.rmdir(mnt)

    if hive.dirty:
        print("WARNING: SYSTEM hive is 'dirty' (has unflushed transaction logs). Recently\n"
              "         paired devices may be missing or have stale keys. If import fails,\n"
              "         boot Windows and do a full shutdown: shutdown /s /t 0\n")

    win = read_devices(hive)
    linux_adapters = [os.path.basename(p) for p in glob.glob("/var/lib/bluetooth/??:??:??:??:??:??")]
    print("Windows adapters:", ", ".join(win) or "none")
    print("Linux adapters:  ", ", ".join(linux_adapters) or "none")

    plan = []
    for amac, devs in win.items():
        target = amac if amac in linux_adapters else None
        if target is None and len(win) == 1 and len(linux_adapters) == 1:
            target = linux_adapters[0]
            print(f"Note: adapter MAC differs ({amac} vs {target}); mapping anyway.")
        if target is None:
            print(f"Skipping Windows adapter {amac}: no matching Linux adapter")
            continue
        for d in devs:
            if a.filter and a.filter.lower() not in f"{d['mac']} {d['name'] or ''}".lower():
                continue
            plan.append((target, d))

    if not plan:
        sys.exit("No devices to import.")
    print("\nDevices to import:")
    for i, (t, d) in enumerate(plan):
        print(f"  [{i}] {d['kind']:7} {d['mac']}  {d['name'] or '(unknown name)'}")

    if a.dry_run:
        for t, d in plan:
            print(f"\n--- /var/lib/bluetooth/{t}/{d['mac']}/info")
            print(dump_ini(build_info(d, {})))
        return

    if not a.yes:
        ans = input("\nImport which? (comma-separated indices, Enter = all, q = quit): ").strip()
        if ans.lower() == "q":
            return
        if ans:
            plan = [plan[int(x)] for x in ans.split(",")]

    stamp = time.strftime("%Y%m%d-%H%M%S")
    for t, d in plan:
        ddir = f"/var/lib/bluetooth/{t}/{d['mac']}"
        info = os.path.join(ddir, "info")
        existing = {}
        if os.path.exists(info):
            shutil.copy2(info, f"{info}.bak-{stamp}")
            existing = parse_ini(open(info).read())
        os.makedirs(ddir, mode=0o700, exist_ok=True)
        with open(info, "w") as f:
            f.write(dump_ini(build_info(d, existing)))
        os.chmod(info, 0o600)
        print(f"Wrote {info}")

    subprocess.run(["systemctl", "restart", "bluetooth"])
    print("\nRestarted bluetooth. Wake the keyboard (press a key); it should connect.\n"
          "If not: bluetoothctl connect <MAC>")


if __name__ == "__main__":
    main()
