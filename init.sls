{% set version = salt['pillar.get']('postgresql:version', 11) %}

# Install postgresql
postgresql:
  pkg.installed:
     - pkgs: [postgresql-{{ version }}]
  service.running:
    - enable: true
    - reload: {{ pillar['postgresql']['reload']|default('true') }}
    - watch:
      - file: /etc/postgresql/{{ version }}/main/*

# Install additional custom packages
{% if pillar['postgresql']['additional_dependencies'] is defined %}
postgresql_additional_dependencies:
  pkg.installed:
    - pkgs: {{ pillar['postgresql']['additional_dependencies'] }}
{% endif %}

# Make sure data directory is owned by postgres (necessary when using seperate mountpoint)
chown_pgdata:
  file.directory:
    - name: /var/lib/postgresql
    - user: postgres
    - group: postgres

# Deploy certificates
{% for file, _ in salt['pillar.get']('postgresql:certificates', {})|dictsort %}
/var/lib/postgresql/{{ version }}/main/{{ file }}:
  file.managed:
    - require:
      - pkg: postgresql
    - mode: 600
    - user: postgres
    - group: postgres
    - contents_pillar: postgresql:certificates:{{ file }}
{% endfor %}

# Deploy configuration
/etc/postgresql/{{ version }}/main/postgresql.conf:
  file.managed:
    - require:
      - pkg: postgresql
    - mode: 644
    - user: postgres
    - group: postgres
    - source: salt://{{ tpldir }}/postgresql.conf.jinja
    - template: jinja
    - defaults:
      config:
        # Default settings of the postgresql package from PGDG
        cluster_name: {{ version }}/main
        data_directory: /var/lib/postgresql/{{ version }}/main
        datestyle: iso, mdy
        default_text_search_config: pg_catalog.english
        dynamic_shared_memory_type: posix
        external_pid_file: /var/run/postgresql/{{ version }}-main.pid
        hba_file: /etc/postgresql/{{ version }}/main/pg_hba.conf
        ident_file: /etc/postgresql/{{ version }}/main/pg_ident.conf
        include_dir: conf.d
        lc_messages: C.UTF-8
        lc_monetary: C.UTF-8
        lc_numeric: C.UTF-8
        lc_time: C.UTF-8
        log_line_prefix: '%m [%p] %q%u@%d '
        log_timezone: localtime
        max_connections: 100
        max_wal_size: 1GB
        min_wal_size: 80MB
        port: 5432
        shared_buffers: 128MB
        ssl: on
        ssl_cert_file: /etc/ssl/certs/ssl-cert-snakeoil.pem
        ssl_key_file: /etc/ssl/private/ssl-cert-snakeoil.key
        stats_temp_directory: /var/run/postgresql/{{ version }}-main.pg_stat_tmp
        timezone: localtime
        unix_socket_directories: /var/run/postgresql

    # Overwrite default options and add additional ones according to pillar
    - context:
{% if salt['pillar.get']('postgresql:config', undefined) is defined %}
      config_override:
  {% for key, value in pillar['postgresql']['config']|dictsort %}
        # Strings will be escaped with '' in postgresql.conf.jinja
        # It's ok to escape enums as well, also it's ok to use True and False as booleans
        #
        # https://www.postgresql.org/docs/11/config-setting.html
        {{ key }}: {{ value }}
  {% endfor %}

{% else %}
      # Make sure config_override is present when no options are defined by pillar
      config_override: {}
{% endif %}

/etc/postgresql/{{ version }}/main/pg_hba.conf:
  file.managed:
    - mode: 640
    - user: postgres
    - group: postgres
    - source: salt://{{ tpldir }}/pg_hba.conf.jinja
    - template: jinja
    - require:
      - pkg: postgresql

# Deploy users. Sort them, so order is not changing between salt runs
{% for config in pillar['postgresql']['users']|default({}) %}
{% set index = loop.index %}

createuser-{{ index }}:
  postgres_user.present:
    - name: {{ config['username'] }}
    - encrypted: True
    - login: {{ config['login']|default(true) }}
    {% if config['password'] is defined %}
    - password: {{ config['password'] }}
    {% endif %}
    - superuser: {{ config['superuser']|default(false) }}
    - createdb: {{ config['createdb']|default(false) }}
    - createroles: {{ config['createroles']|default(false) }}
    - inherit: {{ config['inherit']|default(true) }}
    - replication: {{ config['replication']|default(false) }}
    {% if config['groups'] is defined %}
    - groups:
    {% for group in config['groups']|default({}) %}
        - {{ group }}
    {% endfor %}
    {% endif %}
    - user: postgres

# The "replication" and "all" keywords are not real databases but special keywords used for permissions in pg_hba.conf
{% if config['database'] != "replication" and config['database'] != 'all' %}

# Do not create table for read-only users, assume it's there already
{% if not config['read_only']|default(false) %}
createdb-{{ index }}:
  postgres_database.present:
    - name: {{ config['database'] }}
    - owner: {{ config['db_owner']|default(config['username']) }}
    {% if config['tablespace'] is defined %}
    - tablespace: {{ config['tablespace'] }}
    {% endif %}
    {% if config['encoding'] is defined %}
    - encoding: {{ config['encoding'] }}
    {% endif %}
    {% if config['template'] is defined %}
    - template: {{ config['template'] }}
    {% endif %}
    - user: postgres

{% endif %}
{% endif %}

# Create extensions
{% for extension in config['extensions']|default([]) %}
extension_{{ config['database'] }}_{{ extension }}_{{ index }}:
  postgres_extension.present:
    - name: {{ extension }}
    - maintenance_db: {{ config['database'] }}
    - if_not_exists: true
{% endfor %}


# Grant read-only permissions to database if read_only flag is set
{% if config['read_only']|default(false) %}

# Revoke default CREATE privilege. By default, any role can create objects in the public schema
revoke_create_on_schema_public-{{ index }}:
  postgres_privileges.absent:
    - name: {{ config['username'] }}
    - object_name: public
    - object_type: schema
    - privileges: [CREATE]
    - maintenance_db: {{ config['database'] }}

grant_usage_on_schema_public-{{ index }}:
  postgres_privileges.present:
    - name: {{ config['username'] }}
    - object_name: public
    - object_type: schema
    - privileges: [USAGE]
    - maintenance_db: {{ config['database'] }}

grant_connect_to_database-{{ index }}:
  postgres_privileges.present:
    - name: {{ config['username'] }}
    - object_name: {{ config['database'] }}
    - object_type: database
    - privileges: [CONNECT]

# TODO: This is always executed
grant_table_select-{{ index }}:
  postgres_privileges.present:
    - name: {{ config['username'] }}
    - object_name: ALL
    - object_type: table
    - privileges: [SELECT]
    - prepend: public
    - maintenance_db: {{ config['database'] }}

# Change default privileges, so read-only user also has access to newly created tables
# There's a salt modules for this, but it's not yet released: https://github.com/saltstack/salt/pull/51904/files
# Information for querying the default privleges: https://stackoverflow.com/a/14555063
alter_default_privileges-{{ index }}:
 cmd.run:
    - name: psql {{ config['database'] }} -t -c "ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO {{ config['username'] }};"
    - unless: psql {{ config['database'] }} -t -c "SELECT 1 FROM pg_default_acl a JOIN pg_namespace b ON a.defaclnamespace=b.oid WHERE defaclacl='{ {{ config['username'] }}=r/postgres }'" |grep -q 1
    - runas: postgres
{% endif %}
{% endfor %}
