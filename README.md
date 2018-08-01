# HarIDSync

HarIDSync is client utility tool to keep your LDAP/AD server updated with HarID data. HarIDSync makes requests from your to HarID JSON API and updates data in your LDAP server.

## Features
  - HarID LDAP/AD sync supports most modern popular LDAP servers including Samba4, OpenLDAP and Active Directory
  - CRUD for LDAP server users and groups

## Production setup on Ubuntu/Debian

Add official repo to your list (not working yet):

```sh
  echo "deb [trusted=yes] https://qUdEFyjXhSAfHTs1UsRw@apt.fury.io/harid/ /" | sudo tee --append /etc/apt/sources.list.d/fury.list
  sudo apt update
```

Intsall HarIDSync

```sh
  sudo apt install haridsync
```

Please read and update settings in `/etc/haridsync/haridsync.yml` 

Congratulation, your LDAP/AD server will be synced by now.

## Production upgrade on Ubuntu/Debian

HaridSync debian package can be updated with following commands: 

```sh
  sudo apt update
  sudo apt upgrade
```

## Manual or demo setup instructions on Ubuntu/Debian

```sh
$ git clone https://github.com/hariduspilv/HarIDSync
$ cd HarIDSync
$ bin/haridsync setup
```

Please read and update settings in `config/haridsync.yml` and then do

```
$ bin/haridsync sync
```

Congratulation, your LDAP/AD server should be synced by now.

## More documentatios

More documentations at doc/documentation.md 

Howto doc for managing API keys in HarID portal:
In English: https://harid.ee/docs/en/how_to_manage_api_users_for_harid_ad_ldap_sync.html
Eesti keeles: https://harid.ee/docs/et/kuidas_lisada_api_kasutaja_harid_ad_ldap_andmevahetuseks.html

Man page in Debian servers
```sh
  man haridsync
```

Command line help in Debian servers:
```sh
  haridsync help
```
