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
      # These are the defaults, which can be overridden by pillars
      version: {{ version }}
      listen_addresses: ''
      {% set max_connections = salt['pillar.get']('postgresql:config:max_connections', 100) %}
      max_connections: {{ max_connections }}
      work_mem: {{ (grains['mem_total'] * 0.9 / max_connections)|int }}MB
      shared_buffers: {{ (grains['mem_total'] * 0.1)|int }}MB
      maintenance_work_mem: {{ (grains['mem_total'] / 1024 * 50)|int }}MB
      effective_cache_size: {{ (grains['mem_total'] * 0.8)|int }}MB
      wal_level: replica
      wal_log_hints: false
      max_wal_senders: 5 # NOTE: Since postgresql-10, the default is 10
    - context:
      # Override defaults from pillar configuration
{% for key in [
  'listen_addresses', 'work_mem', 'shared_buffers', 'maintenance_work_mem',
  'effective_cache_size', 'archive_command', 'wal_level', 'wal_log_hints', 'max_wal_senders',
  'wal_keep_segments', 'wal_buffers'
  ] %}
  {% set value = salt['pillar.get']('postgresql:config:' + key, undefined) %}
  {% if value is defined %}
      {{ key }}: {{ value }}
  {% endif %}
{% endfor %}

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
createuser-{{ config['username'] }}:
  cmd.run:
    - name: psql -t -c "CREATE ROLE {{ config['username'] }} {{ config['options']|default('NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT LOGIN') }};"
    - unless: psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='{{ config['username'] }}'" |grep -q 1
    - runas: postgres
{% endfor %}

{% for config in pillar['postgresql']['databases']|default({}) %}
{% if config['database'] != "replication" %}
createdb-{{ config['database'] }}:
  cmd.run:
    - name: psql -t -c "CREATE DATABASE {{ config['database'] }} OWNER {{ config['owner'] }};"
    - unless: psql -t -c "SELECT 1 FROM pg_database WHERE datname='{{ config['database'] }}'" |grep -q 1
    - runas: postgres
    - require:
      - cmd: createuser-{{ config['owner'] }}
{% endif %}

{% for schema in config['schemas']|default({}) %}
createschema-{{ schema['schemaname'] }}:
  cmd.run:
    - name: psql -t -d {{ config['database'] }} -c "CREATE SCHEMA IF NOT EXISTS {{ schema['schemaname'] }} AUTHORIZATION {{ schema['user'] }};"
    - runas: postgres
    - require:
      - cmd: createuser-{{ config['owner'] }}
      - cmd: createdb-{{ config['database'] }}
{% endfor %}
{% endfor %}
