{% set version = '10' %}

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
    - source: salt://{{ slspath }}/pg_hba.conf
    - require:
      - pkg: postgresql

createuser nextcloud:
  cmd.run:
    - unless: psql -t -c "SELECT 1 FROM pg_roles WHERE rolname='nextcloud'" |grep -q 1
    - runas: postgres

createdb -O nextcloud nextcloud:
  cmd.run:
    - unless: psql -t -c "SELECT 1 FROM pg_database WHERE datname='nextcloud'" |grep -q 1
    - runas: postgres
    - require:
      - cmd: "createuser nextcloud"
