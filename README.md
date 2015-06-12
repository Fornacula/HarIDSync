# Candibox

Candibox is backend for HarID (previously called Candient) portal. Candibox makes requests to HarID JSON API and updates data in LDAP server by using Ruby scripts.

## Features
  - Candibox supports most modern popular LDAP servers including Samba4, OpenLDAP and Active Directory
  - CRUD for LDAP server users and groups

## Requirements
  - Ruby (2.0.x) and `bundler` gem _- tested with Ruby 2.1.2p95_
  - remote or local LDAP server _- tested with Samba4_(see: [Installing Samba](#installing-samba))

## Installation

First step is to clone the Gihub project

```sh
$ git clone https://github.com/hitsa/candibox
$ cd candibox
```
Make a copy of _candibox.yml.dist_ file in `config/` folder and rename it to  _candibox.yml_. Change example settings with valid information:

```yml
portal_hostname: 'example.harid.ee'
portal_port: 443

#portal_ca_cert: 'harid.ee.crt'
box_cert: 'server.crt'
box_key: 'server.key'

# LDAP connection setup
ldap_host: localhost
ldap_port: 636
ldap_method: :ssl
ldap_base: dc=example,dc=com
ldap_bind_dn: cn=Administrator,cn=Users,dc=example,dc=com
ldap_password: Pa$$w0rd
allow_anonymous: false
```

Run setup script which will install all Ruby dependencies into `.bundle` folder and generates self-signed SSL certificate to `certs/` folder

```sh
$ bin/setup
```
**NB! Before you can synchronize with HarID portal you must ask EENet to authorize your newly generated Candibox certificate in HarID portal. Please contact EENet customer support and send them the contents of your certificate file.**

## Usage

To see all script commands just run:
```sh
$ ./bin/candibox_sync
```

or use help

```sh
$ ./bin/candibox_sync help
```

### How to sync data with HarID portal

Before starting the script please ensure HarID portal HTTPS certificate can be validated by OpenSSL. By default, the script would use OpenSSL CA Bundle (in `/etc/ssl/certs` on most systems), but if for some reason that is not the case, download full certificate chain PEM file from the portal and use  `--server_ca_cert` to specify it's location to the script.

By default candibox uses `config/candibox.yml` settings to synchronize with portal but it also supports use cases where single Samba server is used for multiple HarID subdomains (e.g. as subtrees) and takes portal hostname as well as box private key and certificate as command line arguments for easier scripting or CRON usage:

Synchronize with default values from `config/candibox.yml` file:
```sh
./bin/candibox_sync ldap_sync
```

Using command line arguments:
```sh
./bin/candibox_sync ldap_sync --host example.harid.ee --box_cert cert.crt --box_private_key key_file.key
```

### How to sync data by using JSON file

Make sure that JSON includes all the mandatory attributes (see [example below](#json_example)) and give full path to file as an argument:

```sh
$ ./bin/candibox_sync  ldap_sync --file path/to/file/json_file.json
```

<a name="installing-samba"></a>
## Installing Samba

Below examples are based on Debian Wheezy, but they are generic enough to be easily adapted for other distributions or operating systems.

First, ensure the package manager has access to **Samba 4**:

```
echo "deb http://http.debian.net/debian wheezy-backports main" > /etc/apt/sources.list.d/backports.list
apt-get update
```

Then install Samba 4 with required tools:

```
aptitude -t wheezy-backports install samba smbclient
```

### Configuring Samba

Samba 4 comes with a _provisioning_ tool **samba-tool domain provision** that does most of the heavy lifting. Only thing left is to put together a correct command line.

On Debian, Samba installs preconfigured, but we need to reconfigure it, so remove default conf:

```
mv /etc/samba/smb.conf /etc/samba/smb.conf.dist
```

_Note 1:_ For Samba to bind to correct network interfaces, be sure to include these options with correct values:

```
--option="interfaces=lo eth0" --option="bind interfaces only=yes"
```

_Note 2:_ Samba server must be **DNS server for the LAN and to itself**, so it needs to be told a correct IP address to forward DNS requests outside of Samba domain. Usually network _router_ IP would be a good choice:

```
--option="dns forwarder = 192.168.0.1"
```

and set samba server's own nameserver to local IP

```
# file: /etc/resolv.conf
domain example.com
nameserver AA.BB.CC.DD
``` 

_Note 3:_ Candibox assumes that **UNIX addons** (i.e. `--use-rfc2307`) are present, so do not remove that option.

**NB!** Samba refuses to complete provisioning if Administrator does not meet these requirements (this can be eased later on, but for first install, it is reqired:

  * at least 8 characters
  * contains at least **3** of these character classes:
    - lower chars
    - upper chars
    - numbers
    - symbols

An example of full provisioning is below. Be sure to **adjust** it to your configuration:

```
samba-tool domain provision --use-rfc2307 --dns-backend=SAMBA_INTERNAL --server-role=dc --option="interfaces=lo eth0" --option="bind interfaces only=yes" --option="dns forwarder = 192.168.0.1" --option="tls enabled = yes" --adminpass='Pa$$w0rd' --realm='example.com' --domain='example'
```

Above command configures Samba with LDAP suffix: **DC=example,DC=com** (with NETBIOS domain _EXAMPLE_), uses internal DNS server as backend and adds **UNIX addons** to the schema.

And don't forget to start samba server

```
service samba start
```


## Examples

### Scheduled updates with CRON

Add cron job
```sh
00 06 * * * /bin/bash -l -c './bin/candibox_sync ldap_sync  --host domain_base.harid.ee --box_cert cert.crt --box_private_key key_file.key
```
or
```sh
00 06 * * * /bin/bash -l -c './bin/candibox_sync ldap_sync  --host domain_base.harid.ee --box_cert cert.crt --box_private_key key_file.key --server_ca_cert harid.ee.crt'
```

### <a name="json_example"></a>JSON data format

```json
{
  "users": [
    {
      "uid": "fiona",
      "uid_number": 5,
      "gid_number": 155,
      "first_name": "Fiona",
      "last_name": "Nahk",
      "homedir": "",
      "shell": "",
      "active": true,
      "primary_phone": "0491 570 156",
      "phone_numbers": [ "0491 570 156", "0491 570 157", "0491 570 158" ],
      "primary_email": "fiona@example.com",
      "email_addresses":[ "fiona@example.com", "Fiona.Nahk@example.com" ],
      "updated_at": "2015-01-22T12:51:19.746Z"
    },
    {
      "uid": "marko",
      "uid_number": 109,
      "gid_number": 10,
      "first_name": "Marko",
      "last_name": "Keskus",
      "homedir": "",
      "shell": "",
      "active": true,
      "phone_numbers": null,
      "email_addresses": ["Marko.Keskus@example.com"],
      "updated_at": "2015-01-22T12:51:19.746Z"
    },
    {
      "uid": "peeter",
      "uid_number": 100,
      "gid_number": 10,
      "first_name": "Peeter",
      "last_name": "Kask",
      "homedir": "",
      "shell": "",
      "active": true,
      "phone_numbers": null,
      "primary_email": "Peeter.Kask@example.com",
      "email_addresses": ["Peeter.Kask@example.com", "peeterkask@example.com"],
      "updated_at": "2015-01-22T12:51:19.746Z"
    },
    {
      "uid": "ester",
      "uid_number": 12,
      "gid_number": 12,
      "first_name": "Ester",
      "last_name": "Tester",
      "homedir": null,
      "shell": null,
      "active": true,
      "phone_numbers": null,
      "primary_email": "ester.tester@example.com",
      "email_addresses": ["ester.tester@example.com"],
      "updated_at": "2015-01-22T12:51:57.087Z"
    }
  ],
  "groups": [
    {
      "name": "fax_machines",
      "gid_number": 101,
      "description": "Members of this groups have access to fax machines",
      "active": true,
      "updated_at": "2015-01-22T18:21:31.596Z",
      "created_at": "2015-01-22T18:21:09.782Z",
      "member_uids": []
    },
    {
      "name": "printers",
      "gid_number": 102,
      "description": "Group for printer users",
      "active": true,
      "updated_at": "2015-01-21T10:27:47.283Z",
      "created_at": "2015-01-21T10:27:47.283Z",
      "member_uids": [
        "peeter"
      ]
    }
  ],
  "deleted_users": [
    {
      "uid": "marko",
      "uid_number": 109
    },
    {
      "uid": "fiona",
      "uid_number": 12
    }
  ],
  "deleted_groups": [
    {
      "name": "fax_machine",
      "gid_number": 12
    },
    {
      "name": "1st_floor_printers",
      "gid_number": 133
    },
    {
      "name": "printers",
      "gid_number": 102
    }
  ]
}
```
