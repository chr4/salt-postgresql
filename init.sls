{% set version = pillar['postgresql']['version']|default('10') %}

postgresql:
  pkg.installed:
     - pkgs: [postgresql-{{ version }}]
  service.running:
    # Make sure service is only reloaded upon config file changes.
    # Restarts result in a downtime, do not restart automatically.
    - enable: true
    - reload: true
    - watch:
      - file: /etc/postgresql/{{ version }}/main/*

# Deploy configuration
/etc/postgresql/{{ version }}/main/postgresql.conf:
  file.managed:
    - mode: 644
    - user: postgres
    - group: postgres
    - source: salt://{{ slspath }}/postgresql.conf.jinja
    - template: jinja
    - defaults:
      max_connections: 100
      version: {{ version }}
      # memory: {{ grains['mem_total'] }}
    - require:
      - pkg: postgresql

/etc/postgresql/{{ version }}/main/pg_hba.conf:
  file.managed:
    - mode: 640
    - user: postgres
    - group: postgres
    - source: salt://{{ slspath }}/pg_hba.conf.jinja
    - template: jinja
    - require:
      - pkg: postgresql


{% for username, config in pillar['postgresql']['users'].items() %}
createuser-{{ username }}:
  cmd.run:
    - name: createuser {{ config['args']|default('') }} {{ username }}
    - unless: psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='{{ username }}'" |grep -q 1
    - runas: postgres

createdb -O {{ username }} {{ config['database'] }}:
  cmd.run:
    - unless: psql -t -c "SELECT 1 FROM pg_database WHERE datname='{{ config['database'] }}'" |grep -q 1
    - runas: postgres
    - require:
      - cmd: createuser-{{ username }}
{% endfor %}
