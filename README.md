<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->
**Table of Contents**  *generated with [DocToc](https://github.com/thlorenz/doctoc)*

- [Candibox](#candibox)
  - [Features](#features)
  - [Instructions on Ubuntu/Debian](#instructions-on-ubuntudebian)
    - [Requirements](#requirements)
    - [Install Candibox](#install-candibox)
    - [Usage](#usage)
    - [How to sync data with HarID portal](#how-to-sync-data-with-harid-portal)
    - [Installing Samba](#installing-samba)
      - [Configuring Samba](#configuring-samba)
    - [Scheduled updates with CRON](#scheduled-updates-with-cron)
  - [Instructions on Windows](#instructions-on-windows)
    - [AD DC configuration](#ad-dc-configuration)
    - [Install prerequisites](#install-prerequisites)
      - [Ruby2.1.6 installation](#ruby216-installation)
        - [Add root certificate to Ruby](#add-root-certificate-to-ruby)
      - [DevKit installation](#devkit-installation)
      - [Install bundler gem](#install-bundler-gem)
      - [Install Git](#install-git)
    - [Install Candibox](#install-candibox-1)
    - [Usage](#usage-1)
    - [Scheduled updates](#scheduled-updates)
  - [<a name="json_example"></a>HarID JSON API data format](#a-namejson_exampleaharid-json-api-data-format)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# Candibox

Candibox is backend for HarID (previously called Candient) portal. Candibox makes requests to HarID JSON API and updates data in LDAP server by using Ruby scripts.

## Features
  - Candibox supports most modern popular LDAP servers including Samba4, OpenLDAP and Active Directory
  - CRUD for LDAP server users and groups

## Instructions on Ubuntu/Debian
### Requirements
  - Ruby (2.0.x with development headers - ruby-dev) and `bundler` gem _- tested with Ruby 2.1.2p95_
  - remote or local LDAP server or Windows AD DS _- tested with Samba4 (see: [Installing Samba](#installing-samba)) and Windows AD DS_
### Install Candibox
Candibox is available as debian package (see [releases](https://github.com/hitsa/candibox/releases) for further instructions) or read instructions below to install latest unstable version:

First step is to clone the Gihub project

```sh
$ git clone https://github.com/hitsa/candibox
$ cd candibox
```

Run setup command which will install all Ruby dependencies into `.bundle` folder and  generates keypair and default configuration file `candibox.yml` to `config/` folder.

```sh
$ bin/setup
```

Change generated settings in `config/candibox.yml` with valid information. Example is given in `config/candibox.yml.dist` file:

```yml
portal_hostname: example.harid.ee
portal_port: 443
api_user: SomEu5eR
secret: SecretTok3n

#portal_ca_cert: harid.ee.crt
box_key: server.key

# LDAP connection setup
ldap_host: localhost
ldap_port: 636
ldap_method: :ssl
ldap_base: DC=example,DC=com
ldap_bind_dn: CN=Administrator,CN=Users,DC=example,DC=com
ldap_password: Pa$$w0rd
allow_anonymous: false
```

**NB! Before you can synchronize with HarID portal you must ask EENet to authorize your newly generated Candibox public key in HarID portal. Please contact EENet customer support and send them the contents of your public key. Public key is printed out every time you run previously mentioned setup script or use command below:**

```sh
$ bin/candibox read_public_key
```

### Usage

To see all script commands just run:

```sh
$ ./bin/candibox
```

or use help

```sh
$ ./bin/candibox help
```

### How to sync data with HarID portal

Before starting the script please ensure HarID portal HTTPS certificate can be validated by OpenSSL. By default, the script would use OpenSSL CA Bundle (in `/etc/ssl/certs` on most systems), but if for some reason that is not the case, download full certificate chain PEM file from the portal and use  `--server_ca_cert` to specify it's location to the script.

By default candibox uses `config/candibox.yml` settings to synchronize with portal but it also supports use cases where single Samba server is used for multiple HarID subdomains (e.g. as subtrees) and takes portal hostname as well as box private key and username with secret as command line arguments for easier scripting or CRON usage:

Synchronize with default values from `config/candibox.yml` file:

```sh
./bin/candibox sync
```

Using command line arguments:

```sh
./bin/candibox sync --host example.harid.ee --username SomEu5eR --secret SecretTok3n --box_private_key key_file.key
```

<a name="installing-samba"></a>
### Installing Samba

Below examples are based on Debian Jessie, but they are generic enough to be easily adapted for other distributions or operating systems.

Ensure the package manager has access to **Samba 4**:

```
apt-get install samba smbclient
```

#### Configuring Samba

Samba 4 comes with a _provisioning_ tool **samba-tool domain provision** that does most of the heavy lifting. Only thing left is to put together a correct command line.

On Debian, Samba installs preconfigured, but we need to reconfigure it, so stop samba service and remove default conf:

```
service smbd stop
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

```sh
samba-tool domain provision --use-rfc2307 --dns-backend=SAMBA_INTERNAL --server-role=dc --option="interfaces=lo eth0" --option="bind interfaces only=yes" --option="dns forwarder = 192.168.0.1" --option="tls enabled = yes" --adminpass='Pa$$w0rd' --realm='example.com' --domain='example'
```

Above command configures Samba with LDAP suffix: **DC=example,DC=com** (with NETBIOS domain _EXAMPLE_), uses internal DNS server as backend and adds **UNIX addons** to the schema.

**NB! By default Samba 4 has password expiration set to 42 days. To turn off password expiration to all users run the following command:**

```sh
samba-tool domain passwordsettings set --min-pwd-age=0 --max-pwd-age=0
```

or disable expiry for administrator account only:

```sh
samba-tool user setexpiry Administrator --noexpiry
```

And don't forget to start samba server

```sh
service samba-ad-dc start
```


### Scheduled updates with CRON

Add cron job
```sh
00 06 * * * /bin/bash -l -c './bin/candibox sync'
```
or
```sh
00 06 * * * /bin/bash -l -c './bin/candibox sync  --host example.harid.ee --box_private_key key_file.key --username SomEu5eR --secret SecretTok3n'
```
## Instructions on Windows
### AD DC configuration
SSL port 636 must be enabled to use candibox with AD DC. To generate self-signed
certificate follow the instructions here:

http://gregtechnobabble.blogspot.com/2012/11/enabling-ldap-ssl-in-windows-2012-part-1.html

### Install prerequisites
#### Ruby2.1.6 installation
1. Download Ruby2.1.6 or Ruby2.1.6(x64) installer from http://rubyinstaller.org/downloads/
2. Run installer
3. Select language
4. Agree with terms
5. Select option `Add Ruby executables to your PATH`
6. Select option `Associate .rb and .rbw files with this Ruby installation`
7. Finish installation
8. Test Ruby by running following command in CMD:
```
ruby -v
```
Result should be something like:
```
ruby 2.1.6p336 (2015-04-13 revision 50298) [x64-mingw32]
```

##### Add root certificate to Ruby
https://github.com/oneclick/rubyinstaller/issues/148

#### DevKit installation
Candibox depends on some native extensions. Ruby Development Kit must be installed to use them.
1. Download Development Kit `For use with Ruby 2.0 and above (x64 - 64bits only)` from http://rubyinstaller.org/downloads/
2. Extract it to permanent location for example `C:\Ruby21-DevKit-x64`
3. In CMD navigate to extracted development kit folder and run the following commands:

 ```
 ruby dk.rb init
 ruby dk.rb install
 ```

#### Install bundler gem
1. In CMD run the following command:
 ```
 gem install bundler
 ```

#### Install Git
Install git to be able to use gems from git repositories.
1. Download installer from http://msysgit.github.io/
2. Select option `Use Git from the Windows Command Prompt`
3. Rest of the options use default settings
4. After installation restart CMD

### Install Candibox
1. Navigate to system root folder and run command:
 ```
 cd C:/
 git clone https://github.com/hitsa/candibox.git
 ```

2. Install project dependencies by running bundle install in candibox project folder:
 ```
 cd C:/candibox
 bundle install --path vendor/bundle
 ```

3. Generate new keyfile by running following command in project folder:
 ```
 ruby bin/candibox setup
 ```

4. Ask EENet to authorize your newly generated Candibox public key in HarID portal.
5. Verify settings in `config.yml`.

### Usage
Try to synchronize data with HarID portal by running command:
 ```
 ruby bin/candibox sync
 ```

 or with full filepath:
  ```
  ruby C:\candibox\bin\candibox sync
  ```

### Scheduled updates
  * Greate new task with `Task Scheduler`
  * Navigate to `General` tab. Add task name and description and select option:

    `Run whether user is logged or not`
  * Navigate to `Triggers` tab and create new trigger. It is recommended to set
  synchronization to be triggered daily basis repeated every 5 minutes.
  * Navigate to `Action` tab and create new action.

    * Select action type `Start a program`

    * Type to `Program/script` field:
    ```
    ruby
    ```

    * Add arguments:
    ```
    C:\candibox\bin\candibox sync
    ```
  And you're good to go.

## <a name="json_example"></a>HarID JSON API data format

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


[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/hitsa/candibox/trend.png)](https://bitdeli.com/free "Bitdeli Badge")

