# postgresql salt formula

This formula installs and configures postgresql.


## States

### init.sls

Install and configure postgresql.


### repository.sls

Configure official PostgreSQL repository.


### postgis.sls

Install the PostGIS extention.


#### sysctl.sls

Configure sysctls according to the PostgreSQL best practises.


## Pillars

Some states require settings set in the salt-pillar.
See [pillar.example](pillar.example) for an example pillar file.
