# Reload postgres config
{% set version = pillar['postgresql']['version']|default('10') %}

postgres-reload:
  cmd.run:
    - name: psql -t -c "SELECT pg_reload_conf();"
    - runas: postgres
    - onchanges:
      - file: /etc/postgresql/{{ version }}/main/pg_hba.conf
