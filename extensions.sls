# Install postgres extensions
postgis:
  pkg.installed:
     - pkgs: [postgresql-{{ pillar['postgresql']['version'] }}-postgis-{{ pillar['postgresql']['postgis']['version'] }}]

{% for database in pillar['postgresql']['databases'] %}
  {% for extension in database['extensions'] %}
postgres-extension-{{ database['database'] }}-{{ loop.index }}:
  cmd.run:
    - name: psql -d {{ database['database'] }} -t -c "CREATE EXTENSION {{ extension }};"
    - unless: psql -t -c "SELECT 1 FROM pg_extension WHERE extname='{{ extension }}'" |grep -q 1
    - runas: postgres
    - require:
      - pkg: postgis
  {% endfor %}
{% endfor %}
