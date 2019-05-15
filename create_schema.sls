{% for config in pillar['postgresql']['schemas'] %}
createschema-{{ loop.index }}:
  cmd.run:
    - name: psql -t -d {{ config['database'] }} -c "CREATE SCHEMA IF NOT EXISTS {{ config['schemaname'] }} AUTHORIZATION {{ config['username'] }};"
    - runas: postgres
{% endfor %}
