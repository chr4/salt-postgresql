# Major upgrades with logical replication

## Enable `logical` replication mode, restart required.

```bash
# Make sure no failover is happening while restarting for logical replication (DOWNTIME!)
sudo touch /run/keepalived-manual-failover

# /etc/postgresql/11/main/postgresql.conf
wal_level = 'logical'

sudo systemctl restart postgresql
```


## Disable WAL archive uploading on the new replica

Disable `archive_command` on the new instance, so WAL archives are not uploaded until we know that everything works.

```
# If archive_command is an empty string (the default) while archive_mode is
# enabled, WAL archiving is temporarily disabled, but the server continues to
# accumulate WAL segment files in the expectation that a command will soon be
# provided.
archive_mode = on
archive_command = ''

# Adjust configuration options that have changed (old: wal_keep_segments = 32)
wal_keep_size = 512
```


## Export and import schema

```bash
# Export schema on old database
pg_dumpall -U postgres -s > schema.sql

# Import schema into new database
psql -U postgres -d triebwerk -f schema.sql
```


## OPTIONAL: Possible tuning parameters for the initial sync (see [docs](https://www.postgresql.org/docs/current/runtime-config-replication.html):

```bash
# The values here are the defaults
max_logical_replication_workers = 4
max_sync_workers_per_subscription = 2

# max_wal_size can be increased (e.g. from 3GB to 20GB during replication) on the fly when the warnings appear in the logs.
```


## Create publication (on the primary)

*NOTE: I had to use `postgres` user for replication (after adapting `pg_hba.conf` accordingly) to prevent permission denied errors: `ERROR:  permission denied for table`.*


### PostGIS

There are errors copying `spatial_ref_sys` and other GIS tables. This is something we need to exclude as it is a postgis table that should be created with `CREATE EXTENSION` anyway (it should be read-only). Therefore, we're only replicating tables from `schema.sql`:

```bash
echo "CREATE PUBLICATION migrate_pg13_triebwerk FOR TABLE $(grep 'CREATE TABLE' schema.sql | cut -d\. -f2 | awk '{ print $1 }' | paste -sd "," -);"
```


## Create subscription (on the replica)

```sql
-- I had to use postgres user, as "replication" permission doesn't seem to be enough
CREATE SUBSCRIPTION migrate_pg13_triebwerk CONNECTION 'host=master.postgresql.production.io.ki dbname=triebwerk user=postgres' PUBLICATION migrate_pg13_triebwerk;

-- Check replication status
SELECT * FROM pg_stat_subscription;

-- In case you need to remove the subscription again, the replication slot might need to be dropped on the primary
SELECT pg_drop_replication_slot('migrate_pg13_triebwerk');
```

Then get a good coffee wait for the replica to catch up...


## Migrate to the new instance

- [ ] Restart postgresql on the third instance (to make sure it `listen`s)
- [ ] Stopping `keepalived` on the third instance
- [ ] Stop `keepalived` on the old replica instance
- [ ] Start `keepalived` on the third instance
- [ ] Enable WAL archiving
- [ ] Stop `haproxy`
- [ ] Promote third instance (by stopping postgresql primary)
- [ ] Adapt sequences on replica (see below)
- [ ] Deploy original `postgresql.conf` with correct `wal_level`, `archive_mode`, etc. once it's working (restart might be necessary)
- [ ] Remove subscription from new primary
  ```sql
  ALTER SUBSCRIPTION migrate_pg13_triebwerk DISABLE;
  ALTER SUBSCRIPTION migrate_pg13_triebwerk SET (slot_name = NONE);
  DROP SUBSCRIPTION migrate_pg13_triebwerk;
  DROP PUBLICATION migrate_pg13_triebwerk;
  ```
- [ ] Check whether replication and wal archives work
- [ ] Doublecheck that keepalived scripts have version 13
- [ ] Re-create old replica instance with pg-13, resync
- [ ] Re-create old master instance with pg-13, resync
- [ ] Failover to one of the newly created instances
- [ ] Re-attach (might work without a sync) the other new instance to new master
- [ ] Delete third instance
- [ ] Create a new `pg_basebackup`


# Limitations

Some [Limitations in PostgreSQL Logical Replication](https://hevodata.com/learn/postgresql-logical-replication/)

- It doesn’t replicate the schema or DDL.
- It doesn’t replicate sequences.
- Tables must have a primary key or unique key to participate in the PostgreSQL logical replication process.
- It doesn’t replicate truncate.
- Bi-directional replication is not supported.
- Large objects are not replicated using PostgreSQL logical replication.

And [some more](https://severalnines.com/database-blog/overview-logical-replication-postgresql)

- Tables must have the same full qualified name between publication and subscription.
- Tables must have primary key or unique key
- Mutual (bi-directional) Replication is not supported
- Does not replicate schema/DDL
- Does not replicate sequences
- Does not replicate TRUNCATE
- Does not replicate Large Objects
- Subscriptions can have more columns or different order of columns, but the types and column names must match between Publication and Subscription.
- Superuser privileges to add all tables
- You cannot stream over to the same host (subscription will get locked).


Also [at least 10 might have this](https://www.2ndquadrant.com/en/blog/logical-replication-postgresql-10/)

> When new tables are added to the publication, the subscription will not learn about them automatically, and so they will not be replicated. To replicate them we need to run a command which updates the subscription’s idea about what tables are published:

`ALTER SUBSCRIPTION testsub REFRESH PUBLICATION;`


As well as this from the official docs:

> Only persistent base tables and partitioned tables can be part of a publication. Temporary tables, unlogged tables, foreign tables, materialized views, and regular views cannot be part of a publication.


Replication also stops when other parts of the schema are added, e.g. adding a new column is enough.

The link above has some workarounds here, mainly `ALTER TABLE` statements need to be issued on the replica manually :( bu then replication can be picked up again it seems.


# Workarounds

pg_dash also has some workarounds for sequences and schema changes: https://pgdash.io/blog/postgres-replication-gotchas.html


## Sequences

Sequences are not replicated, therefore the `nextval` of those needs to be migrated manually. The following query might help identifying those sequences and their `last_value`:

```sql
SELECT schemaname AS schema, sequencename AS sequence, last_value FROM pg_sequences
```

The sequences in the database can be grepped from `schema.sql`:

```bash
grep 'CREATE SEQUENCE' schema.sql | cut -d\. -f2
```


```sql
-- Set all sequences to max id + 1000, so they continue properly without causing duplicates
SELECT setval('actors_id_seq', (SELECT MAX(id) + 1000 FROM actors));
SELECT setval('actors_roles_id_seq', (SELECT MAX(id) + 1000 FROM actors_roles));
SELECT setval('admins_products_id_seq', (SELECT MAX(id) + 1000 FROM admins_products));
SELECT setval('admins_providers_id_seq', (SELECT MAX(id) + 1000 FROM admins_providers));
SELECT setval('clients_products_id_seq', (SELECT MAX(id) + 1000 FROM clients_products));
SELECT setval('permissions_id_seq', (SELECT MAX(id) + 1000 FROM permissions));
SELECT setval('permissions_roles_id_seq', (SELECT MAX(id) + 1000 FROM permissions_roles));
SELECT setval('platforms_products_id_seq', (SELECT MAX(id) + 1000 FROM platforms_products));
SELECT setval('platforms_providers_id_seq', (SELECT MAX(id) + 1000 FROM platforms_providers));
SELECT setval('products_webhooks_id_seq', (SELECT MAX(id) + 1000 FROM products_webhooks));
SELECT setval('ride_payment_recoveries_rides_id_seq', (SELECT MAX(id) + 1000 FROM ride_payment_recoveries_rides));
SELECT setval('roles_id_seq', (SELECT MAX(id) + 1000 FROM roles));
SELECT setval('versions_id_seq', (SELECT MAX(id) + 1000 FROM versions));
```


## Tables without primary keys

*NOTE: The backend team has eliminated all tables without primary keys. This shouldn't be relevant anymore*

This happens a lot with helper tables like `clients_products` and can lead to errors when deleting items from a table with the following:

```
HINT:  To enable deleting from the table, set REPLICA IDENTITY using ALTER TABLE.
```

```bash
# grep all tables without proper primary keys
rg --multiline 'create table.*\n.*' | rg --multiline -v '.*\n.*\sid\s.*' | rg 'create table' | awk '{ print $3 }'
```
