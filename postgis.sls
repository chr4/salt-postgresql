# Install postgresql and postgis
postgis:
  pkg.installed:
     - pkgs: [postgresql-{{ pillar['postgresql']['version'] }}-postgis-{{ pillar['postgresql']['postgis']['version'] }}]

{% for config in pillar['postgresql']['users'] %}
  {% if config['gisdb'] %}
    postgis-createdb-{{ loop.index }}:
      cmd.run:
        - name: psql -d {{ config['database'] }} -t -c "CREATE EXTENSION IF NOT EXISTS postgis;"
        - runas: postgres
  {% endif %}
{% endfor %}
