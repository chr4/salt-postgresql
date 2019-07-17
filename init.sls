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
    - source: salt://{{ slspath }}/postgresql.conf.jinja
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
    - source: salt://{{ slspath }}/pg_hba.conf.jinja
    - template: jinja
    - require:
      - pkg: postgresql

# Deploy users. Sort them, so order is not changing between salt runs
{% for config in pillar['postgresql']['users']|default({}) %}
createuser-{{ loop.index }}:
  cmd.run:
    - name: psql -t -c "CREATE ROLE {{ config['username'] }} {{ config['options']|default('NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN') }};"
    - unless: psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='{{ config['username'] }}'" |grep -q 1
    - runas: postgres

# The "replication" keyword is not a real database but a special keyword used for replication permissions in pg_hba.conf
{% if config['database'] != "replication" %}
createdb-{{ loop.index }}:
  cmd.run:
    - name: psql -t -c "CREATE DATABASE {{ config['database'] }} OWNER {{ config['username'] }};"
    - unless: psql -t -c "SELECT 1 FROM pg_database WHERE datname='{{ config['database'] }}'" |grep -q 1
    - runas: postgres
    - require:
      - cmd: createuser-{{ loop.index }}
{% endif %}
{% endfor %}


# Disable automatic updates. This broke production once.
{% if salt['pillar.get']('postgresql:unattended_upgrades', true) == false %}
postgresql_disable_unattended_upgrades:
  file.replace:
    - name: /etc/apt/apt.conf.d/50unattended-upgrades
    - pattern: |
        Unattended-Upgrade::Package-Blacklist {
    - repl: |
        Unattended-Upgrade::Package-Blacklist {
          "postgresql-.*";
    - unless: grep -q 'postgresql-.*' /etc/apt/apt.conf.d/50unattended-upgrades
    - onlyif: test -f /etc/apt/apt.conf.d/50unattended-upgrades
{% endif %}
