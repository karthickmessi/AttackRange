# AttackRange — Purple Team Detection Lab

A self-built purple-team lab combining offensive penetration testing against a deliberately vulnerable target with defensive detection engineering using Wazuh SIEM. Every attack executed in this project was independently detected, investigated, and — where detection initially failed — remediated through custom detection tooling.

**Author:** Karthickraja S | eJPT Certified | [LinkedIn](https://linkedin.com/in/KARTHICKRAJA2005S) | [Portfolio](https://karthickmessi.github.io)

---

## Why This Project

Most entry-level security projects demonstrate either offensive skills (running exploits) or defensive skills (watching a SIEM dashboard) in isolation. This project connects both sides of the same kill chain: every attack technique executed was traced through to its detection outcome, and where detection failed, a custom solution was engineered to close the gap — rather than just reporting the gap as a limitation.

---

## Architecture

| Component | Tool | Role |
|---|---|---|
| SIEM | Wazuh 4.14.0 (Docker single-node) | Log ingestion, rule-based alerting, dashboard |
| Attacker | Host Linux (Metasploit Framework, Nmap, Hydra) | Recon and exploitation |
| Target | `tleemcjr/metasploitable2` (Docker) | Deliberately vulnerable Linux services |
| Custom Detection | Bash process-monitoring script | Closes a real detection gap (see below) |

Wazuh manager and the vulnerable target run as separate Docker containers on **different Docker networks** (`172.17.0.0/16` for the target, `172.18.0.0/16` for the Wazuh stack), connected via syslog forwarding — this cross-network routing became a significant part of the debugging work (see Detection Engineering section).

---

## Attack Timeline

### Attack 1 — Telnet Brute Force
**MITRE ATT&CK:** T1110 (Brute Force)

- **Recon:** Full-port Nmap scan (`nmap -sV -p- <target>`) identified 20+ open services, including legacy SSH (OpenSSH 4.7p1) and Telnet.
- **Pivot:** Initial brute-force attempt against SSH failed due to a real-world crypto compatibility issue — the target's 2007-era SSH server only supports deprecated key exchange algorithms (`ssh-rsa`, `ssh-dss`) that modern SSH clients refuse to negotiate. Pivoted to Telnet (same MITRE technique, same target concept) to demonstrate T1110 without fighting deprecated cryptography.
- **Execution:** Hydra dictionary attack (`hydra -L usernames.txt -P passwords.txt telnet://<target>`) cracked valid credentials: `msfadmin:msfadmin`.
- **Proof of access:** Logged in via Telnet, confirmed with `whoami`, `id`, `uname -a`.
- **Detection:** Caught by Wazuh's built-in rule **2501** ("syslog: User authentication failure") via forwarded `auth.log` entries — 2 alerts generated (failed + successful login), Level 5.

### Attack 2 — UnrealIRCd 3.2.8.1 Backdoor Exploit
**MITRE ATT&CK:** T1190 (Exploit Public-Facing Application)

- **Recon:** Nmap identified UnrealIRCd running on port 6667.
- **Vulnerability:** UnrealIRCd 3.2.8.1 is a known-backdoored release (the official 2010 download was compromised by attackers) — CVE-2010-2075. Any client can trigger command execution via a magic string sent over the IRC protocol, no authentication required.
- **Execution:** Exploited via Metasploit (`exploit/unix/irc/unreal_ircd_3281_backdoor`), yielding a Meterpreter session.
- **Impact:** Confirmed **root** access (`getuid` → root, `id` → uid=0(root)).
- **Detection:** Initially undetected. See Detection Engineering below — this is the most valuable finding of the project.

### Attack 3 — Post-Exploitation Recon
**MITRE ATT&CK:** T1082 (System Information Discovery), T1033 (System Owner/User Discovery)

- From the root Meterpreter shell obtained in Attack 2, performed standard post-exploitation enumeration: `whoami`, `id`, `/etc/passwd` review, `hostname`, `ifconfig`.
- Demonstrates the natural next step an attacker takes after initial compromise — mapping the environment before further lateral movement or persistence.

---

## Detection Engineering — The Real Work

### Getting Attack 1 detected: cross-Docker-network syslog routing

The vulnerable target runs on a completely different Docker network than Wazuh. Getting its logs to Wazuh required:

1. Configuring the target's legacy `syslogd` to forward `auth,authpriv.*` events to the Docker host gateway.
2. Adding a custom `<remote>` syslog listener block to Wazuh manager's config (`ossec.conf`), since Wazuh only listens for its native agent protocol by default.
3. Debugging with `tcpdump` when the first attempt silently failed — packets were reaching Wazuh's container, but Wazuh was silently dropping them because Docker's inter-network routing rewrites the source IP (packets arrived from the `172.18.0.0/16` gateway, not the target's real `172.17.0.0/16` address), which didn't match the `<allowed-ips>` restriction.
4. Discovering that `docker restart` does not re-run Wazuh's config-mount init step — required a full `stop` / `rm` / `up -d` cycle for config changes to actually take effect.

**Result:** Attack 1 generates 2 confirmed alerts (Wazuh rule 2501, Level 5).

### Discovering and closing a detection gap on Attack 2

After confirming Attack 1 was detected, Attack 2 (the root-access exploit) produced zero alerts — the raw archive log confirmed the exploit simply never touched the Linux authentication subsystem our pipeline was watching. This is a realistic and important finding: exploit-based attacks against vulnerable services often bypass auth-log monitoring entirely, since they don't go through a login flow.

Rather than stop at reporting the gap, I built a custom lightweight process-monitoring script that:
- Polls the target container's process list (`docker top`) every second from the host
- Diffs it against a known-good baseline
- Forwards any newly-spawned process to Wazuh via direct UDP syslog (`logger -n <wazuh-ip> -P 514 -d`)

This successfully caught the exploit's payload process (`./vyIswKBbSaTc`) live, closing the detection gap.

**Tuning note:** the script also flagged `distccd`'s per-connection worker processes as "new" (expected noise from a daemon that spawns a fresh process per connection) — a real false-positive pattern that would need an allow-list in a production deployment.

---

## MITRE ATT&CK Coverage Summary

| Technique | ID | Attack | Detected? |
|---|---|---|---|
| Brute Force | T1110 | Attack 1 | Wazuh rule 2501 |
| Exploit Public-Facing Application | T1190 | Attack 2 | Custom process monitor (after gap found) |
| System Information Discovery | T1082 | Attack 3 | Documented, not separately alerted |
| System Owner/User Discovery | T1033 | Attack 3 | Documented, not separately alerted |

---

## Key Takeaways

- Built and debugged a real SIEM pipeline end-to-end, including a genuinely difficult cross-network routing issue diagnosed with `tcpdump`.
- Found a real detection gap through evidence (not assumption) and engineered a working fix rather than just documenting the limitation.
- Practiced true positive / false positive triage on live, self-generated alerts.
- Adapted attack methodology in real time when the planned technique (SSH brute force) hit a real-world compatibility wall.

## Tools Used
Wazuh 4.14.0, Docker, Metasploit Framework, Nmap, Hydra, tcpdump, Bash

## Skills Demonstrated
SIEM deployment & configuration, log forwarding (syslog), detection rule triage, custom detection engineering, penetration testing, MITRE ATT&CK mapping, Linux networking (Docker bridge networks), root-cause debugging
