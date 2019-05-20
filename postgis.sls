# Install postgresql and postgis
postgis:
  pkg.installed:
     - pkgs: [postgresql-{{ pillar['postgresql']['version'] }}-postgis-{{ pillar['postgresql']['postgis']['version'] }}]

{% for config in pillar['postgresql']['databases'] %}
  {% if config['gisdb'] %}
postgis-extension-{{ loop.index }}:
  cmd.run:
    - name: psql -d {{ config['database'] }} -t -c "CREATE EXTENSION IF NOT EXISTS postgis;"
    - runas: postgres
    - require:
      - pkg: postgis
  {% endif %}
{% endfor %}
