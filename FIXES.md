# htb-operator — VPN & machine-IP fixes

This is a fork of [`htb-operator`](https://github.com/user0x1337/htb-operator),
based on the **v1.4.3** tag, fixing several problems with
`machine start --start-vpn` on networks where HTB's default **UDP** VPN is
blocked, plus a wrong-IP bug.

Only four source files are changed (see **Files changed** at the bottom); the
diff against upstream v1.4.3 is the contents of this document.

Install this fork with pipx:

```bash
pipx install --force git+https://github.com/z3r0s6/htb-operator-fixed-vpn
```

---

## Symptoms that were fixed

1. **Wrong machine IP.** `htb-operator` reported e.g. `10.129.15.20` while the
   HTB website showed `10.129.15.22`, and it wrote the wrong IP into
   `/etc/hosts`.
2. **`machine start --start-vpn` hung forever** with nothing printed after
   `Machine deployed to lab.` — no spinner, no error, terminal stuck.
3. After adding a timeout, a **working VPN tunnel was killed**: the connection
   came up (`IPv4: 10.10.x.x/23`) but was then terminated because OpenVPN had
   not printed the exact string `Initialization Sequence Completed` in time.
4. **No way to use TCP** for the VPN from `machine start`, even though the
   default UDP transport was blocked on the network.

---

## Changes

### 1. `htbapi/machine.py` — reconcile the machine IP with the authoritative source

**Root cause:** the `machine/active` API endpoint can return a *stale* IP right
after a (re)spawn (an IP left over from a previous spawn). The website reads the
IP from the `machine/profile/{id}` endpoint, which is authoritative. The
original code only fell back to the profile endpoint when `machine/active`
returned **no** IP — it never caught the stale-but-non-null case.

**Fix:** in `ActiveMachineInfo.__init__`, once spawning has finished, always
reconcile against the profile endpoint and prefer the profile IP (the same value
the website shows as the *Target IP Address*). This corrects the reported IP,
the `/etc/hosts` entry, the status panel and the `$HTB_MACHINE_IP` script
variable.

### 2. `command/machine.py` — wait for a real IP, not just `isSpawning == False`

**Root cause:** the spawn-wait loop stopped as soon as `isSpawning` flipped to
`False`, which can happen a moment before HTB finalises the IP.

**Fix:** in `_execute_and_wait_for_ip_assigning`, keep polling while the IP is
still missing/placeholder (`None`, `-`, `Assigning...`), bounded to ~2 minutes
after spawning completes so it can never loop forever.

### 3. `command/vpn.py` — bounded, correct VPN-connection detection

**Root cause:** `start_vpn()` read OpenVPN's output in an *unbounded* loop and
only exited when it saw `Initialization Sequence Completed`. If OpenVPN could
not connect (e.g. UDP blocked), the whole `machine start` flow hung forever.
A first attempt at a fix then over-corrected and **terminated tunnels that had
actually come up** but hadn't printed that exact line yet.

**Fix:**
- Added `import select` and `import time`.
- The VPN read loop now has a **90 s overall timeout** (so it can never hang
  silently). On non-Windows it uses `select()` so the deadline is always
  honoured even when OpenVPN is silent.
- The tunnel is treated as **UP** as soon as **either** condition holds:
  - the tun interface is assigned an IP (`net_addr_v4_add` / `net_addr_v6_add`), **or**
  - OpenVPN prints `Initialization Sequence Completed`.
- Once an IP has been assigned, OpenVPN is **never terminated** (it is a working
  tunnel). After the IP appears, it waits a short grace period (15 s) for the
  completion line, then proceeds regardless.
- OpenVPN is only terminated on a genuine failure: a fatal error, the process
  exiting on its own, or no sign of life at all within the timeout. The failure
  message tells the user to try another VPN server.

### 4. `console/argument_creator.py` — new `--tcp` flag for `machine start`

**Root cause:** `machine start --start-vpn` always downloaded a **UDP** OpenVPN
config. There was no way to request TCP, even though `htb-operator vpn start`
already supported `--tcp`. On networks that block UDP/1337, the VPN never
connected on any server.

**Fix:** added `--tcp` to the `machine start` parser. `VpnCommand` already reads
`args.tcp`, so the flag propagates automatically — no other wiring needed.

```
machine start --id <ID> --start-vpn --tcp
```

---

## Usage after the fixes

Always add `--tcp` if your network blocks UDP:

```bash
# Season / release machines (e.g. Checkpoint, NanoCorp) -> Release Arena server
htb-operator vpn switch --id 680                      # a working Release Arena server
sudo htb-operator machine start --id 909 --update-hosts-file --start-vpn --tcp

# Regular labs / retired machines -> a Machines VIP+ (Labs) server
htb-operator vpn list --labs --only-accessible        # pick an accessible labs server
sudo htb-operator machine start --id <ID> --update-hosts-file --start-vpn --tcp
```

Verify:

```bash
ip -brief addr show | grep tun
htb-operator vpn status
ping -c3 <machine>.htb
```

### VPN-server cheat sheet

| Machine type            | VPN server to use          | `vpn list` flag    |
|-------------------------|----------------------------|--------------------|
| Season / release boxes  | Release Arena              | `--release-arena`  |
| Active labs machines    | Machines VIP+ (Labs)       | `--labs`           |
| Retired machines        | Machines VIP+ (Labs)       | `--labs`           |

- Everything uses OpenVPN; `--tcp` just changes the transport (use it when UDP
  is blocked).
- If the auto-picked server stalls (reaches "Establishing VPN connection..." but
  no `IPv4:` line appears), that server is busy/degraded — switch with
  `vpn switch --id <other-ID>` and retry.

---

## Files changed

| File                              | Change                                                            |
|-----------------------------------|-------------------------------------------------------------------|
| `htbapi/machine.py`               | Reconcile active-machine IP against the authoritative profile IP. |
| `command/machine.py`              | Wait for a real IP, not just `isSpawning == False`.               |
| `command/vpn.py`                  | Bounded VPN wait; treat IP assignment as success; never kill a live tunnel. |
| `console/argument_creator.py`     | Add `--tcp` flag to `machine start`.                              |

Patched against **htb-operator 1.4.3**, Python 3.13.
