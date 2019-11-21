## Vault with SoftHSM

This is a Vagrant setup to sandbox a Vault Enterprise+HSM setup with SoftHSMv2, an open source software-based HSM that uses the PKCS#11 standard interface.

## Automatic process

There are two scripts:

`setup_softhsm.sh`: This will install the correct packages, and initialize a virtual slot we will use for Vault
`setup_vault.sh`: This will download the trial Vault Enterprise HSM binary and configure it with systemd

**NOTE: As this is an Enterprise trial, it will auto-seal after 30 minutes unless given a valid license key**

Resources

* https://www.vaultproject.io/docs/enterprise/hsm/index.html
* https://www.vaultproject.io/docs/enterprise/hsm/configuration.html
* https://www.opendnssec.org/softhsm/
* https://github.com/opendnssec/SoftHSMv2

## Manual Process steps

### Install SoftHSM

The required packages for Vault HSM on Debian 9 are libltdl7, libsofthsm2, and softhsm2; install them like this:

```
$ sudo apt-get update && sudo apt-get install -y libltdl7 libsofthsm2 softhsm2
```

It's also quite handy to have PKCS related tools such as pkcs11-tool when debugging issues; you can optionally install this tool as part of the opensc package:

```
$ sudo apt-get install -y opensc
```

The SoftHSM PKCS#11 shared library will be installed to /usr/lib/softhsm by default on Debian, and you can do a quick verification of its presence to ensure that it's where we expect it to be:

```
$ ls -lh /usr/lib/softhsm/
total 2.7M
-rw-r--r--.  1 root root 2.0M Feb 12  2017 libsofthsm2.a
-rw-r--r--.  1 root root 691K Feb 12  2017 libsofthsm2.so
```

Here we note that our Cryptoki shared library file libsofthsm2.so; your file could be named either libsofthsm.so or softhsm.so and be located elsewhere depending on OS distribution.

Make sure that you locate it and note its full path for later use.

Now that you have the required software installed, you'll need to establish a minimal SoftHSM configuration and initialize a token in the slot that you'll use with Vault; first create a directory for the SoftHSM data:

```
$ sudo mkdir -p /var/lib/softhsm/tokens/
```

Next, create a basic SoftHSM configuration file:

```
$ sudo mkdir -p /var/lib/softhsm/tokens/
$ sudo tee /etc/softhsm/softhsm2.conf <<EOF
# SoftHSM v2 configuration file
directories.tokendir = /var/lib/softhsm/tokens/
objectstore.backend = file
# ERROR, WARNING, INFO, DEBUG
log.level = DEBUG
EOF
```

Using the softhsm2-util tool, let's now take a moment to examine the current state of our shiny new software based HSM:

```
$ softhsm2-util --show-slots
Available slots:
Slot 0
    Slot info:
        Description:      SoftHSM slot ID 0x0
        Manufacturer ID:  SoftHSM project
        Hardware version: 2.2
        Firmware version: 2.2
        Token present:    yes
    Token info:
        Manufacturer ID:  SoftHSM project
        Model:          SoftHSM v2
        Hardware version: 2.2
        Firmware version: 2.2
        Serial number:
        Initialized:      no
        User PIN init.:   no
        Label:
```

Let's use softhsm2-util to initialize a new token in slot 0 for use with Vault:

```
$ sudo softhsm2-util --init-token --slot 0 --label "hsm_demo" --pin 1234 --so-pin asdf
```

Now our slots look like this, with the newly initialized slot 0, which is now actually referred to as slot 112253752 but with the same hsm_example label we originally defined, and the original empty slot 0 is now occupying the slot 1 location:

```
$ softhsm2-util --show-slots
Slot 112253752
    Slot info:
        Description:      SoftHSM slot ID 0x6b0db38
        Manufacturer ID:  SoftHSM project
        Hardware version: 2.2
        Firmware version: 2.2
        Token present:    yes
    Token info:
        Manufacturer ID:  SoftHSM project
        Model:          SoftHSM v2
        Hardware version: 2.2
        Firmware version: 2.2
        Serial number:    2fb8da6586b0db38
        Initialized:      yes
        User PIN init.:   yes
        Label:          hsm_example
Slot 1
    Slot info:
        Description:      SoftHSM slot ID 0x1
        Manufacturer ID:  SoftHSM project
        Hardware version: 2.2
        Firmware version: 2.2
        Token present:    yes
    Token info:
        Manufacturer ID:  SoftHSM project
        Model:          SoftHSM v2
        Hardware version: 2.2
        Firmware version: 2.2
        Serial number:
        Initialized:      no
        User PIN init.:   no
```

So that looks good; note the new slot value as we'll need that when configuring Vault.

### Vault Enterprise + HSM Configuration

We'll be using the most minimal non-developer-mode Vault configuration possible for this guide, which is to run the Vault server with the file storage backend for all Vault data, while also specifying the required HSM configuration.

Here's an example minimal Vault HSM configuration; make sure to use the correct value for slot as shown in the `softhsm2-util --show-slots` command output and the correct path your libsofthsm2.so file.

```
$ VAULT_HSM_SLOT=$(softhsm2-util --show-slots | grep "^Slot " | head -1 | cut -d " " -f 2)

$ mkdir -p /etc/vault/
$ sudo cat << EOF > /etc/vault/config.hcl
listener "tcp" {
  address = "127.0.0.1:8200"
  tls_disable = "true"
}

storage "file" {
  path = "/home/vault/data"
}

seal "pkcs11" {
  lib            = "/usr/lib/softhsm/libsofthsm2.so"
  slot           = "${VAULT_HSM_SLOT}"
  pin            = "1234"
  key_label      = "hsm_demo"
  hmac_key_label = "hmac-key"
  generate_key   = "true"
}
EOF

sudo cat << EOF > /etc/systemd/system/vault.service
[Unit]
Description=vault agent
Requires=network-online.target
After=network-online.target
[Service]
Restart=on-failure
User=root
Group=root
PermissionsStartOnly=true
ExecStart=/usr/local/bin/vault server -config /etc/vault/config.hcl
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT
[Install]
WantedBy=multi-user.target
EOF

$ sudo chmod 0644 /etc/systemd/system/vault.service

$ systemctl daemon-reload

$ service vault start

$ service vault status
● vault.service - vault agent
   Loaded: loaded (/etc/systemd/system/vault.service; disabled; vendor preset: enabled)
   Active: active (running) since Thu 2019-11-21 19:31:20 UTC; 6min ago
  Process: 3750 ExecStartPre=/sbin/setcap cap_ipc_lock=+ep /usr/local/bin/vault (code=exited, status=0/SUCCESS)
 Main PID: 3751 (vault)
    Tasks: 9 (limit: 4915)
   CGroup: /system.slice/vault.service
           └─3751 /usr/local/bin/vault server -config /etc/vault/config.hcl

expiration_time="2019-11-21 20:01:21 +0000 UTC" time_left=29m0s
Nov 21 19:33:20 debian-9 vault[3751]: 2019-11-21T19:33:20.610Z [WARN]  core.licensing: core: licensing warning: expiration_time="2019-11-21 20:01:21 +0000 UTC" time_left=28m0s
```


Initialize Vault using a special set of command line flags for use with HSM:

```
$ vault operator init -recovery-shares=1 \ recovery-threshold=1
Recovery Key 1: A63tTM9+OzxA9t1x5JOJ4WoDJt3xCQDUaiLgHin3xXI=

Initial Root Token: s.M5NklwwKZgyBezgJ6oLFuXJH

Success! Vault is initialized
```

You’ll note that instead of an unseal key, a recovery key is issued when using an HSM.
