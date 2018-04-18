# HarID LDAP/AD sync

HarID LDAP/AD sync is client utility tool to keep your LDAP/AD server updated with HarID data. HarID LDAP/AD sync makes requests from your to HarID JSON API and updates data in your LDAP server.

## Features
  - HarID LDAP/AD sync supports most modern popular LDAP servers including Samba4, OpenLDAP and Active Directory
  - CRUD for LDAP server users and groups

## Instructions on Ubuntu/Debian
### Requirements
  - Ruby (development headers - ruby-dev) and `bundler` gem _- tested with Ruby 2.4.2p198
  - remote or local LDAP server or Windows AD 

### Install HarID LDAP/AD sync

First step is to clone the Gihub project

```sh
$ git clone https://github.com/hariduspilv/HarIDSync
$ cd HarIDSync
```

Run setup command which will install all Ruby dependencies into `.bundle` folder and generates keypair and default configuration file `harid_sync.yml` to `config/` folder.

```sh
$ bin/setup
```

Change generated settings in `config/harid_sync.yml` with valid information. Example is given in `config/harid_sync.yml.dist` file:

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
```

Descriptions:
ldap_base => is where you overwrite users, groups etc.
ldap_bind_dn => is the user on the LDAP server permitted to overwrite your LDAP directory within the defined ldap_base.
ldap_password => is the password for the bind_dn user.
ldap_method => whether to use :ssl, :tls, or :plain (unencrypted)

**NB! Before you can synchronize with HarID portal you must login to HarID and authorize your newly generated public key in HarID portal. Please contact HarID customer support, if you need any help.**

Howto doc for managing API keys in HarID portal:
In English: https://harid.ee/docs/en/how_to_manage_api_users_for_harid_ad_ldap_sync.html
Eesti keeles: https://harid.ee/docs/et/kuidas_lisada_api_kasutaja_harid_ad_ldap_andmevahetuseks.html

```sh
$ bin/harid_sync read_public_key
```

### Usage

To see all script commands just run:

```sh
$ ./bin/harid_sync
```

or use help

```sh
$ ./bin/harid_sync help
```

### How to sync data with HarID portal

Before starting the script please ensure HarID portal HTTPS certificate can be validated by OpenSSL. By default, the script would use OpenSSL CA Bundle (in `/etc/ssl/certs` on most systems), but if for some reason that is not the case, download full certificate chain PEM file from the portal and use  `--server_ca_cert` to specify it's location to the script.

Synchronize with default values from `config/harid_sync.yml` file:

```sh
./bin/harid_sync sync
```

Using command line arguments:

```sh
./bin/harid_sync sync --host harid.ee --username SomEu5eR --secret SecretTok3n --box_private_key key_file.key
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

_Note 3:_ HarID Sync assumes that **UNIX addons** (i.e. `--use-rfc2307`) are present, so do not remove that option.

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
00 06 * * * /bin/bash -l -c './bin/harid_sync sync'
```
or
```sh
00 06 * * * /bin/bash -l -c './bin/harid_sync sync  --host harid.ee --box_private_key key_file.key --username SomEu5eR --secret SecretTok3n'
```
## Instructions on Windows
### AD DC configuration
SSL port 636 must be enabled to use HarID Sync with AD DC. To generate self-signed
certificate follow the instructions here:

http://gregtechnobabble.blogspot.com/2012/11/enabling-ldap-ssl-in-windows-2012-part-1.html

### Install prerequisites
#### Ruby2.1.6 installation
1. Download Ruby2.4.x or Ruby2.4.x(x64) installer from http://rubyinstaller.org/downloads/
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
ruby 2.4.2p198 (2017-09-14 revision 59899) [x86_64-linux]
```

##### Add root certificate to Ruby
https://github.com/oneclick/rubyinstaller/issues/148

#### DevKit installation
HarID Sync depends on some native extensions. Ruby Development Kit must be installed to use them.
1. Download Development Kit `For use with Ruby 2.4 and above (x64 - 64bits only)` from http://rubyinstaller.org/downloads/
2. Extract it to permanent location for example `C:\Ruby24-DevKit-x64`
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

### Install HarID Sync
1. Navigate to system root folder and run command:
 ```
 cd C:/
 git clone https://github.com/hariduspilv/HarIDSync
 ```

2. Install project dependencies by running bundle install in HarID Sync project folder:
 ```
 cd C:/harid_sync
 bundle install --path vendor/bundle
 ```

3. Generate new keyfile by running following command in project folder:
 ```
 ruby bin/harid_sync setup
 ```

4. Add your newly generated HarID Sync public key into HarID portal.
5. Verify settings in `harid_sync.yml`.

### Usage
Try to synchronize data with HarID portal by running command:
 ```
 ruby bin/harid_sync sync
 ```

 or with full filepath:
  ```
  ruby C:\harid_sync\bin\harid_sync sync
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
    C:\harid_sync\bin\harid_sync sync
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
